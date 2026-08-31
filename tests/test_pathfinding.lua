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

-------------------------------------------------------------------------------
-- Continent routing must not destroy in-city walk edges
-------------------------------------------------------------------------------

-- Regression: ConnectNearbyNodes writes correct same-map walk edges and then
-- calls ConnectViaContinentRouting, whose hub strategy iterated every node
-- sharing the hub's mapID. For a destination on the hub map itself,
-- EstimateSameContinentTravel(hub, hub) returns 0, AddEdge clamps that to the
-- 0.001 epsilon, and the assignment overwrote the walk edge written moments
-- earlier. The final in-city approach then cost nothing, so the ETA was short
-- by the whole walk and Dijkstra treated every node on the map as the target.
T:run("ConnectNearbyNodes: hub routing does not overwrite the in-city walk edge", function(t)
    resetState()
    local graph = QR.PathCalculator:BuildGraph()

    local anchor = graph.nodes["Stormwind City"]
    t:assertNotNil(anchor, "Stormwind City node exists")

    -- A destination on the far side of the same map (Stormwind, uiMapID 84),
    -- which is also the Alliance continent hub for the Eastern Kingdoms.
    graph:AddNode("QR Test Target", { mapID = 84, x = 0.95, y = 0.95 })
    QR.PathCalculator:ConnectNearbyNodes("QR Test Target", 84, 0.95, 0.95)

    local edge = graph:GetEdge("QR Test Target", "Stormwind City")
        or graph:GetEdge("Stormwind City", "QR Test Target")
    t:assertNotNil(edge, "An edge to Stormwind City exists")

    t:assertEqual("walk", edge.edgeType,
        "Edge to a node on the same map stays a walk edge (got: " .. tostring(edge.edgeType) .. ")")
    t:assertTrue(edge.weight > 1,
        "In-city walk keeps its real cost instead of the 0.001 epsilon (got: " .. tostring(edge.weight) .. ")")
end)

-------------------------------------------------------------------------------
-- The player node must not keep walk edges from the map it was built on
-------------------------------------------------------------------------------

-- Regression: UpdatePlayerLocation rewrote only the node's coordinates, while
-- its walk edges were created once in BuildGraph against the map the player
-- stood on then. Nothing marks the graph dirty on movement, so every route
-- computed between arriving in a new zone and the next bag update started with
-- a walk into the zone the player had just left.
T:run("UpdatePlayerLocation: zone change drops the old map's walk edges", function(t)
    resetState()
    MockWoW.config.currentMapID = 84  -- Stormwind
    local graph = QR.PathCalculator:BuildGraph()

    -- Find a node the player node is connected to by a walk edge on map 84.
    local staleNeighbour
    for otherName, edge in pairs(graph.edges["Player Location"] or {}) do
        local other = graph.nodes[otherName]
        if other and other.mapID == 84 and edge.edgeType == "walk" then
            staleNeighbour = otherName
            break
        end
    end
    t:assertNotNil(staleNeighbour, "Player node starts with a walk edge on map 84")

    -- The player hearths to another continent.
    MockWoW.config.currentMapID = 2339  -- Dornogal, Khaz Algar
    QR.PathCalculator:UpdatePlayerLocation()

    t:assertEqual(2339, graph.nodes["Player Location"].mapID, "Player node follows the move")

    local stale = graph.edges["Player Location"][staleNeighbour]
    t:assertNil(stale,
        "Walk edge to the old map's node is gone (kept: " .. tostring(stale and stale.edgeType) .. ")")
end)

-------------------------------------------------------------------------------
-- Teleport edge weights must follow live cooldown state
-------------------------------------------------------------------------------

-- Regression: AddPlayerTeleportEdges bakes the remaining cooldown into the edge
-- weight and only runs inside BuildGraph. No cooldown event marks the graph
-- dirty, so a teleport used after the build stayed priced as ready and kept
-- being chosen as step 1 — the "consider cooldowns" setting silently did
-- nothing after the first build.
T:run("CalculatePath: teleport edges are re-priced against live cooldowns", function(t)
    resetState()
    QR.db = QR.db or {}
    QR.db.considerCooldowns = true
    QR.db.loadingScreenTime = 0

    local spellID = 3565  -- a known teleport spell in the fixtures
    MockWoW.config.knownSpells[spellID] = true
    QR.PlayerInventory:ScanAll()

    local graph = QR.PathCalculator:BuildGraph()

    -- Find any teleport edge out of the player node and remember its weight.
    local edgeName, before
    for otherName, edge in pairs(graph.edges["Player Location"] or {}) do
        if edge.edgeType == "teleport" and edge.data and edge.data.teleportID then
            edgeName, before = otherName, edge
            break
        end
    end
    t:assertNotNil(edgeName, "Player node has at least one teleport edge")

    local weightWhenReady = before.weight
    local teleportID = before.data.teleportID

    -- The teleport goes on a long cooldown after the graph was built.
    MockWoW.config.spellCooldowns[teleportID] = { start = GetTime(), duration = 1800 }
    MockWoW.config.itemCooldowns[teleportID] = { start = GetTime(), duration = 1800 }

    -- Drive CalculatePath rather than calling RefreshTeleportEdgeWeights
    -- directly: the wiring into CalculatePath is the fix, and calling the method
    -- by hand guards the method while leaving the wiring untested. Deleting the
    -- call site used to keep this test green.
    MockWoW.config.currentMapID = 84
    QR.PathCalculator:CalculatePath(85, 0.5, 0.5, "Repricing Target")

    local after = graph.edges["Player Location"][edgeName]
    t:assertTrue(after.weight > weightWhenReady,
        "Weight rises once the teleport is on cooldown (was " .. tostring(weightWhenReady)
            .. ", now " .. tostring(after.weight) .. ")")
end)

