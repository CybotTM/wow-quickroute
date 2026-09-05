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

    if weight == nil then weight = 1 end
    if type(weight) ~= "number" or weight ~= weight
        or weight == math_huge or weight == -math_huge then
        return false
    end
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

--- Select the cheapest alternative without mutating edges returned in old routes.
function QR.Graph:SetEdgeOptions(from, to, options)
    local best
    for _, option in ipairs(options) do
        if not best or option.weight < best.weight
            or (option.weight == best.weight
                and tostring(option.data.teleportID or option.edgeType)
                    < tostring(best.data.teleportID or best.edgeType)) then
            best = option
        end
    end
    if not best then
        self.edges[from][to] = nil
        return
    end
    self.edges[from][to] = {
        weight = best.weight, edgeType = best.edgeType, data = best.data,
        alternatives = options,
    }
end

--- Keep competing methods for a pair, replacing only the same method/ability.
function QR.Graph:AddEdgeOption(from, to, weight, edgeType, data)
    local existing = self:GetEdge(from, to)
    if not self:AddEdge(from, to, weight, edgeType, data) then return false end
    local incoming = self:GetEdge(from, to)
    local options = {}
    for _, option in ipairs(existing and (existing.alternatives or { existing }) or {}) do
        if option.edgeType ~= incoming.edgeType
            or option.data.teleportID ~= incoming.data.teleportID then
            options[#options + 1] = option
        end
    end
    options[#options + 1] = incoming
    self:SetEdgeOptions(from, to, options)
    return true
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
local function FindDistances(graph, start, goal, filter)
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
        local current = pq:Pop()

        -- Skip if we've already processed this node with a better distance
        if not visited[current] then
            visited[current] = true

            -- Found the goal
            if current == goal then
                break
            end

            -- Process neighbors
            local neighbors = graph:GetNeighbors(current)
            for neighbor, selected in pairs(neighbors) do
                local edge = selected
                if filter then
                    edge = nil
                    for _, option in ipairs(selected.alternatives or { selected }) do
                        if filter(current, neighbor, option) and (not edge or option.weight < edge.weight) then edge = option end
                    end
                end
                if edge and not visited[neighbor] then
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

    return dist, prev, prevEdge
end

--- All reachable costs in one search; useful when comparing many destinations.
function QR.Graph:FindDistances(start)
    if not self.nodes[start] then return {} end
    local dist = FindDistances(self, start)
    return dist
end

function QR.Graph:FindShortestPath(start, goal, filter)
    if not self.nodes[start] or not self.nodes[goal] then
        return nil, nil, nil
    end
    local dist, prev, prevEdge = FindDistances(self, start, goal, filter)

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

--- Dijkstra over (location, travel state). A phase switch can make a previously
-- visited portal usable; location alone is therefore not a sufficient key.
function QR.Graph:FindShortestPathWithState(start, goal, policy)
    if not self.nodes[start] or not self.nodes[goal] then return nil end
    local function key(node, state)
        local name = tostring(node)
        return #name .. ":" .. name .. policy:Signature(state)
    end
    local initial = policy.initialState or {}
    local startKey = key(start, initial)
    local distance, previous, previousEdge, states = { [startKey] = 0 }, {}, {}, {}
    states[startKey] = { node = start, state = initial }
    local queue = PriorityQueue()
    queue:Push(startKey, 0)
    local finalKey, count = nil, 1
    while not queue:IsEmpty() do
        local currentKey, cost = queue:Pop()
        if distance[currentKey] == cost then
            local current = states[currentKey]
            if current.node == goal then finalKey = currentKey; break end
            for neighbor, selected in pairs(self:GetNeighbors(current.node)) do
                for _, edge in ipairs(selected.alternatives or { selected }) do
                    local nextState = policy:Advance(current.node, neighbor, edge, current.state)
                    if nextState then
                        local nextKey = key(neighbor, nextState)
                        local nextCost = cost + edge.weight
                        if nextCost < (distance[nextKey] or math_huge) then
                            if not states[nextKey] then
                                count = count + 1
                                if count > (policy.maxStates or 50000) then
                                    return nil, nil, nil, "search_limit"
                                end
                                states[nextKey] = { node = neighbor, state = nextState }
                            end
                            distance[nextKey] = nextCost
                            previous[nextKey], previousEdge[nextKey] = currentKey, edge
                            queue:Push(nextKey, nextCost)
                        end
                    end
                end
            end
        end
    end
    if not finalKey then return nil end
    local reversePath, reverseEdges = {}, {}
    local current = finalKey
    while current do
        reversePath[#reversePath + 1] = states[current].node
        if previousEdge[current] then reverseEdges[#reverseEdges + 1] = previousEdge[current] end
        current = previous[current]
    end
    local path, edges = {}, {}
    for i = #reversePath, 1, -1 do path[#path + 1] = reversePath[i] end
    for i = #reverseEdges, 1, -1 do edges[#edges + 1] = reverseEdges[i] end
    return path, distance[finalKey], edges
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
