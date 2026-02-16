-------------------------------------------------------------------------------
-- test_route_features.lua
-- Tests for route collapsing, cooldown filter, and loading screen time features
-- in QR.PathCalculator
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

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

T:run("AbsorbWalk: teleport + walk to same map absorbed", function(t)
    resetState()
    local steps = {
        { type = "teleport", from = "A", to = "Stormwind", time = 10, destMapID = 84, destX = 0.5, destY = 0.5,
          action = "Teleport to Stormwind", localizedTo = "Sturmwind", navTitle = "TeleportNav", navX = 0.5, navY = 0.5 },
        { type = "walk", from = "Stormwind", to = "SW-dest", time = 20, destMapID = 84, destX = 0.6, destY = 0.7,
          action = "Go to Stormwind", localizedTo = "SW-Ziel", navTitle = "WalkNav", navX = 0.6, navY = 0.7 },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(1, #result, "Walk absorbed into teleport")
    t:assertEqual("teleport", result[1].type, "Type stays teleport")
    t:assertEqual(30, result[1].time, "Time combined: 10 + 20 = 30")
    t:assertEqual(0.6, result[1].destX, "destX from walk step")
    t:assertEqual(0.7, result[1].destY, "destY from walk step")
    t:assertEqual("SW-dest", result[1].to, "to from walk step")
    -- Verify localized/nav fields are preserved from walk step
    t:assertEqual("SW-Ziel", result[1].localizedTo, "localizedTo from walk step")
    t:assertEqual("WalkNav", result[1].navTitle, "navTitle from walk step")
    t:assertEqual(0.6, result[1].navX, "navX from walk step")
    t:assertEqual(0.7, result[1].navY, "navY from walk step")
end)

T:run("AbsorbWalk: portal + walk to same map absorbed", function(t)
    resetState()
    local steps = {
        { type = "portal", from = "SW-portal", to = "Ironforge", time = 5, destMapID = 87, destX = 0.3, destY = 0.4, action = "Portal to Ironforge" },
        { type = "walk", from = "Ironforge", to = "IF-dest", time = 15, destMapID = 87, destX = 0.5, destY = 0.6, action = "Go to Ironforge" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(1, #result, "Walk absorbed into portal")
    t:assertEqual(20, result[1].time, "Time combined: 5 + 15 = 20")
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

T:run("AbsorbWalk: multi-step chain with two absorptions", function(t)
    resetState()
    local steps = {
        { type = "teleport", from = "A", to = "SW", time = 10, destMapID = 84, action = "Teleport to Stormwind" },
        { type = "walk", from = "SW", to = "SW-portal", time = 5, destMapID = 84, action = "Go to Stormwind" },
        { type = "portal", from = "SW-portal", to = "IF", time = 3, destMapID = 87, action = "Portal to Ironforge" },
        { type = "walk", from = "IF", to = "IF-dest", time = 8, destMapID = 87, action = "Go to Ironforge" },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Both walks absorbed: 4 steps → 2")
    t:assertEqual("teleport", result[1].type, "First is teleport")
    t:assertEqual(15, result[1].time, "Teleport absorbed walk: 10 + 5")
    t:assertEqual("portal", result[2].type, "Second is portal")
    t:assertEqual(11, result[2].time, "Portal absorbed walk: 3 + 8")
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

T:run("LoadingTime: loadingScreenTime=0 adds no extra cost to portals", function(t)
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
    -- Portal base time is 5 (from TravelTime:GetPortalTime())
    t:assertEqual(5, portalEdge.weight, "Portal weight is base 5 with loadingScreenTime=0")
end)

T:run("LoadingTime: loadingScreenTime=10 adds +10s to portal edges", function(t)
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
    -- Portal base 5 + loading 10 = 15
    t:assertEqual(15, portalEdge.weight, "Portal weight is 5+10=15 with loadingScreenTime=10")
end)

T:run("LoadingTime: loadingScreenTime=10 adds +10s to teleport edges", function(t)
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

    -- Base teleport time (from TravelTime:GetEffectiveTime) + 10 loading
    -- The base time varies, but it should include the +10
    local baseTime = QR.TravelTime:GetEffectiveTime(446540,
        teleportEdge.data.teleportData, false)
    t:assertEqual(baseTime + 10, teleportEdge.weight,
        "Teleport weight includes +10s loading screen time")
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