-------------------------------------------------------------------------------
-- Continent routing must not fall through to the cross-continent last resort
-------------------------------------------------------------------------------

-- Regression: the guard that stops coarse "travel" estimates from overwriting
-- measured walk edges was applied after a candidate had been chosen, and a
-- refusal left connectedSomething false. The node then reached Strategy 4,
-- where GetCrossContinentTravel returns 0 for a continent to itself and
-- baseTime - 60 goes negative, which AddEdge clamps to the 0.001 epsilon. A
-- destination inside a capital looked one free hop away: Ironforge to a point
-- in Stormwind came back as a single 19s step with the Deeprun Tram gone.
T:run("CalculatePath: a destination inside a capital keeps its real legs", function(t)
    resetState()
    MockWoW.config.currentMapID = 87  -- Ironforge
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true

    local result = QR.PathCalculator:CalculatePath(84, 0.60, 0.75, "Stormwind Target")
    t:assertNotNil(result, "a route from Ironforge to Stormwind exists")
    if not result then return end

    t:assertGreaterThan(#(result.steps or {}), 1,
        "the route has more than one step (got " .. tostring(#(result.steps or {})) .. ")")
    t:assertGreaterThan(result.totalTime or 0, 60,
        "crossing between two capitals is not priced under a minute (got "
            .. tostring(result.totalTime) .. "s)")
end)

T:run("BuildGraph: no travel edge is cheaper than a second", function(t)
    resetState()
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()

    local offenders = {}
    for from, targets in pairs(graph.edges) do
        for to, edge in pairs(targets) do
            if edge.edgeType == "travel" and edge.weight < 1 then
                offenders[#offenders + 1] = from .. " -> " .. to
            end
        end
    end
    t:assertEqual(0, #offenders,
        "no sub-second travel edge (" .. table.concat(offenders, ", ") .. ")")
end)

-------------------------------------------------------------------------------
-- The node index must not survive the graph it describes
-------------------------------------------------------------------------------

-- Regression: BuildGraph replaced self.graph but left self.nodeIndex in place.
-- The index then handed back node names belonging to a discarded graph object,
-- Graph:AddEdge refused them, and the edges vanished with no error.
T:run("BuildGraph: a build that skips the index rebuild still produces every edge", function(t)
    resetState()
    local function build()
        QR.PathCalculator.graph = nil
        QR.PathCalculator.graphDirty = true
        local g = QR.PathCalculator:BuildGraph()
        local edges = 0
        for _, targets in pairs(g.edges) do
            for _ in pairs(targets) do edges = edges + 1 end
        end
        return edges
    end

    local wasScanned = QR.DungeonData and QR.DungeonData.scanned

    -- First build populates the index.
    build()

    -- AddDungeonNodes returns early when the Encounter Journal has not been
    -- scanned, and BuildNodeIndex sits after that return, so this build never
    -- refreshes the index. If the previous one is left in place it names nodes
    -- belonging to a graph object that no longer exists, Graph:AddEdge refuses
    -- them, and the edges disappear with no error.
    if QR.DungeonData then QR.DungeonData.scanned = false end
    local withPossiblyStaleIndex = build()

    -- The same build again with the index explicitly cleared: this is what the
    -- edge count has to be.
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PathCalculator.nodeIndex = nil
    local withFreshIndex = build()

    if QR.DungeonData then QR.DungeonData.scanned = wasScanned end

    t:assertEqual(withFreshIndex, withPossiblyStaleIndex,
        "a build following a different graph loses no edges ("
            .. withPossiblyStaleIndex .. " vs " .. withFreshIndex .. ")")
end)

-------------------------------------------------------------------------------
-- Moving must not destroy the player's teleport edges
-------------------------------------------------------------------------------

-- Regression: ReconnectPlayerNode drops the player node's walk and travel edges
-- when the player moves and keeps the teleport edges on purpose -- its own
-- docstring says so. It then calls ConnectNearbyNodes, which wrote a walk edge
-- to every node on the player's map and in every adjacent zone with no check,
-- and the graph holds one edge per node pair. So a mage standing in Elwynn
-- Forest lost "Teleport: Stormwind" after a single step: the edge became a walk
-- edge, the route step became type=walk with no teleportID, and it therefore
-- got no secure Use button either. Nothing rebuilds the graph on movement --
-- only bag, toy, spell, equipment and restriction events do -- so it stayed
-- gone until one of those happened to fire.
T:run("Movement does not overwrite the player's teleport edges", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerClassName = "Mage"
    MockWoW.config.knownSpells = { [3561] = true }  -- Teleport: Stormwind
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 37                -- Elwynn Forest
    MockWoW.config.playerX, MockWoW.config.playerY = 0.40, 0.60
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()

    local function playerEdgeType()
        local graph = QR.PathCalculator.graph
        local edge = graph and graph:GetEdge("Player Location", "Stormwind City")
        return edge and edge.edgeType or "no edge"
    end

    t:assertEqual("teleport", playerEdgeType(),
        "the teleport edge exists as built (got: " .. playerEdgeType() .. ")")

    local before = QR.PathCalculator:CalculatePath(84, 0.4965, 0.8725, "Stormwind City")
    t:assertNotNil(before, "a route is found before moving")
    if before then
        t:assertEqual("teleport", before.steps[1].type, "and it starts with the teleport")
        t:assertEqual(3561, before.steps[1].teleportID,
            "carrying the spell ID the Use button needs")
    end

    -- One step. Only the reported position changes; nothing marks the graph
    -- dirty, which is the whole point.
    MockWoW.config.playerX = 0.4001
    QR.PathCalculator:UpdatePlayerLocation()
    t:assertFalse(QR.PathCalculator.graphDirty,
        "movement alone does not mark the graph for a rebuild")

    t:assertEqual("teleport", playerEdgeType(),
        "the teleport edge survives the move (got: " .. playerEdgeType() .. ")")

    local after = QR.PathCalculator:CalculatePath(84, 0.4965, 0.8725, "Stormwind City")
    t:assertNotNil(after, "a route is still found after moving")
    if after then
        t:assertEqual("teleport", after.steps[1].type,
            "and it still starts with the teleport, not a walk")
        t:assertEqual(3561, after.steps[1].teleportID,
            "still carrying the spell ID, so the step keeps its Use button")
    end
end)

-- The same defect through the other writer. Standing in Elwynn Forest reaches
-- the Stormwind node through the adjacent-zone pass; standing INSIDE Stormwind
-- reaches it through the same-map pass, which is a separate call site with its
-- own guard. Removing that one alone left the suite green while reinstating the
-- whole regression for any player in a city they can teleport to.
T:run("Movement inside a city does not overwrite its teleport edge", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerClassName = "Mage"
    MockWoW.config.knownSpells = { [3561] = true }  -- Teleport: Stormwind
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 84                -- Stormwind City itself
    MockWoW.config.playerX, MockWoW.config.playerY = 0.60, 0.40
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()

    local function playerEdgeType()
        local graph = QR.PathCalculator.graph
        local edge = graph and graph:GetEdge("Player Location", "Stormwind City")
        return edge and edge.edgeType or "no edge"
    end

    t:assertEqual("teleport", playerEdgeType(),
        "the teleport edge exists as built (got: " .. playerEdgeType() .. ")")

    MockWoW.config.playerX = 0.6001
    QR.PathCalculator:UpdatePlayerLocation()

    t:assertEqual("teleport", playerEdgeType(),
        "the same-map pass does not overwrite it (got: " .. playerEdgeType() .. ")")

    local after = QR.PathCalculator:CalculatePath(84, 0.4965, 0.8725, "Stormwind City")
    t:assertNotNil(after, "a route is still found")
    if after then
        t:assertEqual("teleport", after.steps[1].type,
            "and it still starts with the teleport")
        t:assertEqual(3561, after.steps[1].teleportID, "carrying its spell ID")
    end
end)

-------------------------------------------------------------------------------
-- Continent routing must never manufacture a near-free edge
-------------------------------------------------------------------------------

-- Graph:AddEdge clamps a weight of zero or less to a 0.001 epsilon, which
-- Dijkstra then reads as free -- that is how the original zone-graph errors
-- stayed invisible. Three guards in ConnectViaContinentRouting exist to keep
-- that from happening; these drive the strategies directly on a hand-built
-- graph, because a full route rarely reaches the last-resort ones.
local function scratchGraph()
    QR.PathCalculator.graph = QR.Graph:New()
    QR.PathCalculator.nodeIndex = nil
    return QR.PathCalculator.graph
end

T:run("Strategy 2 does not replace measured walk edges on the hub's own map", function(t)
    -- A node standing ON the continent hub map already has measured walk edges
    -- from the same-map pass. EstimateSameContinentTravel(hub, hub) is 0, so
    -- running strategy 2 here would overwrite each of them with a free edge.
    local graph = scratchGraph()
    graph:AddNode("Here", { mapID = 84, x = 0.10, y = 0.10, nodeType = "zone" })
    graph:AddNode("Stormwind City", { mapID = 84, x = 0.4965, y = 0.8725, nodeType = "city" })
    graph:AddBidirectionalEdge("Here", "Stormwind City", 42, "walk", {})
    QR.PathCalculator:BuildNodeIndex()

    QR.PathCalculator:ConnectViaContinentRouting("Here", 84, 0.10, 0.10)

    local edge = graph:GetEdge("Here", "Stormwind City")
    t:assertNotNil(edge, "the edge is still there")
    if not edge then return end
    t:assertEqual("walk", edge.edgeType,
        "the measured walk edge survives (got: " .. tostring(edge.edgeType) .. ")")
    t:assertEqual(42, edge.weight,
        "with its measured weight (got: " .. tostring(edge.weight) .. ")")
end)

T:run("A travel estimate never replaces a measured walk edge", function(t)
    -- The same rule from the other side: the node is on a map with no continent
    -- of its own, so strategy 4 runs and reaches for every hub -- including one
    -- this node already has a measured edge to.
    local graph = scratchGraph()
    graph:AddNode("Orphan", { mapID = 99999, x = 0.5, y = 0.5, nodeType = "zone" })
    graph:AddNode("Stormwind City", { mapID = 84, x = 0.4965, y = 0.8725, nodeType = "city" })
    graph:AddBidirectionalEdge("Orphan", "Stormwind City", 7, "walk", {})
    QR.PathCalculator:BuildNodeIndex()

    QR.PathCalculator:ConnectViaContinentRouting("Orphan", 99999, 0.5, 0.5)

    local edge = graph:GetEdge("Orphan", "Stormwind City")
    t:assertNotNil(edge, "the edge is still there")
    if not edge then return end
    t:assertEqual("walk", edge.edgeType,
        "the measured walk edge survives (got: " .. tostring(edge.edgeType) .. ")")
    t:assertEqual(7, edge.weight, "with its measured weight")
end)

T:run("Strategy 4 connects an unreachable node without a sub-second edge", function(t)
    -- The last resort connects to every hub and city at baseTime - 60. This
    -- pins the reachable property: the node gets edges, and none of them is
    -- near-free. It does NOT reach the sub-second case -- that needs
    -- baseTime = 0, which only happens for a continent to itself, and the
    -- continent check above this write makes that state unreachable from a
    -- built graph. The floor behind it is documented as uncovered where it
    -- stands rather than pinned here.
    local graph = scratchGraph()
    graph:AddNode("Orphan", { mapID = 99999, x = 0.5, y = 0.5, nodeType = "zone" })
    graph:AddNode("Stormwind City", { mapID = 84, x = 0.4965, y = 0.8725, nodeType = "city" })
    graph:AddNode("Orgrimmar", { mapID = 85, x = 0.469, y = 0.387, nodeType = "city" })
    QR.PathCalculator:BuildNodeIndex()

    QR.PathCalculator:ConnectViaContinentRouting("Orphan", 99999, 0.5, 0.5)

    local written, tooCheap = 0, {}
    for to, edge in pairs(graph.edges["Orphan"] or {}) do
        written = written + 1
        if edge.weight < 1 then
            tooCheap[#tooCheap + 1] = to .. " w=" .. tostring(edge.weight)
        end
    end
    t:assertGreaterThan(written, 0, "the last resort connected the node to something")
    t:assertEqual(0, #tooCheap,
        "no edge is under a second (" .. table.concat(tooCheap, ", ") .. ")")
end)

-------------------------------------------------------------------------------
-- The last-resort fallback picks the same node every time
-------------------------------------------------------------------------------

-- Regression: the fallback read like a search -- bestNode, bestTime, a "<"
-- comparison -- while the value compared was the constant CROSS_CONTINENT_TIME,
-- so the condition was true exactly once and the node taken was whichever name
-- pairs() yielded first. That is Lua hash order: it can differ between runs and
-- between clients, and a bug report naming a route through it is not
-- reproducible. Every candidate really does cost the same here, so the fix is
-- determinism rather than a cheapest-first search.
T:run("Strategy 4 fallback picks the lexicographically first candidate", function(t)
    local graph = scratchGraph()
    -- Map 99999 has no continent, so strategies 1-3 cannot connect it. The
    -- candidates are plain zone nodes, not hubs or cities, so the hub pass
    -- writes nothing and the fallback is what runs.
    graph:AddNode("Orphan", { mapID = 99999, x = 0.5, y = 0.5, nodeType = "zone" })
    local names = { "Zeta Outpost", "Alpha Landing", "Mid Station", "Beta Camp" }
    for i, name in ipairs(names) do
        graph:AddNode(name, { mapID = 84, x = 0.1 * i, y = 0.2, nodeType = "zone" })
    end
    QR.PathCalculator:BuildNodeIndex()

    QR.PathCalculator:ConnectViaContinentRouting("Orphan", 99999, 0.5, 0.5)

    local written = {}
    for to, edge in pairs(graph.edges["Orphan"] or {}) do
        written[#written + 1] = to
        t:assertEqual("travel", edge.edgeType, "the fallback writes a travel edge")
    end
    t:assertEqual(1, #written,
        "exactly one node is connected (got: " .. table.concat(written, ", ") .. ")")
    t:assertEqual("Alpha Landing", written[1],
        "and it is the lexicographically first candidate, not whichever the "
            .. "hash order yielded (got: " .. tostring(written[1]) .. ")")
end)

-------------------------------------------------------------------------------
-- Dungeon teleports become edges to the entrance the graph already has
-------------------------------------------------------------------------------

-- A player who owns a dungeon teleport was routed to that dungeon's entrance on
-- foot: the addon knew the entrance and knew the spell existed as a spell, but
-- nothing connected the two. AddPlayerTeleportEdges cannot do it -- it runs
-- before the dungeon nodes exist and builds its destination from data.mapID,
-- which these spells do not carry.
local function firstKnownDungeonTeleport(QR)
    local ids = {}
    for spellID in pairs(QR.DungeonTeleportSpells or {}) do ids[#ids + 1] = spellID end
    table.sort(ids)
    for _, spellID in ipairs(ids) do
        local data = QR.DungeonTeleportSpells[spellID]
        local inst = QR.DungeonData and QR.DungeonData.instances
            and QR.DungeonData.instances[data.journalInstanceID]
        if inst and inst.zoneMapID and inst.x and inst.y and inst.name then
            return spellID, data, "Dungeon: " .. inst.name
        end
    end
end

T:run("A known dungeon teleport becomes an edge to that dungeon's node", function(t)
    resetState()
    local spellID, data, nodeName = firstKnownDungeonTeleport(QR)
    t:assertNotNil(spellID, "the data has a teleport whose instance the graph models")
    if not spellID then return end

    MockWoW.config.knownSpells = { [spellID] = true }
    QR.PlayerInventory:ScanAll()
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()

    local graph = QR.PathCalculator.graph
    t:assertNotNil(graph and graph.nodes[nodeName],
        "the dungeon node exists (" .. tostring(nodeName) .. ")")
    local edge = graph and graph:GetEdge("Player Location", nodeName)
    t:assertNotNil(edge, "and the player has an edge to it")
    if not edge then return end
    t:assertEqual("teleport", edge.edgeType, "which is a teleport edge")
    t:assertEqual(spellID, edge.data and edge.data.teleportID,
        "carrying the spell ID the Use button needs")
end)

T:run("An unknown dungeon teleport creates no edge", function(t)
    -- The data table is a generous name match against the client's instance
    -- list, so IsSpellKnown is what makes it correct. A spell the player does
    -- not have must not shorten any route.
    resetState()
    local spellID, _, nodeName = firstKnownDungeonTeleport(QR)
    if not spellID then return end

    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()

    local graph = QR.PathCalculator.graph
    local edge = graph and graph:GetEdge("Player Location", nodeName)
    t:assert(edge == nil or edge.edgeType ~= "teleport",
        "no teleport edge for a spell the player does not know")
end)

-------------------------------------------------------------------------------
-- The player node has to be connected before the player moves
-------------------------------------------------------------------------------

-- Regression: nothing connected the player node at build time except the
-- teleports they own. ConnectSameMapNodes reaches it only when another node
-- shares its map, ConnectIslandNodes skips it by name, and ReconnectPlayerNode
-- -- the only other caller -- is gated on the position having changed. So a
-- character with no teleports, standing somewhere the graph has no other node
-- for, had a player node with zero edges and no route anywhere.
T:run("A teleport-less character in Thunder Bluff can route out", function(t)
    resetState()
    MockWoW.config.playerClass = "WARRIOR"
    MockWoW.config.playerClassName = "Warrior"
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 88  -- Thunder Bluff: no other node on that map
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()

    local graph = QR.PathCalculator.graph
    local edges = graph and graph.edges and graph.edges["Player Location"]
    local count = 0
    for _ in pairs(edges or {}) do count = count + 1 end
    t:assertGreaterThan(count, 0,
        "the player node has edges straight after the build (got " .. tostring(count) .. ")")

    local route = QR.PathCalculator:CalculatePath(84, 0.4965, 0.8725, "Stormwind City")
    t:assertNotNil(route, "and a route to Stormwind exists")
    if not route then return end
    t:assertGreaterThan(#(route.steps or {}), 0, "with at least one step")
end)

-------------------------------------------------------------------------------
-- Flight paths
-------------------------------------------------------------------------------

-- The flight network was missing entirely, which is why a character without
-- teleports could be stranded: Pandaria and Draenor have portals in and no
-- modelled way out. The zone positions come from the client's TaxiNodes table,
-- so the distance an edge is priced from is exact; only the speed it is divided
-- by is an estimate, like every other constant in TravelTime.
T:run("Flight edges connect zones the player has discovered", function(t)
    resetState()
    -- The client tells the addon which flight points the player has. The test
    -- supplies that set directly rather than mocking C_TaxiMap, which is the
    -- one piece whose live behaviour could not be verified.
    local flightZones = {}
    for uiMapID in pairs(QR.FlightPoints or {}) do flightZones[#flightZones + 1] = uiMapID end
    table.sort(flightZones)
    t:assertGreaterThan(#flightZones, 100, "the data has a plausible number of flight zones")

    QR.PathCalculator.knownFlightZonesOverride = nil
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()
    local without = 0
    for _, edges in pairs(QR.PathCalculator.graph.edges or {}) do
        for _, e in pairs(edges) do if e.edgeType == "flight" then without = without + 1 end end
    end
    t:assertEqual(0, without,
        "no flight edges when the client says nothing (got " .. tostring(without) .. ")")

    local known = {}
    for _, uiMapID in ipairs(flightZones) do known[uiMapID] = true end
    QR.PathCalculator.knownFlightZonesOverride = known
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()
    local with = 0
    for _, edges in pairs(QR.PathCalculator.graph.edges or {}) do
        for _, e in pairs(edges) do if e.edgeType == "flight" then with = with + 1 end end
    end
    t:assertGreaterThan(with, 0,
        "and flight edges once it does (got " .. tostring(with) .. ")")

    QR.PathCalculator.knownFlightZonesOverride = nil
end)

-- Snapshot every edge of a graph built with the given discovered-zone set.
local function flightGraphSnapshot(override, mapID)
    QR.PathCalculator.knownFlightZonesOverride = override
    MockWoW.config.currentMapID = mapID or 84
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR:InitializeGraph()
    local edges = {}
    for from, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for to, e in pairs(tos) do
            edges[from .. "\1" .. to] = { weight = e.weight, edgeType = e.edgeType }
        end
    end
    return edges
end

local function allFlightZones()
    local known = {}
    for uiMapID in pairs(QR.FlightPoints or {}) do known[uiMapID] = true end
    return known
end

T:run("Adding flight never makes an existing edge worse", function(t)
    -- The graph holds one edge per ordered pair, so every write is a
    -- replacement, and portals and one-way transports are written unpaired. A
    -- bidirectional flight write guarded by the forward edge alone replaced the
    -- 10s Valdrakken -> Waking Shores portal with a 101s flight, taking the
    -- portalData with it. Each direction has to be judged on its own.
    resetState()
    local before = flightGraphSnapshot(nil, 84)
    local after = flightGraphSnapshot(allFlightZones(), 84)

    local worse = {}
    for key, a in pairs(after) do
        local b = before[key]
        if b and a.weight > b.weight + 0.001 then
            local from, to = key:match("^(.-)\1(.*)$")
            worse[#worse + 1] = string.format("%s -> %s (%s %.1f became %s %.1f)",
                from, to, b.edgeType, b.weight, a.edgeType, a.weight)
        end
    end
    t:assertEqual(0, #worse,
        "no edge got heavier: " .. (worse[1] or "none"))

    -- The pair the regression was found on, named so the guard says what it is
    -- guarding rather than only counting.
    local portal = QR.PathCalculator.graph:GetEdge("Valdrakken", "Waking Shores")
    if portal then
        t:assertEqual("portal", portal.edgeType,
            "and the Valdrakken portal is still a portal (got: " .. tostring(portal.edgeType) .. ")")
    end
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Adding flight makes nothing worse at any speed", function(t)
    -- The test above runs at the shipped FLIGHT_SPEED, where the invariant
    -- also held under the OLD build order -- the two regressions only appeared
    -- below about 17 yd/s. So that test passed by numeric margin and could not
    -- see a reordering. TravelTime.lua invites recalibrating this constant, so
    -- the invariant is checked at a speed where the margin is gone.
    resetState()
    local realSpeed = QR.TravelTime.FLIGHT_SPEED
    local before = flightGraphSnapshot(nil, 84)
    QR.TravelTime.FLIGHT_SPEED = 5
    local after = flightGraphSnapshot(allFlightZones(), 84)
    QR.TravelTime.FLIGHT_SPEED = realSpeed

    local worse
    for key, a in pairs(after) do
        local b = before[key]
        if b and a.weight > b.weight + 0.001 and not worse then
            local from, to = key:match("^(.-)\1(.*)$")
            worse = string.format("%s -> %s (%s %.1f became %s %.1f)",
                from, to, b.edgeType, b.weight, a.edgeType, a.weight)
        end
    end
    t:assertEqual(nil, worse,
        "at a speed slow enough to lose every race: " .. tostring(worse))

    -- And the graph is rebuilt at the real speed so nothing leaks out.
    flightGraphSnapshot(nil, 84)
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("A neutral continent still flies to its own world map", function(t)
    -- The continent test below suppresses flights between two named
    -- continents. That rule, applied bluntly, also suppressed Kul Tiras to
    -- Mechagon, which is a real flight -- the addon files Mechagon under
    -- BFA_NEUTRAL while the rest of Kul Tiras is KUL_TIRAS. Nothing caught
    -- that, so removing the wildcard again would go unnoticed.
    resetState()
    flightGraphSnapshot(allFlightZones(), 84)

    local neutralCrossings = 0
    for _, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for _, e in pairs(tos) do
            if e.edgeType == "flight" and e.data then
                local ca = QR.GetContinentForZone(e.data.fromMapID)
                local cb = QR.GetContinentForZone(e.data.toMapID)
                if ca and cb and ca ~= cb then neutralCrossings = neutralCrossings + 1 end
            end
        end
    end
    t:assertGreaterThan(neutralCrossings, 0,
        "flights across a neutral continent boundary exist (got " .. neutralCrossings .. ")")
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Flight edges stay inside one continent", function(t)
    -- continentID is a world map, not a taxi network: world map 530 holds
    -- Outland and the Burning Crusade starting zones together. Flying from
    -- Azuremyst Isle to Shattrath is not possible, and the addon's own
    -- continent map is what says so.
    resetState()
    flightGraphSnapshot(allFlightZones(), 84)

    local crossings = {}
    for from, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for to, e in pairs(tos) do
            if e.edgeType == "flight" and e.data and e.data.fromMapID and e.data.toMapID then
                local ca = QR.GetContinentForZone(e.data.fromMapID)
                local cb = QR.GetContinentForZone(e.data.toMapID)
                -- A *_NEUTRAL continent is a wildcard on its own world map:
                -- the addon files Mechagon under BFA_NEUTRAL while the rest of
                -- Kul Tiras is KUL_TIRAS, and that flight does exist. Two
                -- NAMED continents on one world map stay apart, which is what
                -- keeps Outland away from the Burning Crusade start zones.
                local neutral = (ca and ca:find("NEUTRAL", 1, true))
                    or (cb and cb:find("NEUTRAL", 1, true))
                if ca and cb and ca ~= cb and not neutral then
                    crossings[#crossings + 1] = string.format("%s (%s) -> %s (%s)", from, ca, to, cb)
                end
            end
        end
    end
    t:assertEqual(0, #crossings,
        "no flight edge crosses continents: " .. (crossings[1] or "none"))
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Flight edges never attach to the player node", function(t)
    -- The player node carries the position the graph was built at, and
    -- ReconnectPlayerNode drops only walk and travel edges on movement. A
    -- flight edge would survive the move and price a flight from a zone the
    -- player has left -- a route that cannot be taken, not just a bad estimate.
    -- Built in Elwynn Forest, which has a flight master and NO other graph
    -- node, so the player node is the only candidate and this guard is the
    -- only thing standing between it and a flight edge. An earlier version of
    -- this test built in a zone that had a dungeon node too, where the
    -- alphabetical tiebreak decided instead and deleting the guard changed
    -- nothing.
    resetState()
    flightGraphSnapshot(allFlightZones(), 37)

    local attached = 0
    for _, e in pairs((QR.PathCalculator.graph.edges or {})["Player Location"] or {}) do
        if e.edgeType == "flight" then attached = attached + 1 end
    end
    t:assertEqual(0, attached,
        "player node carries no flight edges (got " .. attached .. ")")

    -- And the anchor the zone does use is a real node, chosen the documented way.
    -- With the player excluded and nothing else on the map, there is no
    -- anchor at all -- which is the correct answer, and the one that stops a
    -- flight edge being priced from a position the player is about to leave.
    t:assertEqual(nil, QR.PathCalculator:FlightAnchorForMap(37),
        "a map whose only node is the player has no anchor")
    local elsewhere = QR.PathCalculator:FlightAnchorForMap(84)
    t:assertNotNil(elsewhere, "a map with a real node still has one")
    t:assert(elsewhere ~= "Player Location", "and it is never the player node")
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("The flight anchor does not depend on table order", function(t)
    -- NodesOnMap yields pairs() hash order. Taking its first element made the
    -- graph depend on that order: learning an unrelated teleport rehashed the
    -- node table and re-anchored flight edges on six unrelated maps.
    resetState()
    flightGraphSnapshot(allFlightZones(), 84)

    local checked = 0
    for uiMapID in pairs(QR.FlightPoints or {}) do
        local nodes = QR.PathCalculator:NodesOnMap(uiMapID)
        if #nodes > 1 then
            local anchor = QR.PathCalculator:FlightAnchorForMap(uiMapID)
            -- The documented order: never the player, then by nodeType --
            -- city, hub, destination, teleport_dest, transport, everything
            -- else -- and alphabetical within a rank. Recomputed here
            -- independently of the implementation.
            local rank = { city = 1, hub = 2, destination = 3, teleport_dest = 4, transport = 5 }
            local function rankOf(name)
                local data = QR.PathCalculator.graph.nodes[name]
                return (data and data.nodeType and rank[data.nodeType]) or 6
            end
            local want
            for _, name in ipairs(nodes) do
                if name ~= "Player Location" then
                    if not want then
                        want = name
                    else
                        local rn, rw = rankOf(name), rankOf(want)
                        if rn < rw or (rn == rw and name < want) then want = name end
                    end
                end
            end
            t:assertEqual(want, anchor,
                "map " .. uiMapID .. " anchors on the documented first node")
            checked = checked + 1
        end
    end
    t:assertGreaterThan(checked, 10,
        "and enough maps have a real choice to make that meaningful (" .. checked .. ")")
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Only zones the player discovered get flight edges", function(t)
    -- Flying from a flight master you have not found is not possible, so
    -- ignoring the discovered set hands out routes that cannot be taken.
    resetState()
    -- Exactly two zones, both on the Eastern Kingdoms world map.
    local two = { [15] = true, [36] = true }
    flightGraphSnapshot(two, 84)

    local zones = {}
    local count = 0
    for _, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for _, e in pairs(tos) do
            if e.edgeType == "flight" then
                count = count + 1
                zones[e.data.fromMapID] = true
                zones[e.data.toMapID] = true
            end
        end
    end
    t:assertGreaterThan(count, 0, "the two discovered zones are connected")
    for mapID in pairs(zones) do
        t:assertEqual(true, two[mapID] or false,
            "no flight edge touches undiscovered map " .. tostring(mapID))
    end
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("A flight leg reads as a flight in every text surface", function(t)
    -- BuildSteps had no flight branch, so a flight fell through to STEP_GO_TO
    -- and read "Go to X" everywhere except the route list, which formats its
    -- own line.
    resetState()
    flightGraphSnapshot(allFlightZones(), 15)
    local route = QR.PathCalculator:CalculatePath(84, 0.55, 0.60, "Stormwind")
    t:assertNotNil(route, "the Badlands route exists")
    if not route then QR.PathCalculator.knownFlightZonesOverride = nil return end

    local flightStep
    for _, step in ipairs(route.steps or {}) do
        if step.type == "flight" then flightStep = step break end
    end
    t:assertNotNil(flightStep, "and it contains a flight leg")
    if flightStep then
        t:assertNotNil(flightStep.action, "the leg has an action line")
        t:assertEqual(false, flightStep.action:find("^Go to ") ~= nil,
            "which is not the walk wording (got: " .. tostring(flightStep.action) .. ")")
    end
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Every flight edge is priced by the documented formula", function(t)
    -- overhead + distance / speed, from the two flight points' world
    -- positions. Nothing else in the suite pins the weight, so dropping the
    -- overhead or changing the speed constant went unnoticed.
    resetState()
    flightGraphSnapshot(allFlightZones(), 84)
    local speed = QR.TravelTime.FLIGHT_SPEED
    local overhead = QR.TravelTime.FLIGHT_OVERHEAD
    t:assertGreaterThan(speed, 0, "the speed constant is positive")
    t:assertGreaterThan(overhead, 0, "and the overhead is a real cost")

    local checked, wrong = 0, nil
    for _, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for _, e in pairs(tos) do
            if e.edgeType == "flight" then
                local a = QR.FlightPoints[e.data.fromMapID]
                local b = QR.FlightPoints[e.data.toMapID]
                if a and b then
                    local dx, dy = a.worldX - b.worldX, a.worldY - b.worldY
                    local want = overhead + math.sqrt(dx * dx + dy * dy) / speed
                    if math.abs(want - e.weight) > 0.01 and not wrong then
                        wrong = string.format("%d->%d wanted %.2f got %.2f",
                            e.data.fromMapID, e.data.toMapID, want, e.weight)
                    end
                    checked = checked + 1
                end
            end
        end
    end
    t:assertEqual(nil, wrong, "every flight weight matches: " .. tostring(wrong))
    t:assertGreaterThan(checked, 100, "over enough edges to mean something (" .. checked .. ")")
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("A flight pair is written in both directions", function(t)
    -- Each direction is decided separately, which is what stops a flight from
    -- replacing a one-way portal. The other half of that has to hold too: a
    -- pair with nothing competing gets BOTH directions, not one.
    resetState()
    flightGraphSnapshot(allFlightZones(), 84)

    local oneWay
    for from, tos in pairs(QR.PathCalculator.graph.edges or {}) do
        for to, e in pairs(tos) do
            if e.edgeType == "flight" then
                local back = QR.PathCalculator.graph:GetEdge(to, from)
                -- Either the same flight comes back, or something strictly
                -- better already held that direction and kept it.
                local ok = back and (back.edgeType == "flight" or back.weight <= e.weight)
                if not ok and not oneWay then
                    oneWay = from .. " -> " .. to .. " has no return edge"
                end
            end
        end
    end
    t:assertEqual(nil, oneWay, "every flight direction is answered: " .. tostring(oneWay))
    QR.PathCalculator.knownFlightZonesOverride = nil
end)

T:run("Undiscovered flight points do not count as discovered", function(t)
    -- state 0 is a node the player has not found. This is the one live API
    -- behaviour that could not be verified offline, and the gate the whole
    -- feature rests on: treating state 0 as discovered hands out flights from
    -- flight masters the player has never visited.
    resetState()
    local saved = _G.C_TaxiMap
    -- Sorted so the two zones under test are the same on every run.
    local zoneIDs = {}
    for uiMapID in pairs(QR.FlightPoints or {}) do zoneIDs[#zoneIDs + 1] = uiMapID end
    table.sort(zoneIDs)
    local firstZone, secondZone = zoneIDs[1], zoneIDs[2]
    t:assertNotNil(secondZone, "the data has at least two flight zones")
    _G.C_TaxiMap = {
        GetAllTaxiNodes = function(uiMapID)
            if uiMapID == firstZone then return { { state = 1 } } end
            return { { state = 0 }, { state = 0 } }
        end,
    }
    QR.PathCalculator.knownFlightZonesOverride = nil
    local known = QR.PathCalculator:GetKnownFlightZones()
    t:assertNotNil(known, "the client answered")
    if known then
        t:assertEqual(true, known[firstZone] or false,
            "the zone with a discovered node counts")
        t:assertEqual(nil, known[secondZone],
            "the zone whose nodes are all state 0 does not")
    end
    _G.C_TaxiMap = saved
end)

T:run("An answering client with nothing discovered is not the same as no client", function(t)
    -- nil means "the client did not say, do not model flight at all"; empty
    -- means "the player has none". Collapsing them made a level-one character
    -- log a data-availability problem that does not exist.
    resetState()
    local saved = _G.C_TaxiMap
    _G.C_TaxiMap = { GetAllTaxiNodes = function() return {} end }
    QR.PathCalculator.knownFlightZonesOverride = nil
    local known = QR.PathCalculator:GetKnownFlightZones()
    t:assertNotNil(known, "an answering client returns a set, not nil")
    if known then
        t:assertEqual(nil, next(known), "and that set is empty")
    end

    _G.C_TaxiMap = nil
    t:assertEqual(nil, QR.PathCalculator:GetKnownFlightZones(),
        "an absent API returns nil")
    _G.C_TaxiMap = saved
end)
