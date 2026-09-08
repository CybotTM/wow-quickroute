-------------------------------------------------------------------------------
-- test_combat_idle.lua
-- QuickRoute is to do nothing at all while the player is fighting. Not less --
-- nothing: no route, no bag walk, no survey record. Work postponed this way
-- must still happen once the fight ends rather than being dropped, except
-- where running it late would record something untrue.
--
-- Events are delivered to each module's own frame rather than through
-- MockWoW:FireEvent, because MockWoW:Reset in an earlier file empties the
-- dispatch registry and orphans every frame registered before it.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local QTB = QR.QuestTeleportButtons

local routeCalls = 0

--- Three tracked quests, a teleport that reaches them, and a counted stand-in
-- for the route planner. Restores everything it touched.
local function withCountedRoutes(body)
    local saved = {
        inCombat = MockWoW.config.inCombatLockdown,
        playerX = MockWoW.config.playerX,
        playerY = MockWoW.config.playerY,
        watches = MockWoW.config.questWatches,
        waypoints = MockWoW.config.questWaypoints,
        titles = MockWoW.config.questTitles,
        calculate = QR.PathCalculator.CalculatePath,
        enabled = QTB.enabled,
    }

    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playerX, MockWoW.config.playerY = 0.5, 0.5
    MockWoW.config.questWatches = { 71001, 71002, 71003 }
    MockWoW.config.questWaypoints = {}
    MockWoW.config.questTitles = {}
    for _, id in ipairs(MockWoW.config.questWatches) do
        MockWoW.config.questWaypoints[id] = { mapID = 84, x = 0.5, y = 0.5 }
        MockWoW.config.questTitles[id] = "Budget quest " .. id
    end
    saved.knownSpell = MockWoW.config.knownSpells[3561]
    MockWoW.config.knownSpells[3561] = true
    QR.PlayerInventory:ScanAll()

    -- Every cached route records the graph it was computed against and is
    -- discarded while a rebuild is pending. Both are shared with the rest of
    -- the suite, so this file states what it needs rather than inheriting it.
    saved.graphDirty = QR.PathCalculator.graphDirty
    if not QR.PathCalculator.graph then QR.PathCalculator:BuildGraph() end
    QR.PathCalculator.graphDirty = false

    QTB.enabled = true
    if not QTB.initialized then QTB:Initialize() end
    QTB:InvalidateCache()

    -- Counted rather than real: this file is about how many routes are asked
    -- for, and the real ones are slow enough to dominate the suite.
    QR.PathCalculator.CalculatePath = function()
        routeCalls = routeCalls + 1
        return { steps = { { type = "teleport", teleportID = 3561, sourceType = "spell" } } }
    end

    local ok, err = pcall(body)

    MockWoW.config.inCombatLockdown = saved.inCombat
    MockWoW.config.playerX, MockWoW.config.playerY = saved.playerX, saved.playerY
    MockWoW.config.questWatches = saved.watches
    MockWoW.config.questWaypoints = saved.waypoints
    MockWoW.config.questTitles = saved.titles
    QR.PathCalculator.CalculatePath = saved.calculate
    QR.PathCalculator.graphDirty = saved.graphDirty
    MockWoW.config.knownSpells[3561] = saved.knownSpell
    QTB.enabled = saved.enabled
    if not ok then error(err, 0) end
end

--- Route calculations caused by delivering one event to the module.
local function routesFor(event)
    routeCalls = 0
    QTB.eventFrame:GetScript("OnEvent")(QTB.eventFrame, event)
    return routeCalls
end

-------------------------------------------------------------------------------
-- Cost during combat: there is to be none
-------------------------------------------------------------------------------

T:run("no route is calculated during combat", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE") -- warm, out of combat
        MockWoW.config.inCombatLockdown = true
        for _, event in ipairs({
            "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
            "ZONE_CHANGED_NEW_AREA", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED",
            "SPELL_UPDATE_COOLDOWN",
        }) do
            t:assertEqual(0, routesFor(event), event .. " must route nothing in combat")
        end
    end)
end)

