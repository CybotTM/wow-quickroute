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
        unresolved = WI._unresolvedQuestID, retried = WI._retriedQuestID,
        hasPin = cfg.hasUserWaypoint, pin = cfg.userWaypoint, priority = QR.db.waypointPriority,
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
        QR.db.waypointPriority = "mappin"
        cfg.hasUserWaypoint, cfg.userWaypoint = false, nil
        if state.pin then
            local px, py = state.pin.x, state.pin.y
            cfg.hasUserWaypoint = true
            cfg.userWaypoint = { uiMapID = state.pin.map,
                position = { x = px, y = py, GetXY = function() return px, py end } }
        end
        if state.quest then
            cfg.superTrackedQuestID = state.quest.id
            cfg.questTitles[state.quest.id] = state.quest.title
            -- `later`: tracked, but its coordinates have not arrived yet.
            if not state.quest.later then
                cfg.questWaypoints[state.quest.id] = { mapID = state.quest.map, x = state.quest.x, y = state.quest.y }
            end
        else
            cfg.superTrackedQuestID = 0
        end
        WI:OnWaypointChanged(state.trigger or "SUPER_TRACKING_CHANGED")
        if state.after then state.after(result) end
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
    cfg.hasUserWaypoint, cfg.userWaypoint, QR.db.waypointPriority = saved.hasPin, saved.pin, saved.priority
    QR.db.autoDestination, QR.MainFrame.isShowing, QR.MainFrame.activeTab = saved.auto, saved.showing, saved.tab
    QR.db.diagnosticTrace, QR.db.trace, WI._pendingTriggers = saved.trace, saved.store, saved.pending
    WI._unresolvedQuestID, WI._retriedQuestID = saved.unresolved, saved.retried
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

