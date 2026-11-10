-------------------------------------------------------------------------------
-- autoshow_cases.lua
-- Auto-destination opens the route window only for a destination in another
-- zone. Shared by test_autoshow_zone.lua (retail) and
-- test_forever_autoshow_zone.lua (QR_TEST_FLAVOR=forever). Not named
-- test_*.lua, so the runner does not pick it up on its own.
--
-- The cases are the shapes of a WoW Forever diagnostic trace (28 automatic
-- opens: 11 with the waypoint cleared, 13 with it in the player's zone, 4 in
-- another zone), with its quest IDs, maps and coordinates.
-------------------------------------------------------------------------------

local T, QR, MockWoW, flavor = ...
local WI = QR.WaypointIntegration
local D = QR.Diagnostics
local prefix = "Auto-show by zone (" .. flavor .. "): "

local ZEPHRAS, ALTERAC = 2521, 1416

--- Run one waypoint change the way the client reports it, and record what
-- the window did. `state` gives the player's map and position and the
-- super-tracked quest with its coordinates (nil: the quest was turned in).
local function change(state)
    local cfg = MockWoW.config
    local saved = {
        map = cfg.currentMapID, x = cfg.playerX, y = cfg.playerY, super = cfg.superTrackedQuestID,
        auto = QR.db.autoDestination, showing = QR.MainFrame.isShowing, tab = QR.MainFrame.activeTab,
        show = QR.UI.Show, refresh = QR.UI.RefreshRoute, combat = cfg.inCombatLockdown,
        trace = QR.db.diagnosticTrace, store = QR.db.trace, pending = WI._pendingTriggers,
    }
    local result = { shows = {}, refreshes = 0 }
    QR.UI.Show = function(_, reason) result.shows[#result.shows + 1] = reason end
    QR.UI.RefreshRoute = function() result.refreshes = result.refreshes + 1 end
    local ok, err = pcall(function()
        cfg.inCombatLockdown = false
        cfg.currentMapID, cfg.playerX, cfg.playerY = state.map, state.x, state.y
        QR.db.autoDestination = state.auto ~= false
        QR.MainFrame.isShowing = state.windowOpen == true
        QR.MainFrame.activeTab = "route"
        QR.db.diagnosticTrace = true
        QR.db.trace = nil
        WI._pendingTriggers = nil
        WI:ClearQuestCoordCache()
        if state.quest then
            cfg.superTrackedQuestID = state.quest.id
            cfg.questTitles[state.quest.id] = state.quest.title
            cfg.questWaypoints[state.quest.id] = { mapID = state.quest.map, x = state.quest.x, y = state.quest.y }
        else
            cfg.superTrackedQuestID = 0
        end
        WI:OnWaypointChanged(state.trigger or "SUPER_TRACKING_CHANGED")
        for _, e in ipairs(D:GetTraceEntries()) do
            if e.c == "waypoint" and e.f and e.f.outcome ~= "debounce" then result.trace = e.f end
        end
    end)
    QR.UI.Show, QR.UI.RefreshRoute = saved.show, saved.refresh
    if state.quest then
        cfg.questTitles[state.quest.id], cfg.questWaypoints[state.quest.id] = nil, nil
    end
    cfg.currentMapID, cfg.playerX, cfg.playerY, cfg.superTrackedQuestID = saved.map, saved.x, saved.y, saved.super
    cfg.inCombatLockdown = saved.combat
    QR.db.autoDestination, QR.MainFrame.isShowing, QR.MainFrame.activeTab = saved.auto, saved.showing, saved.tab
    QR.db.diagnosticTrace, QR.db.trace, WI._pendingTriggers = saved.trace, saved.store, saved.pending
    WI:ClearQuestCoordCache()
    if not ok then error(err, 0) end
    return result
end

-- Trace #334: quest 93065 accepted on Zephras Isle, its objective on the same map.
local SAME_ZONE = {
    map = ZEPHRAS, x = 0.6623, y = 0.7659,
    quest = { id = 93065, title = "Bereit für die Schlacht", map = ZEPHRAS, x = 0.6115, y = 0.7093 },
}
-- Trace #313: quest 92640 turned in at the quest giver; super-tracking cleared.
local CLEARED = { map = ZEPHRAS, x = 0.6623, y = 0.7659, quest = nil }
-- Trace #1659: quest 94946 accepted on Zephras Isle, its objective in Alterac Mountains.
local OTHER_ZONE = {
    map = ZEPHRAS, x = 0.6662, y = 0.7989,
    quest = { id = 94946, title = "Die magische Stadt Dalaran", map = ALTERAC, x = 0.1230, y = 0.5630 },
}

T:run(prefix .. "a destination in the player's zone does not open the window", function(t)
    local r = change(SAME_ZONE)
    t:assertEqual(0, #r.shows, "no open for quest 93065 on the player's own map")
    t:assertEqual("skip-same-zone", r.trace and r.trace.outcome, "and the trace says why")
    t:assertEqual(ZEPHRAS, r.trace and r.trace.playerZone, "with the player's zone")
    t:assertEqual(ZEPHRAS, r.trace and r.trace.destZone, "and the destination's")
end)

T:run(prefix .. "a cleared waypoint does not open the window", function(t)
    local r = change(CLEARED)
    t:assertEqual(0, #r.shows, "no open after the quest was turned in")
    t:assertEqual("skip-cleared", r.trace and r.trace.outcome, "and the trace says why")
end)

T:run(prefix .. "a destination in another zone opens the window", function(t)
    local r = change(OTHER_ZONE)
    t:assertEqual(1, #r.shows, "the window opens for quest 94946 in Alterac Mountains")
    t:assertEqual("waypoint-auto:SUPER_TRACKING_CHANGED", r.shows[1], "with the trigger as reason")
    t:assertEqual("auto-show", r.trace and r.trace.outcome, "traced as an auto-show")
    t:assertEqual(ALTERAC, r.trace and r.trace.destZone, "to Alterac Mountains")
end)

T:run(prefix .. "the same for a TomTom trigger", function(t)
    local state = {}
    for k, v in pairs(SAME_ZONE) do state[k] = v end
    state.trigger = "TomTom:SetClosestWaypoint"
    t:assertEqual(0, #change(state).shows, "same zone: no open")
    for k, v in pairs(OTHER_ZONE) do state[k] = v end
    state.trigger = "TomTom:SetClosestWaypoint"
    local r = change(state)
    t:assertEqual("waypoint-auto:TomTom:SetClosestWaypoint", r.shows[1], "another zone: opens")
end)

T:run(prefix .. "an open route window is still refreshed", function(t)
    local state = {}
    for k, v in pairs(SAME_ZONE) do state[k] = v end
    state.windowOpen = true
    local r = change(state)
    t:assertEqual(1, r.refreshes, "same zone, window open: refreshed")
    t:assertEqual(0, #r.shows, "and not reopened")
    state = { map = CLEARED.map, x = CLEARED.x, y = CLEARED.y, windowOpen = true }
    r = change(state)
    t:assertEqual(1, r.refreshes, "cleared, window open: refreshed")
end)

T:run(prefix .. "auto-destination off never opens it", function(t)
    local state = {}
    for k, v in pairs(OTHER_ZONE) do state[k] = v end
    state.auto = false
    local r = change(state)
    t:assertEqual(0, #r.shows, "off: no open even for another zone")
end)

T:run(prefix .. "a sub-zone of the player's zone is the same zone", function(t)
    local db = MockWoW.mapDatabase
    local CAVE, OTHER = 991001, 991002
    local savedZephras = db[ZEPHRAS]
    db[ZEPHRAS] = db[ZEPHRAS] or { mapID = ZEPHRAS, name = "Zephras Isle", mapType = 3, parentMapID = 947 }
    db[CAVE] = { mapID = CAVE, name = "A cave", mapType = 4, parentMapID = ZEPHRAS }
    db[OTHER] = { mapID = OTHER, name = "A cave elsewhere", mapType = 4, parentMapID = ALTERAC }
    local ok, err = pcall(function()
        local r = change({ map = ZEPHRAS, x = 0.66, y = 0.77,
            quest = { id = 93065, title = "In a cave", map = CAVE, x = 0.5, y = 0.5 } })
        t:assertEqual(0, #r.shows, "destination in a cave under the player's zone: no open")
        r = change({ map = CAVE, x = 0.5, y = 0.5,
            quest = { id = 93065, title = "Outside", map = ZEPHRAS, x = 0.61, y = 0.71 } })
        t:assertEqual(0, #r.shows, "player in that cave, destination in its zone: no open")
        r = change({ map = CAVE, x = 0.5, y = 0.5,
            quest = { id = 94946, title = "Elsewhere", map = OTHER, x = 0.5, y = 0.5 } })
        t:assertEqual(1, #r.shows, "a cave under another zone: opens")
    end)
    db[CAVE], db[OTHER], db[ZEPHRAS] = nil, nil, savedZephras
    if not ok then error(err, 0) end
end)

-- The client can report a continent map for the player, for a moment after a
-- loading screen (the trace has the Zephras -> Alterac trip land on Eastern
-- Kingdoms, 1415) or where no zone covers the spot. A continent is not a
-- zone, so a destination on a zone of that continent is elsewhere.
T:run(prefix .. "a player on a continent map is in no zone", function(t)
    local continent, zone = 1415, ALTERAC
    if flavor ~= "forever" then continent, zone = 13, 37 end
    local r = change({ map = continent, x = 0.45, y = 0.40,
        quest = { id = 94946, title = "On this continent", map = zone, x = 0.12, y = 0.56 } })
    t:assertEqual(1, #r.shows, "the window opens")
    t:assertEqual(continent, r.trace and r.trace.playerZone, "the player's map is the continent")
end)
