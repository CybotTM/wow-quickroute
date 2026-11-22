-------------------------------------------------------------------------------
-- test_route_background.lua
-- Background route requests (CalculatePathAsync with background = true): the
-- quest buttons ask for routes nobody is waiting for. They queue behind every
-- other request, take a smaller slice, wait out combat and write no trace.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local PC = QR.PathCalculator

--- A driver the test steps by hand: C_Timer.After queues instead of running,
-- CalculatePath is a stand-in that records its destination and parks once,
-- and SetYieldHook is watched so a slice's budget can be measured.
local function withDriver(body)
    local saved = {
        after = C_Timer.After,
        calculate = PC.CalculatePath,
        setHook = QR.Graph.SetYieldHook,
        combat = MockWoW.config.inCombatLockdown,
        step = MockWoW.config.profileStep,
    }
    PC:CancelAsync()
    local queue, order, budgets = {}, {}, {}
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    local hook
    QR.Graph.SetYieldHook = function(h)
        hook = h
        saved.setHook(h)
    end
    MockWoW.config.profileStep = 1
    PC.CalculatePath = function(_, destMapID)
        -- How many profiler milliseconds this slice may spend: the mock clock
        -- advances by one on every read, so count the reads until the hook
        -- says the budget is gone. The read that set the deadline is the
        -- driver's, so a budget of N leaves N - 1 reads here.
        local reads = 0
        while hook and not hook() and reads < 100 do reads = reads + 1 end
        budgets[#budgets + 1] = { dest = destMapID, reads = reads }
        coroutine.yield()
        order[#order + 1] = destMapID
        return { totalTime = 1, steps = {} }
    end
    local function drain(limit)
        local steps = 0
        while #queue > 0 and steps < (limit or 50) do
            table.remove(queue, 1)()
            steps = steps + 1
        end
        return steps
    end
    local ok, err = pcall(body, { queue = queue, order = order, budgets = budgets, drain = drain,
        currentHook = function() return hook end })
    PC:CancelAsync()
    -- A parked stand-in still holds a coroutine; let it finish so the next
    -- file starts with an idle calculator.
    MockWoW.config.inCombatLockdown = false
    drain(200)
    C_Timer.After = saved.after
    PC.CalculatePath = saved.calculate
    QR.Graph.SetYieldHook = saved.setHook
    MockWoW.config.inCombatLockdown = saved.combat
    MockWoW.config.profileStep = saved.step
    PC.asyncRunning, PC.asyncQueue = nil, {}
    if not ok then error(err, 0) end
end

local function budgetFor(budgets, dest)
    for _, entry in ipairs(budgets) do
        if entry.dest == dest then return entry.reads end
    end
end

T:run("Background routes: a foreground request overtakes a waiting background one", function(t)
    withDriver(function(d)
        PC:CalculatePathAsync(10, 0.5, 0.5, nil, function() end, { consumer = "first" })
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() end, { consumer = "quest_buttons", background = true })
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() end, { consumer = "panel" })
        d.drain()
        t:assertEqual("10,30,20", table.concat(d.order, ","),
            "the panel's request runs before the waiting background one, order " .. table.concat(d.order, ","))
    end)
end)

T:run("Background routes: a background request takes the small budget", function(t)
    withDriver(function(d)
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() end, { consumer = "quest_buttons", background = true })
        d.drain()
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() end, { consumer = "panel" })
        d.drain()
        local background, foreground = budgetFor(d.budgets, 20), budgetFor(d.budgets, 30)
        t:assertEqual(PC.BACKGROUND_BUDGET_MS - 1, background,
            "the background slice spends BACKGROUND_BUDGET_MS, got " .. tostring(background) .. " reads")
        t:assertEqual(PC.FRAME_BUDGET_MS - 1, foreground,
            "the foreground slice spends FRAME_BUDGET_MS, got " .. tostring(foreground) .. " reads")
    end)
end)

T:run("Background routes: a waiting foreground request speeds up the running background one", function(t)
    withDriver(function(d)
        -- The background request's first slice runs before the panel asks,
        -- its second one after: measured once per slice.
        local reads = {}
        local function measure()
            local count = 0
            -- The hook of the running slice, installed by the driver.
            local hook = d.currentHook()
            while hook and not hook() and count < 100 do count = count + 1 end
            reads[#reads + 1] = count
        end
        PC.CalculatePath = function(_, destMapID)
            if destMapID == 20 then
                measure(); coroutine.yield()
                measure(); coroutine.yield()
            end
            d.order[#d.order + 1] = destMapID
            return { totalTime = 1, steps = {} }
        end
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() end, { consumer = "quest_buttons", background = true })
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() end, { consumer = "panel" })
        d.drain()
        t:assertEqual(PC.BACKGROUND_BUDGET_MS - 1, reads[1],
            "alone, the background slice gets the small budget, got " .. tostring(reads[1]) .. " reads")
        t:assertEqual(PC.FRAME_BUDGET_MS - 1, reads[2],
            "with the panel waiting, it gets the full budget, got " .. tostring(reads[2]) .. " reads")
        t:assertEqual("20,30", table.concat(d.order, ","), "and both finish, background first")
    end)
end)

