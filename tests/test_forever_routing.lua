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
    -- The tower stop of taxi path 302 lies outside Classic Orgrimmar's map.
    t:assertEqual(1411, zeppelin and zeppelin.fromMapID, "zeppelin leaves from Durotar 1411")
    t:assertEqual(1420, zeppelin and zeppelin.destMapID, "zeppelin lands in Tirisfal Glades 1420")
end)

--- Run fn with every Forever flight master known. Flight edges need the client
-- to report the taxi nodes as discovered; the mock has no taxi map.
local function withKnownFlights(fn)
    local known = {}
    for mapID in pairs(QR.FlightPoints) do known[mapID] = true end
    QR.PathCalculator.knownFlightZonesOverride = known
    local ok, err = pcall(fn)
    QR.PathCalculator.knownFlightZonesOverride = nil
    QR.PathCalculator.graph, QR.PathCalculator.graphDirty = nil, true
    if not ok then error(err, 0) end
end

local function stepsOfType(result, kind)
    local found = {}
    for _, step in ipairs(result and result.steps or {}) do
        if step.type == kind then found[#found + 1] = step end
    end
    return found
end

T:run("Forever routing: Horde from Orgrimmar to Felwood flies to Splintertree Post", function(t)
    withKnownFlights(function()
        resetState("Horde", 1454)  -- Orgrimmar
        local result = QR.PathCalculator:CalculatePath(1448, 0.5, 0.5)  -- Felwood
        t:assertNotNil(result, "route from Orgrimmar (1454) to Felwood (1448)")
        local flight = stepsOfType(result, "flight")[1]
        t:assertNotNil(flight, "a flight step")
        t:assertEqual(1440, flight and flight.destMapID, "the flight lands in Ashenvale 1440")
    end)
end)

T:run("Forever routing: a zone whose only node is its flight master gets one", function(t)
    -- Arathi Highlands has no capital, transport, dungeon or teleport landing;
    -- its flight master (Hammerfall for the Horde) is the only thing in it.
    local graph
    withKnownFlights(function()
        resetState("Horde", 1411)
        graph = QR.PathCalculator:BuildGraph()
    end)
    local onMap = {}
    for name, data in pairs(graph and graph.nodes or {}) do
        if data.mapID == 1417 then onMap[#onMap + 1] = name end
    end
    t:assertEqual(1, #onMap, "nodes on Arathi Highlands 1417 (" .. table.concat(onMap, ", ") .. ")")
    local node = graph and graph.nodes[QR.PathCalculator:FlightPointFor(1417).node]
    t:assertNotNil(node, "graph node at the Arathi Highlands flight master")
    t:assertEqual(1417, node and node.mapID, "flight master node map")
    t:assertEqual("flight_master", node and node.nodeType, "flight master node type")
    local flights = 0
    for _, edge in pairs(graph and node and graph.edges[QR.PathCalculator:FlightPointFor(1417).node] or {}) do
        if edge.edgeType == "flight" then flights = flights + 1 end
    end
    t:assertGreaterThan(flights, 0, "flight edges leaving the Arathi Highlands flight master")
end)

T:run("Forever routing: Riverglades reaches Stormwind over the map-bounds adjacency", function(t)
    resetState("Alliance", 2548)  -- Riverglades
    local derived = 0
    for _, edge in ipairs(QR.ZoneAdjacencies[2548] or {}) do
        if edge.source == "map_bounds" and edge.provenance == QR.Provenance.ESTIMATED then
            derived = derived + 1
        end
    end
    t:assertGreaterThan(derived, 0, "Riverglades edges derived from map bounds")
    local result = QR.PathCalculator:CalculatePath(1453, 0.5, 0.5)  -- Stormwind City
    t:assertNotNil(result, "route from Riverglades (2548) to Stormwind City (1453)")
    t:assertEqual(0, #stepsOfType(result, "boat"), "boat steps on the overland route")
    t:assertEqual(0, #stepsOfType(result, "zeppelin"), "zeppelin steps on the overland route")
end)

T:run("Forever routing: Mount Hyjal reaches Orgrimmar", function(t)
    resetState("Horde", 2482)  -- Mount Hyjal
    local result = QR.PathCalculator:CalculatePath(1454, 0.5, 0.5)  -- Orgrimmar
    t:assertNotNil(result, "route from Mount Hyjal (2482) to Orgrimmar (1454)")
    t:assertGreaterThan(result and #result.steps or 0, 0, "route steps")
end)

T:run("Forever routing: the Zephras Isle zeppelin from Forever's TaxiPath", function(t)
    resetState("Horde", 1454)  -- Orgrimmar
    local result = QR.PathCalculator:CalculatePath(2521, 0.5, 0.5)  -- Zephras Isle
    t:assertNotNil(result, "route from Orgrimmar (1454) to Zephras Isle (2521)")
    local zeppelins = stepsOfType(result, "zeppelin")
    local last = zeppelins[#zeppelins]
    t:assertEqual(2521, last and last.destMapID, "a zeppelin lands on Zephras Isle 2521")
end)

T:run("Forever routing: the Tanaris boat to Riverglades from Forever's TaxiPath", function(t)
    local leg
    for _, portal in ipairs(QR.StandalonePortals) do
        local a, b = portal.from.mapID, portal.to.mapID
        if (a == 1446 and b == 2548) or (a == 2548 and b == 1446) then leg = portal end
    end
    t:assertNotNil(leg, "transport between Tanaris 1446 and Riverglades 2548")
    t:assertEqual("boat", leg and leg.type, "transport type")
    t:assertEqual(11391, leg and leg.taxiPathIDs and leg.taxiPathIDs[1], "taxi path the boat comes from")
end)

-- The owner's trip: from the start zone (Zephras Isle) by zeppelin to Dalaran,
-- then through the portal in Dalaran to Stormwind's Mage Sanctum. The portal
-- is not in Forever's tables; it comes from scripts/data/forever_observed_portals.json,
-- backed by the zone survey's loading-screen crossing 1416 -> 1453.
local function fromZephrasToStormwind(faction)
    resetState(faction, 2521)
    MockWoW.config.playerX, MockWoW.config.playerY = 0.6623, 0.7659
    return QR.PathCalculator:CalculatePath(1453, 0.5, 0.6)  -- Stormwind City
end

T:run("Forever routing: Alliance from Zephras Isle takes the zeppelin and the Dalaran portal", function(t)
    local result = fromZephrasToStormwind("Alliance")
    t:assertNotNil(result, "route from Zephras Isle (2521) to Stormwind City (1453)")
    if not result then return end
    local zeppelins, portals = stepsOfType(result, "zeppelin"), stepsOfType(result, "portal")
    t:assertEqual(1, #zeppelins, "one zeppelin")
    t:assertEqual(1416, zeppelins[1] and zeppelins[1].destMapID, "to Dalaran in Alterac Mountains")
    t:assertEqual(1, #portals, "one portal")
    t:assertEqual(1453, portals[1] and portals[1].destMapID, "to Stormwind City")
    local zeppelinAt, portalAt
    for i, step in ipairs(result.steps) do
        if step == zeppelins[1] then zeppelinAt = i end
        if step == portals[1] then portalAt = i end
    end
    t:assert(zeppelinAt and portalAt and zeppelinAt < portalAt, "the zeppelin first, then the portal ("
        .. tostring(zeppelinAt) .. ", " .. tostring(portalAt) .. ")")
end)

T:run("Forever routing: a Horde character does not get the Dalaran portal", function(t)
    local result = fromZephrasToStormwind("Horde")
    t:assertNotNil(result, "route from Zephras Isle (2521) to Stormwind City (1453)")
    t:assertEqual(0, #stepsOfType(result, "portal"), "no portal step for the Horde")
end)

T:run("Forever routing: the Dalaran portal goes one way only", function(t)
    resetState("Alliance", 1453)
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4987, 0.8667   -- the portal's arrival point
    local result = QR.PathCalculator:CalculatePath(1416, 0.1209, 0.5641)   -- its departure point
    t:assertNotNil(result, "route from Stormwind City back to Dalaran")
    t:assertEqual(0, #stepsOfType(result, "portal"), "no portal back: nobody has seen one")
end)
