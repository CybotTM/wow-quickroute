local T, QR, MockWoW = ...

local function isolated(body)
    local changes = {}
    local function set(owner, key, value)
        changes[#changes + 1] = { owner, key, owner[key] }
        owner[key] = value
    end
    set(_G, "GetTime", function() return 100 end)
    local ok, err = pcall(body, set)
    for index = #changes, 1, -1 do
        local change = changes[index]
        change[1][change[2]] = change[3]
    end
    if not ok then error(err) end
end

local function duration(remaining, total, start)
    return {
        GetRemainingDuration = function() return remaining end,
        GetTotalDuration = function() return total end,
        GetStartTime = function() return start end,
    }
end

T:run("Spell cooldown: GCD-only recovery does not remove a ready teleport", function(t)
    isolated(function(set)
        local gcd, own, queriedIgnoreGCD = false, nil, false
        set(C_Spell, "GetSpellCooldownDuration", function(_, ignoreGCD)
            queriedIgnoreGCD = ignoreGCD
            if own then return own end
            if gcd and not ignoreGCD then return duration(1.5, 1.5, 100) end
        end)
        set(C_Spell, "GetSpellCooldown", function()
            return { startTime = gcd and 100 or 0, duration = gcd and 1.5 or 0, isOnGCD = gcd }
        end)
        local tracker = QR.CooldownTracker
        t:assertTrue(tracker:GetCooldown(3561, "spell").ready, "Teleport is ready before the unrelated GCD")
        gcd = true
        t:assertTrue(tracker:GetCooldown(3561, "spell").ready, "A GCD-only nil duration does not hide the teleport")
        t:assertTrue(queriedIgnoreGCD, "Retail duration queries explicitly exclude the global cooldown")
        own = duration(0, 0, 0)
        t:assertTrue(tracker:GetCooldown(3561, "spell").ready, "A public zero-duration object is also ready during GCD")
        gcd, own = false, nil
        t:assertTrue(tracker:GetCooldown(3561, "spell").ready, "Readiness stays stable after the GCD ends")
    end)
end)

T:run("Spell cooldown: personal durations remain active even when short or overlapped by GCD", function(t)
    isolated(function(set)
        local own = duration(1, 1, 100)
        set(C_Spell, "GetSpellCooldownDuration", function() return own end)
        set(C_Spell, "GetSpellCooldown", function()
            return { startTime = 100, duration = 1.5, isOnGCD = true }
        end)
        local tracker = QR.CooldownTracker
        local result = tracker:GetCooldown(3561, "spell")
        t:assertFalse(result.ready, "A genuine one-second personal cooldown is never ignored")
        t:assertEqual(1, result.remaining, "The short personal duration wins over the overlapping GCD")
        t:assertEqual(1, result.duration, "The result retains the real total duration")
        t:assertEqual(100, result.start, "The result retains the real cooldown start")
        t:assertTrue(result.isPersonal, "The modern ignoreGCD query identifies a short personal duration")
        set(tracker, "batchOpen", false)
        set(tracker, "batchMemo", nil)
        set(tracker, "batchStamp", nil)
        tracker:BeginBatch()
        t:assertTrue(tracker:GetCooldown(3561, "spell").isPersonal, "Batch copies preserve the personal-duration evidence")
        tracker:EndBatch()
        own = duration(300, 600, 0)
        result = tracker:GetCooldown(3561, "spell")
        t:assertFalse(result.ready, "A long personal cooldown remains unavailable during GCD")
        t:assertEqual(300, result.remaining, "The actual remaining cooldown is used instead of GCD duration")
        own = duration(-0.1, 1, 98)
        t:assertTrue(tracker:GetCooldown(3561, "spell").ready, "An expired personal duration is clamped to ready")
    end)
end)

T:run("Spell cooldown: inaccessible duration objects safely use public cooldown metadata", function(t)
    isolated(function(set)
        local secret = 7777
        set(_G, "issecretvalue", function(value) return value == secret end)
        set(C_Spell, "GetSpellCooldownDuration", function() return duration(secret, secret, secret) end)
        set(C_Spell, "GetSpellCooldown", function() return { startTime = 95, duration = 60 } end)
        local tracker = QR.CooldownTracker
        local result = tracker:GetCooldown(3561, "spell")
        t:assertFalse(result.ready, "Secret duration accessors fall back to a public active cooldown")
        t:assertEqual(55, result.remaining, "Public metadata still provides the actual remaining cooldown")
        set(C_Spell, "GetSpellCooldownDuration", function()
            return setmetatable({}, { __index = function() error("Duration access restricted") end })
        end)
        result = tracker:GetCooldown(3561, "spell")
        t:assertEqual(55, result.remaining, "Restricted method lookup cannot interrupt the public fallback")
        set(C_Spell, "GetSpellCooldown", function() return { startTime = secret, duration = secret, isActive = true } end)
        set(_G, "GetSpellCooldown", nil)
        result = tracker:GetCooldown(3561, "spell")
        t:assertFalse(result.ready, "An unreadable active cooldown cannot be advertised as ready")
        t:assertEqual(0, result.remaining, "Unknown secret durations are not exposed as fabricated numeric timing")
    end)
end)

T:run("Spell cooldown: missing and failing modern APIs preserve legacy and item cooldowns", function(t)
    isolated(function(set)
        set(C_Spell, "GetSpellCooldownDuration", nil)
        set(C_Spell, "GetSpellCooldown", function() return { startTime = 100, duration = 1 } end)
        local tracker = QR.CooldownTracker
        t:assertFalse(tracker:GetCooldown(3561, "spell").ready, "A short numeric fallback cooldown stays active")
        t:assertFalse(tracker:GetCooldown(3561, "spell").isPersonal, "Fallback metadata clears evidence from a prior modern query")
        set(C_Spell, "GetSpellCooldownDuration", function() error("Duration API unavailable") end)
        t:assertEqual(1, tracker:GetCooldown(3561, "spell").remaining, "A raised duration API still uses public numeric metadata")
        set(C_Spell, "GetSpellCooldown", function() error("Modern metadata unavailable") end)
        set(_G, "GetSpellCooldown", function() return 90, 30, 1 end)
        t:assertEqual(20, tracker:GetCooldown(3561, "spell").remaining, "A failed modern metadata API falls back to legacy cooldowns")
        set(_G, "GetSpellCooldown", nil)
        t:assertFalse(tracker:GetCooldown(3561, "spell").ready, "Entirely unavailable spell APIs do not promise readiness")
        set(_G, "GetItemCooldown", function() return 90, 30, 1 end)
        t:assertEqual(20, tracker:GetCooldown(6948, "item").remaining, "Item cooldown timing remains unchanged")
        t:assertEqual(20, tracker:GetCooldown(140192, "toy").remaining, "Toy cooldown timing remains unchanged")
    end)
end)

T:run("Spell cooldown: GCD-only events do not notify views or arm expiry timers", function(t)
    isolated(function(set)
        local tracker, callbacks, timers = QR.CooldownTracker, 0, 0
        local own = nil
        set(C_Spell, "GetSpellCooldownDuration", function(_, ignoreGCD)
            if ignoreGCD then return own end
            return duration(1.5, 1.5, 100)
        end)
        set(C_Spell, "GetSpellCooldown", function() return { startTime = 100, duration = 1.5, isOnGCD = true } end)
        set(QR.PlayerInventory, "GetAllTeleports", function() return { [3561] = { sourceType = "spell" } } end)
        set(tracker, "listeners", { { callback = function() callbacks = callbacks + 1 end, isActive = function() return true end } })
        set(tracker, "observedCooldowns", { ["spell:3561"] = false })
        set(tracker, "expiryTimer", nil)
        set(tracker, "expiryDeadline", nil)
        set(tracker, "notifying", false)
        set(_G, "InCombatLockdown", function() return false end)
        set(C_Timer, "NewTimer", function()
            timers = timers + 1
            return { Cancel = function() end }
        end)
        tracker:RefreshWatchedCooldowns(false)
        t:assertEqual(0, callbacks, "GCD-only readiness does not refresh existing inventory views")
        t:assertEqual(0, timers, "A GCD-only result does not schedule a false personal cooldown expiry")
        own = setmetatable({}, { __index = function() error("Duration access restricted") end })
        set(C_Spell, "GetSpellCooldown", function() return nil end)
        set(_G, "GetSpellCooldown", nil)
        tracker:RefreshWatchedCooldowns(false)
        t:assertEqual(1, callbacks, "Ready-to-unknown cooldown state updates the visible view")
        t:assertEqual(0, timers, "Unknown cooldown timing does not invent an expiry timer")
        own = nil
        tracker:RefreshWatchedCooldowns(false)
        t:assertEqual(2, callbacks, "Unknown-to-ready recovery updates the visible view")
        t:assertEqual(0, timers, "Recovered readiness does not invent an expiry timer")
        own = duration(10, 10, 100)
        tracker:RefreshWatchedCooldowns(false)
        t:assertEqual(3, callbacks, "A real personal cooldown still notifies the visible view")
        t:assertEqual(1, timers, "A real personal cooldown still schedules its expiry")
    end)
end)

-- Items and toys share the global cooldown, so pressing any ability at all
-- makes every one of them unavailable for about a second and a half. Treating
-- that as a readiness change emptied the quest route cache and re-routed every
-- tracked quest on every keypress. No route can change over a window that
-- closes before the player could act on the answer.
T:run("Quest replanning: the global cooldown is not a readiness change", function(t)
    local QTB = QR.QuestTeleportButtons
    if not QTB.initialized then QTB:Initialize() end
    local saved = {
        combat = MockWoW.config.inCombatLockdown,
        time = MockWoW.config.baseTime,
        cooldowns = MockWoW.config.spellCooldowns,
        items = MockWoW.config.itemCooldowns,
        state = QTB.cooldownState,
        watches = MockWoW.config.questWatches,
    }
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.baseTime = 1000000
    MockWoW.config.spellCooldowns, MockWoW.config.itemCooldowns = {}, {}
    MockWoW.config.knownSpells[3561] = true
    QR.PlayerInventory:ScanAll()

    -- Quests to route, or a wiped cache costs nothing and the assertion below
    -- would hold whether or not the code is right.
    saved.waypoints, saved.titles = MockWoW.config.questWaypoints, MockWoW.config.questTitles
    MockWoW.config.questWatches = { 78001, 78002, 78003 }
    MockWoW.config.questWaypoints, MockWoW.config.questTitles = {}, {}
    for _, id in ipairs(MockWoW.config.questWatches) do
        MockWoW.config.questWaypoints[id] = { mapID = 84, x = 0.5, y = 0.5 }
        MockWoW.config.questTitles[id] = "GCD quest " .. id
    end
    QR.WaypointIntegration:ClearQuestCoordCache()
    QTB:InvalidateCache()
    if not QR.PathCalculator.graph then QR.PathCalculator:BuildGraph() end
    QR.PathCalculator.graphDirty = false

    local routes = 0
    local realCalc = QR.PathCalculator.CalculatePath
    QR.PathCalculator.CalculatePath = function(self, ...)
        routes = routes + 1
        return realCalc(self, ...)
    end

    local frame = QTB.eventFrame
    frame:GetScript("OnEvent")(frame, "QUEST_LOG_UPDATE")        -- fill the cache
    frame:GetScript("OnEvent")(frame, "SPELL_UPDATE_COOLDOWN")   -- settle the state
    t:assertNotNil(next(QTB.questCache), "the quests are cached before the ability press")
    routes = 0

    -- One ability press: everything that shares the global cooldown reports a
    -- 1.5s wait.
    MockWoW.config.spellCooldowns[3561] = { start = 1000000, duration = 1.5, enable = 1 }
    frame:GetScript("OnEvent")(frame, "SPELL_UPDATE_COOLDOWN")
    t:assertEqual(0, routes, "a global cooldown does not re-route anything")

    -- A real teleport cooldown still does. The refresh that follows refills the
    -- cache in the same breath here, because the mock runs timers immediately,
    -- so the observable is the routing rather than an empty table.
    routes = 0
    MockWoW.config.spellCooldowns[3561] = { start = 1000000, duration = 1800, enable = 1 }
    frame:GetScript("OnEvent")(frame, "SPELL_UPDATE_COOLDOWN")
    t:assertTrue(routes > 0, "a real cooldown still re-routes the tracked quests")

    QR.PathCalculator.CalculatePath = realCalc
    QTB.cooldownState = saved.state
    MockWoW.config.spellCooldowns, MockWoW.config.itemCooldowns = saved.cooldowns, saved.items
    MockWoW.config.baseTime = saved.time
    MockWoW.config.inCombatLockdown = saved.combat
    MockWoW.config.questWatches = saved.watches
    MockWoW.config.questWaypoints, MockWoW.config.questTitles = saved.waypoints, saved.titles
end)
