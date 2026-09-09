-------------------------------------------------------------------------------
-- test_route_recompute_budget.lua
-- How often QuickRoute is allowed to route again, and when it must not route at
-- all. Both are about cost rather than about a result: routing one quest is a
-- Dijkstra run over the whole graph, so a handler that does it once per tracked
-- quest, once a second, is a stutter -- see
-- https://github.com/CybotTM/wow-quickroute/issues/66.
--
-- Events are delivered to the module's own frame rather than through
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
-- Freshness: what the cache must never serve
-------------------------------------------------------------------------------

-- Completing an objective can advance a quest to one in another zone without
-- the player moving a step. Position, graph and age all still match, so the
-- destination has to be part of the key -- otherwise the button goes on
-- offering the teleport for where the quest used to point, and the player is
-- sent to the wrong place.
T:run("a quest whose objective moved to another zone is routed again", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE")
        t:assertEqual(0, routesFor("QUEST_LOG_UPDATE"), "nothing changed, nothing recomputed")

        MockWoW.config.questWaypoints[71001] = { mapID = 1670, x = 0.5, y = 0.5 }
        QR.WaypointIntegration:ClearQuestCoordCache()
        t:assertEqual(1, routesFor("QUEST_LOG_UPDATE"),
            "the quest that moved is routed again, and only that one")
    end)
end)

-------------------------------------------------------------------------------
-- Cost while moving
-------------------------------------------------------------------------------

T:run("standing still, a repeated QUEST_LOG_UPDATE routes nothing again", function(t)
    withCountedRoutes(function()
        t:assertTrue(routesFor("QUEST_LOG_UPDATE") > 0, "the first firing computes the routes")
        t:assertEqual(0, routesFor("QUEST_LOG_UPDATE"), "a second identical firing reuses them")
        t:assertEqual(0, routesFor("QUEST_LOG_UPDATE"), "and so does a third")
    end)
end)

T:run("walking does not re-route on every QUEST_LOG_UPDATE", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE")
        -- Twenty firings while running: about a second of play, and two per
        -- cent of the map crossed.
        local total = 0
        for _ = 1, 20 do
            MockWoW.config.playerX = MockWoW.config.playerX + 0.001
            total = total + routesFor("QUEST_LOG_UPDATE")
        end
        t:assertEqual(0, total, "small steps do not invalidate any quest's route")
    end)
end)

T:run("crossing the zone does route again", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE")
        MockWoW.config.playerX = 0.95 -- far side of the zone
        t:assertTrue(routesFor("QUEST_LOG_UPDATE") > 0,
            "a teleport worth taking from here may not be worth it from there")
    end)
end)

T:run("changing zone routes again, even at the same coordinates", function(t)
    withCountedRoutes(function()
        local savedMap = MockWoW.config.currentMapID
        routesFor("QUEST_LOG_UPDATE")
        -- Same x and y, different zone: every zone's coordinates run 0..1, so a
        -- position key that does not name the map cannot tell these apart.
        MockWoW.config.currentMapID = 85
        local routed = routesFor("QUEST_LOG_UPDATE")
        MockWoW.config.currentMapID = savedMap
        t:assertTrue(routed > 0, "a route from another zone is a different route")
    end)
end)

-- A tracked-set change used to empty the cache. Measured with 25 quests, that
-- re-routed all of them and changed none: only the quest added or removed is
-- affected, and PruneQuestCache already drops what is no longer watched. These
-- two pin that outcome instead of the wipe.
T:run("a newly tracked quest is routed, and only that one", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE")
        local watches = MockWoW.config.questWatches
        watches[#watches + 1] = 71004
        MockWoW.config.questWaypoints[71004] = { mapID = 84, x = 0.5, y = 0.5 }
        MockWoW.config.questTitles[71004] = "Budget quest 71004"
        t:assertEqual(1, routesFor("QUEST_WATCH_LIST_CHANGED"),
            "the quest just tracked is routed; the three already cached are reused")
    end)
end)

T:run("an untracked quest's cached route is dropped", function(t)
    withCountedRoutes(function()
        routesFor("QUEST_LOG_UPDATE")
        t:assertNotNil(QTB.questCache[71003], "cached while the quest was tracked")
        local watches = MockWoW.config.questWatches
        watches[#watches] = nil
        routesFor("QUEST_WATCH_LIST_CHANGED")
        t:assertNil(QTB.questCache[71003], "and dropped once it is no longer watched")
    end)
end)
