-------------------------------------------------------------------------------
-- test_graph.lua
-- Tests for QR.Graph (Dijkstra's algorithm, node/edge management)
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

T:run("Graph:New creates empty graph", function(t)
    local g = QR.Graph:New()
    t:assertNotNil(g, "Graph created")
    t:assertNotNil(g.nodes, "Nodes table exists")
    t:assertNotNil(g.edges, "Edges table exists")
end)

T:run("Graph:AddNode adds nodes correctly", function(t)
    local g = QR.Graph:New()

    t:assertTrue(g:AddNode("A", { mapID = 1 }), "First add returns true")
    t:assertFalse(g:AddNode("A", { mapID = 2 }), "Duplicate add returns false")
    t:assertTrue(g:AddNode("B"), "Add without data returns true")

    t:assertNotNil(g.nodes["A"], "Node A exists")
    t:assertEqual(1, g.nodes["A"].mapID, "Node A data preserved")
    t:assertNotNil(g.nodes["B"], "Node B exists")
end)

T:run("Graph:RemoveNode removes node and edges", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddNode("C")
    g:AddEdge("A", "B", 10, "walk")
    g:AddEdge("B", "C", 5, "walk")
    g:AddEdge("C", "A", 3, "walk")

    t:assertTrue(g:RemoveNode("B"), "Remove existing node returns true")
    t:assertFalse(g:RemoveNode("B"), "Remove missing node returns false")
    t:assertNil(g.nodes["B"], "Node B no longer in nodes")
    t:assertNil(g.edges["B"], "Node B edges removed")

    -- Edge from C to A should still exist
    t:assertNotNil(g:GetEdge("C", "A"), "Edge C->A still exists")
end)

T:run("Graph:AddEdge validates node existence", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")

    t:assertTrue(g:AddEdge("A", "B", 10, "walk"), "Edge between valid nodes")
    t:assertFalse(g:AddEdge("A", "Z", 10, "walk"), "Edge to nonexistent node fails")
    t:assertFalse(g:AddEdge("Z", "A", 10, "walk"), "Edge from nonexistent node fails")
end)

T:run("Graph:AddBidirectionalEdge adds both directions", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")

    t:assertTrue(g:AddBidirectionalEdge("A", "B", 10, "walk"), "Bidirectional edge added")

    local ab = g:GetEdge("A", "B")
    t:assertNotNil(ab, "Edge A->B exists")
    t:assertEqual(10, ab.weight, "A->B weight correct")

    local ba = g:GetEdge("B", "A")
    t:assertNotNil(ba, "Edge B->A exists")
    t:assertEqual(10, ba.weight, "B->A weight correct")
end)

T:run("Graph:GetNeighbors returns correct edges", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddNode("C")
    g:AddEdge("A", "B", 10, "walk")
    g:AddEdge("A", "C", 20, "portal")

    local neighbors = g:GetNeighbors("A")
    t:assertNotNil(neighbors["B"], "B is neighbor of A")
    t:assertNotNil(neighbors["C"], "C is neighbor of A")
    t:assertNil(neighbors["A"], "A is not its own neighbor")
end)

T:run("Dijkstra: Direct path", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddEdge("A", "B", 10, "walk")

    local path, cost = g:FindShortestPath("A", "B")
    t:assertNotNil(path, "Path found")
    t:assertEqual(10, cost, "Cost is 10")
    t:assertEqual(2, #path, "Path has 2 nodes")
    t:assertEqual("A", path[1], "Starts at A")
    t:assertEqual("B", path[2], "Ends at B")
end)

T:run("Dijkstra: Multi-hop path", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddNode("C")
    g:AddNode("D")
    g:AddEdge("A", "B", 10, "walk")
    g:AddEdge("B", "C", 20, "portal")
    g:AddEdge("C", "D", 5, "teleport")

    local path, cost = g:FindShortestPath("A", "D")
    t:assertNotNil(path, "Path found")
    t:assertEqual(35, cost, "Cost is 35")
    t:assertEqual(4, #path, "Path has 4 nodes")
end)

T:run("Dijkstra: Shortest of multiple paths", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddNode("C")
    -- Direct path: A->C costs 100
    g:AddEdge("A", "C", 100, "walk")
    -- Indirect path: A->B->C costs 30
    g:AddEdge("A", "B", 10, "teleport")
    g:AddEdge("B", "C", 20, "portal")

    local path, cost = g:FindShortestPath("A", "C")
    t:assertNotNil(path, "Path found")
    t:assertEqual(30, cost, "Shortest path cost is 30")
    t:assertEqual(3, #path, "Path goes through B (3 nodes)")
    t:assertEqual("B", path[2], "Path goes through B")
end)

T:run("Dijkstra: No path returns nil", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    -- No edges

    local path, cost = g:FindShortestPath("A", "B")
    t:assertNil(path, "No path found")
    t:assertNil(cost, "No cost")
end)

T:run("Dijkstra: Start equals goal", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")

    local path, cost = g:FindShortestPath("A", "A")
    t:assertNotNil(path, "Path found (same node)")
    t:assertEqual(0, cost, "Cost is 0")
    t:assertEqual(1, #path, "Path has 1 node")
end)

T:run("Dijkstra: Invalid start or goal returns nil", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")

    local path = g:FindShortestPath("A", "Z")
    t:assertNil(path, "Path to nonexistent goal is nil")

    path = g:FindShortestPath("Z", "A")
    t:assertNil(path, "Path from nonexistent start is nil")
end)

T:run("Dijkstra: Edge data preserved in path edges", function(t)
    local g = QR.Graph:New()
    g:AddNode("A")
    g:AddNode("B")
    g:AddEdge("A", "B", 10, "portal", { portalName = "Test Portal" })

    local path, cost, pathEdges = g:FindShortestPath("A", "B")
    t:assertNotNil(pathEdges, "Path edges returned")
    t:assertEqual(1, #pathEdges, "One edge in path")
    t:assertEqual("portal", pathEdges[1].edgeType, "Edge type is portal")
    t:assertEqual("Test Portal", pathEdges[1].data.portalName, "Edge data preserved")
end)

T:run("Dijkstra: Large graph (10 node chain)", function(t)
    local g = QR.Graph:New()
    for i = 1, 10 do
        g:AddNode("N" .. i)
    end
    for i = 1, 9 do
        g:AddEdge("N" .. i, "N" .. (i + 1), 5, "walk")
    end

    local path, cost = g:FindShortestPath("N1", "N10")
    t:assertNotNil(path, "Path found in 10-node chain")
    t:assertEqual(45, cost, "Cost is 9 * 5 = 45")
    t:assertEqual(10, #path, "Path visits all 10 nodes")
end)

-------------------------------------------------------------------------------
-- 3.9: BuildGraph pcall Error Handling
-- Test that BuildGraph handles errors in individual phases gracefully
-- by wrapping each phase in pcall and continuing.
-------------------------------------------------------------------------------

T:run("BuildGraph: continues when AddZoneNodes fails", function(t)
    MockWoW:Reset()
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true

    -- Save original method and replace with error-throwing version
    local origAddZoneNodes = QR.PathCalculator.AddZoneNodes
    QR.PathCalculator.AddZoneNodes = function()
        error("Simulated AddZoneNodes failure")
    end

    -- Suppress error output during test
    local origError = QR.Error
    local errors = {}
    QR.Error = function(self, msg)
        errors[#errors + 1] = msg
    end

    local graph = QR.PathCalculator:BuildGraph()

    -- Graph should still be created (not nil), even if partial
    t:assertNotNil(graph, "Graph created despite AddZoneNodes failure")

    -- An error should have been logged about AddZoneNodes
    local foundError = false
    for _, msg in ipairs(errors) do
        if msg:find("AddZoneNodes") then
            foundError = true
        end
    end
    t:assertTrue(foundError, "Error logged for AddZoneNodes failure")

    -- graphDirty should remain true (since build was not fully successful)
    t:assertTrue(QR.PathCalculator.graphDirty,
        "graphDirty stays true after partial build failure")

    -- Restore
    QR.PathCalculator.AddZoneNodes = origAddZoneNodes
    QR.Error = origError
end)

T:run("BuildGraph: continues when AddPortalConnections fails", function(t)
    MockWoW:Reset()
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true

    local origAddPortals = QR.PathCalculator.AddPortalConnections
    QR.PathCalculator.AddPortalConnections = function()
        error("Simulated portal connection failure")
    end

    local origError = QR.Error
    local errors = {}
    QR.Error = function(self, msg)
        errors[#errors + 1] = msg
    end

    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph created despite AddPortalConnections failure")

    -- Zone nodes should still exist (that phase succeeded)
    local hasNodes = false
    for _ in pairs(graph.nodes) do
        hasNodes = true
        break
    end
    t:assertTrue(hasNodes, "Graph has nodes from AddZoneNodes despite portal failure")

    -- Restore
    QR.PathCalculator.AddPortalConnections = origAddPortals
    QR.Error = origError
end)
