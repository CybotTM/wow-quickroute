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
    -- One frame: the timers already scheduled run, the ones they schedule wait.
    local function tick()
        local frame = queue
        queue = {}
        for _, callback in ipairs(frame) do callback() end
    end
    local ok, err = pcall(body, pc, drain, tick)
    pc.CalculatePath, C_Timer.After = savedCalculate, savedAfter
    pc:CancelAsync()
    if not ok then error(err, 0) end
end

T:run("RoutingAPI: the global is present and versioned", function(t)
    t:assertNotNil(_G.QuickRouteAPI, "other addons find QuickRouteAPI")
    t:assertEqual(QR.RoutingAPI, _G.QuickRouteAPI, "the global is the module, not a copy")
    t:assertEqual(2, QuickRouteAPI:GetVersion(), "the contract states its version")
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

T:run("RoutingAPI: a consumer refuses a step for one destination, not for all of them", function(t)
    QR.PathCalculator:ClearExcludedEdges()
    local target = { mapID = 84, x = 0.5, y = 0.5 }
    t:assertFalse(QuickRouteAPI:RejectStep("Gate", "Goal"),
        "a refusal without a destination is refused: it would close the connection everywhere")
    t:assertTrue(QuickRouteAPI:RejectStep("Gate", "Goal", target), "with one it is accepted")
    QR.PathCalculator:NoteJourneyDestination(84, 0.5, 0.5)
    t:assertTrue(QR.PathCalculator:IsEdgeExcluded("Gate", "Goal"), "and reaches the router for that destination")
    QR.PathCalculator:NoteJourneyDestination(1519, 0.1, 0.1)
    t:assertFalse(QR.PathCalculator:IsEdgeExcluded("Gate", "Goal"),
        "the player's own route somewhere else is unaffected")
    QuickRouteAPI:AcceptStep("Gate", "Goal")
    QR.PathCalculator:NoteJourneyDestination(84, 0.5, 0.5)
    t:assertFalse(QR.PathCalculator:IsEdgeExcluded("Gate", "Goal"), "and it can be taken back")
    QR.PathCalculator:ClearExcludedEdges()
end)

T:run("RoutingAPI: a superseded request is told, not left silent", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local first, second
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function(route, failure) first = failure and failure.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" },
            function(route, failure) second = failure and failure.reason or "route" end)
        drain()
        t:assertEqual("superseded", first, "the first request hears why it will get nothing")
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

T:run("RoutingAPI: a retry issued from the superseded callback is not lost", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local log = {}
        local function consumerA(route, failure)
            if failure and failure.reason == "superseded" then
                log[#log + 1] = "a:superseded"
                QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" }, function(r, f)
                    log[#log + 1] = "retry:" .. (f and f.reason or "route")
                end)
            else
                log[#log + 1] = "a:route"
            end
        end
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" }, consumerA)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" }, function(r, f)
            log[#log + 1] = "b:" .. (f and f.reason or "route")
        end)
        drain()
        -- Every consumer hears exactly one answer: A that it was superseded, the
        -- retry it then issued, and B.
        local heard = {}
        for _, entry in ipairs(log) do heard[entry:match("^[^:]+")] = true end
        t:assertTrue(heard["retry"], "the retry hears an answer, got: " .. table.concat(log, ", "))
        t:assertTrue(heard["a"], "and so does the consumer that was superseded")
        t:assertTrue(heard["b"], "and so does the one that superseded it")
    end)
end)

T:run("RoutingAPI: superseded reads as its own sentence, not as an internal error", function(t)
    local text = QR.PathCalculator:DescribeFailure({ reason = "superseded" })
    t:assertEqual(QR.L["ROUTE_FAIL_SUPERSEDED"], text, "the player is told what happened")
    t:assertNotNil(text ~= QR.L["ROUTE_FAIL_INTERNAL"] or nil, "and not that the addon is broken")
end)

T:run("RoutingAPI: an internal calculation queues behind the contract rather than taking it", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local heard, internal
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function(_, failure) heard = failure and failure.reason or "route" end)
        -- QuickRoute's own dungeon offer, the route panel, POIRouting: all of
        -- these take the calculator without going through the contract. They
        -- used to supersede whatever was in flight, so opening the route panel
        -- cancelled a foreign addon's request. Each consumer now supersedes
        -- only its own earlier requests, and the rest queue.
        pc:CalculatePathAsync(85, 0.2, 0.2, nil, function(route) internal = route and "route" or "none" end,
            { consumer = QR.ROUTE_CONSUMER.ROUTE_PANEL })
        drain()
        t:assertEqual("route", heard, "the contract's request still publishes")
        t:assertEqual("route", internal, "and so does the internal one that followed it")
    end)
