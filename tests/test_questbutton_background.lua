-------------------------------------------------------------------------------
-- test_questbutton_background.lua
-- The quest buttons' routes are background work: asked for as background
-- requests, answered on a later frame, bounded per minute, spread in expiry,
-- and paused inside instances.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local QTB = QR.QuestTeleportButtons
local PC = QR.PathCalculator

--- The real module and calculator, with a stand-in search that records its
-- destination and, when asked to, finishes one frame later. C_Timer.After
-- queues; the test drains the queue itself.
local function withButtons(body)
    local cfg = MockWoW.config
    local saved = {
        combat = cfg.inCombatLockdown, watches = cfg.questWatches,
        waypoints = cfg.questWaypoints, titles = cfg.questTitles,
        knownSpell = cfg.knownSpells[3561], baseTime = cfg.baseTime,
        inInstance = cfg.inInstance, instanceType = cfg.instanceType,
        calculate = PC.CalculatePath, async = PC.CalculatePathAsync,
        after = C_Timer.After, routes = QTB.ROUTES_PER_MINUTE, enabled = QTB.enabled,
        graphDirty = PC.graphDirty,
    }
    cfg.inCombatLockdown = false
    cfg.inInstance, cfg.instanceType = false, "none"
    cfg.questWatches, cfg.questWaypoints, cfg.questTitles = {}, {}, {}
    cfg.knownSpells[3561] = true
    QR.PlayerInventory:ScanAll()
    QR.WaypointIntegration:ClearQuestCoordCache()
    if not PC.graph then PC:BuildGraph() end
    PC.graphDirty = false
    PC:CancelAsync()
    PC.asyncRunning, PC.asyncQueue = nil, {}

    local state = { routes = {}, yield = false, queue = {} }
    C_Timer.After = function(_, callback) state.queue[#state.queue + 1] = callback end
    PC.CalculatePath = function(_, destMapID)
        state.routes[#state.routes + 1] = destMapID
        if state.yield and coroutine.running() then coroutine.yield() end
        return { totalTime = 10, steps = { { type = "teleport", teleportID = 3561, sourceType = "spell" } } }
    end
    function state.drain(limit)
        local steps = 0
        while #state.queue > 0 and steps < (limit or 100) do
            table.remove(state.queue, 1)()
            steps = steps + 1
        end
    end
    function state.track(questID, mapID, x, y)
        cfg.questTitles[questID] = "Background quest " .. questID
        cfg.questWaypoints[questID] = { mapID = mapID or 84, x = x or 0.5, y = y or 0.5 }
        cfg.questWatches[#cfg.questWatches + 1] = questID
    end
    function state.refresh()
        QTB:RefreshButtons()
        state.drain()
    end

    QTB.enabled = true
    if not QTB.initialized then QTB:Initialize() end
    QTB:ReleaseAllButtons()
    -- The bound counts by GetTime, and the mock's clock stands still, so the
    -- routes of earlier tests would fill it.
    QTB:ResetRouteBudget()

    local ok, err = pcall(body, state)

    QTB:CancelRefresh()
    PC:CancelAsync()
    cfg.inCombatLockdown = false
    state.yield = false
    state.drain(200)
    QTB:ReleaseAllButtons()
    QTB:ResetRouteBudget()
    PC.asyncRunning, PC.asyncQueue = nil, {}
    cfg.inCombatLockdown, cfg.questWatches = saved.combat, saved.watches
    cfg.questWaypoints, cfg.questTitles = saved.waypoints, saved.titles
    cfg.knownSpells[3561], cfg.baseTime = saved.knownSpell, saved.baseTime
    cfg.inInstance, cfg.instanceType = saved.inInstance, saved.instanceType
    PC.CalculatePath, PC.CalculatePathAsync = saved.calculate, saved.async
    PC.graphDirty = saved.graphDirty
    C_Timer.After = saved.after
    QTB.ROUTES_PER_MINUTE, QTB.enabled = saved.routes, saved.enabled
    QR.WaypointIntegration:ClearQuestCoordCache()
    if not ok then error(err, 0) end
end

local function spellOf(questID)
    local btn = QTB.activeButtons[questID]
    return btn and btn:GetAttribute("spell")
end

T:run("Quest button background: a cache miss asks for a background route", function(t)
    withButtons(function(s)
        local options
        local async = PC.CalculatePathAsync
        PC.CalculatePathAsync = function(calc, a, b, c, d, callback, opts)
            options = opts
            return async(calc, a, b, c, d, callback, opts)
        end
        s.track(71101)
        s.refresh()
        t:assertTrue(options and options.background, "the request is a background one")
        t:assertEqual("quest-buttons", options and options.consumer, "under the quest buttons' consumer key")
        t:assertEqual(3561, spellOf(71101), "and its answer configures the button, got " .. tostring(spellOf(71101)))
    end)
end)

T:run("Quest button background: a route that finishes on a later frame configures the button then", function(t)
    withButtons(function(s)
        s.yield = true
        s.track(71102)
        QTB:RefreshButtons()
        s.drain(1) -- the refresh's first frame: the route starts and parks
        t:assertNotNil(PC.asyncRunning, "the route is being calculated")
        t:assertNil(QTB.activeButtons[71102], "no button while the route is still being calculated")
        s.drain()
        t:assertEqual(3561, spellOf(71102), "the late answer configures the button, got " .. tostring(spellOf(71102)))
    end)
end)

T:run("Quest button background: a refresh replaced by an event lets its route finish into the cache", function(t)
    withButtons(function(s)
        s.yield = true
        s.track(71103)
        QTB:RefreshButtons()
        s.drain(1)
        QTB:CancelRefresh()
        t:assertFalse(PC.asyncRunning and PC.asyncRunning.superseded or false,
            "the route keeps running after a plain event")
        s.drain()
        t:assertNil(QTB.activeButtons[71103], "the replaced refresh configures nothing")
        t:assertNotNil(QTB.questCache[71103], "but the answer fills the cache for the next refresh")
        local routes = #s.routes
        s.refresh()
        t:assertEqual(routes, #s.routes, "which routes nothing again, routes " .. #s.routes)
        t:assertEqual(3561, spellOf(71103), "and shows the cached teleport, got " .. tostring(spellOf(71103)))
    end)
end)

T:run("Quest button background: an invalidation drops the route that is still running", function(t)
    withButtons(function(s)
        s.yield = true
        s.track(71109)
        QTB:RefreshButtons()
        s.drain(1)
        QTB:InvalidateCache()
        t:assertTrue(PC.asyncRunning and PC.asyncRunning.superseded,
            "the route of the old cache epoch is superseded")
        s.drain()
        t:assertNil(QTB.activeButtons[71109], "it configures nothing")
        t:assertNil(QTB.questCache[71109], "and fills no cache entry")
    end)
end)

T:run("Quest button background: quest events during a long search do not start it over", function(t)
    withButtons(function(s)
        -- A search that needs several frames, with QUEST_LOG_UPDATE arriving
        -- before it finishes, again and again, as while the player moves.
        local slices = 0
        PC.CalculatePath = function(_, destMapID)
            s.routes[#s.routes + 1] = destMapID
            for _ = 1, 5 do slices = slices + 1; coroutine.yield() end
            return { totalTime = 10, steps = { { type = "teleport", teleportID = 3561, sourceType = "spell" } } }
        end
        s.track(71111)
        local frame = QTB.eventFrame
        QTB:RefreshButtons()
        for _ = 1, 6 do
            s.drain(2)
            frame:GetScript("OnEvent")(frame, "QUEST_LOG_UPDATE")
        end
        s.drain()
        t:assertEqual(1, #s.routes, "one search for the quest, routes " .. #s.routes)
        t:assertEqual(1, QTB:GetRouteBudgetUsed(), "one slot of the bound, used " .. QTB:GetRouteBudgetUsed())
        t:assertEqual(3561, spellOf(71111), "and the quest gets its button, got " .. tostring(spellOf(71111)))
    end)
end)

T:run("Quest button background: late answers still fill no more than the secure pool", function(t)
    withButtons(function(s)
        s.yield = true
        for id = 71120, 71129 do s.track(id) end
        s.refresh()
        local shown = 0
        for _ in pairs(QTB.activeButtons) do shown = shown + 1 end
        t:assertEqual(QTB:GetPoolSize(), shown, "the pool's buttons are configured, shown " .. shown)
        t:assertEqual(QTB:GetPoolSize(), #s.routes, "and no quest past the full pool is routed, routes " .. #s.routes)
    end)
end)

T:run("Quest button background: a late answer without a route keeps the icon but not its action", function(t)
    withButtons(function(s)
        s.track(71130)
        s.refresh()
        t:assertEqual(3561, spellOf(71130), "a button from the first refresh")
        PC.CalculatePath = function(_, destMapID)
            s.routes[#s.routes + 1] = destMapID
            coroutine.yield()
            return nil
        end
        QTB:InvalidateCache()
        s.refresh()
        local btn = QTB.activeButtons[71130]
        t:assertNotNil(btn, "the icon stays through a short gap")
        t:assertNotNil(btn and btn._pendingSince, "marked as waiting for a route")
        t:assertNil(btn and btn:GetAttribute("type"), "with no action while it waits")
    end)
end)

T:run("Quest button background: a route cancelled from outside does not strand the refresh", function(t)
    withButtons(function(s)
        s.yield = true
        s.track(71131)
        s.track(71132)
        QTB:RefreshButtons()
        s.drain(1)
        -- PathCalculator:CancelAsync supersedes every request, whoever asked.
        PC:CancelAsync()
        s.drain()
        t:assertFalse(QTB._refreshRunning, "the refresh ran to its end")
        t:assertEqual(3561, spellOf(71132), "and routed the next quest, got " .. tostring(spellOf(71132)))
    end)
end)

T:run("Quest button background: inside an instance an untracked quest still loses its button", function(t)
    withButtons(function(s)
        s.track(71112)
        s.track(71113)
        s.refresh()
        t:assertEqual(3561, spellOf(71112), "a button before entering")
        MockWoW.config.inInstance, MockWoW.config.instanceType = true, "party"
        MockWoW.config.questWatches = { 71113 }
        s.refresh()
        t:assertNil(QTB.activeButtons[71112], "the untracked quest's button is released")
        t:assertEqual(3561, spellOf(71113), "the tracked one stays")
    end)
end)

T:run("Quest button background: an answer arriving in combat configures nothing", function(t)
    withButtons(function(s)
        s.yield = true
        s.track(71104)
        QTB:RefreshButtons()
        s.drain(1)
        t:assertNotNil(PC.asyncRunning, "the route is being calculated when the fight starts")
        MockWoW.config.inCombatLockdown = true
        s.drain(20)
        t:assertNil(QTB.activeButtons[71104], "no secure button work in combat")
    end)
end)

T:run("Quest button background: over the bound the button on screen stays as it is", function(t)
    withButtons(function(s)
        QTB.ROUTES_PER_MINUTE = 1
        local start = MockWoW.config.baseTime
        s.track(71105)
        s.refresh()
        t:assertEqual(1, #s.routes, "the first refresh routes, routes " .. #s.routes)
        -- The entry expires; the window still holds the first route.
        MockWoW.config.baseTime = start + 31
        s.refresh()
        t:assertEqual(1, #s.routes, "no second route inside the window, routes " .. #s.routes)
        t:assertEqual(3561, spellOf(71105), "the button keeps its teleport, got " .. tostring(spellOf(71105)))
        t:assertEqual(start + 60, QTB._pendingRefreshAt,
            "and the next look is when the slot frees, got " .. tostring(QTB._pendingRefreshAt))
        -- The window has room again.
        MockWoW.config.baseTime = start + 61
        s.refresh()
        t:assertEqual(2, #s.routes, "a freed slot routes again, routes " .. #s.routes)
    end)
end)

T:run("Quest button background: over the bound a quest that moved on loses its teleport", function(t)
    withButtons(function(s)
        QTB.ROUTES_PER_MINUTE = 1
        s.track(71106)
        s.refresh()
        t:assertEqual(3561, spellOf(71106), "the first refresh shows the teleport")
        MockWoW.config.questWaypoints[71106] = { mapID = 84, x = 0.9, y = 0.9 }
        QR.WaypointIntegration:ClearQuestCoordCache()
        s.refresh()
        t:assertEqual(1, #s.routes, "no route over the bound, routes " .. #s.routes)
        local btn = QTB.activeButtons[71106]
        t:assertNil(btn and btn:GetAttribute("type"),
            "the old teleport is no action for the new destination, type " .. tostring(btn and btn:GetAttribute("type")))
    end)
end)

T:run("Quest button background: inside an instance nothing is routed and the buttons stay", function(t)
    withButtons(function(s)
        s.track(71107)
        s.refresh()
        t:assertEqual(3561, spellOf(71107), "a button before entering")
        for _, kind in ipairs({ "party", "raid", "scenario", "pvp", "arena" }) do
            MockWoW.config.inInstance, MockWoW.config.instanceType = true, kind
            QTB:InvalidateCache()
            s.refresh()
            t:assertEqual(1, #s.routes, kind .. ": no route inside, routes " .. #s.routes)
            t:assertEqual(3561, spellOf(71107), kind .. ": the button stays, got " .. tostring(spellOf(71107)))
        end
        MockWoW.config.inInstance, MockWoW.config.instanceType = false, "none"
        s.refresh()
        t:assertEqual(2, #s.routes, "outside again, the buttons route, routes " .. #s.routes)
    end)
end)

T:run("Quest button background: housing does not pause", function(t)
    withButtons(function(s)
        -- The Warcraft Wiki's IsInInstance page lists "neighborhood" and
        -- "interior" for a housing neighbourhood and a house; a teleport
        -- often starts there.
        s.track(71108)
        MockWoW.config.inInstance, MockWoW.config.instanceType = true, "neighborhood"
        s.refresh()
        t:assertEqual(1, #s.routes, "a housing neighbourhood routes as before, routes " .. #s.routes)
        MockWoW.config.instanceType = "interior"
        QTB:InvalidateCache()
        s.refresh()
        t:assertEqual(2, #s.routes, "and so does a house, routes " .. #s.routes)
    end)
end)

T:run("Quest button background: entries of one refresh expire at different times", function(t)
    withButtons(function(s)
        -- 71104 % 11 == 0 and 71114 % 11 == 10: no spread and the widest one.
        s.track(71104, 84)
        s.track(71114, 85)
        local start = MockWoW.config.baseTime
        s.refresh()
        t:assertEqual(2, #s.routes, "both quests route, routes " .. #s.routes)
        MockWoW.config.baseTime = start + 25
        s.refresh()
        t:assertEqual(3, #s.routes, "after 25 s one of them routes again, routes " .. #s.routes)
        t:assertEqual(85, s.routes[3], "the one with the widest spread, got map " .. tostring(s.routes[3]))
    end)
end)

T:run("Quest button background: the trace counts routes, deferrals, joins and instance types", function(t)
    local D = QR.Diagnostics
    local saved = D.PerfCount
    local counted = {}
    D.PerfCount = function(_, key) counted[key] = (counted[key] or 0) + 1 end
    local ok, err = pcall(withButtons, function(s)
        QTB.ROUTES_PER_MINUTE = 1
        -- A search of several frames, so the second refresh finds it running.
        PC.CalculatePath = function(_, destMapID)
            s.routes[#s.routes + 1] = destMapID
            for _ = 1, 3 do coroutine.yield() end
            return { totalTime = 10, steps = { { type = "teleport", teleportID = 3561, sourceType = "spell" } } }
        end
        s.track(71140)
        QTB:RefreshButtons()
        s.drain(1)
        QTB:CancelRefresh()
        QTB:RefreshButtons()
        s.drain()
        s.track(71141)
        s.refresh()
        MockWoW.config.inInstance, MockWoW.config.instanceType = true, "party"
        s.refresh()
    end)
    D.PerfCount = saved
    if not ok then error(err, 0) end
    t:assertEqual(1, counted["qtb-route"], "one route, got " .. tostring(counted["qtb-route"]))
    t:assertEqual(1, counted["qtb-joined"], "a refresh that waited for it, got " .. tostring(counted["qtb-joined"]))
    t:assertTrue((counted["qtb-deferred"] or 0) >= 1, "a quest over the bound, got " .. tostring(counted["qtb-deferred"]))
    t:assertEqual(1, counted["instance:party"], "the instance type, got " .. tostring(counted["instance:party"]))
    t:assertEqual(1, counted["qtb-paused"], "and the pause, got " .. tostring(counted["qtb-paused"]))
end)
