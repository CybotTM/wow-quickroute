-- Standalone Lua heap attribution; this does not measure native WoW RAM.
-- Run from repo root: lua5.1 scripts/benchmark_memory.lua [addon-directory/] [full|currency|quest|search]
-- GC is paused only during allocation samples, then resumed after collection.
package.path = "tests/?.lua;" .. package.path
local root = arg[1] or "QuickRoute/"
local function kb() return collectgarbage("count") end
local function retained() collectgarbage("collect"); return kb() end
local function log(label, before)
    local peak = kb()
    local after = retained()
    print(string.format("HEAP %-28s before=%.1fKB beforeGC=%.1fKB retained=%.1fKB delta=%.1fKB", label, before or 0, peak, after, after-(before or 0)))
    io.flush()
    return after
end
local start = retained()
local Mock = require("mock_wow_api")
Mock:Install()
local base = log("mock-only", start)
local QR = {}
local files = {}
for line in io.lines(root .. "QuickRoute.toc") do
    line = line:gsub("\r", ""):gsub("\\", "/")
    if line:match("%.lua$") and not line:match("^#") then
        local before = retained()
        collectgarbage("stop")
        local chunk = assert(loadfile(root .. line))
        local compiled = kb()
        chunk("QuickRoute", QR)
        chunk = nil
        local peak = kb()
        local after = retained()
        collectgarbage("restart")
        files[#files+1] = {name=line, retained=after-before, compile=compiled-before, peak=peak-before}
    end
end
log("all-addon-files-loaded", base)
table.sort(files, function(a,b) return a.retained>b.retained end)
for index=1,math.min(12,#files) do
    local file=files[index]
    print(string.format("FILE %-39s retained=%.1fKB compile=%.1fKB totalAllocated=%.1fKB",file.name,file.retained,file.compile,file.peak))
end
local last=retained()
Mock:FireEvent("ADDON_LOADED","QuickRoute")
last=log("ADDON_LOADED",last)
for _, moduleName in ipairs({"PathCalculator", "SecureButtons", "MainFrame", "UI", "TeleportPanel", "MapSidebar", "QuestTeleportButtons"}) do
    local object=QR[moduleName]
    local method=moduleName=="PathCalculator" and "BuildGraph" or "Initialize"
    local original=object[method]
    local first=true
    object[method]=function(self,...)
        if not first then return original(self,...) end
        first=false
        local before=retained()
        local result=original(self,...)
        log("init-"..moduleName,before)
        return result
    end
end
Mock:FireEvent("PLAYER_LOGIN")
last=log("PLAYER_LOGIN",last)
QR.debugMode=false
QR.db.debugMode=false
local mode = arg[2] or "full"
if mode == "currency" then
    QR.Catalog:GetCurrencies()
elseif mode == "quest" then
    QR.Catalog:GetQuestLocations(QR.DestinationCatalog.quests[1].questID, "giver", true)
elseif mode == "search" then
    QR.Catalog:Search("storm", 84, 40)
elseif mode == "full" then
    QR.Catalog:Initialize()
else
    error("Unknown catalogue benchmark mode: " .. tostring(mode))
end
last=log("catalogue-"..mode,last)
Mock.config.knownSpells={[3561]=true,[446540]=true}
QR.PlayerInfo:InvalidateCache()
QR.PlayerInventory:ScanAll()
QR.PathCalculator:CalculatePath(84,0.6,0.6,"warmup")
last=log("first-real-route-and-graph",last)
local function measure(label,count,fn)
    local before=retained()
    collectgarbage("stop")
    local started=os.clock()
    local found=0
    for index=1,count do
        local result=fn(index)
        if result then found=found+1 end
    end
    local elapsed=os.clock()-started
    local allocated=kb()-before
    local after=retained()
    collectgarbage("restart")
    print(string.format("ROUTES %-24s count=%d found=%d allocated=%.1fKB perRoute=%.1fKB retainedDelta=%.1fKB retainedTotal=%.1fKB cpu=%.1fms",label,count,found,allocated,allocated/count,after-before,after,elapsed*1000))
    io.flush()
end
measure("25-stationary",25,function(index)return QR.PathCalculator:CalculatePath(84,0.55+index*0.003,0.65)end)
measure("25-moving",25,function(index)Mock.config.playerX=0.35+index*0.002;return QR.PathCalculator:CalculatePath(84,0.55+index*0.003,0.65)end)
measure("25-moving-repeat",25,function(index)Mock.config.playerX=0.45+index*0.002;return QR.PathCalculator:CalculatePath(84,0.55+index*0.003,0.65)end)
measure("25-different-map",25,function(index)return QR.PathCalculator:CalculatePath(2339,0.4+index*0.001,0.5)end)
measure("25-hypothetical",25,function(index)return QR.PathCalculator:CalculatePathFrom(84,0.4,0.5,2339,0.4+index*0.001,0.5,{excludeCooldowns=true})end)
-- MultiRoute reuses one private graph for its matrix. The diagnostic above
-- deliberately measures the one-shot API and is not the tour workload.
do
    local before = retained()
    local context = assert(QR.PathCalculator:CreateRouteContext({excludeCooldowns=true}))
    log("tour-context-created",before)
    measure("25-tour-context",25,function(index)
        return context:CalculatePathFrom(84,0.4,0.5,2339,0.4+index*0.001,0.5,{excludeCooldowns=true})
    end)
    measure("25-tour-context-repeat",25,function(index)
        return context:CalculatePathFrom(84,0.4,0.5,2339,0.4+index*0.001,0.5,{excludeCooldowns=true})
    end)
end
for batch=1,3 do
    measure("100-settled-"..batch,100,function(index)return QR.PathCalculator:CalculatePath(84,0.55+(index%25)*0.003,0.65)end)
end
local graph=QR.PathCalculator.graph
local nodes,edges,zoneCaches=0,0,0
for _ in pairs(graph.nodes)do nodes=nodes+1 end
for _,outgoing in pairs(graph.edges)do for _ in pairs(outgoing)do edges=edges+1 end end
for _ in pairs(QR.PathCalculator.zoneTravelCache or {})do zoneCaches=zoneCaches+1 end
print(string.format("CACHE graphNodes=%d graphEdges=%d zoneTravelSources=%d catalogueSearchRows=%d",nodes,edges,zoneCaches,#(QR.Catalog.searchRows or {})))
local before=retained()
for _,key in ipairs({"byCurrency","byQuest","byNPC","byMap","searchRows"})do QR.Catalog[key]=nil end
log("drop-catalogue-index-tables",before)
before=retained()
QR.PathCalculator.zoneTravelCache=nil
log("drop-zone-travel-cache",before)
before=retained()
QR.PathCalculator.graph=nil
graph=nil
QR.PathCalculator.nodeIndex=nil
log("drop-main-graph-and-index",before)