end)

T:run("RoutingAPI: a late publish does not keep a newer request from being told", function(t)
    withDriver(function(pc, drain, tick)
        -- h1 is short and finishes in its first slice; its publish waits one
        -- tick. h2 is asked for before that tick and takes several frames. In
        -- version 1 that tick emptied the one slot the contract kept, which h2
        -- had taken, so when h3 replaced h2 nobody told h2 -- the one answer
        -- the contract promises never to withhold.
        local calls = 0
        pc.CalculatePath = function()
            calls = calls + 1
            if calls > 1 then
                for _ = 1, 3 do coroutine.yield() end
            end
            return { totalTime = 1, steps = {} }
        end
        local heard = {}
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) heard.h1 = f and f.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) heard.h2 = f and f.reason or "route" end)
        tick()
        t:assertNil(heard.h2, "h2 is still running after one frame")
        QuickRouteAPI:CalculateRoute({ mapID = 86, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) heard.h3 = f and f.reason or "route" end)
        drain()
        t:assertEqual("superseded", heard.h2, "h2 is told it was replaced, got " .. tostring(heard.h2))
        t:assertEqual("route", heard.h3, "h3 got its route, got " .. tostring(heard.h3))
    end)
end)

T:run("RoutingAPI: cancelling one request leaves another consumer's alone", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local internal
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        pc:CalculatePathAsync(85, 0.2, 0.2, nil, function(route) internal = route and "route" or "none" end,
            { consumer = QR.ROUTE_CONSUMER.DUNGEON_OFFER })
        QuickRouteAPI:Cancel(handle)
        drain()
        t:assertEqual("route", internal, "the other consumer's request survives the withdrawal")
    end)
end)

T:run("RoutingAPI: one owner's retries do not replace each other forever", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local rounds = 0
        local function retryer(mapID)
            local again
            again = function(_, failure)
                if failure and failure.retryable then
                    rounds = rounds + 1
                    if rounds < 50 then
                        QuickRouteAPI:CalculateRoute({ mapID = mapID, x = 0.5, y = 0.5, owner = "AddonA" }, again)
                    end
                end
            end
            return again
        end
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" }, retryer(84))
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" }, retryer(85))
        drain()
        t:assertEqual(0, rounds,
            "supersession is not advertised as retryable, so neither consumer restarts the other, got " .. rounds)
    end)
end)

T:run("RoutingAPI: a cancelled request stays silent even when something supersedes it", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local calls = 0
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function() calls = calls + 1 end)
        QuickRouteAPI:Cancel(handle)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" }, function() end)
        drain()
        t:assertEqual(0, calls, "a withdrawn consumer hears nothing at all, got " .. calls)
    end)
end)

T:run("RoutingAPI: cancelling after a supersede still silences the consumer", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local calls = 0
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function() calls = calls + 1 end)
        -- The supersede is queued first, the withdrawal comes after it. The
        -- queued notice has to notice.
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" }, function() end)
        t:assertTrue(QuickRouteAPI:Cancel(handle), "the handle is accepted")
        drain()
        t:assertEqual(0, calls, "a withdrawn consumer hears nothing, got " .. calls)
    end)
end)

T:run("RoutingAPI: two addons with different owners do not supersede each other", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local a, b
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) a = f and f.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonB" },
            function(_, f) b = f and f.reason or "route" end)
        drain()
        t:assertEqual("route", a, "addon A still gets its route, got " .. tostring(a))
        t:assertEqual("route", b, "addon B gets its route, got " .. tostring(b))
    end)
end)

T:run("RoutingAPI: requests without an owner run independently", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local first, second
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function(_, f) first = f and f.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5 },
            function(_, f) second = f and f.reason or "route" end)
        drain()
        t:assertEqual("route", first, "the first request is not replaced, got " .. tostring(first))
        t:assertEqual("route", second, "the second one publishes too, got " .. tostring(second))
    end)
end)

T:run("RoutingAPI: an owner's request does not supersede a request without one", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local anonymous, owned
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function(_, f) anonymous = f and f.reason or "route" end)
        QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) owned = f and f.reason or "route" end)
        drain()
        t:assertEqual("route", anonymous, "the request without an owner survives, got " .. tostring(anonymous))
        t:assertEqual("route", owned, "and the owned one publishes, got " .. tostring(owned))
    end)
