-------------------------------------------------------------------------------
-- trace_cases.lua
-- The diagnostic-trace cases, shared by test_diagnostic_trace.lua (retail) and
-- test_forever_diagnostic_trace.lua (QR_TEST_FLAVOR=forever): the trace is
-- shared code and has to hold on both clients. Not named test_*.lua, so the
-- runner does not pick it up on its own.
-------------------------------------------------------------------------------

local T, QR, MockWoW, flavor = ...
local D = QR.Diagnostics
local prefix = "Trace (" .. flavor .. "): "

--- Run a case with the trace state of the suite saved and put back.
local function withTrace(enabled, fn)
    local saved = {
        setting = QR.db.diagnosticTrace,
        trace = QR.db.trace,
        cap = D.TRACE_CAP,
        maxBytes = D.TRACE_MAX_BYTES,
        auto = QR.db.autoDestination,
        showing = QR.MainFrame.isShowing,
        combat = MockWoW.config.inCombatLockdown,
        baseTime = MockWoW.config.baseTime,
        superQuest = MockWoW.config.superTrackedQuestID,
        pending = QR.WaypointIntegration._pendingTriggers,
    }
    QR.db.trace = nil
    QR.db.diagnosticTrace = enabled
    MockWoW.config.inCombatLockdown = false
    -- MockWoW:Reset() forgets every frame's event handler, and other files
    -- call it; a fresh frame is wired to FireEvent again.
    if D.traceFrame then D.traceFrame:UnregisterAllEvents() end
    D.traceFrame = nil
    D:ApplyTraceSetting()
    local ok, err = pcall(fn)
    QR.db.diagnosticTrace = saved.setting
    D:ApplyTraceSetting()
    QR.db.trace = saved.trace
    D.TRACE_CAP, D.TRACE_MAX_BYTES = saved.cap, saved.maxBytes
    QR.db.autoDestination = saved.auto
    if QR.MainFrame.frame then QR.MainFrame.frame:Hide() end
    QR.MainFrame.isShowing = saved.showing
    MockWoW.config.inCombatLockdown = saved.combat
    MockWoW.config.baseTime = saved.baseTime
    MockWoW.config.superTrackedQuestID = saved.superQuest
    QR.WaypointIntegration._pendingTriggers = saved.pending
    if not ok then error(err, 0) end
end

local function find(category, pred)
    for _, e in ipairs(D:GetTraceEntries()) do
        if e.c == category and (not pred or pred(e)) then return e end
    end
end

local function count(category, pred)
    local n = 0
    for _, e in ipairs(D:GetTraceEntries()) do
        if e.c == category and (not pred or pred(e)) then n = n + 1 end
    end
    return n
end

T:run(prefix .. "off by default and off writes nothing", function(t)
    t:assertFalse(QR.db.diagnosticTrace, "the setting defaults to off")
    withTrace(false, function()
        QR.db.autoDestination = true
        QR:Log("INFO", "a line while off")
        D:Trace("misc", "a direct trace while off")
        MockWoW:FireEvent("QUEST_ACCEPTED", 4711)
        MockWoW:FireEvent("SUPER_TRACKING_CHANGED")
        t:assertNil(QR.db.trace, "no trace table is created")
        t:assertNil(_G.QuickRouteDB.trace, "nothing reaches the SavedVariables")
        t:assertFalse(D.traceFrame and D.traceFrame:IsEventRegistered("QUEST_ACCEPTED") or false,
            "the trace events are not registered")
    end)
end)