T:run("Background routes: combat parks a background request until the fight ends", function(t)
    withDriver(function(d)
        local done = false
        MockWoW.config.inCombatLockdown = true
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() done = true end,
            { consumer = "quest_buttons", background = true })
        d.drain(10)
        t:assertEqual(0, #d.budgets, "no slice ran in combat, slices " .. #d.budgets)
        t:assertFalse(done, "and nothing was published")
        t:assertNotNil(PC.asyncRunning, "the request is still the running one")
        MockWoW.config.inCombatLockdown = false
        d.drain()
        t:assertTrue(done, "after the fight the request finishes")
    end)
end)

T:run("Background routes: combat parks a background request between two slices", function(t)
    withDriver(function(d)
        local done = false
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() done = true end,
            { consumer = "quest_buttons", background = true })
        t:assertEqual(1, #d.budgets, "the first slice ran before the fight")
        MockWoW.config.inCombatLockdown = true
        d.drain(10)
        t:assertFalse(done, "the parked request does not finish in combat")
        t:assertEqual(0, #d.order, "its second slice did not run")
        MockWoW.config.inCombatLockdown = false
        d.drain()
        t:assertTrue(done, "it finishes after the fight")
    end)
end)

T:run("Background routes: a foreground request in combat is not held up by a parked one", function(t)
    withDriver(function(d)
        local panel = false
        MockWoW.config.inCombatLockdown = true
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() end, { consumer = "quest_buttons", background = true })
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() panel = true end, { consumer = "api" })
        d.drain(20)
        t:assertTrue(panel, "the foreground request finished in combat")
        t:assertEqual("20,30", table.concat(d.order, ","),
            "the parked background request ran to its end first, order " .. table.concat(d.order, ","))
    end)
end)

T:run("Background routes: the wait after a fight parks a background request until it is over", function(t)
    local cfg = MockWoW.config
    local savedTime = cfg.baseTime
    local ok, err = pcall(withDriver, function(d)
        -- What the combat frame does when the fight ends.
        QR.combatFrame:GetScript("OnEvent")(QR.combatFrame, "PLAYER_REGEN_ENABLED")
        t:assertEqual(cfg.baseTime, QR.combatEndedAt, "the end of the fight is recorded")
        local done = false
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() done = true end,
            { consumer = "quest_buttons", background = true })
        d.drain(10)
        t:assertEqual(0, #d.budgets, "no slice ran in the wait, slices " .. #d.budgets)
        t:assertFalse(done, "and nothing was published")
        cfg.baseTime = cfg.baseTime + QR.POST_COMBAT_GRACE - 1
        d.drain(10)
        t:assertFalse(done, "one second before the end it still waits")
        cfg.baseTime = cfg.baseTime + 1
        d.drain()
        t:assertTrue(done, "when the wait is over the request finishes")
    end)
    cfg.baseTime, QR.combatEndedAt = savedTime, nil
    if not ok then error(err, 0) end
end)

T:run("Background routes: a foreground request is not held up by the wait after a fight", function(t)
    local ok, err = pcall(withDriver, function(d)
        QR.combatEndedAt = MockWoW.config.baseTime
        local panel = false
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() panel = true end, { consumer = "api" })
        d.drain(20)
        t:assertTrue(panel, "the foreground request finished in the wait")
    end)
    QR.combatEndedAt = nil
    if not ok then error(err, 0) end
end)

T:run("Background routes: a new fight restarts the wait from its own end", function(t)
    local cfg = MockWoW.config
    local savedTime = cfg.baseTime
    QR.combatEndedAt = cfg.baseTime
    cfg.baseTime = cfg.baseTime + QR.POST_COMBAT_GRACE - 1
    local before = QR:PostCombatGraceLeft()
    QR.combatFrame:GetScript("OnEvent")(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    local after = QR:PostCombatGraceLeft()
    cfg.baseTime, QR.combatEndedAt = savedTime, nil
    t:assertEqual(1, before, "one second was left of the first wait")
    t:assertEqual(QR.POST_COMBAT_GRACE, after, "the second fight's end starts a full wait")
end)

T:run("Background routes: a background request writes no trace entries", function(t)
    local D = QR.Diagnostics
    local savedTracing, savedTrace = D.IsTracing, D.Trace
    local written = {}
    D.IsTracing = function() return true end
    D.Trace = function(_, category, message) written[#written + 1] = category .. ":" .. message end
    local ok, err = pcall(withDriver, function(d)
        PC:CalculatePathAsync(20, 0.5, 0.5, nil, function() end, { consumer = "quest_buttons", background = true })
        d.drain()
        local background = #written
        PC:CalculatePathAsync(30, 0.5, 0.5, nil, function() end, { consumer = "panel" })
        d.drain()
        t:assertEqual(0, background, "the background request traced nothing, got " .. table.concat(written, " | "))
        t:assertEqual(2, #written - background, "a foreground request still traces request and result, got " .. (#written - background))
    end)
    D.IsTracing, D.Trace = savedTracing, savedTrace
    if not ok then error(err, 0) end
end)