end)

T:run("RoutingAPI: an owner that is not a non-empty string is refused", function(t)
    for _, owner in ipairs({ "", 42, {} }) do
        local handle, failure = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = owner },
            function() end)
        t:assertNil(handle, "no handle for owner " .. tostring(owner))
        t:assertEqual("invalid_request", failure and failure.reason,
            "the refusal is named for owner " .. tostring(owner))
    end
end)

T:run("RoutingAPI: a request cancelled before its finished route is delivered stays silent", function(t)
    withDriver(function(pc, drain)
        -- Finishes inside the first slice, so the calculator is done before
        -- Cancel; only the delivery, one tick later, is left to stop.
        pc.CalculatePath = function() return { totalTime = 1, steps = {} } end
        local calls = 0
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
            function() calls = calls + 1 end)
        QuickRouteAPI:Cancel(handle)
        drain()
        t:assertEqual(0, calls, "the withdrawn consumer is not called, got " .. calls)
    end)
end)

T:run("RoutingAPI: past the pending limit a request is refused, and nobody else's is touched", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local heard = {}
        for i = 1, QuickRouteAPI.MAX_PENDING do
            local handle = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 },
                function(_, f) heard[i] = f and f.reason or "route" end)
            t:assertNotNil(handle, "request " .. i .. " within the limit is taken")
        end
        local told
        local refused, failure = QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5 },
            function(_, f) told = f and f.reason or "route" end)
        t:assertNil(refused, "a request past the limit gets no handle")
        t:assertEqual("busy", failure and failure.reason, "the refusal is named, got "
            .. tostring(failure and failure.reason))
        t:assertTrue(failure and failure.retryable, "and retrying later can work")
        local newOwner = QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonB" },
            function() end)
        t:assertNil(newOwner, "an owner with nothing waiting is refused too")
        drain()
        t:assertEqual("busy", told, "the refused consumer also hears it through its callback, got " .. tostring(told))
        for i = 1, QuickRouteAPI.MAX_PENDING do
            t:assertEqual("route", heard[i], "request " .. i .. " still got its route, got " .. tostring(heard[i]))
        end
        t:assertNotNil(QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5 }, function() end),
            "once the queue has drained a request is taken again")
        drain()
    end)
end)

T:run("RoutingAPI: at the limit an owner can still replace its own waiting request", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local first, second
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) first = f and f.reason or "route" end)
        for _ = 2, QuickRouteAPI.MAX_PENDING do
            QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        end
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) second = f and f.reason or "route" end)
        t:assertNotNil(handle, "the owner's replacement is taken although the queue is full")
        drain()
        t:assertEqual("superseded", first, "the replaced request is told, got " .. tostring(first))
        t:assertEqual("route", second, "the replacement publishes, got " .. tostring(second))
    end)
end)

T:run("RoutingAPI: at the limit an owner can replace its request while it waits in the queue", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        -- An anonymous request takes the calculator first, so AddonA's waits in
        -- the queue rather than running.
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        local first, second
        QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) first = f and f.reason or "route" end)
        for _ = 3, QuickRouteAPI.MAX_PENDING do
            QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        end
        local handle = QuickRouteAPI:CalculateRoute({ mapID = 85, x = 0.5, y = 0.5, owner = "AddonA" },
            function(_, f) second = f and f.reason or "route" end)
        t:assertNotNil(handle, "the queued owner's replacement is taken although the queue is full")
        drain()
        t:assertEqual("superseded", first, "the queued request is told it was replaced, got " .. tostring(first))
        t:assertEqual("route", second, "the replacement publishes, got " .. tostring(second))
    end)
end)

T:run("RoutingAPI: a cancelled running request does not hold a place under the limit", function(t)
    withDriver(function(pc, drain)
        pc.CalculatePath = function() coroutine.yield() return { totalTime = 1, steps = {} } end
        local running = QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end)
        QuickRouteAPI:Cancel(running)
        local taken = 0
        for _ = 1, QuickRouteAPI.MAX_PENDING do
            if QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function() end) then
                taken = taken + 1
            end
        end
        t:assertEqual(QuickRouteAPI.MAX_PENDING, taken,
            "the full limit is available after the cancel, got " .. taken)
        drain()
    end)
end)