T:run("the zone survey does not record during combat", function(t)
    local ZS = QR.ZoneSurvey
    local savedCombat, savedEnabled = MockWoW.config.inCombatLockdown, QR.db.zoneSurveyEnabled
    local savedCapture = ZS.Capture
    local captures = 0
    ZS.Capture = function(self, ...) captures = captures + 1; return savedCapture(self, ...) end
    QR.db.zoneSurveyEnabled = true

    local handler = ZS.frame and ZS.frame:GetScript("OnEvent")
    t:assertNotNil(handler, "the survey has an event handler to drive")

    MockWoW.config.inCombatLockdown = true
    handler(ZS.frame, "ZONE_CHANGED_NEW_AREA")
    t:assertEqual(0, captures, "a border crossed mid-fight is not written to disk")

    -- Dropped rather than deferred: run later it would describe wherever the
    -- fight ended, which is not the crossing it was meant to record.
    MockWoW.config.inCombatLockdown = false
    handler(ZS.frame, "ZONE_CHANGED_NEW_AREA")
    t:assertEqual(1, captures, "out of combat it records as before")

    ZS.Capture = savedCapture
    MockWoW.config.inCombatLockdown = savedCombat
    QR.db.zoneSurveyEnabled = savedEnabled
end)

T:run("a waypoint cleared in combat does not open the window afterwards", function(t)
    local WI = QR.WaypointIntegration
    local savedCombat, savedAuto = MockWoW.config.inCombatLockdown, QR.db.autoDestination
    local savedShowing = QR.MainFrame.isShowing
    local shows = 0
    local realShow = QR.MainFrame.Show
    QR.MainFrame.Show = function(self, ...) shows = shows + 1; return realShow(self, ...) end

    -- Auto-destination opens the route window on a waypoint CHANGE. Clearing a
    -- map pin never did, and must not start doing so just because the clear was
    -- postponed by a fight.
    QR.db.autoDestination = true
    if QR.MainFrame.frame then QR.MainFrame.frame:Hide() end
    QR.MainFrame.isShowing = false
    WI._waypointChangePending = false

    MockWoW.config.inCombatLockdown = true
    WI:OnWaypointCleared()
    t:assertEqual("cleared", WI._waypointChangePending, "the clear is remembered as a clear")

    MockWoW.config.inCombatLockdown = false
    shows = 0
    WI:ResumeDeferredWaypointWork() -- what the leave-combat callback calls
    t:assertEqual(0, shows, "resuming a clear leaves a closed window closed")
    t:assertFalse(WI._waypointChangePending, "and the owed work is consumed")

    QR.MainFrame.Show = realShow
    QR.MainFrame.isShowing = savedShowing
    MockWoW.config.inCombatLockdown = savedCombat
    QR.db.autoDestination = savedAuto
    WI._waypointChangePending = false
end)

T:run("a waypoint change in combat waits for the fight to end", function(t)
    withCountedRoutes(function()
        local WI = QR.WaypointIntegration
        WI._waypointChangePending = false
        -- Auto-destination is what turns a waypoint change into a route, so the
        -- test states it rather than inheriting whatever the suite left.
        -- Auto-destination is what makes a waypoint change reach the UI, so the
        -- test states it rather than inheriting whatever the suite left. The
        -- observable effect of the change path is that call: the clear path
        -- never makes it, which is what the test above pins.
        local savedAuto = QR.db.autoDestination
        QR.db.autoDestination = true
        local shows = 0
        local realShow = QR.UI.Show
        QR.UI.Show = function(self, ...) shows = shows + 1; return realShow(self, ...) end

        MockWoW.config.inCombatLockdown = true
        routeCalls = 0
        WI:_ProcessWaypointChange()
        t:assertEqual(0, routeCalls, "no route is computed while the player is fighting")
        t:assertEqual("changed", WI._waypointChangePending, "but the change is remembered as a change")

        MockWoW.config.inCombatLockdown = false
        WI:ResumeDeferredWaypointWork() -- what the leave-combat callback calls
        t:assertFalse(WI._waypointChangePending, "and is consumed once the fight is over")
        t:assertEqual(1, shows, "and the change path is the one that runs")
        QR.UI.Show = realShow
        QR.db.autoDestination = savedAuto
    end)
end)
