-- The quest coordinate cache must stay bounded without changing retry behavior.
local T, QR, MockWoW = ...

local function withQuestCache(callback)
    local old = { quest = C_QuestLog, map = C_Map, task = C_TaskQuest,
        journal = C_EncounterJournal, hubs = QR.PortalHubs, portals = QR.StandalonePortals,
        continents = QR.Continents, dungeon = QR.DungeonData, time = MockWoW.config.baseTime }
    local calls, positions = {}, {}
    _G.C_QuestLog = {
        GetTitleForQuestID = function() return "Quest cache fixture" end,
        GetNextWaypoint = function(questID)
            calls[questID] = (calls[questID] or 0) + 1
            local position = positions[questID]
            if position then return 53, position.x, position.y end
        end,
    }
    _G.C_Map = { GetMapInfo = function() return { mapType = 3 } end }
    _G.C_TaskQuest, _G.C_EncounterJournal = nil, nil
    QR.PortalHubs, QR.StandalonePortals, QR.Continents = {}, {}, nil
    QR.DungeonData = { scanned = false }
    QR.WaypointIntegration:ClearQuestCoordCache()
    local ok, err = pcall(callback, calls, positions)
    QR.WaypointIntegration:ClearQuestCoordCache()
    _G.C_QuestLog, _G.C_Map, _G.C_TaskQuest, _G.C_EncounterJournal = old.quest, old.map, old.task, old.journal
    QR.PortalHubs, QR.StandalonePortals, QR.Continents = old.hubs, old.portals, old.continents
    QR.DungeonData, MockWoW.config.baseTime = old.dungeon, old.time
    if not ok then error(err) end
end

T:run("Quest cache: recent positive and negative results avoid another coordinate query", function(t)
    withQuestCache(function(calls, positions)
        positions[1] = { x = .2, y = .3 }
        QR.WaypointIntegration:GetQuestWaypoint(1)
        QR.WaypointIntegration:GetQuestWaypoint(2)
        local positive = QR.WaypointIntegration:GetQuestWaypoint(1)
        local negative = QR.WaypointIntegration:GetQuestWaypoint(2)
        t:assertEqual(.2, positive and positive.x, "Positive cache returns its coordinate")
        t:assertNil(negative, "Negative cache does not invent a coordinate")
        t:assertEqual(1, calls[1], "Recent positive result is queried once")
        t:assertEqual(1, calls[2], "Recent negative result is queried once")
    end)
end)

for _, oldestIsPositive in ipairs({ true, false }) do
    T:run("Quest cache: capacity evicts oldest " .. (oldestIsPositive and "positive" or "negative") .. " result", function(t)
        withQuestCache(function(calls, positions)
            for questID = 1, 257 do
                if (questID % 2 == 1) == oldestIsPositive then
                    positions[questID] = { x = .2, y = .3 }
                end
                QR.WaypointIntegration:GetQuestWaypoint(questID)
            end
            QR.WaypointIntegration:GetQuestWaypoint(256)
            QR.WaypointIntegration:GetQuestWaypoint(257)
            t:assertEqual(1, calls[256], "Recent result survives capacity eviction")
            t:assertEqual(1, calls[257], "Newest result survives capacity eviction")
            QR.WaypointIntegration:GetQuestWaypoint(1)
            t:assertEqual(2, calls[1], "Oldest result is queried again after 256 distinct newer quests")
        end)
    end)
end

T:run("Quest cache: positive and negative entries expire at the existing 30 second boundary", function(t)
    withQuestCache(function(calls, positions)
        positions[1] = { x = .2, y = .3 }
        QR.WaypointIntegration:GetQuestWaypoint(1)
        QR.WaypointIntegration:GetQuestWaypoint(2)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 29
        QR.WaypointIntegration:GetQuestWaypoint(1)
        QR.WaypointIntegration:GetQuestWaypoint(2)
        t:assertEqual(1, calls[1], "Positive result remains cached before expiry")
        t:assertEqual(1, calls[2], "Negative result remains cached before expiry")
        positions[1], positions[2] = { x = .4, y = .5 }, { x = .6, y = .7 }
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        local positive = QR.WaypointIntegration:GetQuestWaypoint(1)
        local recovered = QR.WaypointIntegration:GetQuestWaypoint(2)
        t:assertEqual(2, calls[1], "Expired positive result triggers another query")
        t:assertEqual(2, calls[2], "Expired negative result triggers another query")
        t:assertEqual(.4, positive and positive.x, "Expired coordinates are refreshed")
        t:assertEqual(.6, recovered and recovered.x, "Expired missing objective can now resolve")
    end)
end)

T:run("Quest cache: ignoreNegativeCache retries missing objectives but keeps successful results", function(t)
    withQuestCache(function(calls, positions)
        QR.WaypointIntegration:GetQuestWaypoint(1)
        QR.WaypointIntegration:GetQuestWaypoint(1, true)
        t:assertEqual(2, calls[1], "Explicit negative retry reaches the coordinate API")
        positions[1] = { x = .2, y = .3 }
        local recovered = QR.WaypointIntegration:GetQuestWaypoint(1, true)
        t:assertEqual(.2, recovered and recovered.x, "Explicit retry observes newly available coordinates")
        QR.WaypointIntegration:GetQuestWaypoint(1, true)
        t:assertEqual(3, calls[1], "Successful result stays cached even when negative retries are enabled")
    end)
end)

T:run("Quest cache: repeated retries of one quest do not consume distinct quest capacity", function(t)
    withQuestCache(function(calls)
        for questID = 1, 256 do QR.WaypointIntegration:GetQuestWaypoint(questID) end
        for _ = 1, 300 do QR.WaypointIntegration:GetQuestWaypoint(128, true) end
        QR.WaypointIntegration:GetQuestWaypoint(1)
        QR.WaypointIntegration:GetQuestWaypoint(256)
        t:assertEqual(1, calls[1], "Repeated retries do not prematurely evict the oldest distinct quest")
        t:assertEqual(1, calls[256], "Repeated retries do not evict another recent quest")
        QR.WaypointIntegration:GetQuestWaypoint(257)
        QR.WaypointIntegration:GetQuestWaypoint(1)
        t:assertEqual(2, calls[1], "The next distinct quest still evicts the oldest insertion")
    end)
end)

T:run("Quest cache: clear removes entries and restores full capacity after a wrapped cache", function(t)
    withQuestCache(function(calls, positions)
        positions[300] = { x = .2, y = .3 }
        for questID = 1, 300 do QR.WaypointIntegration:GetQuestWaypoint(questID) end
        QR.WaypointIntegration:ClearQuestCoordCache()
        QR.WaypointIntegration:GetQuestWaypoint(300)
        QR.WaypointIntegration:GetQuestWaypoint(299)
        t:assertEqual(2, calls[300], "Clear removes a positive cached result")
        t:assertEqual(2, calls[299], "Clear removes a negative cached result")
        for questID = 301, 554 do QR.WaypointIntegration:GetQuestWaypoint(questID) end
        QR.WaypointIntegration:GetQuestWaypoint(300)
        t:assertEqual(2, calls[300], "All 256 entries fit after clearing the previous order")
        QR.WaypointIntegration:GetQuestWaypoint(555)
        QR.WaypointIntegration:GetQuestWaypoint(300)
        t:assertEqual(3, calls[300], "Eviction restarts from the first entry inserted after clear")
    end)
end)
