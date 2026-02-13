-- Graph.lua
-- Graph data structure with Dijkstra's shortest path algorithm
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type = pairs, ipairs, type
local math_floor, math_huge = math.floor, math.huge
local table_insert = table.insert
local string_format = string.format

-- Graph class
QR.Graph = {}
QR.Graph.__index = QR.Graph

-- Priority Queue (min-heap) for Dijkstra's algorithm
-- Uses parallel arrays to avoid per-Push table allocation
local function PriorityQueue()
    local pq = {
        items = {},
        priorities = {},
        size = 0
    }

    local function parent(i) return math_floor(i / 2) end
    local function left(i) return 2 * i end
    local function right(i) return 2 * i + 1 end

    local function swap(items, priorities, i, j)
        items[i], items[j] = items[j], items[i]
        priorities[i], priorities[j] = priorities[j], priorities[i]
    end

    local function heapifyUp(items, priorities, i)
        local pi = parent(i)
        while i > 1 and priorities[pi] > priorities[i] do
            swap(items, priorities, i, pi)
            i = pi
            pi = parent(i)
        end
    end

    local function heapifyDown(items, priorities, size, i)
        local smallest = i
        local l = left(i)
        local r = right(i)

        if l <= size and priorities[l] < priorities[smallest] then
            smallest = l
        end
        if r <= size and priorities[r] < priorities[smallest] then
            smallest = r
        end

        if smallest ~= i then
            swap(items, priorities, i, smallest)
            heapifyDown(items, priorities, size, smallest)
        end
    end

    function pq:Push(item, priority)
        self.size = self.size + 1
        self.items[self.size] = item
        self.priorities[self.size] = priority
        heapifyUp(self.items, self.priorities, self.size)
    end

    function pq:Pop()
        if self.size == 0 then
            return nil
        end

        local item = self.items[1]
        local priority = self.priorities[1]
        local n = self.size

        self.items[1] = self.items[n]
        self.priorities[1] = self.priorities[n]
        self.items[n] = nil
        self.priorities[n] = nil
        self.size = n - 1

        if self.size > 0 then
            heapifyDown(self.items, self.priorities, self.size, 1)
        end

        return item, priority
    end

    function pq:IsEmpty()
        return self.size == 0
    end

    return pq
end

-- Creates a new graph with empty nodes and edges tables
function QR.Graph:New()
    local graph = setmetatable({}, QR.Graph)
    graph.nodes = {}
    graph.edges = {}
    return graph
end

-- Adds a node to the graph
-- Returns true if node was added, false if it already exists
function QR.Graph:AddNode(name, data)
    if self.nodes[name] then
        return false
    end

    self.nodes[name] = data or {}
    self.edges[name] = {}
    return true
end

-- Removes a node and all edges pointing to it
function QR.Graph:RemoveNode(name)
    if not self.nodes[name] then
        return false
    end

    -- Remove the node
    self.nodes[name] = nil
    self.edges[name] = nil

    -- Remove all edges pointing to this node
    for fromNode, edgeList in pairs(self.edges) do
        edgeList[name] = nil
    end

    return true
end

-- Adds a weighted directed edge from one node to another
-- edgeType can be: "portal", "teleport", "walk", "flight", etc.
function QR.Graph:AddEdge(from, to, weight, edgeType, data)
    if not self.nodes[from] or not self.nodes[to] then
        return false
    end

    weight = weight or 1
    if weight < 0 then
        if QR.Warn then QR:Warn(string_format("Edge %s->%s had negative weight %s, clamping to 0.001", tostring(from), tostring(to), tostring(weight))) end
        weight = 0.001
    elseif weight == 0 then
        weight = 0.001  -- Epsilon to prevent Dijkstra zero-cost loops
    end

    self.edges[from][to] = {
        weight = weight,
        edgeType = edgeType or "walk",
        data = data or {}
    }

    return true
end

-- Adds a bidirectional edge (edge in both directions)
function QR.Graph:AddBidirectionalEdge(nodeA, nodeB, weight, edgeType, data)
    local success1 = self:AddEdge(nodeA, nodeB, weight, edgeType, data)
    local success2 = self:AddEdge(nodeB, nodeA, weight, edgeType, data)
    return success1 and success2
end

