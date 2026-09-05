local T, QR, MockWoW = ...

T:run("Quest destinations: unwatched log quests and map quest givers are searchable", function(t)
    MockWoW:Reset()
    local oldQuest, oldLine, oldTask = C_QuestLog, _G.C_QuestLine, C_TaskQuest
    local oldWatch = QR.WaypointIntegration.GetWatchedQuestWaypoints
    local oldResolve = QR.WaypointIntegration.GetQuestWaypoint
    local oldMap = WorldMapFrame.GetMapID
    QR.WaypointIntegration.GetWatchedQuestWaypoints = function() return {} end
    QR.WaypointIntegration.GetQuestWaypoint = function(_, id)
        return { mapID = 84, x = 0.2, y = 0.3, title = "Unwatched " .. id }
    end
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 2 end,
        GetInfo = function(index) return index == 1 and { isHeader = true } or { questID = 101 } end,
        GetQuestsOnMap = function() return { { questID = 101, x = 0.2, y = 0.3 } } end,
        GetTitleForQuestID = function(id) return "Map quest " .. id end,
    }
    _G.C_QuestLine = { GetAvailableQuestLines = function()
        return { { questID = 202, questName = "A new adventure", x = 0.4, y = 0.6, isQuestStart = true },
            { questID = 203, questName = "Hidden", x = 0.4, y = 0.6, isHidden = true },
            { questID = 204, questName = "Unknown position" } }
    end }
    C_TaskQuest = { GetQuestsOnMap = function() return { { questID = 303, x = 0.6, y = 0.7 } } end }
    WorldMapFrame.GetMapID = function() return 84 end
    local ok, results = pcall(QR.WaypointIntegration.GetSearchQuestWaypoints, QR.WaypointIntegration)
    QR.WaypointIntegration.GetWatchedQuestWaypoints, QR.WaypointIntegration.GetQuestWaypoint = oldWatch, oldResolve
    C_QuestLog, _G.C_QuestLine, C_TaskQuest = oldQuest, oldLine, oldTask
    WorldMapFrame.GetMapID = oldMap
    t:assertTrue(ok, "Quest discovery completes: " .. tostring(results))
    if ok then
        local byID = {}
        for _, entry in ipairs(results) do byID[entry.questID] = entry end
        t:assertEqual(3, #results, "Deduplicated log quest, map giver and world objective returned")
        t:assertNotNil(byID[101], "Unwatched log quest is included")
        t:assertEqual("A new adventure", byID[202] and byID[202].title, "Available quest giver title is included")
        t:assertEqual(0.6, byID[202] and byID[202].y, "Actual giver coordinate retained")
        t:assertNotNil(byID[303], "World quest objective included")
        t:assertNil(byID[203], "Hidden quest giver excluded")
        t:assertNil(byID[204], "Missing giver position is never replaced by map midpoint")
    end
end)

T:run("Quest destinations: missing quest API and invalid quest IDs fail safely", function(t)
    local old = C_QuestLog
    C_QuestLog = nil
    local ok, result = pcall(QR.WaypointIntegration.GetQuestWaypoint, QR.WaypointIntegration, 999999)
    C_QuestLog = old
    t:assertTrue(ok, "Absent C_QuestLog does not raise")
    t:assertNil(ok and result or nil, "Absent API returns no fabricated destination")
end)

T:run("Quest destinations: a matching zone name is not evidence of an endpoint", function(t)
    MockWoW:Reset()
    local questID = 880001
    local oldDD, oldQuest = QR.DungeonData, C_QuestLog
    QR.DungeonData = { scanned = true, instances = {} }
    C_QuestLog = { GetTitleForQuestID = function() return "Stormwind City: Missing objective" end,
        GetHeaderIndexForQuest = function() return 1 end,
        GetInfo = function() return { title = "Stormwind City" } end }
    QR.WaypointIntegration:ClearQuestCoordCache()
    local ok, waypoint = pcall(QR.WaypointIntegration.GetQuestWaypoint, QR.WaypointIntegration, questID)
    QR.DungeonData, C_QuestLog = oldDD, oldQuest
    QR.WaypointIntegration:ClearQuestCoordCache()
    t:assertTrue(ok, "Zone-only quest resolution returns safely")
    t:assertNil(ok and waypoint or nil, "Zone midpoint is never presented as the quest endpoint")
end)

T:run("Quest destinations: ambiguous dungeon highlights do not pick an arbitrary entrance", function(t)
    MockWoW:Reset()
    local oldDD, oldQuest, oldEJ = QR.DungeonData, C_QuestLog, C_EncounterJournal
    QR.DungeonData = { scanned = true, instances = {} }
    C_QuestLog = { GetTitleForQuestID = function() return "Unnamed dungeon quest" end,
        GetQuestTagInfo = function() return { tagID = Enum.QuestTag.Dungeon } end,
        GetQuestAdditionalHighlights = function() return 84, 0.5, 0.5, true end }
    C_EncounterJournal = { GetDungeonEntrancesForMap = function()
        return { { name = "First dungeon", position = { x = 0.1, y = 0.2 } },
            { name = "Another dungeon", position = { x = 0.8, y = 0.9 } } }
    end }
    QR.WaypointIntegration:ClearQuestCoordCache()
    local ok, waypoint = pcall(QR.WaypointIntegration.GetQuestWaypoint, QR.WaypointIntegration, 880002)
    QR.DungeonData, C_QuestLog, C_EncounterJournal = oldDD, oldQuest, oldEJ
    QR.WaypointIntegration:ClearQuestCoordCache()
    t:assertTrue(ok, "Ambiguous dungeon hint resolves safely")
    t:assertNil(ok and waypoint or nil, "First dungeon on the map is not assumed to be the quest target")
end)
