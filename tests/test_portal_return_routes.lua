-- Regression evidence for #21/#40: use the complete graph and public routing.
local T, QR, MockWoW = ...

local function isolated(body)
    local changes = {}
    local function set(tbl, key, value)
        changes[#changes + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(function()
        local pc = QR.PathCalculator
        for _, key in ipairs({ "graph", "nodeIndex", "graphFaction", "zoneTravelGraph",
            "zoneTravelCache", "knownFlightZonesOverride" }) do set(pc, key, nil) end
        set(pc, "graphDirty", true)
        set(QR.PlayerInventory, "GetAllTeleports", function() return {} end)
        set(C_QuestLog, "IsQuestFlaggedCompleted", function() return true end)
        set(C_Map, "GetMapArtID", function(mapID)
            if mapID == 390 then return 402 elseif mapID == 1530 then return 1342 end
        end)
        for _, key in ipairs({ "playerFaction", "playerClass", "currentMapID", "playerX", "playerY" }) do
            set(MockWoW.config, key, MockWoW.config[key])
        end
        MockWoW.config.playerClass = "WARRIOR"
        set(_G, "C_TaxiMap", { GetTaxiNodesForMap = function(mapID)
            local result = {}
            local point = pc:FlightPointFor(mapID)
            if point then
                result[#result + 1] = { faction = 0, isUndiscovered = false,
                    position = { x = point.x, y = point.y } }
            end
            for id, node in pairs(QR.TravelTransitions.nodes) do
                if node.mapID == mapID and (node.taxiNodeID or id:match("FLIGHT")) then
                    result[#result + 1] = { nodeID = node.taxiNodeID, faction = 0,
                        isUndiscovered = false, position = { x = node.x, y = node.y } }
                end
            end
            return result
        end })
        body(set)
    end)
    for i = #changes, 1, -1 do local change = changes[i]; change[1][change[2]] = change[3] end
    QR.PlayerInfo:InvalidateCache()
    if not ok then error(err) end
end

local function routeFrom(mapID, x, y, destination, tx, ty)
    MockWoW.config.currentMapID = mapID
    MockWoW.config.playerX, MockWoW.config.playerY = x, y
    QR.PathCalculator.graphDirty = true
    return QR.PathCalculator:CalculatePath(destination, tx, ty)
end

T:run("Return routes: all named Pandaria and Draenor zones reach their faction capital", function(t)
    isolated(function()
        -- Deliberately explicit: dropping a zone from the production catalogue
        -- must not quietly shrink this stranding regression.
        local maps = { 371, 376, 379, 388, 390, 418, 422, 433, 504, 507, 554, 1530,
            525, 534, 535, 539, 542, 543, 550, 582, 590, 622, 624, 588 }
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            MockWoW.config.playerFaction = faction
            QR.PlayerInfo:InvalidateCache()
            local destination = faction == "Alliance" and 84 or 85
            for _, mapID in ipairs(maps) do
                local route = routeFrom(mapID, .5, .5, destination, .5, .5)
                local label = faction .. " from " .. mapID .. " to " .. destination
                t:assertNotNil(route, label .. " has a complete route with discovered taxis and no personal teleports")
                local portal = false
                for _, step in ipairs(route and route.steps or {}) do
                    if step.type == "portal" then portal = true end
                    t:assert(step.type ~= "teleport", label .. " needs no owned teleport ability")
                end
                t:assertTrue(portal, label .. " leaves through a modeled portal")
            end
        end
    end)
end)

T:run("Return routes: each Oribos realm uses the same discovered flight in both directions", function(t)
    isolated(function(set)
        for _, faction in ipairs({ "Alliance", "Horde" }) do
            MockWoW.config.playerFaction = faction
            QR.PlayerInfo:InvalidateCache()
            local oribos = QR.TravelTransitions.nodes.ORIBOS_FLIGHT
            for _, key in ipairs({ "ASPIRANTS_REST_FLIGHT", "THEATER_OF_PAIN_FLIGHT",
                "TIRNA_VAAL_FLIGHT", "PRIDEFALL_HAMLET_FLIGHT" }) do
                local point = QR.TravelTransitions.nodes[key]
                local outward = routeFrom(oribos.mapID, oribos.x, oribos.y, point.mapID, point.x, point.y)
                local inward = routeFrom(point.mapID, point.x, point.y, oribos.mapID, oribos.x, oribos.y)
                t:assertNotNil(outward, faction .. " Oribos flight to " .. key)
                t:assertNotNil(inward, faction .. " return flight from " .. key)
                if outward and inward then
                    t:assertTrue(math.abs(outward.totalTime - inward.totalTime) < .001,
                        "matched flight-master endpoints have equal modeled durations for " .. key)
                    for _, route in ipairs({ outward, inward }) do
                        local flights = 0
                        for _, step in ipairs(route.steps) do
                            if step.type == "flight" then flights = flights + 1 end
                            t:assert(step.type ~= "portal" and step.type ~= "travel",
                                "realm crossing uses an actual taxi instead of a portal or overland shortcut")
                        end
                        t:assertEqual(1, flights, "one actual realm flight carries each direction")
                    end
                end
            end
        end
        set(C_TaxiMap, "GetTaxiNodesForMap", function() return {} end)
        for _, mapID in ipairs({ 1533, 1536, 1565, 1525 }) do
            t:assertNil(routeFrom(mapID, .5, .5, 1671, .607, .684),
                "undiscovered flight from " .. mapID .. " cannot become a fictitious portal")
        end
    end)
end)

T:run("Return routes: outdoor garrisons connect to their actual host zones", function(t)
    local graph = QR.BuildZoneTravelGraph()
    for _, pair in ipairs({ { 582, 539 }, { 590, 525 } }) do
        local out = graph.edges[pair[1]] and graph.edges[pair[1]][pair[2]]
        local back = graph.edges[pair[2]] and graph.edges[pair[2]][pair[1]]
        t:assertNotNil(out, "garrison " .. pair[1] .. " has a local exit to host zone " .. pair[2])
        t:assertNotNil(back, "garrison entrance also supports return travel")
        if out and back then
            t:assertEqual(out.weight, back.weight, "garrison entrance has symmetric estimated travel costs")
            t:assertEqual("walk", out.edgeType, "garrison exit requires ordinary local travel")
        end
    end
end)