T:run(prefix .. "on persists log lines and events into QuickRouteDB", function(t)
    withTrace(true, function()
        QR:Log("WARN", "a line while on")
        MockWoW:FireEvent("QUEST_ACCEPTED", 4711)
        t:assertNotNil(_G.QuickRouteDB.trace, "the SavedVariables carry the trace")
        t:assertTrue(_G.QuickRouteDB.trace == QR.db.trace, "and it is the table the addon writes")
        local line = find("log", function(e) return e.m == "a line while on" end)
        t:assertNotNil(line, "the log line is stored")
        t:assertEqual("WARN", line and line.l, "with its level")
        t:assertEqual("number", line and type(line.t), "with a Unix time")
        t:assertEqual("number", line and type(line.g), "with GetTime")
        local ev = find("event", function(e) return e.m == "QUEST_ACCEPTED" end)
        t:assertEqual(4711, ev and ev.f and ev.f.a1, "the event and its argument are stored")
        local session = find("session")
        t:assertEqual(flavor, session and session.f and session.f.flavor, "the session names the client")
        t:assertEqual(flavor, QR.db.trace.client and QR.db.trace.client.flavor, "and so does the store")
    end)
end)

T:run(prefix .. "turning it off stops the events and keeps the data", function(t)
    withTrace(true, function()
        MockWoW:FireEvent("QUEST_ACCEPTED", 1)
        t:assertTrue(D.traceFrame:IsEventRegistered("QUEST_ACCEPTED"), "registered while on")
        QR.db.diagnosticTrace = false
        D:ApplyTraceSetting()
        -- The handler also checks the setting, so only the registration shows
        -- whether the events are really given back.
        t:assertFalse(D.traceFrame:IsEventRegistered("QUEST_ACCEPTED"), "unregistered when off")
        MockWoW:FireEvent("QUEST_ACCEPTED", 2)
        QR:Log("INFO", "after off")
        t:assertEqual(1, count("event", function(e) return e.m == "QUEST_ACCEPTED" end), "one event, from before")
        t:assertNil(find("log", function(e) return e.m == "after off" end), "no line after off")
    end)
end)

