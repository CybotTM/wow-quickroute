-------------------------------------------------------------------------------
-- test_graph_build_slices.lua
-- A graph build inside the asynchronous driver pauses between its steps, and
-- everybody else sees the previous, complete graph meanwhile. The phase maps
-- of a graph's fixed part are collected once per graph.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local PC = QR.PathCalculator

local function edgeList(graph)
    local list = {}
    for from, outgoing in pairs(graph.edges) do
        for to, edge in pairs(outgoing) do
            list[#list + 1] = string.format("%s>%s:%s:%.3f:%d", from, to, edge.edgeType,
                edge.weight, edge.alternatives and #edge.alternatives or 1)
        end
    end
    table.sort(list)
    return list
end

local function withDriver(body)
    local saved = { after = C_Timer.After, budget = PC.FRAME_BUDGET_MS, step = MockWoW.config.profileStep }
    PC:CancelAsync()
    PC.asyncRunning, PC.asyncQueue = nil, {}
    local queue = {}
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    MockWoW.config.profileStep = 1
    local function drain()
        local steps = 0
        while #queue > 0 and steps < 100000 do table.remove(queue, 1)(); steps = steps + 1 end
        return steps
    end
    local ok, err = pcall(body, drain)
    PC:CancelAsync()
    drain()
    C_Timer.After, PC.FRAME_BUDGET_MS = saved.after, saved.budget
    MockWoW.config.profileStep = saved.step
    PC.asyncRunning, PC.asyncQueue = nil, {}
    PC.graphDirty = true
    if not ok then error(err, 0) end
end

T:run("Graph build slices: a build inside the driver pauses and others see the previous graph", function(t)
    withDriver(function(drain)
        PC:BuildGraph()
        PC.graphDirty = false
        local previous = PC.graph
        PC.graphDirty = true
        PC.FRAME_BUDGET_MS = 0 -- every pause point pauses
        local pauses = PC.graphPauses or 0
        local route
        PC:CalculatePathAsync(84, 0.6, 0.6, nil, function(r) route = r end)
        t:assertNotNil(PC.asyncRunning, "the route is parked inside its build")
        t:assertEqual(previous, PC.graph, "between slices the previous, complete graph is the published one")
        t:assertTrue(PC.graphDirty and true or false, "and it is still marked for rebuild")
        drain()
        -- Seven pause points between the steps, and more inside the dungeon
        -- pass, one per eight entrances.
        t:assertGreaterThan((PC.graphPauses or 0) - pauses, 12,
            "the build paused between its steps and inside the dungeon pass, pauses " .. ((PC.graphPauses or 0) - pauses))
        t:assertNotNil(route, "the route is published at the end")
        t:assertTrue(PC.graph ~= previous, "on the new graph")
        local sliced = edgeList(PC.graph)
        PC.graphDirty = true
        PC:BuildGraph()
        local whole = edgeList(PC.graph)
        t:assertEqual(#whole, #sliced, "the sliced build has the edges of a build in one piece, got " .. #sliced .. " of " .. #whole)
        t:assertEqual(table.concat(whole, "\n"), table.concat(sliced, "\n"), "edge for edge")
    end)
end)

T:run("Graph build slices: a rebuild by somebody else while the build pauses wins", function(t)
    withDriver(function(drain)
        PC:BuildGraph()
        PC.graphDirty = true
        PC.FRAME_BUDGET_MS = 0
        local route
        PC:CalculatePathAsync(84, 0.6, 0.6, nil, function(r) route = r end)
        t:assertNotNil(PC.asyncRunning, "the route is parked inside its build")
        -- A synchronous caller rebuilds between two slices.
        PC:BuildGraph()
        local theirs = PC.graph
        drain()
        t:assertEqual(theirs, PC.graph, "the parked build gives up and leaves the other graph in place")
        t:assertNotNil(route, "the route is still answered, on that graph")
    end)
end)

T:run("Graph build slices: a mark written while the build pauses survives it", function(t)
    withDriver(function(drain)
        PC:BuildGraph()
        PC.graphDirty = true
        PC.FRAME_BUDGET_MS = 0
        local route
        PC:CalculatePathAsync(84, 0.6, 0.6, nil, function(r) route = r end)
        t:assertNotNil(PC.asyncRunning, "the route is parked inside its build")
        -- What a production site does between two slices, e.g. a zone change.
        PC.graphDirty = true
        PC.dirtyReason = "zone"
        drain()
        t:assertNotNil(route, "the route is still answered")
        t:assertTrue(PC.graphDirty, "but the graph stays marked for the newer data")
        t:assertEqual("zone", PC.dirtyReason, "with the reason of that mark")
    end)
end)

T:run("Graph build slices: outside the driver a build runs in one piece", function(t)
    local pauses = PC.graphPauses or 0
    PC.graphDirty = true
    PC:BuildGraph()
    t:assertEqual(pauses, PC.graphPauses or 0, "a synchronous build never pauses")
    t:assertFalse(PC.graphDirty, "and leaves a clean graph")
end)

T:run("Graph build slices: a build collects the fixed phase maps before the first search", function(t)
    PC.graphDirty = true
    PC:BuildGraph()
    local cache = PC.graph.phaseMapCache
    t:assertNotNil(cache, "the build filled the cache")
    t:assertEqual(PC.graph.staticVersion, cache and cache.version, "for the graph as built")
    withDriver(function(drain)
        PC.graphDirty = true
        PC.FRAME_BUDGET_MS = 0
        PC:CalculatePathAsync(84, 0.6, 0.6, nil, function() end)
        drain()
        t:assertNotNil(PC.graph.phaseMapCache, "a sliced build fills it too")
    end)
end)

T:run("Phase map cache: the fixed part is collected once and again after it changed", function(t)
    local TR = QR.TravelRequirements
    local graph = QR.Graph:New()
    graph:AddNode("A", { mapID = 84, x = 0.1, y = 0.1 })
    graph:AddNode("B", { mapID = 85, x = 0.2, y = 0.2, requirements = { mapArtID = { mapID = 2000, artID = 1 } } })
    graph:AddEdge("A", "B", 1, "walk", {})
    local first = TR:StaticPhaseMaps(graph)
    t:assertTrue(first[2000], "a node's phase map is collected")
    -- A search's own nodes do not change the fixed part.
    graph:AddNode("Player Location", { nodeType = "player", mapID = 84, x = 0.5, y = 0.5 })
    graph:AddNode("Goal", { mapID = 86, x = 0.5, y = 0.5, transient = true,
        requirements = { mapArtID = { mapID = 3000, artID = 1 } } })
    graph:AddEdge("Player Location", "A", 1, "walk", {})
    graph:AddEdge("B", "Goal", 1, "walk", {})
    graph:RemoveNode("Goal")
    t:assertEqual(first, TR:StaticPhaseMaps(graph), "transient nodes and their edges leave the cache as it is")
    -- A fixed edge with a phase map does.
    graph:AddEdge("B", "A", 1, "phaseswitch", { phaseMapID = 4000 })
    local second = TR:StaticPhaseMaps(graph)
    t:assertTrue(second ~= first, "a change to the fixed part collects again")
    t:assertTrue(second[4000], "and finds the new edge's phase map")
end)
