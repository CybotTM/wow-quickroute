local T, QR = ...

local function isolated(body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(body, replace)
    for i = #saved, 1, -1 do
        local item = saved[i]
        item[1][item[2]] = item[3]
    end
    if not ok then error(err) end
end

local function setup(replace)
    local position = { mapID = 627, x = 0.5, y = 0.5 }
    replace(Enum, "GarrisonType", { Type_7_0_Garrison = 3 })
    replace(_G, "C_Garrison", { HasGarrison = function(kind) return kind == 3 end })
    replace(C_QuestLog, "IsOnQuest", function() return false end)
    replace(QR.PlayerInfo, "GetClass", function() return "DEATHKNIGHT" end)
    replace(QR.PlayerInfo, "GetFaction", function() return "Alliance" end)
    replace(_G, "UnitFactionGroup", function() return "Alliance" end)
    replace(_G, "UnitLevel", function() return 90 end)
    replace(_G, "UnitGUID", function() return "Player-Inn-Route-Test" end)
    replace(_G, "GetLocale", function() return "deDE" end)
    replace(_G, "GetBindLocation", function() return "Morgenluft" end)
    replace(_G, "C_TaxiMap", {})
    replace(C_Map, "GetBestMapForUnit", function() return position.mapID end)
    replace(C_Map, "GetPlayerMapPosition", function()
        return { GetXY = function() return position.x, position.y end }
    end)
    replace(QR.db, "hearthstoneBinds", {})
    replace(QR.db, "maxCooldownHours", 24)
    replace(QR.db, "considerCooldowns", true)
    replace(QR.db, "loadingScreenTime", 5)
    replace(QR.Hearthstone, "innIndex", nil)
    replace(QR.Hearthstone, "innIndexIncomplete", nil)
    replace(QR.Hearthstone, "pendingArrival", nil)
    replace(QR.TeleportDestinations, "deathGateUsable", false)
    replace(QR.TravelTime, "CanFly", function() return false end)
    replace(QR.PlayerInventory, "GetAllTeleports", function()
        return {
            [50977] = { sourceType = "spell", data = QR.ClassTeleportSpells[50977] },
            [65360] = { sourceType = "item", data = QR.TeleportItemsData[65360] },
            [6948] = { sourceType = "item", data = QR.TeleportItemsData[6948] },
        }
    end)
    replace(QR.CooldownTracker, "GetCooldown", function()
        return { ready = true, remaining = 0, duration = 0 }
    end)
    -- The IDs, inn coordinates and localized mapping below are synthetic.
    -- They prove resolver/routing integration, not actual Morgenluft coverage.
    replace(QR, "HearthstoneLocations", {
        { areaID = 910001, mapID = 2395, x = 0.45, y = 0.5 },
    })
    -- Retain the real graph builder, route algorithm and world connections,
    -- while isolating all graph and lookup caches from other test files.
    local calculator = { graphDirty = true }
    for key, value in pairs(QR.PathCalculator) do
        if type(value) == "function" then calculator[key] = value end
    end
    replace(QR, "PathCalculator", calculator)
    return calculator, position
end

local function firstTeleport(route)
    return route and route.steps and route.steps[1]
end

T:run("Hearthstone inn routes: a warm graph updates from unknown to localized inn to observed bind", function(t)
    isolated(function(replace)
        local calculator, position = setup(replace)
        local areaAvailable = false
        replace(C_Map, "GetAreaInfo", function(id)
            if areaAvailable and id == 910001 then return "Morgenluft" end
        end)
        local unknown = calculator:CalculatePath(2437, 0.254, 0.84)
        local unknownStep = firstTeleport(unknown)
        t:assertEqual(65360, unknownStep and unknownStep.teleportID,
            "Unknown inn leaves the complete cloak route ahead of Death Gate")
        t:assertFalse(calculator.graphDirty, "The initial route leaves a warm graph")
        local warmGraph = calculator.graph
        areaAvailable = true
        t:assertNil(QR.Hearthstone:GetDestination(), "Incomplete localization stays cached until a world event")
        t:assertEqual(warmGraph, calculator.graph, "A cached unresolved lookup preserves the warm graph")

        QR.Hearthstone:OnEvent("PLAYER_ENTERING_WORLD", true, false)
        t:assertTrue(calculator.graphDirty, "World entry invalidates a graph built without the inn")
        local point = QR.Hearthstone:GetDestination()
        t:assertNotNil(point, "An unobserved German binding resolves from the available catalogue")
        t:assertEqual("INN_DATABASE", point and point.source, "Inferred destination identifies its catalogue source")
        t:assertTrue(point and point.isApproximate, "Catalogue landing is explicitly approximate")
        local inferred = calculator:CalculatePath(2437, 0.254, 0.84)
        local inferredStep = firstTeleport(inferred)
        t:assertEqual(6948, inferredStep and inferredStep.teleportID,
            "Known inn makes the complete hearth route faster than cloak and Death Gate")
        t:assert(inferred and unknown and inferred.totalTime < unknown.totalTime,
            "The inferred hearth reduces the complete route estimate")
        local data = inferredStep and inferredStep.teleportData
        t:assertEqual("INN_DATABASE", data and data.hearthstoneSource,
            "The selected route retains catalogue provenance")
        t:assertTrue(data and data.isApproximate, "The selected route retains the approximation marker")
        t:assertNil(next(QR.db.hearthstoneBinds), "Routing never persists an inferred point as an observation")

        -- Record a same-name binding at a different fixture point, then move
        -- the simulated player back to the original route start.
        position.mapID, position.x, position.y = 2437, 0.254, 0.84
        QR.Hearthstone:OnEvent("HEARTHSTONE_BOUND")
        position.mapID, position.x, position.y = 627, 0.5, 0.5
        t:assertTrue(calculator.graphDirty, "A newly observed bind invalidates the warm inferred graph")
        local observed = calculator:CalculatePath(2437, 0.254, 0.84)
        local observedStep = firstTeleport(observed)
        local observedData = observedStep and observedStep.teleportData
        t:assertEqual(6948, observedStep and observedStep.teleportID, "The observed hearth remains the winning route")
        t:assertEqual(2437, observedData and observedData.mapID,
            "The rebuilt route lands at the observed map instead of the catalogue map")
        t:assertEqual(0.254, observedData and observedData.x, "The route uses the observed binding coordinate")
        t:assertFalse(observedData and observedData.isApproximate == true,
            "An observed landing is no longer labelled as catalogue inference")
        t:assert(observed and inferred and observed.totalTime < inferred.totalTime,
            "The nearer observation changes the complete route estimate")
    end)
end)

T:run("Hearthstone inn routes: an ambiguous German binding cannot displace the known cloak route", function(t)
    isolated(function(replace)
        local calculator = setup(replace)
        QR.HearthstoneLocations[2] = { areaID = 910002, mapID = 94, x = 0.45, y = 0.5 }
        replace(C_Map, "GetAreaInfo", function(id)
            if id == 910001 or id == 910002 then return "Morgenluft" end
        end)
        t:assertNil(QR.Hearthstone:GetDestination(), "Distinct same-name inn candidates remain unresolved")
        local route = calculator:CalculatePath(2437, 0.254, 0.84)
        local step = firstTeleport(route)
        t:assertEqual(65360, step and step.teleportID,
            "Ambiguous binding leaves the valid complete cloak route ahead of Death Gate")
        for _, routeStep in ipairs(route and route.steps or {}) do
            t:assert(routeStep.teleportID ~= 6948, "No route leg uses an unproven ambiguous hearth landing")
        end
        t:assertNil(next(QR.db.hearthstoneBinds), "Ambiguity never creates a saved binding")
    end)
end)
