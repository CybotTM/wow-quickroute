local T, QR, MockWoW = ...

-- The contract other addons consume. A consumer must be able to ask for a
-- route, read the answer, and cancel the request, without QuickRoute taking
-- over the player's pin and without the consumer reaching into internal state.

local function withDriver(body)
    local pc = QR.PathCalculator
    local savedCalculate, savedAfter = pc.CalculatePath, C_Timer.After
    local queue = {}
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    local function drain()
        while #queue > 0 do
            local callback = table.remove(queue, 1)
            callback()
        end
    end
    local ok, err = pcall(body, pc, drain)
    pc.CalculatePath, C_Timer.After = savedCalculate, savedAfter
    pc:CancelAsync()
    if not ok then error(err, 0) end
end

T:run("RoutingAPI: the global is present and versioned", function(t)
    t:assertNotNil(_G.QuickRouteAPI, "other addons find QuickRouteAPI")
    t:assertEqual(QR.RoutingAPI, _G.QuickRouteAPI, "the global is the module, not a copy")
    t:assertEqual(1, QuickRouteAPI:GetVersion(), "the contract states its version")
end)

T:run("RoutingAPI: a route is returned as detached data a consumer can iterate", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function()
            return {
                totalTime = 120,
                steps = {
                    { type = "walk", action = "Go to Gate", time = 20, from = "A", to = "Gate",
                      navMapID = 84, navX = 0.2, navY = 0.3, navTitle = "Gate", secret = "internal" },
                    { type = "portal", action = "Take portal", time = 100, from = "Gate", to = "B",
                      navMapID = 84, navX = 0.4, navY = 0.5, navTitle = "Portal" },
                },
            }
        end
        local got
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, title = "Target" },
            function(result) got = result end)
        t:assertNotNil(handle, "a request yields a handle")
        drain()
        t:assertNotNil(got, "the callback receives a result")
        t:assertEqual(2, #got.steps, "the step list has a usable length, got " .. #got.steps)
        local walked = 0
        for _ in ipairs(got.steps) do walked = walked + 1 end
        t:assertEqual(2, walked, "ipairs walks the whole step list")
        t:assertEqual(85, got.target.mapID, "the result names what was asked for")
        t:assertEqual(120, got.totalTime, "the estimate travels with it")
        t:assertNil(got.steps[1].secret, "internal step fields do not leak into the contract")
        t:assertEqual("Gate", got.steps[1].navTitle, "the named fields do travel")
    end)
end)

T:run("RoutingAPI: a consumer's changes cannot reach QuickRoute", function(t)
    withDriver(function(pc, drain)
        local internal = { totalTime = 10, steps = { { type = "walk", to = "B", navMapID = 84 } } }
        pc.CalculatePath = function() return internal end
        local got
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function(result) got = result end)
        drain()
        got.steps[1].to = "Somewhere else"
        got.totalTime = 0
        t:assertEqual("B", internal.steps[1].to, "the internal step is unchanged")
        t:assertEqual(10, internal.totalTime, "the internal estimate is unchanged")
    end)
end)

T:run("RoutingAPI: a failure arrives as a named reason", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function()
            return nil, { reason = "position_unavailable", retryable = true }
        end
        local route, failure = nil, nil
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function(r, f) route, failure = r, f end)
        drain()
        t:assertNil(route, "no route on failure")
        t:assertEqual("position_unavailable", failure.reason, "the reason reaches the consumer")
        t:assertTrue(failure.retryable, "so does whether retrying can work")
    end)
end)

T:run("RoutingAPI: a cancelled request never calls back", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local calls = 0
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function() calls = calls + 1 end)
        t:assertTrue(QuickRouteAPI:Cancel(handle), "the handle is accepted")
        drain()
        t:assertEqual(0, calls, "the withdrawn request stays silent")
    end)
end)

T:run("RoutingAPI: a bad request is refused without starting work", function(t)
    local handle, failure = QuickRouteAPI:CalculateRoute({ mapID = "84" }, function() end)
    t:assertNil(handle, "a request without numeric coordinates yields no handle")
    t:assertEqual("invalid_request", failure.reason, "the refusal is named")
    t:assertNil(QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, nil), "a missing callback is refused")
