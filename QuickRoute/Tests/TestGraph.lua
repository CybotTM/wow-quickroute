-- TestGraph.lua
-- Tests for the Graph data structure
local ADDON_NAME, QR = ...

QR.Tests = QR.Tests or {}
QR.Tests.Graph = {}

-- Test 1: Create empty graph
function QR.Tests.Graph:TestCreateEmptyGraph()
    local graph = QR.Graph:New()

    if not graph.nodes then
        return false, "Graph should have nodes table"
    end
    if not graph.edges then
        return false, "Graph should have edges table"
    end

    -- Verify they're empty
    local nodeCount = 0
    for _ in pairs(graph.nodes) do nodeCount = nodeCount + 1 end

    if nodeCount ~= 0 then
        return false, "New graph should have 0 nodes"
    end

    return true, "Empty graph created successfully"
end

-- Test 2: Add node
function QR.Tests.Graph:TestAddNode()
    local graph = QR.Graph:New()

    local result = graph:AddNode("Stormwind", { continent = "Eastern Kingdoms" })

    if not result then
        return false, "AddNode should return true for new node"
    end

    if not graph.nodes["Stormwind"] then
        return false, "Stormwind should be in nodes table"
    end

    if graph.nodes["Stormwind"].continent ~= "Eastern Kingdoms" then
        return false, "Node data should be preserved"
    end

    -- Adding same node again should return false
    local duplicateResult = graph:AddNode("Stormwind")
    if duplicateResult then
        return false, "Adding duplicate node should return false"
    end

    return true, "Node added successfully"
end

-- Test 3: Add edge with weight
function QR.Tests.Graph:TestAddEdge()
    local graph = QR.Graph:New()

    graph:AddNode("Stormwind")
    graph:AddNode("Ironforge")

    local result = graph:AddEdge("Stormwind", "Ironforge", 100, "portal", { spellId = 12345 })

    if not result then
        return false, "AddEdge should return true"
    end

    local edge = graph:GetEdge("Stormwind", "Ironforge")

    if not edge then
        return false, "Edge should exist"
    end

    if edge.weight ~= 100 then
        return false, "Edge weight should be 100, got " .. tostring(edge.weight)
    end

    if edge.edgeType ~= "portal" then
        return false, "Edge type should be 'portal'"
    end

    if edge.data.spellId ~= 12345 then
        return false, "Edge data should be preserved"
    end

    -- Reverse edge should not exist (directed graph)
    local reverseEdge = graph:GetEdge("Ironforge", "Stormwind")
    if reverseEdge then
        return false, "Reverse edge should not exist for directed edge"
    end

    return true, "Edge added successfully with correct weight"
end

-- Test 4: Dijkstra finds shortest path
function QR.Tests.Graph:TestDijkstraShortestPath()
    local graph = QR.Graph:New()

    -- Create nodes
    graph:AddNode("Stormwind")
    graph:AddNode("Ironforge")
    graph:AddNode("Darnassus")

    -- Create edges:
    -- Stormwind -> Ironforge: 100 (portal)
    -- Ironforge -> Darnassus: 120 (portal)
    -- Stormwind -> Darnassus: 300 (direct but slow)
    graph:AddEdge("Stormwind", "Ironforge", 100, "portal")
    graph:AddEdge("Ironforge", "Darnassus", 120, "portal")
    graph:AddEdge("Stormwind", "Darnassus", 300, "walk")

    local path, cost, pathEdges = graph:FindShortestPath("Stormwind", "Darnassus")

    if not path then
        return false, "Path should be found"
    end

    -- Expected path: Stormwind -> Ironforge -> Darnassus (cost: 220)
    -- Not: Stormwind -> Darnassus (cost: 300)
    if cost ~= 220 then
        return false, "Cost should be 220, got " .. tostring(cost)
    end

    if #path ~= 3 then
        return false, "Path should have 3 nodes, got " .. #path
    end

    if path[1] ~= "Stormwind" or path[2] ~= "Ironforge" or path[3] ~= "Darnassus" then
        return false, "Path should be Stormwind -> Ironforge -> Darnassus"
    end

    if #pathEdges ~= 2 then
        return false, "Path should have 2 edges, got " .. #pathEdges
    end

    return true, "Dijkstra found shortest path: Stormwind -> Ironforge -> Darnassus = 220"
end

-- Run all tests
function QR.Tests.Graph:RunAll()
    local tests = {
        { name = "Create Empty Graph", func = self.TestCreateEmptyGraph },
        { name = "Add Node", func = self.TestAddNode },
        { name = "Add Edge", func = self.TestAddEdge },
        { name = "Dijkstra Shortest Path", func = self.TestDijkstraShortestPath },
    }

    local passed = 0
    local failed = 0

    print("|cFF00FF00=== QuickRoute Graph Tests ===|r")

    for _, test in ipairs(tests) do
        local success, message = test.func(self)
        if success then
            passed = passed + 1
            print("|cFF00FF00PASS|r: " .. test.name .. " - " .. message)
        else
            failed = failed + 1
            print("|cFFFF0000FAIL|r: " .. test.name .. " - " .. message)
        end
    end

    print(string.format("|cFF00FF00=== Results: %d passed, %d failed ===|r", passed, failed))

    return failed == 0
end

-- Slash command handler
SLASH_QRTEST1 = "/qrtest"
SlashCmdList["QRTEST"] = function(args)
    args = string.lower(args or "")

    if args == "graph" then
        QR.Tests.Graph:RunAll()
    elseif args == "all" then
        print("|cFF00FF00=== Running All QuickRoute Tests ===|r")
        QR.Tests.Graph:RunAll()
        -- Future: Add other test modules here
    else
        print("|cFFFFFF00Usage:|r /qrtest <module>")
        print("  graph - Run Graph tests")
        print("  all   - Run all tests")
    end
end
