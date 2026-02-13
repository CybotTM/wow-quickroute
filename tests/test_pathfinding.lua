-------------------------------------------------------------------------------
-- test_pathfinding.lua
-- Comprehensive tests for QR.PathCalculator and the full pathfinding pipeline
-- Tests graph building, same-zone routing, multi-hop teleport routes,
-- cross-continent routing, flyability, edge cases, and BuildSteps output.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper: reset mock state and force a fresh graph rebuild
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    -- Re-install globals that Reset clears (faction, class, map etc.)
    -- Reset sets defaults, but we need to ensure globals read new config
    -- MockWoW:Install() was called once at start; config changes propagate
    -- because the closures read from MockWoW.config

    -- Invalidate the flyable area cache in PathCalculator by firing zone change
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")

    -- Clear PathCalculator caches
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true

    -- Clear PlayerInventory caches
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}

    -- Clear PlayerInfo cache (faction, class, engineering)
    if QR.PlayerInfo and QR.PlayerInfo.InvalidateCache then
        QR.PlayerInfo:InvalidateCache()
    end
end

-------------------------------------------------------------------------------
-- 1. Graph Building
-------------------------------------------------------------------------------

T:run("BuildGraph creates nodes for capital cities", function(t)
    resetState()
    -- Alliance player by default (faction cached at first call, which was Alliance)
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Alliance cities should be present
    t:assertNotNil(graph.nodes["Stormwind City"], "Stormwind City node exists")
    t:assertNotNil(graph.nodes["Ironforge"], "Ironforge node exists")

    -- Neutral hubs should be present
    t:assertNotNil(graph.nodes["Dalaran (Northrend)"], "Dalaran (Northrend) node exists")
    t:assertNotNil(graph.nodes["Dornogal"], "Dornogal node exists")
    t:assertNotNil(graph.nodes["Valdrakken"], "Valdrakken node exists")
    t:assertNotNil(graph.nodes["Oribos"], "Oribos node exists")

    -- Horde-only capital cities should NOT appear as city nodes for Alliance
    -- (Note: some Horde cities may appear as portal destinations, but not as
    -- capital city nodes added by AddZoneNodes)
    local stormwind = graph.nodes["Stormwind City"]
    t:assertEqual("city", stormwind.nodeType, "Stormwind is a city node")
    t:assertEqual(84, stormwind.mapID, "Stormwind mapID is 84")
end)

T:run("BuildGraph creates portal connections from hubs", function(t)
    resetState()
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Stormwind Portal Room should be a hub node
    t:assertNotNil(graph.nodes["Stormwind Portal Room"], "SW Portal Room node exists")

    -- Check that the portal room has outgoing edges
    local edges = graph:GetNeighbors("Stormwind Portal Room")
    local edgeCount = 0
    for _ in pairs(edges) do edgeCount = edgeCount + 1 end
    t:assertGreaterThan(edgeCount, 0, "SW Portal Room has outgoing edges")

    -- Specifically check a known portal destination
    -- Stormwind Portal Room has a portal to Dornogal
    local foundDornogal = false
    for dest, edge in pairs(edges) do
        if dest == "Dornogal" then
            foundDornogal = true
            t:assertEqual("portal", edge.edgeType, "Edge to Dornogal is portal type")
        end
    end
    t:assertTrue(foundDornogal, "Portal Room has edge to Dornogal")
end)

T:run("BuildGraph adds player teleport edges for known spells", function(t)
    resetState()
    -- Make the player a Mage who knows Teleport: Dalaran - Northrend (53140)
    -- Using a destination on a DIFFERENT map than the player (map 84)
    -- to avoid ConnectSameMapNodes overwriting the teleport edge with walk
    MockWoW.config.knownSpells = { [53140] = true }

    -- Scan inventory so PlayerInventory picks up the spell
    QR.PlayerInventory:ScanAll()

    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Player Location node should exist
    t:assertNotNil(graph.nodes["Player Location"], "Player Location node exists")

    -- Check for teleport edge from Player Location
    -- Teleport: Dalaran - Northrend goes to mapID 125
    local edges = graph:GetNeighbors("Player Location")
    local foundTeleportEdge = false
    for dest, edge in pairs(edges) do
        if edge.edgeType == "teleport" and edge.data and edge.data.teleportData then
            if edge.data.teleportData.mapID == 125 then
                foundTeleportEdge = true
            end
        end
    end
    t:assertTrue(foundTeleportEdge, "Player has teleport edge to Dalaran (mapID 125)")
end)

T:run("BuildGraph creates walking edges between same-map nodes", function(t)
    resetState()
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Stormwind City and Stormwind Portal Room are both on mapID 84
    -- ConnectSameMapNodes should have created a walk edge between them
    local edge = graph:GetEdge("Stormwind City", "Stormwind Portal Room")
    if not edge then
        edge = graph:GetEdge("Stormwind Portal Room", "Stormwind City")
    end
    t:assertNotNil(edge, "Walk edge exists between same-map nodes")
    t:assertEqual("walk", edge.edgeType, "Same-map edge is walk type")
    t:assertGreaterThan(edge.weight, 0, "Walk edge has positive weight")
end)