end)

T:run("RoutingAPI: asking for a route does not touch the player's waypoint", function(t)
    withDriver(function(pc, drain)
        local wi = QR.WaypointIntegration
        local savedSet = wi.SetTomTomWaypoint
        local touched = 0
        wi.SetTomTomWaypoint = function() touched = touched + 1 end
        pc.CalculatePath = function()
            return { totalTime = 5, steps = { { type = "walk", to = "B", navMapID = 84, navX = 0.1, navY = 0.1 } } }
        end
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        drain()
        wi.SetTomTomWaypoint = savedSet
        t:assertEqual(0, touched, "calculating a route set no waypoint")
    end)
end)

T:run("RoutingAPI: the result states what the estimate assumes", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function()
            return { totalTime = 60, steps = {
                { type = "flight", to = "Far", navMapID = 999999, navX = 0.1, navY = 0.1 },
            } }
        end
        local got
        QuickRouteAPI:CalculateRoute({ mapID = 999999, x = 0.5, y = 0.5 }, function(result) got = result end)
        drain()
        t:assertTrue(got.assumptions.taxiTimeIsHeuristic, "a flight leg is declared an estimate")
        t:assertEqual(999999, got.assumptions.movementUnknownMaps[1],
            "a map with unknown movement eligibility is named")
    end)
end)

T:run("RoutingAPI: a consumer can refuse a step the same way the player can", function(t)
    QR.PathCalculator:ClearExcludedEdges()
    t:assertTrue(QuickRouteAPI:RejectStep("Gate", "Goal"), "the refusal is accepted")
    t:assertTrue(QR.PathCalculator:IsEdgeExcluded("Gate", "Goal"), "and reaches the router")
    QuickRouteAPI:AcceptStep("Gate", "Goal")
    t:assertFalse(QR.PathCalculator:IsEdgeExcluded("Gate", "Goal"), "and can be taken back")
    QR.PathCalculator:ClearExcludedEdges()
end)

T:run("RoutingAPI: a superseded request is told, not left silent", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local first, second
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function(route, failure) first = failure and failure.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5 },
            function(route, failure) second = failure and failure.reason or "route" end)
        drain()
        t:assertEqual("superseded", first, "the first consumer hears why it will get nothing")
        t:assertEqual("route", second, "the current request still publishes")
    end)
end)

T:run("RoutingAPI: a forged handle cannot cancel somebody else's calculation", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local delivered = 0
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function() delivered = delivered + 1 end)
        for generation = 1, 20 do
            t:assertFalse(QuickRouteAPI:Cancel({ generation = generation }),
                "a table that this API did not issue is refused")
        end
        drain()
        t:assertEqual(1, delivered, "the real request still published")
        t:assertTrue(QuickRouteAPI:Cancel(handle), "the real handle is still accepted")
    end)
end)

T:run("RoutingAPI: the callback never runs before the caller holds the handle", function(t)
    withDriver(function(pc, drain)
        -- A short route finishes inside the first budget, which used to publish
        -- from inside CalculateRoute itself.
        pc.CalculatePath = function() return { totalTime = 1, steps = {} } end
        local handleAtCallback, sentinel = "unset", {}
        local handle = sentinel
        handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function() handleAtCallback = handle end)
        t:assertEqual("unset", handleAtCallback, "nothing was published before CalculateRoute returned")
        drain()
        t:assertEqual(handle, handleAtCallback, "and the consumer holds its handle when the callback runs")
        t:assertNotNil(handle, "a handle was returned")
    end)
end)

T:run("RoutingAPI: a failure the consumer edits cannot reach the router", function(t)
    withDriver(function(pc, drain)
        local internal = { reason = "position_unavailable", retryable = true }
        pc.CalculatePath = function() return nil, internal end
        local got
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function(_, failure) got = failure end)
        drain()
        got.reason = "edited"
        t:assertEqual("position_unavailable", internal.reason, "the router's own failure table is untouched")
    end)
end)
