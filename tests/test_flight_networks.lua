local T, QR, MockWoW = ...

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
    QR.PlayerInfo:InvalidateCache()
    QR.TravelTime:ClearMovementCache()
    if not ok then error(err) end
end

local function calculator(replace, faction)
    local pc = {}
    for key, value in pairs(QR.PathCalculator) do pc[key] = value end
    pc.graph, pc.nodeIndex, pc.knownFlightZonesOverride = nil, nil, nil
    pc.graphDirty = true
    replace(QR, "PathCalculator", pc)
    replace(QR, "db", { considerCooldowns = true })
    replace(MockWoW.config, "playerFaction", faction)
    replace(MockWoW.config, "currentMapID", 2339)
    replace(MockWoW.config, "playerX", 0.5)
    replace(MockWoW.config, "playerY", 0.5)
    replace(MockWoW.config, "isFlyableArea", false)
    replace(_G, "IsFlying", function() return false end)
    replace(_G, "IsMounted", function() return false end)
    replace(_G, "IsIndoors", function() return false end)
    replace(_G, "IsAdvancedFlyableArea", function() return false end)
    replace(_G, "GetUnitSpeed", function() return 0, 7, 0, 0 end)
    replace(_G, "C_MountJournal", { GetMountIDs = function() return {} end })
    replace(QR.PlayerInventory, "GetAllTeleports", function() return {} end)
    QR.PlayerInfo:InvalidateCache()
    QR.TravelTime:ClearMovementCache()
    return pc
end

for _, side in ipairs({ "Alliance", "Horde" }) do
    local faction = side
    T:run("Flight networks: discovered Dornogal to Deeps improves a real " .. faction .. " route", function(t)
        isolated(function(replace)
            local pc = calculator(replace, faction)
            local known = {}
            replace(_G, "C_TaxiMap", { GetTaxiNodesForMap = function(mapID)
                local point = pc:FlightPointFor(mapID)
                return point and {{ position = { x = point.x, y = point.y },
                    isUndiscovered = not known[mapID] }} or {}
            end })
            local before = pc:CalculatePath(2214, 0.5, 0.5)
            known = { [2339] = true, [2214] = true }
            pc.graphDirty = true
            local after = pc:CalculatePath(2214, 0.5, 0.5)
            t:assertNotNil(before, "The original route can be calculated")
            t:assertNotNil(after, "The route with discovered flights can be calculated")
            if not before or not after then return end
            t:assertGreaterThan(before.totalTime, after.totalTime,
                "A real route improves from " .. before.totalTime .. " to " .. after.totalTime)
            local flight
            for _, edge in ipairs(after.edges) do
                if edge.edgeType == "flight" then flight = edge end
            end
            t:assertNotNil(flight, "The improved route actually takes a flight")
            if flight then
                t:assertEqual(2339, flight.data.fromMapID, "Flight boards in Dornogal")
                t:assertEqual(2214, flight.data.toMapID, "Flight arrives in The Ringing Deeps")
            end
            known[2214] = nil
            pc.graphDirty = true
            local forgotten = pc:CalculatePath(2214, 0.5, 0.5)
            t:assertNotNil(forgotten, "An undiscovered endpoint retains the original route")
            if forgotten then
                t:assertEqual(before.totalTime, forgotten.totalTime,
                    "An undiscovered endpoint does not retain the flight shortcut")
            end
        end)
    end)
end

T:run("Flight networks: neutral endpoints use the current faction's connectivity", function(t)
    isolated(function(replace)
        local pc = calculator(replace, "Alliance")
        local points = {}
        for _, mapID in ipairs({ 2339, 2214 }) do
            points[mapID] = {}
            for key, value in pairs(QR.FlightPoints[mapID]) do points[mapID][key] = value end
        end
        points[2339].network = { Alliance = 1, Horde = 1 }
        points[2214].network = { Alliance = 2, Horde = 1 }
        replace(QR, "FlightPoints", points)
        pc.knownFlightZonesOverride = { [2339] = true, [2214] = true }
        local function hasFlight()
            pc:BuildGraph()
            local a, b = pc:FlightAnchorForMap(2339), pc:FlightAnchorForMap(2214)
            local edge = a and b and pc.graph:GetEdge(a, b)
            return edge and edge.edgeType == "flight" or false
        end
        t:assertFalse(hasFlight(), "Alliance cannot use a Horde-only connecting master")
        MockWoW.config.playerFaction = "Horde"
        QR.PlayerInfo:InvalidateCache()
        t:assertTrue(hasFlight(), "Horde retains the connection between the same neutral endpoints")
    end)
end)
