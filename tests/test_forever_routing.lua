-------------------------------------------------------------------------------
-- test_forever_routing.lua
-- Runs only with QR_TEST_FLAVOR=forever. Routes between Forever zones are
-- built from the Forever data alone: every node of the graph sits on a Forever
-- map, and a route between two zones walks the converted adjacency.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local foreverMaps = MockWoW.foreverMapDatabase

local function resetState(faction, mapID)
    MockWoW:Reset()
    MockWoW.config.playerFaction = faction or "Alliance"
    MockWoW.config.currentMapID = mapID or 1453
    MockWoW.config.playerX, MockWoW.config.playerY = 0.5, 0.5
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
    if QR.PlayerInfo and QR.PlayerInfo.InvalidateCache then QR.PlayerInfo:InvalidateCache() end
    QR.PlayerInventory:ScanAll()
end

T:run("Forever routing: every graph node is on a Forever map", function(t)
    resetState("Alliance", 1436)
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "graph built")
    local count, bad = 0, {}
    for name, node in pairs(graph and graph.nodes or {}) do
        count = count + 1
        if node.mapID and not foreverMaps[node.mapID] then
            bad[#bad + 1] = tostring(name) .. "@" .. tostring(node.mapID)
        end
    end
    t:assertGreaterThan(count, 20, "graph nodes")
    t:assertEqual(0, #bad, "nodes on a non-Forever map (" .. table.concat(bad, ", ", 1, math.min(#bad, 10)) .. ")")
end)

T:run("Forever routing: Westfall to Redridge Mountains over the converted zone adjacency", function(t)
    resetState("Alliance", 1436)  -- Westfall
    local result = QR.PathCalculator:CalculatePath(1433, 0.3, 0.5)  -- Redridge Mountains
    t:assertNotNil(result, "route from Westfall (1436) to Redridge Mountains (1433)")
    if not result then return end
    t:assertGreaterThan(#result.steps, 0, "route steps")
    t:assertGreaterThan(result.totalTime, 0, "route time")
    local maps, through = {}, {}
    for _, step in ipairs(result.steps) do
        for _, id in ipairs({ step.fromMapID, step.destMapID, step.mapID }) do
            if id then
                maps[#maps + 1] = id
                through[id] = true
            end
        end
    end
    local bad = {}
    for _, id in ipairs(maps) do
        if not foreverMaps[id] then bad[#bad + 1] = tostring(id) end
    end
    t:assertEqual(0, #bad, "step map IDs that are not Forever maps (" .. table.concat(bad, ", ") .. ")")
    t:assertTrue(through[1433] == true, "route ends in Redridge Mountains 1433")
end)

T:run("Forever routing: a mage teleport lands on the Forever Ironforge map", function(t)
    resetState("Alliance", 1436)
    MockWoW.config.knownSpells = { [3562] = true }  -- Teleport: Ironforge
    QR.PlayerInventory:ScanAll()
    local result = QR.PathCalculator:CalculatePath(1455, 0.27, 0.73)
    t:assertNotNil(result, "route from Westfall to Ironforge (1455)")
    if not result then return end
    local usedTeleport = false
    for _, step in ipairs(result.steps) do
        if step.destMapID == 1455 and step.type ~= "walk" then usedTeleport = true end
    end
    t:assertTrue(usedTeleport, "a non-walking step lands on Ironforge 1455")
end)

T:run("Forever routing: Horde from Durotar to Undercity takes the zeppelin to Tirisfal", function(t)
    resetState("Horde", 1411)  -- Durotar
    local result = QR.PathCalculator:CalculatePath(1458, 0.5, 0.5)  -- Undercity
    t:assertNotNil(result, "route from Durotar (1411) to Undercity (1458)")
    if not result then return end
    local zeppelin
    for _, step in ipairs(result.steps) do
        if step.type == "zeppelin" then zeppelin = step end
    end
    t:assertNotNil(zeppelin, "a zeppelin step")
    t:assertEqual(1454, zeppelin and zeppelin.fromMapID, "zeppelin leaves from Orgrimmar 1454")
    t:assertEqual(1420, zeppelin and zeppelin.destMapID, "zeppelin lands in Tirisfal Glades 1420")
end)

T:run("Forever routing: Horde from Orgrimmar to the Badlands flies to Kargath", function(t)
    -- Flight edges need the client to report the taxi nodes as discovered;
    -- the mock has no taxi map, so every Forever flight master counts as known.
    local known = {}
    for mapID in pairs(QR.FlightPoints) do known[mapID] = true end
    QR.PathCalculator.knownFlightZonesOverride = known
    local ok, err = pcall(function()
        resetState("Horde", 1454)  -- Orgrimmar
        local result = QR.PathCalculator:CalculatePath(1418, 0.5, 0.5)  -- Badlands
        t:assertNotNil(result, "route from Orgrimmar (1454) to the Badlands (1418)")
        local flight
        for _, step in ipairs(result and result.steps or {}) do
            if step.type == "flight" then flight = step end
        end
        t:assertNotNil(flight, "a flight step")
        t:assertEqual(1418, flight and flight.destMapID, "the flight lands in the Badlands 1418")
    end)
    QR.PathCalculator.knownFlightZonesOverride = nil
    QR.PathCalculator.graph, QR.PathCalculator.graphDirty = nil, true
    if not ok then error(err, 0) end
end)
