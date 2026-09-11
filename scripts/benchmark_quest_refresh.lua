-- Run from the repo root: lua5.1 scripts/benchmark_quest_refresh.lua [addon-directory/]
-- Standalone Lua CPU/heap plus native API call counts, not live WoW FPS.
package.path = "tests/?.lua;" .. package.path
local mock = require("mock_wow_api")
mock:Install()
local loader = require("addon_loader")
local QR = loader:Load(mock, {addonDir=arg[1] or "QuickRoute/", quiet=true})
loader:FireAddonLoaded(mock)
loader:FirePlayerLogin(mock)
QR.debugMode, QR.db.debugMode = false, false
local mapCalls, childCalls, projectionCalls = 0, 0, 0
local hasIntermediate = true
C_QuestLog.GetNextWaypoint = function() if hasIntermediate then return 84, .4, .5 end end
C_QuestLog.GetNextWaypointText = function() if hasIntermediate then return "Take the portal" end end
C_QuestLog.GetQuestsOnMap = function() mapCalls = mapCalls + 1; return {} end
C_QuestLog.GetNextWaypointForMap = function() projectionCalls = projectionCalls + 1 end
C_QuestLog.GetHeaderIndexForQuest = function() end
C_QuestLog.GetQuestTagInfo = function() end
C_QuestLog.GetTitleForQuestID = function(id) return "Cold quest " .. id end
C_TaskQuest.GetQuestLocation = function() end
local children = C_Map.GetMapChildrenInfo
C_Map.GetMapChildrenInfo = function(...) childCalls = childCalls + 1; return children(...) end
local function phase(label, intermediate)
    hasIntermediate = intermediate
    mapCalls, childCalls, projectionCalls = 0, 0, 0
    collectgarbage("collect")
    local heap, started = collectgarbage("count"), os.clock()
    collectgarbage("stop")
    for refresh=1,10 do
        QR.WaypointIntegration:ClearQuestCoordCache()
        local batch = {}
        for index=1,25 do QR.WaypointIntegration:GetQuestWaypoint(991000+index, true, batch) end
    end
    local elapsed, allocated = os.clock()-started, collectgarbage("count")-heap
    collectgarbage("collect")
    local retained = collectgarbage("count")-heap
    collectgarbage("restart")
    print(string.format("COLD %s refreshes=10 quests=25 mapReads=%d childReads=%d projectionReads=%d cpu=%.2fms allocated=%.1fKiB retained=%.1fKiB",label,mapCalls,childCalls,projectionCalls,elapsed*1000,allocated,retained))
end
phase("intermediate unresolved", true)
phase("all coordinates missing", false)
