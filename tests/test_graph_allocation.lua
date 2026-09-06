local T, QR, MockWoW = ...

local function allocation(body)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, err = pcall(body)
    local used = collectgarbage("count") - before
    collectgarbage("restart")
    if not ok then error(err) end
    return used
end

T:run("Graph allocation: replacing one method avoids unnecessary option containers", function(t)
    local graph, data = QR.Graph:New(), { teleportID = 1 }
    graph:AddNode("A"); graph:AddNode("B")
    local used = allocation(function()
        for index = 1, 1000 do graph:AddEdgeOption("A", "B", index, "teleport", data) end
    end)
    t:assert(used < 350, "One thousand single-method replacements allocate under 350 KiB, observed " .. used)
    local path, cost, edges = graph:FindShortestPath("A", "B")
    t:assertEqual(1000, cost, "Replacement retains the latest method weight")
    t:assertEqual(1, edges[1].data.teleportID, "Replacement retains the actionable teleport ID")
    graph:AddEdgeOption("A", "B", 1, "teleport", data)
    t:assertEqual(1000, edges[1].weight, "A previously returned route keeps its original edge weight")
    t:assertEqual("B", path[2], "Previously returned path remains intact")
end)

T:run("Graph allocation: filtering singleton edges adds no per-edge temporary tables", function(t)
    local graph = QR.Graph:New()
    for index = 1, 40 do graph:AddNode(index) end
    for from = 1, 39 do
        for to = 2, 40 do
            if from ~= to then graph:AddEdge(from, to, to == 40 and 100 or 1, "walk") end
        end
    end
    local plain = allocation(function() graph:FindShortestPath(1, 40) end)
    local calls, path, cost = 0
    local filtered = allocation(function()
        path, cost = graph:FindShortestPath(1, 40, function()
            calls = calls + 1
            return true
        end)
    end)
    t:assertGreaterThan(calls, 1000, "The filter evaluates over one thousand outgoing edges")
    t:assert(filtered - plain < 8, "Filtering adds under 8 KiB beyond the same search, observed " .. (filtered - plain))
    t:assertEqual(100, cost, "Filtered singleton search preserves the shortest cost")
    t:assertEqual(40, path[#path], "Filtered singleton search reaches the destination")
end)

T:run("Graph allocation: alternatives retain ordering ties filters and route immutability", function(t)
    local graph = QR.Graph:New()
    graph:AddNode("A"); graph:AddNode("B")
    graph:AddEdgeOption("A", "B", 5, "teleport", { teleportID = 20 })
    graph:AddEdgeOption("A", "B", 5, "teleport", { teleportID = 10 })
    graph:AddEdgeOption("A", "B", 12, "walk")
    t:assertEqual(10, graph:GetEdge("A", "B").data.teleportID, "Unfiltered equal-cost selection retains its deterministic ID tie-break")
    local _, cost, edges = graph:FindShortestPath("A", "B", function(_, _, edge)
        return edge.data.teleportID ~= 20
    end)
    t:assertEqual(5, cost, "Filtering one teleport preserves the other equal-cost method")
    t:assertEqual(10, edges[1].data.teleportID, "Filtered result keeps the usable action ID")
    local snapshot = graph:GetEdge("A", "B")
    graph:AddEdgeOption("A", "B", 30, "teleport", { teleportID = 10 })
    t:assertEqual(5, snapshot.weight, "Existing selected-edge snapshot is not repriced in place")
    t:assertEqual(5, edges[1].weight, "Existing path edge is not repriced in place")
    local policy = { initialState = {}, Signature = function() return "" end,
        Advance = function(_, _, _, edge, state)
            if edge.edgeType == "walk" then return state end
        end }
    local _, stateCost, stateEdges = graph:FindShortestPathWithState("A", "B", policy)
    t:assertEqual(12, stateCost, "Stateful traversal still considers the third parallel option")
    t:assertEqual("walk", stateEdges[1].edgeType, "Stateful traversal retains the selected walking method")
    graph:SetEdgeOptions("A", "B", { snapshot })
    local _, _, flattened = graph:FindShortestPath("A", "B", function(_, _, edge)
        return edge.data.teleportID == 20
    end)
    t:assertNil(flattened, "Selecting one summary edge cannot expose its former alternatives")
    graph:SetEdgeOptions("A", "B", {})
    t:assertNil(graph:GetEdge("A", "B"), "An empty option set removes the edge")
end)

T:run("Routing allocation: added nodes and player movement route without rebuilding an unused index", function(t)
    local config = MockWoW.config
    local savedMap, savedX, savedY = config.playerMapID, config.playerX, config.playerY
    local ok, err = pcall(function()
        config.playerMapID, config.playerX, config.playerY = 84, 0.4, 0.4
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { nodeType = "player", mapID = 84, x = 0.4, y = 0.4 })
        local sentinel = { byMap = {}, byContinent = {}, hubsAndCities = {} }
        local calculator = setmetatable({ graph = graph, graphDirty = false, nodeIndex = sentinel,
            zoneTravelGraph = QR.Graph:New(), zoneTravelCache = {} }, { __index = function(_, key)
                local value = QR.PathCalculator[key]
                if type(value) == "function" then return value end
            end })
        local first = calculator:CalculatePath(84, 0.8, 0.8)
        graph:AddNode("New Stop", { mapID = 84, x = 0.78, y = 0.78 })
        config.playerX, config.playerY = 0.79, 0.79
        local second = calculator:CalculatePath(84, 0.8, 0.8)
        t:assertNotNil(first, "The first route reaches a newly added destination")
        t:assertNotNil(second, "A route after movement still reaches its new destination")
        t:assert(second.totalTime < first.totalTime, "Approaching the destination lowers the estimated route time")
        t:assertNotNil(graph:GetEdge("Player Location", "New Stop"), "Movement connects the new map node without a cached index entry")
        t:assertEqual(sentinel, calculator.nodeIndex, "Route-only connections do not rebuild the unused full node index")
        t:assertEqual(0.79, graph.nodes["Player Location"].x, "The route origin reflects the current player position")
    end)
    config.playerMapID, config.playerX, config.playerY = savedMap, savedX, savedY
    if not ok then error(err) end
end)