-- Undermine (2346) is a UiMap child of The Ringing Deeps (2214) on retail, but
-- the routing knows both and reaches Undermine only through the Dornogal
-- teleporter: two zones. Only a map routing cannot place merges into its
-- parent. Retail data only; on Forever neither map is routable.
if flavor == "retail" then
    T:run(prefix .. "a routable child map is another zone", function(t)
        local db = MockWoW.mapDatabase
        local saved46, saved14 = db[2346].parentMapID, db[2214].parentMapID
        db[2346].parentMapID, db[2214].parentMapID = 2214, 2274   -- the retail UiMap parents
        local ok, err = pcall(function()
            local r = change({ map = 2214, x = 0.5, y = 0.5,
                quest = { id = 82000, title = "In Undermine", map = 2346, x = 0.4, y = 0.4 } })
            t:assertEqual(1, #r.shows, "The Ringing Deeps -> Undermine: opens")
            r = change({ map = 2346, x = 0.4, y = 0.4,
                quest = { id = 82001, title = "In the Deeps", map = 2214, x = 0.5, y = 0.5 } })
            t:assertEqual(1, #r.shows, "Undermine -> The Ringing Deeps: opens")
        end)
        db[2346].parentMapID, db[2214].parentMapID = saved46, saved14
        if not ok then error(err, 0) end
    end)
end

T:run(prefix .. "an unreadable player map opens the window as before", function(t)
    local r = change({ map = nil, x = nil, y = nil, quest = OTHER_ZONE.quest })
    t:assertEqual(1, #r.shows, "no player map: opens")
    t:assertNil(r.trace and r.trace.playerZone, "and the trace has no player zone")
end)

--- Give the mock C_Map the projection calls ResolveMapPosition needs, placing
-- every point of `continent` on `zone` at the same coordinates.
local function withProjection(continent, zone, fn)
    local saved = { C_Map.GetMapInfoAtPosition, C_Map.GetWorldPosFromMapPos, C_Map.GetMapPosFromWorldPos,
        _G.CreateVector2D }
    C_Map.GetMapInfoAtPosition = function(mapID)
        if mapID == continent then return { mapID = zone } end
    end
    _G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    C_Map.GetWorldPosFromMapPos = function(_, pos) return 0, pos end
    C_Map.GetMapPosFromWorldPos = function(_, pos, target) return target, pos end
    local ok, err = pcall(fn)
    C_Map.GetMapInfoAtPosition, C_Map.GetWorldPosFromMapPos, C_Map.GetMapPosFromWorldPos,
        _G.CreateVector2D = saved[1], saved[2], saved[3], saved[4]
    if not ok then error(err, 0) end
end

T:run(prefix .. "a destination on a continent map inside the player's zone is the same zone", function(t)
    local continent, zone = 1415, ALTERAC
    if flavor ~= "forever" then continent, zone = 13, 37 end
    withProjection(continent, zone, function()
        -- A map pin placed on the continent map, at a point of the player's zone.
        local r = change({ map = zone, x = 0.3, y = 0.3, pin = { map = continent, x = 0.45, y = 0.40 } })
        t:assertEqual(0, #r.shows, "resolved onto the player's zone: stays closed")
        t:assertEqual(zone, r.trace and r.trace.destZone, "the destination's zone is the resolved one")
    end)
end)

T:run(prefix .. "without a player position the best map is used", function(t)
    local savedPos = C_Map.GetPlayerMapPosition
    C_Map.GetPlayerMapPosition = function() return nil end
    local ok, err = pcall(function()
        local r = change(SAME_ZONE)
        t:assertEqual(0, #r.shows, "the best map says same zone: stays closed")
        t:assertEqual(ZEPHRAS, r.trace and r.trace.playerZone, "the player's zone from GetBestMapForUnit")
        -- A best map the client keeps secret is no zone at all.
        local savedSecret = _G.issecretvalue
        _G.issecretvalue = function(v) return v == ZEPHRAS end
        local hidden = change(SAME_ZONE)
        _G.issecretvalue = savedSecret
        t:assertEqual(1, #hidden.shows, "a secret best map: unreadable, opens")
        t:assertNil(hidden.trace and hidden.trace.playerZone, "with no player zone")
    end)
    C_Map.GetPlayerMapPosition = savedPos
    if not ok then error(err, 0) end
end)

T:run(prefix .. "a tracked quest without coordinates yet is retried once", function(t)
    -- The shape of the trace at #1650 to #1655: the quest is super-tracked at
    -- once, its coordinates arrive with a later QUEST_POI_UPDATE.
    local state = { map = ZEPHRAS, x = 0.6662, y = 0.7989,
        quest = { id = 94946, title = "Die magische Stadt Dalaran", map = ALTERAC, x = 0.1230, y = 0.5630,
            later = true } }
    state.after = function(result)
        t:assertEqual(0, #result.shows, "nothing resolved yet: no open")
        local first
        for _, e in ipairs(D:GetTraceEntries()) do
            if e.c == "waypoint" and e.f and e.f.outcome ~= "debounce" then first = e.f.outcome end
        end
        t:assertEqual("skip-unresolved", first, "traced as unresolved, not cleared")
        MockWoW.config.questWaypoints[94946] = { mapID = ALTERAC, x = 0.1230, y = 0.5630 }
        WI:ClearQuestCoordCache()   -- what QUEST_POI_UPDATE does first
        WI:OnQuestPOIUpdate()
        t:assertEqual(1, #result.shows, "the next QUEST_POI_UPDATE resolves it: opens")
        t:assertEqual("waypoint-auto:QUEST_POI_UPDATE:retry", result.shows[1], "with the retry as reason")
        WI:OnQuestPOIUpdate()
        t:assertEqual(1, #result.shows, "and only once")
    end
    change(state)
end)

T:run(prefix .. "a quest that never resolves is retried only once", function(t)
    local state = { map = ZEPHRAS, x = 0.6662, y = 0.7989,
        quest = { id = 98286, title = "No coordinates", map = ALTERAC, x = 0.5, y = 0.5, later = true } }
    state.after = function(result)
        WI:ClearQuestCoordCache()
        WI:OnQuestPOIUpdate()       -- the one retry, still nothing
        t:assertEqual(0, #result.shows, "still unresolved: no open")
        t:assertNil(WI._unresolvedQuestID, "and no second retry is armed")
    end
    change(state)
end)

-- A waypoint can arrive on a continent map without its source resolving it
-- first (a TomTom waypoint, an API caller). IsInOtherZone resolves it the way
-- routing does, so a point inside the player's zone is the same zone.
T:run(prefix .. "IsInOtherZone resolves a continent waypoint onto its zone", function(t)
    local continent, zone = 1415, ALTERAC
    if flavor ~= "forever" then continent, zone = 13, 37 end
    local cfg = MockWoW.config
    local savedMap, savedX, savedY = cfg.currentMapID, cfg.playerX, cfg.playerY
    cfg.currentMapID, cfg.playerX, cfg.playerY = zone, 0.3, 0.3
    local ok, err = pcall(withProjection, continent, zone, function()
        local other, playerZone, destZone = WI:IsInOtherZone({ mapID = continent, x = 0.45, y = 0.40 })
        t:assertFalse(other, "a continent point in the player's zone is the same zone")
        t:assertEqual(zone, destZone, "the destination resolved onto the zone")
        t:assertEqual(zone, playerZone, "the player's zone")
    end)
    cfg.currentMapID, cfg.playerX, cfg.playerY = savedMap, savedX, savedY
    if not ok then error(err, 0) end
end)

-- A zone routing cannot place climbs to its parent, but never into a
-- continent: a player the client reports on the continent is not in that zone.
T:run(prefix .. "an unroutable zone does not climb into its continent", function(t)
    local continent = flavor == "forever" and 1415 or 13
    local db = MockWoW.mapDatabase
    local LOST = 991003
    db[LOST] = { mapID = LOST, name = "A zone routing does not know", mapType = 3, parentMapID = continent }
    local ok, err = pcall(function()
        local r = change({ map = continent, x = 0.45, y = 0.40,
            quest = { id = 94946, title = "Somewhere unrouted", map = LOST, x = 0.5, y = 0.5 } })
        t:assertEqual(1, #r.shows, "the player on the continent, the quest in a zone on it: opens")
    end)
    db[LOST] = nil
    if not ok then error(err, 0) end
end)

T:run(prefix .. "the retry is dropped when another quest is tracked by then", function(t)
    local state = { map = ZEPHRAS, x = 0.6662, y = 0.7989,
        quest = { id = 94946, title = "Die magische Stadt Dalaran", map = ALTERAC, x = 0.1230, y = 0.5630,
            later = true } }
    state.after = function(result)
        MockWoW.config.questWaypoints[94946] = { mapID = ALTERAC, x = 0.1230, y = 0.5630 }
        -- The player tracks another quest in another zone; its own change has
        -- run, and the player may have closed the window it opened.
        MockWoW.config.superTrackedQuestID = 94947
        MockWoW.config.questTitles[94947] = "Another quest"
        MockWoW.config.questWaypoints[94947] = { mapID = ALTERAC, x = 0.3, y = 0.4 }
        WI:ClearQuestCoordCache()
        WI:OnQuestPOIUpdate()
        MockWoW.config.questTitles[94947], MockWoW.config.questWaypoints[94947] = nil, nil
        t:assertEqual(0, #result.shows, "the retry for the old quest does not open the window for the new one")
    end
    change(state)
end)
