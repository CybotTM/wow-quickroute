-- Each quest resolution may inspect a map more than once, but must fetch it once.
local T, QR = ...
local QUEST_ID = 991004

local function withQuestScan(callback)
    local old = { quest = C_QuestLog, map = C_Map, task = C_TaskQuest, journal = C_EncounterJournal,
        inInstance = IsInInstance, continents = QR.Continents, hubs = QR.PortalHubs,
        portals = QR.StandalonePortals, continent = QR.GetContinentForZone, dungeon = QR.DungeonData }
    local calls, pois = {}, {}
    _G.C_QuestLog = {
        GetTitleForQuestID = function() return "Quest scan fixture" end,
        GetNextWaypointText = function() return "Take the portal" end,
        GetNextWaypoint = function() return 84, .4, .5 end,
        GetNextWaypointForMap = function() return nil end,
        GetQuestsOnMap = function(mapID)
            calls[mapID] = (calls[mapID] or 0) + 1
            return pois[mapID]
        end,
    }
    _G.C_Map = {
        GetBestMapForUnit = function() return 84 end,
        GetMapInfo = function(mapID) return { mapID = mapID, mapType = 3, name = "Zone " .. mapID } end,
        GetMapChildrenInfo = function()
            return { { mapID = 84 }, { mapID = 102 }, { mapID = 103 }, { mapID = 104 }, { mapID = 104 } }
        end,
    }
    _G.C_TaskQuest, _G.C_EncounterJournal = nil, nil
    _G.IsInInstance = function() return false end
    QR.Continents = { Test = { zones = { 84, 101, 102, 103, 102 } } }
    QR.PortalHubs, QR.StandalonePortals = { City = { mapID = 84 } }, {}
    QR.GetContinentForZone = function(mapID) return mapID ~= 104 and "Test" or nil end
    QR.DungeonData = { scanned = false, instances = {} }
    QR.WaypointIntegration:ClearQuestCoordCache()
    local ok, err = pcall(callback, calls, pois)
    QR.WaypointIntegration:ClearQuestCoordCache()
    _G.C_QuestLog, _G.C_Map, _G.C_TaskQuest, _G.C_EncounterJournal = old.quest, old.map, old.task, old.journal
    _G.IsInInstance = old.inInstance
    QR.Continents, QR.PortalHubs, QR.StandalonePortals = old.continents, old.hubs, old.portals
    QR.GetContinentForZone, QR.DungeonData = old.continent, old.dungeon
    if not ok then error(err) end
end

local function objective(x, y)
    return { { questID = QUEST_ID, x = x, y = y } }
end

T:run("Quest scan: unresolved intermediate target fetches each map only once", function(t)
    withQuestScan(function(calls)
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertNotNil(waypoint, "Unresolved objective retains its transit fallback")
        t:assertEqual(84, waypoint and waypoint.mapID, "Transit fallback remains Stormwind")
        for _, mapID in ipairs({ 84, 101, 102, 103, 104 }) do
            t:assertEqual(1, calls[mapID], "Map " .. mapID .. " is fetched once across both broad passes")
        end
    end)
end)

T:run("Quest scan: header fallback reuses the current map result without changing precedence", function(t)
    withQuestScan(function(calls, pois)
        pois[84] = objective(.7, .8)
        C_QuestLog.GetHeaderIndexForQuest = function() return 1 end
        C_QuestLog.GetInfo = function() return { title = "Zone 84" } end
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertEqual(.7, waypoint and waypoint.x, "Header fallback still uses its precise POI x")
        t:assertEqual(.8, waypoint and waypoint.y, "Header fallback precedes the transit coordinates")
        t:assertEqual(1, calls[84], "Header fallback does not refetch the already inspected player map")
    end)
end)

T:run("Quest scan: final broad fallback still resolves targets after a missing header POI", function(t)
    withQuestScan(function(calls, pois)
        C_QuestLog.GetNextWaypointText = function() return nil end
        C_QuestLog.GetNextWaypoint = function() return nil end
        C_QuestLog.GetHeaderIndexForQuest = function() return 1 end
        C_QuestLog.GetInfo = function() return { title = "Zone 101" } end
        pois[103] = objective(.2, .3)
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertEqual(103, waypoint and waypoint.mapID, "Final broad fallback finds another zone")
        t:assertEqual(.2, waypoint and waypoint.x, "Final fallback preserves the real objective coordinate")
        t:assertEqual(1, calls[101], "Missing header POI is not fetched again in the broad pass")
        t:assertEqual(1, calls[103], "The successful later zone is fetched once")
    end)
end)

T:run("Quest scan: unroutable early POI does not prevent later dungeon entrance resolution", function(t)
    withQuestScan(function(calls, pois)
        pois[104] = objective(.6, .7)
        QR.DungeonData.scanned = true
        C_QuestLog.GetQuestTagInfo = function() return { tagID = Enum.QuestTag.Dungeon } end
        C_QuestLog.GetQuestAdditionalHighlights = function() return 105, false, false, true end
        _G.C_EncounterJournal = { GetDungeonEntrancesForMap = function()
            return { { name = "Known entrance", position = { x = .15, y = .25 } } }
        end }
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertEqual(105, waypoint and waypoint.mapID, "Dungeon fallback wins over an unroutable POI and transit hub")
        t:assertEqual(.15, waypoint and waypoint.x, "Dungeon entrance retains its observed coordinate")
        t:assertEqual(1, calls[104], "Unroutable zone was inspected once before the later fallback")
    end)
end)

T:run("Quest scan: current objective precedes broad scan candidates", function(t)
    withQuestScan(function(calls, pois)
        C_QuestLog.GetNextWaypoint = function() return nil end
        pois[84], pois[101] = objective(.7, .8), objective(.2, .3)
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertEqual(84, waypoint and waypoint.mapID, "Actual current-map objective retains precedence")
        t:assertEqual(1, calls[84], "Current map was fetched once")
        t:assertNil(calls[101], "Successful current-map lookup does not start a broad scan")
    end)
end)

T:run("Quest scan: per-call results do not hide new POIs on a later cache-bypassing request", function(t)
    withQuestScan(function(calls, pois)
        C_QuestLog.GetNextWaypoint = function() return nil end
        local first = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID)
        t:assertNil(first, "First unresolved request has no invented waypoint")
        pois[103] = objective(.25, .35)
        local second = QR.WaypointIntegration:GetQuestWaypoint(QUEST_ID, true)
        t:assertEqual(103, second and second.mapID, "Later request observes newly available objective POIs")
        t:assertEqual(2, calls[103], "The objective map is fetched once per uncached request")
    end)
end)