T:run(prefix .. "the buffer keeps the newest entries up to the cap", function(t)
    withTrace(true, function()
        D.TRACE_CAP = 5
        QR.db.trace = nil
        for i = 1, 12 do QR:Log("INFO", "line " .. i) end
        local store = QR.db.trace
        t:assertEqual(5, store.n, "the count stops at the cap")
        local entries = D:GetTraceEntries()
        t:assertEqual(5, #entries, "five entries read back")
        for i = 1, 5 do
            t:assertEqual("line " .. (7 + i), entries[i] and entries[i].m, "entry " .. i .. " in order")
        end
        t:assertEqual(7, store.dropped, "and the dropped ones are counted")
        local slots = 0
        for _ in pairs(store.e) do slots = slots + 1 end
        t:assertEqual(5, slots, "the table holds no more than the cap")
    end)
end)

T:run(prefix .. "the buffer also stops at its byte bound", function(t)
    withTrace(true, function()
        QR.db.trace = nil
        D.TRACE_MAX_BYTES = 2000
        for i = 1, 100 do QR:Log("INFO", string.rep("x", 150) .. i) end
        local store = QR.db.trace
        t:assertTrue(store.bytes <= 2000, "estimated size within the bound (" .. store.bytes .. ")")
        t:assertGreaterThan(store.n, 0, "and entries are kept")
        local entries = D:GetTraceEntries()
        t:assertEqual(string.rep("x", 150) .. 100, entries[#entries].m, "the newest one last")
    end)
end)

T:run(prefix .. "a waypoint auto-show records its trigger as the reason", function(t)
    withTrace(true, function()
        QR.db.autoDestination = true
        if QR.MainFrame.frame then QR.MainFrame.frame:Hide() end
        QR.MainFrame.isShowing = false
        QR.WaypointIntegration._pendingTriggers = nil
        -- A quest in another zone than the player's: auto-destination opens
        -- the window only for those.
        local cfg = MockWoW.config
        local savedMap, savedQuest = cfg.currentMapID, cfg.superTrackedQuestID
        cfg.currentMapID = flavor == "forever" and 1453 or 84
        cfg.superTrackedQuestID = 77002
        cfg.questTitles[77002] = "Elsewhere"
        cfg.questWaypoints[77002] = { mapID = flavor == "forever" and 1454 or 85, x = 0.5, y = 0.5 }
        QR.WaypointIntegration:ClearQuestCoordCache()
        -- What the SUPER_TRACKING_CHANGED handler in RegisterHooks calls. The
        -- event itself cannot be fired here: MockWoW:Reset() in other files
        -- drops the handler of WaypointIntegration's event frame.
        QR.WaypointIntegration:OnWaypointChanged("SUPER_TRACKING_CHANGED")
        cfg.currentMapID, cfg.superTrackedQuestID = savedMap, savedQuest
        cfg.questTitles[77002], cfg.questWaypoints[77002] = nil, nil
        QR.WaypointIntegration:ClearQuestCoordCache()
        local show = find("window", function(e) return e.f and e.f.action == "show" end)
        t:assertNotNil(show, "the open is traced")
        t:assertEqual("waypoint-auto:SUPER_TRACKING_CHANGED", show and show.f.reason, "with the trigger as reason")
        local wp = find("waypoint", function(e) return e.f and e.f.outcome == "auto-show" end)
        t:assertEqual("SUPER_TRACKING_CHANGED", wp and wp.f.trigger, "and the waypoint entry names the trigger")
        t:assertEqual(true, wp and wp.f.autoDestination, "with the auto-destination state")
    end)
end)

T:run(prefix .. "a window closed directly is traced with its reason", function(t)
    withTrace(true, function()
        QR.MainFrame:Show("route", "test-open")
        QR.MainFrame.frame:Hide()   -- what ESC does
        local onhide = find("window", function(e) return e.f and e.f.action == "onhide" end)
        t:assertEqual("frame-hidden", onhide and onhide.f.reason, "ESC-style close is traced")
        QR.MainFrame:Show("route", "test-open")
        QR.MainFrame:Hide("test-close")
        t:assertEqual(1, count("window", function(e)
            return e.f and e.f.action == "onhide" and e.f.reason == "test-close"
        end), "a Hide() call names itself in the close")
    end)
end)

T:run(prefix .. "bursty quest events are throttled and counted", function(t)
    withTrace(true, function()
        MockWoW.config.baseTime = 5000
        for _ = 1, 3 do MockWoW:FireEvent("QUEST_LOG_UPDATE") end
        t:assertEqual(1, count("event", function(e) return e.m == "QUEST_LOG_UPDATE" end), "one entry per window")
        MockWoW.config.baseTime = 5000 + D.TRACE_THROTTLE_SECONDS + 1
        MockWoW:FireEvent("QUEST_LOG_UPDATE")
        local last
        for _, e in ipairs(D:GetTraceEntries()) do
            if e.m == "QUEST_LOG_UPDATE" then last = e end
        end
        t:assertEqual(2, last and last.f and last.f.dropped, "the next one says how many were hidden")
    end)
end)

T:run(prefix .. "a waypoint entry keeps all of its fields", function(t)
    withTrace(true, function()
        local fields = {}
        for i = 1, 24 do fields["k" .. i] = i end
        D:Trace("waypoint", "wide", fields)
        local e = find("waypoint", function(x) return x.m == "wide" end)
        local kept = 0
        for _ in pairs(e and e.f or {}) do kept = kept + 1 end
        t:assertEqual(24, kept, "24 fields kept")
        t:assertNil(e and e.f._truncated, "and none dropped")
    end)
end)

-- A quest tracked a moment ago may have no coordinates yet when the trigger
-- fires, and have them by the time the debounced change runs. Resolving the
-- waypoint at trigger time caches "not found" for that quest for 30 s, so the
-- trace must not do it: with the trace on, the debounced change has to find
-- the same route as with it off.
local QUEST = 77001
local questMap = flavor == "forever" and 1453 or 84

local function questArrivesDuringDebounce()
    local WI = QR.WaypointIntegration
    local cfg = MockWoW.config
    local saved = {
        newTimer = C_Timer.NewTimer, show = QR.UI.Show,
        quest = cfg.superTrackedQuestID, title = cfg.questTitles[QUEST], wp = cfg.questWaypoints[QUEST],
        auto = QR.db.autoDestination, pending = WI._pendingTriggers, combat = cfg.inCombatLockdown,
    }
    local queued = {}
    C_Timer.NewTimer = function(_, callback)
        queued[#queued + 1] = callback
        return { Cancel = function() end }
    end
    QR.UI.Show = function() end
    local ok, result = pcall(function()
        cfg.inCombatLockdown = false
        QR.db.autoDestination = true
        WI._pendingTriggers = nil
        WI:ClearQuestCoordCache()
        cfg.superTrackedQuestID = QUEST
        cfg.questTitles[QUEST] = "A quest just accepted"
        cfg.questWaypoints[QUEST] = nil                       -- not loaded yet
        WI:OnWaypointChanged("SUPER_TRACKING_CHANGED")
        cfg.questWaypoints[QUEST] = { mapID = questMap, x = 0.3, y = 0.6 }   -- loaded now
        for _, callback in ipairs(queued) do callback() end
        local waypoint = WI:GetActiveWaypoint()
        local route = waypoint and QR.PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y)
        return { waypoint = waypoint, route = route }
    end)
    C_Timer.NewTimer, QR.UI.Show = saved.newTimer, saved.show
    cfg.superTrackedQuestID, cfg.questTitles[QUEST], cfg.questWaypoints[QUEST] = saved.quest, saved.title, saved.wp
    QR.db.autoDestination, WI._pendingTriggers, cfg.inCombatLockdown = saved.auto, saved.pending, saved.combat
    WI:ClearQuestCoordCache()
    if not ok then error(result, 0) end
    return result
end

T:run(prefix .. "a quest whose coordinates arrive during the debounce is routed with the trace on", function(t)
    local off, on
    withTrace(false, function() off = questArrivesDuringDebounce() end)
    withTrace(true, function() on = questArrivesDuringDebounce() end)
    t:assertEqual(questMap, off.waypoint and off.waypoint.mapID, "trace off: the quest is the waypoint")
    t:assertNotNil(off.route, "trace off: a route is found")
    t:assertEqual(questMap, on.waypoint and on.waypoint.mapID, "trace on: the quest is the waypoint too")
    t:assertNotNil(on.route, "trace on: a route is found too")
end)

-- Which game map the player was on: WoW gives no phase ID, but a phase that
-- puts the player on another game map (a phased Dalaran, 2980 "Dalaran City"
-- on Forever, or the instanced 2959) shows up as GetInstanceInfo's 8th value.
local GAME_MAP_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED" }

local function lastEvent(name)
    local last
    for _, e in ipairs(D:GetTraceEntries()) do
        if e.c == "event" and e.m == name then last = e end
    end
    return last
end

T:run(prefix .. "zone and loading entries name the game map", function(t)
    local cfg = MockWoW.config
    local saved = { cfg.instanceName, cfg.instanceType, cfg.instanceMapID, cfg.currentMapID }
    withTrace(true, function()
        cfg.instanceName, cfg.instanceType, cfg.instanceMapID = "Dalaran City", "none", 2980
        cfg.currentMapID = flavor == "forever" and 1453 or 84
        for _, event in ipairs(GAME_MAP_EVENTS) do
            MockWoW:FireEvent(event)
            local e = lastEvent(event)
            local f = e and e.f or {}
            t:assertEqual(2980, f.instanceMapID, event .. ": the game map")
            t:assertEqual("Dalaran City", f.instanceName, event .. ": its name")
            t:assertEqual("none", f.instanceType, event .. ": the instance type")
            t:assertEqual(0, f.difficultyID, event .. ": the difficulty")
            t:assertEqual(cfg.currentMapID, f.bestMap, event .. ": the best map")
            t:assertEqual(3, f.bestMapType, event .. ": and its type")
        end
        MockWoW:FireEvent("QUEST_ACCEPTED", 1)
        local other = lastEvent("QUEST_ACCEPTED")
        t:assertNil(other and other.f and other.f.instanceMapID, "other events carry no game map")
    end)
    cfg.instanceName, cfg.instanceType, cfg.instanceMapID, cfg.currentMapID = saved[1], saved[2], saved[3], saved[4]
end)

T:run(prefix .. "without the map APIs the entries are written without those fields", function(t)
    local savedInfo, savedBest, savedSecret = _G.GetInstanceInfo, C_Map.GetBestMapForUnit, _G.issecretvalue
    withTrace(true, function()
        _G.GetInstanceInfo, C_Map.GetBestMapForUnit = nil, nil
        D.lastTraceError = nil
        MockWoW:FireEvent("PLAYER_ENTERING_WORLD")
        local e = lastEvent("PLAYER_ENTERING_WORLD")
        t:assertNotNil(e, "the entry is written")
        t:assertNil(e and e.f and e.f.instanceMapID, "no game map")
        t:assertNil(e and e.f and e.f.bestMap, "no best map")
        t:assertNil(D.lastTraceError, "and no error")
        -- An API that raises (a client in a restricted state) is no worse.
        _G.GetInstanceInfo = function() error("restricted") end
        C_Map.GetBestMapForUnit = function() error("restricted") end
        MockWoW:FireEvent("ZONE_CHANGED")
        e = lastEvent("ZONE_CHANGED")
        t:assertNotNil(e, "the entry is written when the APIs raise")
        t:assertNil(e and e.f and e.f.instanceMapID, "with no game map")
        t:assertNil(D.lastTraceError, "and no error")
        _G.GetInstanceInfo, C_Map.GetBestMapForUnit = savedInfo, savedBest
        -- A value the client keeps secret is left out, the others stay.
        _G.issecretvalue = function(v) return v == 2980 end
        local cfg = MockWoW.config
        local savedMapID = cfg.instanceMapID
        cfg.instanceMapID = 2980
        MockWoW:FireEvent("LOADING_SCREEN_DISABLED")
        e = lastEvent("LOADING_SCREEN_DISABLED")
        t:assertNil(e and e.f and e.f.instanceMapID, "a secret game map is left out")
        t:assertNotNil(e and e.f and e.f.instanceType, "the rest is kept")
        cfg.instanceMapID = savedMapID
    end)
    _G.GetInstanceInfo, C_Map.GetBestMapForUnit, _G.issecretvalue = savedInfo, savedBest, savedSecret
end)

T:run(prefix .. "the session entry names the character's race, faction, class and level", function(t)
    local savedRace = _G.UnitRace
    _G.UnitRace = function(unit)
        if unit == "player" then return "Mensch", "Human", 1 end
    end
    withTrace(true, function()
        local session = find("session")
        local f = session and session.f or {}
        t:assertEqual("Human", f.race, "the race's file token, not its localized name")
        t:assertEqual(1, f.raceID, "and its ID")
        t:assertEqual(MockWoW.config.playerFaction, f.faction, "the faction")
        t:assertEqual(MockWoW.config.playerClass, f.class, "the class token")
        t:assertEqual(MockWoW.config.playerLevel, f.level, "the level")
        t:assertNil(f.name, "no name")
    end)
    _G.UnitRace = nil
    withTrace(true, function()
        local f = (find("session") or {}).f or {}
        t:assertNil(f.race, "without UnitRace: no race")
        t:assertEqual(MockWoW.config.playerFaction, f.faction, "and the rest still there")
    end)
    _G.UnitRace = function() error("restricted") end
    withTrace(true, function()
        local f = (find("session") or {}).f or {}
        t:assertNotNil(find("session"), "a raising UnitRace still leaves the session entry")
        t:assertNil(f.race, "without a race")
        t:assertEqual(MockWoW.config.playerFaction, f.faction, "and with the rest")
    end)
    _G.UnitRace = savedRace
end)
