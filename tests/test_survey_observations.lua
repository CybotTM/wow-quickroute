-- Corrections taken from the zone survey (QR.ZoneSurvey) of a live 12.1.5
-- client. Each case names the observation it rests on.
local T, QR, MockWoW = ...

local function isolated(body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(function()
        local pc = QR.PathCalculator
        for _, key in ipairs({ "graph", "nodeIndex", "graphFaction", "zoneTravelGraph",
            "zoneTravelCache", "knownFlightZonesOverride" }) do replace(pc, key, nil) end
        replace(pc, "graphDirty", true)
        for _, key in ipairs({ "playerFaction", "playerClass", "currentMapID", "playerX", "playerY" }) do
            replace(MockWoW.config, key, MockWoW.config[key])
        end
        MockWoW.config.playerClass = "WARRIOR"
        replace(_G, "C_TaxiMap", { GetTaxiNodesForMap = function() return {} end })
        replace(QR.CooldownTracker, "GetCooldown", function()
            return { ready = true, remaining = 0, duration = 0 }
        end)
        body(replace)
    end)
    for i = #saved, 1, -1 do local item = saved[i]; item[1][item[2]] = item[3] end
    QR.PlayerInfo:InvalidateCache()
    if not ok then error(err) end
end

T:run("Survey: the Arcantina key lands in the Arcantina, where the survey saw it land", function(t)
    -- Three arrivals from Azj-Kahet, Silithus and Moonglade at one point.
    local choices = QR.TeleportDestinations:GetDestinations(253629, QR.TeleportItemsData[253629])
    t:assertEqual(1, #choices, "the key has one landing, got " .. #choices)
    local landing = choices[1]
    t:assertEqual(2541, landing and landing.mapID,
        "the key lands on the Arcantina map, got " .. tostring(landing and landing.mapID))
    t:assertEqual(0.5050, landing and landing.x, "at the observed x, got " .. tostring(landing and landing.x))
    t:assertEqual(0.8070, landing and landing.y, "at the observed y, got " .. tostring(landing and landing.y))
end)

T:run("Survey: a route by the Arcantina key leaves through the Arcantina exit", function(t)
    isolated(function(replace)
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return { [253629] = { sourceType = "toy", data = QR.TeleportItemsData[253629] } }
        end)
        local portal = QR.TravelTransitions.nodes.SILVERMOON_ARCANTINA_PORTAL
        -- Silithus, one of the observed departure maps.
        MockWoW.config.currentMapID = 81
        MockWoW.config.playerX, MockWoW.config.playerY = 0.6909, 0.1863
        local route = QR.PathCalculator:CalculatePath(portal.mapID, portal.x, portal.y)
        t:assertNotNil(route, "Silithus reaches Silvermoon with only the key")
        local steps = route and route.steps or {}
        local keyStep, exitStep
        for i, step in ipairs(steps) do
            if step.teleportID == 253629 then keyStep = i end
            if keyStep and not exitStep and step.type == "portal" then exitStep = i end
        end
        t:assertNotNil(keyStep, "the route uses the key, steps: " .. #steps)
        t:assertNotNil(exitStep, "after the key the route takes a portal out of the Arcantina")
        local exitFrom = exitStep and steps[exitStep].from
        t:assertEqual("Travel:ARCANTINA_EXIT", exitFrom,
            "that portal is the Arcantina exit, got " .. tostring(exitFrom))
        local data = keyStep and steps[keyStep].teleportData
        t:assertEqual(2541, data and data.mapID,
            "the key step lands on the Arcantina map, got " .. tostring(data and data.mapID))
    end)
end)

T:run("Survey: observed walks into sub-zones are overland edges both ways", function(t)
    local graph = QR.BuildZoneTravelGraph()
    -- { sub-zone, neighbour } pairs seen without a loading screen.
    local pairsSeen = {
        { 425, 37 },     -- Northshire / Elwynn Forest
        { 2536, 2437 },  -- Atal'Aman / Zul'Aman
        { 2536, 2395 },  -- Atal'Aman / Eversong Woods
        { 2216, 2255 },  -- City of Threads - Lower / Azj-Kahet
        { 2510, 2413 },  -- The Grudge Pit / Harandar
    }
    for _, pair in ipairs(pairsSeen) do
        local a, b = pair[1], pair[2]
        local out = graph.edges[a] and graph.edges[a][b]
        local back = graph.edges[b] and graph.edges[b][a]
        t:assertNotNil(out, a .. " -> " .. b .. " is a walk edge")
        t:assertNotNil(back, b .. " -> " .. a .. " is a walk edge")
        t:assertTrue(QR.AreSameContinent(a, b), a .. " and " .. b .. " share a continent")
    end
end)

T:run("Survey: the Arcantina keeps its ground estimate after joining a continent", function(t)
    -- Before 2541 was listed under Eastern Kingdoms it had no continent and
    -- was priced on the ground. Listing it must not make it flyable.
    local eligibility = QR.TravelTime:RemoteFlightEligibility(2541)
    t:assertEqual("ground", eligibility, "the Arcantina is priced on the ground, got " .. tostring(eligibility))
end)
