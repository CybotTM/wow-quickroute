-------------------------------------------------------------------------------
-- test_route_features.lua
-- Tests for route collapsing, cooldown filter, and loading screen time features
-- in QR.PathCalculator
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...
local savedLoadingScreenTime = QR.db and QR.db.loadingScreenTime
local savedMaxCooldownHours = QR.db and QR.db.maxCooldownHours

-------------------------------------------------------------------------------
-- Helper: reset mock state and force a fresh graph rebuild
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
    if QR.PlayerInfo and QR.PlayerInfo.InvalidateCache then
        QR.PlayerInfo:InvalidateCache()
    end
    -- Reset db settings for these features
    if QR.db then
        QR.db.loadingScreenTime = nil
        QR.db.maxCooldownHours = nil
    end
end

-------------------------------------------------------------------------------
-- 1. Route Step Collapsing (CollapseConsecutiveSteps)
-------------------------------------------------------------------------------

T:run("CollapseSteps: empty steps returns empty", function(t)
    resetState()
    local result = QR.PathCalculator:CollapseConsecutiveSteps({})
    t:assertNotNil(result, "Returns a table")
    t:assertEqual(0, #result, "Empty input returns empty output")
end)

T:run("CollapseSteps: nil input returns nil", function(t)
    resetState()
    local result = QR.PathCalculator:CollapseConsecutiveSteps(nil)
    t:assertNil(result, "nil input returns nil")
end)

T:run("CollapseSteps: single walk step not collapsed", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 30, action = "Go to B" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(1, #result, "Single step not collapsed")
    t:assertEqual("walk", result[1].type, "Type preserved")
    t:assertEqual(30, result[1].time, "Time preserved")
    t:assertNil(result[1].collapsed, "Not marked as collapsed")
end)

T:run("CollapseSteps: two consecutive walk steps merged", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 20, action = "Go to B" },
        { type = "walk", from = "B", to = "C", time = 30, action = "Go to C" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(1, #result, "Two walk steps collapsed into one")
    t:assertEqual(50, result[1].time, "Combined time is 20 + 30 = 50")
    t:assertEqual("A", result[1].from, "From is first step's origin")
    t:assertEqual("C", result[1].to, "To is last step's destination")
    t:assertTrue(result[1].collapsed, "Marked as collapsed")
    t:assertEqual(2, result[1].collapsedCount, "collapsedCount is 2")
end)

T:run("CollapseSteps: walk + teleport + walk not fully merged", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 20, action = "Go to B" },
        { type = "teleport", from = "B", to = "C", time = 3, action = "Teleport to C" },
        { type = "walk", from = "C", to = "D", time = 25, action = "Go to D" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(3, #result, "Non-consecutive walks not merged")
    t:assertEqual("walk", result[1].type, "First is walk")
    t:assertEqual("teleport", result[2].type, "Second is teleport")
    t:assertEqual("walk", result[3].type, "Third is walk")
end)

T:run("CollapseSteps: walk, walk, portal, walk, walk → 3 steps", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 10, action = "Go to B" },
        { type = "walk", from = "B", to = "C", time = 15, action = "Go to C" },
        { type = "portal", from = "C", to = "D", time = 5, action = "Take portal to D" },
        { type = "walk", from = "D", to = "E", time = 20, action = "Go to E" },
        { type = "walk", from = "E", to = "F", time = 25, action = "Go to F" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(3, #result, "5 steps collapsed into 3")

    -- First merged walk
    t:assertEqual("walk", result[1].type, "First is merged walk")
    t:assertEqual(25, result[1].time, "First merged time 10+15=25")
    t:assertEqual("A", result[1].from, "First merged from = A")
    t:assertEqual("C", result[1].to, "First merged to = C")
    t:assertTrue(result[1].collapsed, "First marked collapsed")
    t:assertEqual(2, result[1].collapsedCount, "First collapsedCount = 2")

    -- Portal
    t:assertEqual("portal", result[2].type, "Second is portal")
    t:assertEqual(5, result[2].time, "Portal time = 5")

    -- Second merged walk
    t:assertEqual("walk", result[3].type, "Third is merged walk")
    t:assertEqual(45, result[3].time, "Second merged time 20+25=45")
    t:assertEqual("D", result[3].from, "Second merged from = D")
    t:assertEqual("F", result[3].to, "Second merged to = F")
    t:assertTrue(result[3].collapsed, "Third marked collapsed")
    t:assertEqual(2, result[3].collapsedCount, "Third collapsedCount = 2")
end)

T:run("CollapseSteps: travel + walk merged (mixed walk/travel types)", function(t)
    resetState()
    local steps = {
        { type = "travel", from = "A", to = "B", time = 60, action = "Travel to B" },
        { type = "walk", from = "B", to = "C", time = 30, action = "Walk to C" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(1, #result, "travel + walk collapsed")
    t:assertEqual(90, result[1].time, "Combined time 60+30=90")
    t:assertTrue(result[1].collapsed, "Marked collapsed")
end)

-- A cave approach: three walk segments, the middle one the cave mouth, the last
-- one inside on a different map. Merging them left the player pointed at the
-- final coordinate with no way to reach it.
T:run("CollapseSteps: a map change ends the merge and keeps the crossing visible", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 20, navMapID = 2393, navX = 0.50, navY = 0.56, navTitle = "B" },
        { type = "walk", from = "B", to = "C", time = 15, navMapID = 2393, navX = 0.41, navY = 0.62, navTitle = "Cave mouth" },
        { type = "walk", from = "C", to = "D", time = 25, navMapID = 2395, navX = 0.30, navY = 0.44, navTitle = "D" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(2, #result, "the two segments on map 2393 merge, the crossing to 2395 does not")
    t:assertEqual(35, result[1].time, "merged time is 20+15")
    t:assertEqual(2393, result[1].navMapID, "first row stays on map 2393")
    t:assertEqual(2395, result[2].navMapID, "the crossing keeps its own row")
    t:assertEqual(2, #result[1].waypoints, "both anchors of the merged run stay executable")
    t:assertEqual("Cave mouth", result[1].waypoints[2].title, "the intermediate anchor is retained in order")
end)

T:run("CollapseSteps: a mandatory anchor is never summarised away", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 20, navMapID = 84, navX = 0.5, navY = 0.5, navTitle = "B" },
        { type = "walk", from = "B", to = "C", time = 10, navMapID = 84, navX = 0.6, navY = 0.4, navTitle = "Entrance", mandatoryAnchor = true },
        { type = "walk", from = "C", to = "D", time = 30, navMapID = 84, navX = 0.7, navY = 0.3, navTitle = "D" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(3, #result, "the mandatory entrance stays its own step on both sides")
    t:assertEqual("Entrance", result[2].navTitle, "the entrance keeps its own navigation target")
end)

T:run("CollapseSteps: same-map runs still merge and carry their anchors", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 10, navMapID = 84, navX = 0.1, navY = 0.2, navTitle = "B" },
        { type = "travel", from = "B", to = "C", time = 15, navMapID = 84, navX = 0.3, navY = 0.4, navTitle = "C" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(1, #result, "one map, one row")
    t:assertEqual(25, result[1].time, "combined time 10+15")
    t:assertEqual(2, #result[1].waypoints, "both anchors kept")
    t:assertFalse(result[1].waypoints[1].mandatory, "an ordinary anchor is not marked mandatory")
end)

T:run("SelectStepAnchor: a merged row navigates to the anchor still ahead", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 20, navMapID = 2393, navX = 0.50, navY = 0.56, navTitle = "B" },
        { type = "walk", from = "B", to = "C", time = 15, navMapID = 2393, navX = 0.41, navY = 0.62, navTitle = "Cave mouth" },
    }
    local merged = QR.PathCalculator:CollapseConsecutiveSteps(steps)[1]
    local saved = QR.PathCalculator.GetPlayerPosition
    QR.PathCalculator.GetPlayerPosition = function() return 84, 0.1, 0.1 end
    local anchor = QR.PathCalculator:SelectStepAnchor(merged)
    t:assertEqual("B", anchor.title, "off the map, navigation starts at the first anchor")
    QR.PathCalculator.GetPlayerPosition = function() return 2393, 0.50, 0.56 end
    anchor = QR.PathCalculator:SelectStepAnchor(merged)
    t:assertEqual("Cave mouth", anchor.title, "standing on the first anchor, navigation moves to the next")
    QR.PathCalculator.GetPlayerPosition = saved
end)

T:run("SelectStepAnchor: a step without merged anchors keeps its own target", function(t)
    resetState()
    local step = { type = "portal", navMapID = 84, navX = 0.2, navY = 0.3, navTitle = "Portal room", to = "Stormwind City" }
    local anchor = QR.PathCalculator:SelectStepAnchor(step)
    t:assertEqual(84, anchor.mapID, "map unchanged")
    t:assertEqual("Portal room", anchor.title, "title unchanged")
end)

T:run("CollapseSteps: non-walk types not collapsed (portal + portal)", function(t)
    resetState()
    local steps = {
        { type = "portal", from = "A", to = "B", time = 5, action = "Portal to B" },
        { type = "portal", from = "B", to = "C", time = 5, action = "Portal to C" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(2, #result, "Consecutive portals NOT collapsed")
end)

T:run("CollapseSteps: collapsed step preserves destination fields", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 10, destMapID = 84, destX = 0.3, destY = 0.4, action = "Go to B" },
        { type = "walk", from = "B", to = "C", time = 20, destMapID = 84, destX = 0.6, destY = 0.7, action = "Go to C" },
    }
    local result = QR.PathCalculator:CollapseConsecutiveSteps(steps)
    t:assertEqual(1, #result, "Collapsed into one")
    -- Should use last step's destination fields
    t:assertEqual(84, result[1].destMapID, "destMapID from last step")
    t:assertEqual(0.6, result[1].destX, "destX from last step")
    t:assertEqual(0.7, result[1].destY, "destY from last step")
    -- But from should be from first step
    t:assertEqual("A", result[1].from, "from is from first step")
end)

-------------------------------------------------------------------------------
-- 1b. AbsorbRedundantWalkSteps (walk after transport to same map)
-------------------------------------------------------------------------------

T:run("AbsorbWalk: teleport retains last-mile walking directions", function(t)
    resetState()
    local steps = {
        { type = "teleport", from = "A", to = "Stormwind", time = 10, destMapID = 84, destX = 0.5, destY = 0.5,
          action = "Teleport to Stormwind", localizedTo = "Sturmwind", navTitle = "TeleportNav", navX = 0.5, navY = 0.5 },
        { type = "walk", from = "Stormwind", to = "SW-dest", time = 20, destMapID = 84, destX = 0.6, destY = 0.7,
          action = "Go to Stormwind", localizedTo = "SW-Ziel", navTitle = "WalkNav", navX = 0.6, navY = 0.7 },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Last-mile walk stays separate")
    t:assertEqual("teleport", result[1].type, "First step stays teleport")
    t:assertEqual(10, result[1].time, "Teleport time is not charged for walking")
    t:assertEqual(0.5, result[1].destX, "Teleport landing remains unchanged")
    t:assertEqual("SW-dest", result[2].to, "Walk reaches requested target")
    t:assertEqual("SW-Ziel", result[2].localizedTo, "Walk keeps localized destination")
    t:assertEqual(0.6, result[2].navX, "Final navigation X reaches target")
    t:assertEqual(0.7, result[2].navY, "Final navigation Y reaches target")
end)

T:run("AbsorbWalk: portal retains last-mile walk", function(t)
    resetState()
    local steps = {
        { type = "portal", from = "SW-portal", to = "Ironforge", time = 5, destMapID = 87, destX = 0.3, destY = 0.4, action = "Portal to Ironforge" },
        { type = "walk", from = "Ironforge", to = "IF-dest", time = 15, destMapID = 87, destX = 0.5, destY = 0.6, action = "Go to Ironforge" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Walk after portal stays actionable")
    t:assertEqual(15, result[2].time, "Walking time remains on the walk")
end)

T:run("AbsorbWalk: transport + walk to DIFFERENT map NOT absorbed", function(t)
    resetState()
    local steps = {
        { type = "teleport", from = "A", to = "Stormwind", time = 10, destMapID = 84, destX = 0.5, destY = 0.5, action = "Teleport to Stormwind" },
        { type = "walk", from = "Stormwind", to = "B", time = 20, destMapID = 85, destX = 0.3, destY = 0.4, action = "Go to Orgrimmar" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Walk to different map NOT absorbed")
end)

T:run("AbsorbWalk: walk + walk NOT absorbed (only transport + walk)", function(t)
    resetState()
    local steps = {
        { type = "walk", from = "A", to = "B", time = 10, destMapID = 84, destX = 0.5, destY = 0.5, action = "Go to B" },
        { type = "walk", from = "B", to = "C", time = 20, destMapID = 84, destX = 0.6, destY = 0.7, action = "Go to C" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Consecutive walks not absorbed by this pass")
end)

T:run("AbsorbWalk: unknown coordinates never imply redundant walks", function(t)
    resetState()
    local steps = {
        { type = "teleport", from = "A", to = "SW", time = 10, destMapID = 84, action = "Teleport to Stormwind" },
        { type = "walk", from = "SW", to = "SW-portal", time = 5, destMapID = 84, action = "Go to Stormwind" },
        { type = "portal", from = "SW-portal", to = "IF", time = 3, destMapID = 87, action = "Portal to Ironforge" },
        { type = "walk", from = "IF", to = "IF-dest", time = 8, destMapID = 87, action = "Go to Ironforge" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(4, #result, "All directions remain when landing coordinates are unknown")
    t:assertEqual("teleport", result[1].type, "First step is teleport")
    t:assertEqual("walk", result[2].type, "Walk to portal remains")
    t:assertEqual("portal", result[3].type, "Third step is portal")
    t:assertEqual("walk", result[4].type, "Walk from portal remains")
end)

T:run("AbsorbWalk: nil/empty input handled", function(t)
    resetState()
    t:assertNil(QR.PathCalculator:AbsorbRedundantWalkSteps(nil), "nil returns nil")
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps({})
    t:assertEqual(0, #result, "Empty returns empty")
end)

-------------------------------------------------------------------------------
-- 2. Max Cooldown Filter
-------------------------------------------------------------------------------

T:run("CooldownFilter: teleport with CD < max is included", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    -- Mage knows Teleport: Dornogal (446540) — short CD spell
    MockWoW.config.knownSpells = { [446540] = true }
    -- Spell has a 15 minute (900s) cooldown
    MockWoW.config.spellCooldowns = {
        [446540] = { start = 100, duration = 900, enable = 1 },
    }
    QR.PlayerInventory:ScanAll()

    -- Set max to 1 hour — 900s < 3600s, so it should be included
    QR.db.maxCooldownHours = 1

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    -- Check for teleport edge from Player Location
    local edges = graph:GetNeighbors("Player Location")
    local foundTeleport = false
    if edges then
        for _, edge in pairs(edges) do
            if edge.edgeType == "teleport" and edge.data and edge.data.teleportID == 446540 then
                foundTeleport = true
            end
        end
    end
    t:assertTrue(foundTeleport, "Teleport with CD < max is included in graph")
end)

T:run("CooldownFilter: teleport with CD > max is excluded", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    -- Mage knows Teleport: Dornogal (446540)
    MockWoW.config.knownSpells = { [446540] = true }
    -- Spell has an 8 hour (28800s) cooldown
    MockWoW.config.spellCooldowns = {
        [446540] = { start = 100, duration = 28800, enable = 1 },
    }
    QR.PlayerInventory:ScanAll()

    -- Set max to 1 hour — 28800s > 3600s, so it should be excluded
    QR.db.maxCooldownHours = 1

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    -- Check that teleport edge is NOT present
    local edges = graph:GetNeighbors("Player Location")
    local foundTeleport = false
    if edges then
        for _, edge in pairs(edges) do
            if edge.edgeType == "teleport" and edge.data and edge.data.teleportID == 446540 then
                foundTeleport = true
            end
        end
    end
    t:assertFalse(foundTeleport, "Teleport with CD > max is excluded from graph")
end)

T:run("CooldownFilter: maxCooldownHours=24 means no filtering", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = { [446540] = true }
    -- Spell has an 8 hour cooldown
    MockWoW.config.spellCooldowns = {
        [446540] = { start = 100, duration = 28800, enable = 1 },
    }
    QR.PlayerInventory:ScanAll()

    -- 24 means "no filter"
    QR.db.maxCooldownHours = 24

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    local edges = graph:GetNeighbors("Player Location")
    local foundTeleport = false
    if edges then
        for _, edge in pairs(edges) do
            if edge.edgeType == "teleport" and edge.data and edge.data.teleportID == 446540 then
                foundTeleport = true
            end
        end
    end
    t:assertTrue(foundTeleport, "maxCooldownHours=24 does not filter teleports")
end)

T:run("CooldownFilter: nil maxCooldownHours means no filtering", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = { [446540] = true }
    MockWoW.config.spellCooldowns = {
        [446540] = { start = 100, duration = 28800, enable = 1 },
    }
    QR.PlayerInventory:ScanAll()

    -- nil = no filter
    QR.db.maxCooldownHours = nil

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    local edges = graph:GetNeighbors("Player Location")
    local foundTeleport = false
    if edges then
        for _, edge in pairs(edges) do
            if edge.edgeType == "teleport" and edge.data and edge.data.teleportID == 446540 then
                foundTeleport = true
            end
        end
    end
    t:assertTrue(foundTeleport, "nil maxCooldownHours does not filter teleports")
end)

-------------------------------------------------------------------------------
-- 3. Loading Screen Time Cost
-------------------------------------------------------------------------------

T:run("LoadingTime: loadingScreenTime=0 retains only the portal graph epsilon", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.db.loadingScreenTime = 0

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    -- Find a portal edge from Stormwind Portal Room
    local edges = graph:GetNeighbors("Stormwind Portal Room")
    t:assertNotNil(edges, "Portal room has edges")
    local portalEdge = nil
    for _, edge in pairs(edges) do
        if edge.edgeType == "portal" then
            portalEdge = edge
            break
        end
    end
    t:assertNotNil(portalEdge, "Found a portal edge")
    t:assertEqual(0.001, portalEdge.weight, "Zero loading retains only the positive graph epsilon")
end)

T:run("LoadingTime: loadingScreenTime=10 prices a portal at ten seconds", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    QR.db.loadingScreenTime = 10

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    -- Find a portal edge
    local edges = graph:GetNeighbors("Stormwind Portal Room")
    t:assertNotNil(edges, "Portal room has edges")
    local portalEdge = nil
    for _, edge in pairs(edges) do
        if edge.edgeType == "portal" then
            portalEdge = edge
            break
        end
    end
    t:assertNotNil(portalEdge, "Found a portal edge")
    t:assertEqual(10, portalEdge.weight, "The configured ten-second loading duration is charged once")
end)

T:run("LoadingTime: teleport edges use the shared estimate including one load", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    -- Mage knows Teleport: Dornogal (446540)
    MockWoW.config.knownSpells = { [446540] = true }
    QR.PlayerInventory:ScanAll()

    QR.db.loadingScreenTime = 10

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph built")

    local edges = graph:GetNeighbors("Player Location")
    local teleportEdge = nil
    if edges then
        for _, edge in pairs(edges) do
            if edge.edgeType == "teleport" and edge.data and edge.data.teleportID == 446540 then
                teleportEdge = edge
                break
            end
        end
    end
    t:assertNotNil(teleportEdge, "Found teleport edge")

    local baseTime = QR.TravelTime:GetEffectiveTime(446540,
        teleportEdge.data.teleportData, false)
    t:assertEqual(baseTime, teleportEdge.weight,
        "Teleport weight agrees with the shared estimate instead of adding a second load")
end)

T:run("LoadingTime: walk edges NOT affected by loading screen time", function(t)
    resetState()
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    MockWoW.config.knownSpells = {}
    QR.PlayerInventory:ScanAll()

    -- First build with loadingScreenTime=0
    QR.db.loadingScreenTime = 0
    QR.PathCalculator.graphDirty = true
    local graph0 = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph0, "Graph built with loading=0")

    -- Find a walk edge weight
    local walkEdge0 = graph0:GetEdge("Stormwind City", "Stormwind Portal Room")
    if not walkEdge0 then
        walkEdge0 = graph0:GetEdge("Stormwind Portal Room", "Stormwind City")
    end
    t:assertNotNil(walkEdge0, "Walk edge found with loading=0")
    local walkWeight0 = walkEdge0.weight

    -- Now build with loadingScreenTime=10
    QR.db.loadingScreenTime = 10
    QR.PathCalculator.graphDirty = true
    local graph10 = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph10, "Graph built with loading=10")

    local walkEdge10 = graph10:GetEdge("Stormwind City", "Stormwind Portal Room")
    if not walkEdge10 then
        walkEdge10 = graph10:GetEdge("Stormwind Portal Room", "Stormwind City")
    end
    t:assertNotNil(walkEdge10, "Walk edge found with loading=10")

    t:assertEqual(walkWeight0, walkEdge10.weight,
        "Walk edge weight unchanged by loadingScreenTime")
end)

if QR.db then
    QR.db.loadingScreenTime = savedLoadingScreenTime
    QR.db.maxCooldownHours = savedMaxCooldownHours
end