-- Gets the edge between two nodes
function QR.Graph:GetEdge(from, to)
    if not self.edges[from] then
        return nil
    end
    return self.edges[from][to]
end

-- Gets all neighbors (outgoing edges) of a node
function QR.Graph:GetNeighbors(node)
    return self.edges[node] or {}
end

-- Dijkstra's algorithm to find the shortest path
-- Returns: path (array of node names), cost (total weight), pathEdges (array of edges used)
function QR.Graph:FindShortestPath(start, goal)
    if not self.nodes[start] or not self.nodes[goal] then
        return nil, nil, nil
    end

    local dist = {}
    local prev = {}
    local prevEdge = {}
    local visited = {}
    local HUGE = math_huge

    -- Lazy initialization: only set dist when a node is first encountered
    dist[start] = 0

    local pq = PriorityQueue()
    pq:Push(start, 0)

    while not pq:IsEmpty() do
        local current, currentDist = pq:Pop()

        -- Skip if we've already processed this node with a better distance
        if not visited[current] then
            visited[current] = true

            -- Found the goal
            if current == goal then
                break
            end

            -- Process neighbors
            local neighbors = self:GetNeighbors(current)
            for neighbor, edge in pairs(neighbors) do
                if not visited[neighbor] then
                    local newDist = dist[current] + edge.weight
                    local neighborDist = dist[neighbor] or HUGE

                    if newDist < neighborDist then
                        dist[neighbor] = newDist
                        prev[neighbor] = current
                        prevEdge[neighbor] = edge
                        pq:Push(neighbor, newDist)
                    end
                end
            end
        end
    end

    -- No path found
    if not prev[goal] and start ~= goal then
        return nil, nil, nil
    end

    -- Reconstruct path (build in reverse, then flip for O(n) instead of O(n²))
    local reversePath = {}
    local reverseEdges = {}
    local current = goal

    while current do
        reversePath[#reversePath + 1] = current
        if prevEdge[current] then
            reverseEdges[#reverseEdges + 1] = prevEdge[current]
        end
        current = prev[current]
    end

    -- Reverse both arrays
    local path = {}
    local pathEdges = {}
    for i = #reversePath, 1, -1 do
        path[#path + 1] = reversePath[i]
    end
    for i = #reverseEdges, 1, -1 do
        pathEdges[#pathEdges + 1] = reverseEdges[i]
    end

    return path, dist[goal], pathEdges
end

-- Debug helper to print the graph structure
-- @param verbose boolean Show all edges (default: false for summary only)
function QR.Graph:Print(verbose)
    local nodeCount = 0
    local edgeCount = 0
    local edgesByType = {}

    -- Count nodes
    for name, data in pairs(self.nodes) do
        nodeCount = nodeCount + 1
    end

    -- Count and categorize edges
    for from, edges in pairs(self.edges) do
        for to, edge in pairs(edges) do
            edgeCount = edgeCount + 1
            local edgeType = edge.edgeType or "unknown"
            edgesByType[edgeType] = (edgesByType[edgeType] or 0) + 1
        end
    end

    print("|cFF00FF00=== Graph Summary ===|r")
    print(string_format("  Total nodes: |cFFFFFF00%d|r", nodeCount))
    print(string_format("  Total edges: |cFFFFFF00%d|r", edgeCount))

    -- Show edge breakdown by type
    print("  Edges by type:")
    for edgeType, count in pairs(edgesByType) do
        print(string_format("    |cFFAAAAAA%s|r: %d", edgeType, count))
    end

    if verbose then
        print("|cFF00FF00=== Graph Nodes ===|r")
        for name, data in pairs(self.nodes) do
            local mapID = data.mapID or "?"
            local x = data.x and string_format("%.2f", data.x) or "?"
            local y = data.y and string_format("%.2f", data.y) or "?"
            print(string_format("  |cFFFFFF00%s|r (map: %s, pos: %s, %s)", name, mapID, x, y))
        end

        print("|cFF00FF00=== Graph Edges ===|r")
        for from, edges in pairs(self.edges) do
            for to, edge in pairs(edges) do
                print(string_format("  %s |cFFAAAAAA->|r %s |cFF888888(weight: %d, type: %s)|r",
                    from, to, edge.weight, edge.edgeType))
            end
        end
    end
end