-------------------------------------------------------------------------------
-- 2. Same-Zone Routing
-------------------------------------------------------------------------------

T:run("Same-zone routing: player on map 84, destination on map 84", function(t)
    resetState()
    -- Player is in Stormwind (mapID 84) at position (0.5, 0.5)
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    local result = QR.PathCalculator:CalculatePath(84, 0.6, 0.7)

    t:assertNotNil(result, "Path found for same-zone destination")
    t:assertNotNil(result.steps, "Steps are returned")
    t:assertGreaterThan(#result.steps, 0, "At least one step")

    -- The result should involve walking, not teleporting
    -- Check that totalTime is reasonable for same-zone travel
    t:assertGreaterThan(result.totalTime, 0, "Total time is positive")
end)

T:run("Same-zone: two nodes on same map get correct walk time", function(t)
    resetState()
    -- Manually build a graph with two nodes on the same map
    local g = QR.Graph:New()
    g:AddNode("A", { mapID = 84, x = 0.0, y = 0.0 })
    g:AddNode("B", { mapID = 84, x = 1.0, y = 0.0 })

    -- Use TravelTime to get expected distance
    local expectedTime = QR.TravelTime:EstimateWalkingTime(0.0, 0.0, 1.0, 0.0, false)
    t:assertGreaterThan(expectedTime, 0, "Expected walk time is positive")

    -- Add a walking edge and verify time matches
    g:AddBidirectionalEdge("A", "B", expectedTime, "walk")

    local path, cost = g:FindShortestPath("A", "B")
    t:assertNotNil(path, "Path found between same-map nodes")
    t:assertEqual(expectedTime, cost, "Path cost equals walk time")
end)

-------------------------------------------------------------------------------
-- 3. Multi-Hop Teleport Routes
-------------------------------------------------------------------------------

T:run("Multi-hop: Mage teleport to Dalaran then portal to Stormwind", function(t)
    resetState()
    -- Player is a Mage in a remote location (Borean Tundra, mapID 114)
    MockWoW.config.currentMapID = 114
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5

    -- Mage knows Teleport: Dalaran - Northrend (53140)
    MockWoW.config.knownSpells = { [53140] = true }
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Calculate path to Stormwind (mapID 84)
    local result = QR.PathCalculator:CalculatePath(84, 0.5, 0.87)

    t:assertNotNil(result, "Path found from Borean Tundra to Stormwind")
    t:assertNotNil(result.steps, "Steps present")
    t:assertGreaterThan(#result.steps, 0, "Has at least one step")

    -- The path should include a teleport step
    local hasTeleport = false
    for _, step in ipairs(result.steps) do
        if step.type == "teleport" then
            hasTeleport = true
            break
        end
    end
    t:assertTrue(hasTeleport, "Route includes a teleport step")
end)

T:run("Multi-hop: Dalaran Hearthstone toy reaches Dalaran", function(t)
    resetState()
    -- Player is in a remote location, owns Dalaran Hearthstone toy
    MockWoW.config.currentMapID = 114  -- Borean Tundra
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerClassName = "Mage"

    -- Own the Dalaran Hearthstone toy (itemID 140192)
    MockWoW.config.ownedToys = { [140192] = true }
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Calculate path to Dalaran (Broken Isles, mapID 627)
    local result = QR.PathCalculator:CalculatePath(627, 0.5, 0.53)

    t:assertNotNil(result, "Path found to Dalaran Broken Isles via toy")
    t:assertNotNil(result.steps, "Steps present")

    -- Should include a teleport step using the Dalaran Hearthstone
    local hasTeleport = false
    for _, step in ipairs(result.steps) do
        if step.type == "teleport" then
            hasTeleport = true
        end
    end
    t:assertTrue(hasTeleport, "Route uses Dalaran Hearthstone teleport")
end)

-------------------------------------------------------------------------------
-- 4. Cross-Continent Routing
-------------------------------------------------------------------------------

T:run("Cross-continent: route from Stormwind to Valdrakken via portals", function(t)
    resetState()
    -- Player is in Stormwind (Eastern Kingdoms)
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Route to Valdrakken (Dragon Isles, mapID 2112)
    -- Valdrakken is a node in the graph with portals from SW Portal Room
    local result = QR.PathCalculator:CalculatePath(2112, 0.58, 0.35)

    t:assertNotNil(result, "Path found to Valdrakken (cross-continent)")
    t:assertNotNil(result.steps, "Steps present")
    t:assertGreaterThan(#result.steps, 0, "Has at least one step")

    -- The path should involve portal steps (not just walking)
    local hasPortal = false
    for _, step in ipairs(result.steps) do
        if step.type == "portal" then
            hasPortal = true
            break
        end
    end
    t:assertTrue(hasPortal, "Cross-continent route uses portals")
end)

T:run("Cross-continent: route to Dalaran Northrend via portal chain", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Route to Dalaran Northrend (mapID 125)
    local result = QR.PathCalculator:CalculatePath(125, 0.49, 0.47)

    t:assertNotNil(result, "Path found to Dalaran Northrend")
    t:assertNotNil(result.steps, "Steps present")

    -- Should go: Player -> walk to SW Portal Room -> portal to Dalaran
    local hasPortal = false
    for _, step in ipairs(result.steps) do
        if step.type == "portal" then
            hasPortal = true
        end
    end
    t:assertTrue(hasPortal, "Route uses portal to reach Dalaran Northrend")
end)

T:run("ConnectViaContinentRouting creates hub connections", function(t)
    resetState()
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Add a test node on a map in Eastern Kingdoms that has no same-map node
    -- (e.g. Arathi Highlands, mapID 14)
    graph:AddNode("TestNode", {
        mapID = 14,
        x = 0.5,
        y = 0.5,
        nodeType = "destination",
    })

    -- Call ConnectNearbyNodes - since no other node is on mapID 14,
    -- it should invoke ConnectViaContinentRouting
    QR.PathCalculator:ConnectNearbyNodes("TestNode", 14, 0.5, 0.5)

    -- Verify TestNode has edges now
    local edges = graph:GetNeighbors("TestNode")
    local edgeCount = 0
    for _ in pairs(edges) do edgeCount = edgeCount + 1 end
    t:assertGreaterThan(edgeCount, 0, "ConnectViaContinentRouting created edges")

    -- Clean up
    graph:RemoveNode("TestNode")
end)

-------------------------------------------------------------------------------
-- 5. Flyability Per-Map
-------------------------------------------------------------------------------

T:run("ConnectSameMapNodes: player's current map uses fly speed", function(t)
    resetState()
    -- Player is on mapID 84, flyable
    MockWoW.config.currentMapID = 84
    MockWoW.config.isFlyableArea = true
    -- Fire zone change to ensure flyable cache picks up new value
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")

    -- Build a minimal graph with two nodes on mapID 84
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph
    graph:AddNode("NodeA", { mapID = 84, x = 0.0, y = 0.0 })
    graph:AddNode("NodeB", { mapID = 84, x = 0.5, y = 0.0 })

    -- Also add two nodes on a DIFFERENT map (mapID 87)
    graph:AddNode("NodeC", { mapID = 87, x = 0.0, y = 0.0 })
    graph:AddNode("NodeD", { mapID = 87, x = 0.5, y = 0.0 })

    QR.PathCalculator:ConnectSameMapNodes()

    -- Get edge on player's map (should use fly speed -> lower time)
    local edgeAB = graph:GetEdge("NodeA", "NodeB")
    t:assertNotNil(edgeAB, "Edge A->B created on player's map")

    -- Get edge on remote map (should use ground speed -> higher time)
    local edgeCD = graph:GetEdge("NodeC", "NodeD")
    t:assertNotNil(edgeCD, "Edge C->D created on remote map")

    -- Flying should be faster than ground, so edgeAB.weight < edgeCD.weight
    -- (both have same coordinate distance of 0.5)
    t:assertGreaterThan(edgeCD.weight, edgeAB.weight,
        "Remote map (ground) is slower than player's map (flying)")
end)

T:run("ConnectSameMapNodes: non-flyable area uses ground speed", function(t)
    resetState()
    -- Use mapID 87 (different from the previous test's 84) so the
    -- IsFlyableArea cache key differs and a fresh lookup occurs.
    MockWoW.config.currentMapID = 87
    MockWoW.config.isFlyableArea = false
    -- Fire zone change to ensure flyable cache picks up new value
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")

    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph
    -- Both node pairs on the PLAYER's map (87) and a remote map (125)
    graph:AddNode("NodeA", { mapID = 87, x = 0.0, y = 0.0 })
    graph:AddNode("NodeB", { mapID = 87, x = 0.5, y = 0.0 })

    graph:AddNode("NodeC", { mapID = 125, x = 0.0, y = 0.0 })
    graph:AddNode("NodeD", { mapID = 125, x = 0.5, y = 0.0 })

    QR.PathCalculator:ConnectSameMapNodes()

    local edgeAB = graph:GetEdge("NodeA", "NodeB")
    t:assertNotNil(edgeAB, "Edge A->B created")

    local edgeCD = graph:GetEdge("NodeC", "NodeD")
    t:assertNotNil(edgeCD, "Edge C->D created")

    -- When player map is not flyable, both should use ground speed
    -- so the weights should be equal (same coordinate distance)
    t:assertEqual(edgeAB.weight, edgeCD.weight,
        "Non-flyable player map and remote map have same ground travel time")
end)

-------------------------------------------------------------------------------
-- 6. Edge Cases
-------------------------------------------------------------------------------

T:run("Edge case: no teleports available, walk-only or portal path", function(t)
    resetState()
    -- Player in Stormwind, no spells, no toys, no items
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    MockWoW.config.bagItems = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Destination is also in Stormwind
    local result = QR.PathCalculator:CalculatePath(84, 0.6, 0.7)

    t:assertNotNil(result, "Walk-only path found for same-zone")
    -- Steps should not include teleport type (no teleports available)
    local hasTeleport = false
    for _, step in ipairs(result.steps) do
        if step.type == "teleport" then
            hasTeleport = true
        end
    end
    t:assertFalse(hasTeleport, "No teleport steps when player has no teleports")
end)

T:run("Edge case: destination on same node as player (trivial path)", function(t)
    resetState()
    -- Player at exactly Stormwind City coordinates
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.4965
    MockWoW.config.playerY = 0.8725
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Destination very close to same position
    local result = QR.PathCalculator:CalculatePath(84, 0.4965, 0.8725)

    -- Should still find a path (even if trivial)
    t:assertNotNil(result, "Trivial same-position path found")
    t:assertNotNil(result.totalTime, "Total time is defined")
end)

T:run("Edge case: unreachable destination returns nil", function(t)
    resetState()
    -- Build a minimal graph with no connections to a remote map
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph
    QR.PathCalculator.graphDirty = false

    -- Add only the player node, no other nodes or edges
    graph:AddNode("Player Location", {
        mapID = 84,
        x = 0.5,
        y = 0.5,
        nodeType = "player",
    })

    -- Add an isolated node on a different map with no edges
    graph:AddNode("Isolated", {
        mapID = 99999,
        x = 0.5,
        y = 0.5,
        nodeType = "destination",
    })

    -- Directly run Dijkstra between disconnected nodes
    local path, cost = graph:FindShortestPath("Player Location", "Isolated")
    t:assertNil(path, "No path found between disconnected nodes")
    t:assertNil(cost, "No cost for disconnected nodes")
end)

-------------------------------------------------------------------------------
-- 7. BuildSteps
-------------------------------------------------------------------------------

T:run("BuildSteps: walk step has human-readable action text", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
    graph:AddNode("Stormwind City", { mapID = 84, x = 0.49, y = 0.87 })
    graph:AddEdge("Player Location", "Stormwind City", 30, "walk", {})

    local path = { "Player Location", "Stormwind City" }
    local edges = { { weight = 30, edgeType = "walk", data = {} } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertNotNil(steps, "Steps returned")
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    t:assertNotNil(step.action, "Action text exists")
    -- Walk action should contain "Go to"
    local hasGoTo = step.action:find("Go to") or step.action:find("Gehe zu")
    t:assertNotNil(hasGoTo, "Walk step contains 'Go to' text")
    t:assertEqual("walk", step.type, "Step type is walk")
    t:assertEqual(30, step.time, "Step time is 30")
end)

T:run("BuildSteps: teleport step includes teleport name", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
    graph:AddNode("Dalaran (Northrend)", { mapID = 125, x = 0.49, y = 0.47 })
    graph:AddEdge("Player Location", "Dalaran (Northrend)", 3, "teleport", {
        teleportID = 53140,
        teleportData = {
            name = "Teleport: Dalaran - Northrend",
            mapID = 125,
            x = 0.4947,
            y = 0.4709,
        },
        sourceType = "spell",
    })

    local path = { "Player Location", "Dalaran (Northrend)" }
    local edges = { {
        weight = 3,
        edgeType = "teleport",
        data = {
            teleportID = 53140,
            teleportData = {
                name = "Teleport: Dalaran - Northrend",
                mapID = 125,
                x = 0.4947,
                y = 0.4709,
            },
            sourceType = "spell",
        },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertNotNil(steps, "Steps returned")
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    t:assertEqual("teleport", step.type, "Step type is teleport")
    -- Action should mention the teleport name
    local hasTeleportName = step.action:find("Teleport: Dalaran")
        or step.action:find("teleport")
        or step.action:find("Teleport")
    t:assertNotNil(hasTeleportName, "Teleport step mentions teleport name")
    t:assertEqual(53140, step.teleportID, "teleportID is preserved")
    t:assertEqual("spell", step.sourceType, "sourceType is preserved")
end)

T:run("BuildSteps: portal step says 'Take portal to X'", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Stormwind Portal Room", { mapID = 84, x = 0.49, y = 0.87 })
    graph:AddNode("Dornogal", { mapID = 2339, x = 0.48, y = 0.55 })
    graph:AddEdge("Stormwind Portal Room", "Dornogal", 5, "portal", {
        portalData = { destination = "Dornogal", mapID = 2339 },
    })

    local path = { "Stormwind Portal Room", "Dornogal" }
    local edges = { {
        weight = 5,
        edgeType = "portal",
        data = { portalData = { destination = "Dornogal", mapID = 2339 } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertNotNil(steps, "Steps returned")
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    t:assertEqual("portal", step.type, "Step type is portal")
    -- Should contain "portal" and destination name
    local hasPortal = step.action:find("[Pp]ortal")
    t:assertNotNil(hasPortal, "Portal step mentions 'portal'")
    local hasDornogal = step.action:find("Dornogal")
    t:assertNotNil(hasDornogal, "Portal step mentions destination 'Dornogal'")
end)

T:run("BuildSteps: steps have destMapID, destX, destY for Nav button", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("A", { mapID = 84, x = 0.5, y = 0.5 })
    graph:AddNode("B", { mapID = 2339, x = 0.48, y = 0.55 })
    graph:AddEdge("A", "B", 5, "portal", {
        portalData = { destination = "Dornogal", mapID = 2339 },
    })

    local path = { "A", "B" }
    local edges = { {
        weight = 5,
        edgeType = "portal",
        data = { portalData = { destination = "Dornogal", mapID = 2339 } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    t:assertNotNil(step.destMapID, "destMapID is set")
    t:assertEqual(2339, step.destMapID, "destMapID is correct (2339)")
    t:assertNotNil(step.destX, "destX is set")
    t:assertNotNil(step.destY, "destY is set")
end)

T:run("BuildSteps: boat step mentions 'boat'", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Harbor", { mapID = 84, x = 0.23, y = 0.57 })
    graph:AddNode("Northrend Dock", { mapID = 114, x = 0.60, y = 0.70 })
    graph:AddEdge("Harbor", "Northrend Dock", 120, "boat", {
        transportData = { name = "Stormwind to Borean Tundra" },
    })

    local path = { "Harbor", "Northrend Dock" }
    local edges = { {
        weight = 120,
        edgeType = "boat",
        data = { transportData = { name = "Stormwind to Borean Tundra" } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")
    t:assertEqual("boat", steps[1].type, "Step type is boat")
    local hasBoat = steps[1].action:find("[Bb]oat") or steps[1].action:find("Schiff")
    t:assertNotNil(hasBoat, "Boat step mentions 'boat' or 'Schiff'")
end)

T:run("BuildSteps: zeppelin step mentions 'zeppelin'", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Zeppelin Tower", { mapID = 85, x = 0.51, y = 0.56 })
    graph:AddNode("Tirisfal", { mapID = 18, x = 0.62, y = 0.59 })
    graph:AddEdge("Zeppelin Tower", "Tirisfal", 90, "zeppelin", {
        transportData = { name = "Orgrimmar to Undercity" },
    })

    local path = { "Zeppelin Tower", "Tirisfal" }
    local edges = { {
        weight = 90,
        edgeType = "zeppelin",
        data = { transportData = { name = "Orgrimmar to Undercity" } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")
    t:assertEqual("zeppelin", steps[1].type, "Step type is zeppelin")
    local hasZeppelin = steps[1].action:find("[Zz]eppelin")
    t:assertNotNil(hasZeppelin, "Zeppelin step mentions 'zeppelin'")
end)

T:run("BuildSteps: portal step navMapID points to FROM node (entrance)", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    -- Portal FROM Dalaran (Broken Isles, map 627) TO Shattrath City (map 111)
    graph:AddNode("Dalaran Portal Room", { mapID = 627, x = 0.46, y = 0.63 })
    graph:AddNode("Shattrath City", { mapID = 111, x = 0.57, y = 0.48 })
    graph:AddEdge("Dalaran Portal Room", "Shattrath City", 5, "portal", {
        portalData = { destination = "Shattrath City", mapID = 111 },
    })

    local path = { "Dalaran Portal Room", "Shattrath City" }
    local edges = { {
        weight = 5,
        edgeType = "portal",
        data = { portalData = { destination = "Shattrath City", mapID = 111 } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    -- destMapID should point to destination (Shattrath, 111) for route progress tracking
    t:assertEqual(111, step.destMapID, "destMapID is destination (Shattrath 111)")
    -- navMapID should point to FROM node (Dalaran, 627) where player needs to walk
    t:assertEqual(627, step.navMapID, "navMapID is FROM node (Dalaran 627)")
    t:assertTrue(math.abs(step.navX - 0.46) < 0.01, "navX is FROM node X coordinate")
    t:assertTrue(math.abs(step.navY - 0.63) < 0.01, "navY is FROM node Y coordinate")
end)

T:run("BuildSteps: walk step navMapID equals destMapID", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
    graph:AddNode("Stormwind Portal Room", { mapID = 84, x = 0.49, y = 0.87 })
    graph:AddEdge("Player Location", "Stormwind Portal Room", 30, "walk", {})

    local path = { "Player Location", "Stormwind Portal Room" }
    local edges = { { weight = 30, edgeType = "walk", data = {} } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    -- For walk steps, nav and dest should be the same (destination)
    t:assertEqual(step.destMapID, step.navMapID, "Walk step: navMapID equals destMapID")
    t:assertEqual(step.destX, step.navX, "Walk step: navX equals destX")
    t:assertEqual(step.destY, step.navY, "Walk step: navY equals destY")
end)

T:run("BuildSteps: boat step navMapID points to FROM node (dock)", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("Harbor", { mapID = 84, x = 0.23, y = 0.57 })
    graph:AddNode("Northrend Dock", { mapID = 114, x = 0.60, y = 0.70 })
    graph:AddEdge("Harbor", "Northrend Dock", 120, "boat", {
        transportData = { name = "Stormwind to Borean Tundra" },
    })

    local path = { "Harbor", "Northrend Dock" }
    local edges = { {
        weight = 120,
        edgeType = "boat",
        data = { transportData = { name = "Stormwind to Borean Tundra" } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")

    local step = steps[1]
    -- destMapID = destination (Borean Tundra 114)
    t:assertEqual(114, step.destMapID, "destMapID is destination (Borean Tundra 114)")
    -- navMapID = FROM node (Harbor in Stormwind 84) where player boards
    t:assertEqual(84, step.navMapID, "navMapID is FROM node (Harbor 84)")
end)

T:run("BuildSteps: tram step mentions 'tram'", function(t)
    resetState()
    QR.PathCalculator.graph = QR.Graph:New()
    local graph = QR.PathCalculator.graph

    graph:AddNode("SW Tram", { mapID = 84, x = 0.64, y = 0.08 })
    graph:AddNode("IF Tram", { mapID = 87, x = 0.77, y = 0.51 })
    graph:AddEdge("SW Tram", "IF Tram", 60, "tram", {
        transportData = { name = "Deeprun Tram" },
    })

    local path = { "SW Tram", "IF Tram" }
    local edges = { {
        weight = 60,
        edgeType = "tram",
        data = { transportData = { name = "Deeprun Tram" } },
    } }

    local steps = QR.PathCalculator:BuildSteps(path, edges)
    t:assertEqual(1, #steps, "One step")
    t:assertEqual("tram", steps[1].type, "Step type is tram")
    -- Should contain "Tram" or "Tiefenbahn" (German)
    local hasTram = steps[1].action:find("[Tt]ram") or steps[1].action:find("Tiefenbahn")
    t:assertNotNil(hasTram, "Tram step mentions 'Tram'")
end)

-------------------------------------------------------------------------------
-- 8. Full Integration: end-to-end CalculatePath
-------------------------------------------------------------------------------

T:run("Integration: Mage in SW with all teleports, route to Dornogal", function(t)
    resetState()
    -- Alliance Mage in Stormwind
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5

    -- Knows Teleport: Dornogal (446540) and Teleport: Stormwind (3561)
    MockWoW.config.knownSpells = {
        [446540] = true,
        [3561] = true,
    }
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    local result = QR.PathCalculator:CalculatePath(2339, 0.48, 0.55)

    t:assertNotNil(result, "Path found to Dornogal")
    t:assertNotNil(result.totalTime, "totalTime present")
    t:assertNotNil(result.steps, "steps present")
    t:assertGreaterThan(#result.steps, 0, "Has at least one step")
end)

T:run("Integration: Warrior with no teleports, route stays connected", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.87
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    MockWoW.config.bagItems = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    -- Route to Ironforge (mapID 87), reachable via portal from SW Portal Room
    local result = QR.PathCalculator:CalculatePath(87, 0.27, 0.73)

    t:assertNotNil(result, "Warrior can route to Ironforge via portals")
    t:assertNotNil(result.steps, "Steps present")
    t:assertGreaterThan(#result.steps, 0, "Has at least one step")

    -- Path should include a portal step (SW Portal Room -> Ironforge)
    local hasPortal = false
    for _, step in ipairs(result.steps) do
        if step.type == "portal" then
            hasPortal = true
        end
    end
    t:assertTrue(hasPortal, "Route uses portal from Stormwind Portal Room")
end)

T:run("Integration: faction filtering works correctly for Alliance", function(t)
    resetState()
    -- The test runner initializes with Alliance faction, and the module-level
    -- cached faction persists as Alliance for the entire test session.
    -- Verify Alliance-specific graph structure.
    MockWoW.config.currentMapID = 84
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    -- Alliance portal hubs should exist
    t:assertNotNil(graph.nodes["Stormwind Portal Room"], "SW Portal Room exists for Alliance")

    -- Horde-only portal hub should NOT exist
    t:assertNil(graph.nodes["Orgrimmar Portal Room"],
        "Orgrimmar Portal Room absent for Alliance")

    -- Alliance capital city
    t:assertNotNil(graph.nodes["Stormwind City"], "Stormwind City exists")
    t:assertNotNil(graph.nodes["Ironforge"], "Ironforge exists")
    t:assertNotNil(graph.nodes["Exodar"], "Exodar exists")

    -- Neutral hubs should exist
    t:assertNotNil(graph.nodes["Dornogal"], "Dornogal (neutral) exists")
    t:assertNotNil(graph.nodes["Oribos"], "Oribos (neutral) exists")
end)

T:run("Integration: CalculatePath returns expected result structure", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    local result = QR.PathCalculator:CalculatePath(84, 0.6, 0.7)

    t:assertNotNil(result, "Result is not nil")
    t:assertNotNil(result.path, "result.path exists")
    t:assertNotNil(result.totalTime, "result.totalTime exists")
    t:assertNotNil(result.edges, "result.edges exists")
    t:assertNotNil(result.steps, "result.steps exists")

    -- path is an array of node names
    t:assertGreaterThan(#result.path, 0, "path has entries")
    -- totalTime is a number
    t:assertEqual("number", type(result.totalTime), "totalTime is a number")
    -- steps is an array
    t:assertEqual("table", type(result.steps), "steps is a table")
end)

T:run("Graph is cleaned up after CalculatePath (destination node removed)", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true
    QR.PathCalculator:CalculatePath(84, 0.6, 0.7)

    -- The destination node should have been removed after CalculatePath
    local graph = QR.PathCalculator.graph
    t:assertNotNil(graph, "Graph still exists after CalculatePath")

    -- Verify the graph still has its base nodes intact
    t:assertNotNil(graph.nodes["Stormwind City"], "Base nodes still present after cleanup")
    t:assertNotNil(graph.nodes["Player Location"], "Player Location still present")
end)

T:run("GraphDirty triggers rebuild on next CalculatePath", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    -- First calculation builds the graph
    QR.PathCalculator.graphDirty = true
    local result1 = QR.PathCalculator:CalculatePath(84, 0.6, 0.7)
    t:assertNotNil(result1, "First path found")
    t:assertFalse(QR.PathCalculator.graphDirty, "Graph is clean after build")

    -- Mark dirty and calculate again
    QR.PathCalculator:OnInventoryChanged()
    t:assertTrue(QR.PathCalculator.graphDirty, "Graph marked dirty by OnInventoryChanged")

    local result2 = QR.PathCalculator:CalculatePath(84, 0.6, 0.7)
    t:assertNotNil(result2, "Second path found after rebuild")
    t:assertFalse(QR.PathCalculator.graphDirty, "Graph clean again after rebuild")
end)

T:run("Portal time uses TravelTime module constants", function(t)
    resetState()
    -- Verify portal time matches the expected constant
    local portalTime = QR.TravelTime:GetPortalTime()
    t:assertEqual(5, portalTime, "Portal loading time is 5 seconds")

    -- Verify transport times
    local boatTime = QR.TravelTime:GetTransportTime("boat")
    t:assertEqual(180, boatTime, "Boat travel time is 180 seconds")

    local tramTime = QR.TravelTime:GetTransportTime("tram")
    t:assertEqual(60, tramTime, "Tram travel time is 60 seconds")

    local zepTime = QR.TravelTime:GetTransportTime("zeppelin")
    t:assertEqual(90, zepTime, "Zeppelin travel time is 90 seconds")
end)

T:run("Multiple CalculatePath calls don't leak destination nodes", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.PathCalculator.graphDirty = true

    -- Count initial nodes
    QR.PathCalculator:BuildGraph()
    local initialNodeCount = 0
    for _ in pairs(QR.PathCalculator.graph.nodes) do
        initialNodeCount = initialNodeCount + 1
    end

    -- Run several CalculatePath calls
    QR.PathCalculator:CalculatePath(84, 0.1, 0.1)
    QR.PathCalculator:CalculatePath(84, 0.9, 0.9)
    QR.PathCalculator:CalculatePath(87, 0.3, 0.7)

    -- Count nodes after multiple calculations
    local finalNodeCount = 0
    for _ in pairs(QR.PathCalculator.graph.nodes) do
        finalNodeCount = finalNodeCount + 1
    end

    -- Node count should not grow (destinations should be cleaned up)
    t:assertEqual(initialNodeCount, finalNodeCount,
        "Node count unchanged after multiple CalculatePath calls (" ..
        initialNodeCount .. " initial, " .. finalNodeCount .. " final)")
end)

-------------------------------------------------------------------------------
-- 3.6: Horde Player Path Tests
-- Since cachedPlayerFaction is module-local and cached as "Alliance" from
-- test runner init, we test Horde routing at the graph level by manually
-- constructing a Horde-style graph and verifying correct pathfinding.
-- We also test that GetAvailablePortals responds to faction config changes.
-------------------------------------------------------------------------------

T:run("Horde: GetAvailablePortals returns Horde portal hubs", function(t)
    resetState()
    -- Switch mock faction to Horde
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()
    t:assertNotNil(portals, "GetAvailablePortals returns a table")
    t:assertNotNil(portals.hubs, "portals.hubs exists")

    -- Should have Orgrimmar Portal Room (Horde hub)
    local hasOrgPortalRoom = portals.hubs["Orgrimmar Portal Room"] ~= nil
    t:assertTrue(hasOrgPortalRoom,
        "Orgrimmar Portal Room available for Horde")

    -- Should NOT have Stormwind Portal Room (Alliance hub)
    local hasSWPortalRoom = portals.hubs["Stormwind Portal Room"] ~= nil
    t:assertFalse(hasSWPortalRoom,
        "Stormwind Portal Room NOT available for Horde")

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)

T:run("Horde: Orgrimmar Portal Room has portal destinations", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()
    local orgHub = portals.hubs["Orgrimmar Portal Room"]
    t:assertNotNil(orgHub, "Orgrimmar Portal Room hub data exists")
    t:assertNotNil(orgHub.portals, "Orgrimmar Portal Room has portals list")
    t:assertGreaterThan(#orgHub.portals, 0,
        "Orgrimmar Portal Room has at least one portal")

    -- Check that Dornogal is a destination (neutral, available to all)
    local foundDornogal = false
    for _, portal in ipairs(orgHub.portals) do
        if portal.destination == "Dornogal" then
            foundDornogal = true
        end
    end
    t:assertTrue(foundDornogal,
        "Orgrimmar Portal Room has portal to Dornogal")

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)

T:run("Horde: graph pathfinding works with Horde portal network", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()
    MockWoW.config.currentMapID = 85  -- Orgrimmar

    -- Build a Horde-style graph manually
    local g = QR.Graph:New()

    -- Horde cities
    g:AddNode("Player Location", { mapID = 85, x = 0.47, y = 0.39 })
    g:AddNode("Orgrimmar", { mapID = 85, x = 0.469, y = 0.387 })
    g:AddNode("Orgrimmar Portal Room", { mapID = 85, x = 0.44, y = 0.38 })
    g:AddNode("Dornogal", { mapID = 2339, x = 0.485, y = 0.552 })
    g:AddNode("Valdrakken", { mapID = 2112, x = 0.5835, y = 0.3535 })

    -- Walking edges (same map)
    g:AddBidirectionalEdge("Player Location", "Orgrimmar", 10, "walk")
    g:AddBidirectionalEdge("Orgrimmar", "Orgrimmar Portal Room", 15, "walk")
    g:AddBidirectionalEdge("Player Location", "Orgrimmar Portal Room", 20, "walk")

    -- Portal edges from Orgrimmar Portal Room
    g:AddEdge("Orgrimmar Portal Room", "Dornogal", 5, "portal")
    g:AddEdge("Orgrimmar Portal Room", "Valdrakken", 5, "portal")

    -- Find path from Player to Dornogal
    local path, cost, edges = g:FindShortestPath("Player Location", "Dornogal")
    t:assertNotNil(path, "Horde path to Dornogal found")
    t:assertGreaterThan(#path, 1, "Path has multiple nodes")

    -- Verify path goes through Orgrimmar Portal Room
    local throughPortalRoom = false
    for _, node in ipairs(path) do
        if node == "Orgrimmar Portal Room" then
            throughPortalRoom = true
        end
    end
    t:assertTrue(throughPortalRoom, "Path routes through Orgrimmar Portal Room")

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)

T:run("Horde: Horde spell teleports work in graph", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    -- Build a graph with a Horde teleport spell
    local g = QR.Graph:New()
    g:AddNode("Player Location", { mapID = 85, x = 0.5, y = 0.5 })
    g:AddNode("Orgrimmar", { mapID = 85, x = 0.469, y = 0.387 })
    g:AddNode("Dazar'alor", { mapID = 1165, x = 0.502, y = 0.408 })

    -- Horde Mage teleport to Dazar'alor
    g:AddEdge("Player Location", "Dazar'alor", 3, "teleport", {
        teleportID = 281404,
        teleportData = { name = "Teleport: Dazar'alor", mapID = 1165 },
        sourceType = "spell",
    })

    -- Walking edge
    g:AddBidirectionalEdge("Player Location", "Orgrimmar", 10, "walk")

    local path, cost = g:FindShortestPath("Player Location", "Dazar'alor")
    t:assertNotNil(path, "Path found using Horde teleport spell")
    t:assertEqual(3, cost, "Direct teleport cost is 3 seconds")
    t:assertEqual(2, #path, "Direct teleport is 2-node path")

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)

T:run("Horde: neutral hubs accessible to Horde via GetAvailablePortals", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()

    -- Check that neutral hubs are accessible
    -- Dalaran (Broken Isles) has a hub with faction "both"
    local foundNeutralHub = false
    for hubName, hubData in pairs(portals.hubs) do
        if hubData.faction == "both" then
            foundNeutralHub = true
            break
        end
    end
    t:assertTrue(foundNeutralHub, "At least one neutral hub accessible to Horde")

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)

T:run("Horde: faction-specific portal filtering excludes Alliance-only portals", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()

    -- Verify no Alliance-only hubs are present
    for hubName, hubData in pairs(portals.hubs) do
        local isAllianceOnly = hubData.faction == "Alliance"
        t:assertFalse(isAllianceOnly,
            "Hub " .. hubName .. " should not be Alliance-only for Horde player")
    end

    -- Restore
    MockWoW.config.playerFaction = "Alliance"
end)
