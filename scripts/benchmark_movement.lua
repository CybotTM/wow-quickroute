-- Real route workload with deterministic WoW boundary fixtures.
-- Run from the repository root: lua5.1 scripts/benchmark_movement.lua [addon-directory/]
-- Reports standalone Lua CPU time, not in-client FPS or native API cost.
package.path = 'tests/?.lua;' .. package.path
local mock = require('mock_wow_api')
mock:Install()
local cfg = mock.config
cfg.knownSpells = {[3561] = true}
local loader = require('addon_loader')
local QR = loader:Load(mock, {addonDir=arg[1] or 'QuickRoute/', quiet=true})
loader:FireAddonLoaded(mock)
loader:FirePlayerLogin(mock)
QR.debugMode = false
QR.db.debugMode = false
QR.MainFrame:Hide()
local qtb = QR.QuestTeleportButtons
cfg.questWatches, cfg.questWaypoints = {}, {}
for i=1,25 do
    cfg.questWatches[i] = 10000+i
    cfg.questWaypoints[10000+i] = {mapID=84, x=0.55 + i * 0.003, y=0.65}
end
QR.PlayerInventory:ScanAll()
QR.PathCalculator:CalculatePath(84,0.6,0.6,'warmup')
local now, pending = 0, {}
C_Timer.After = function(delay, callback) pending[#pending+1] = {due=now+delay, callback=callback} end
C_Timer.NewTimer = function(delay, callback)
    local timer = {due=now+delay,callback=callback}
    function timer:Cancel() self.cancelled = true end
    pending[#pending+1]=timer
    return timer
end
local routeCalls, maxRoute, routeTime, graphCalls = 0,0,0,0
local calc, build = QR.PathCalculator.CalculatePath, QR.PathCalculator.BuildGraph
QR.PathCalculator.CalculatePath = function(self,...)
    routeCalls=routeCalls+1
    local started=os.clock()
    local result=calc(self,...)
    local duration=os.clock()-started
    routeTime=routeTime+duration
    maxRoute=math.max(maxRoute,duration)
    return result
end
QR.PathCalculator.BuildGraph = function(self,...)
    graphCalls=graphCalls+1
    return build(self,...)
end
local function phase(name, moving, questEvents)
    local startCalls,startTime,startBuilds=routeCalls,routeTime,graphCalls
    maxRoute=0
    local cpu,maxFrame=0,0
    for tick=1,600 do
        now=now+1/60
        cfg.baseTime=1000000+now
        if moving then cfg.playerX=0.35+(now*0.002)%0.1 end
        local started=os.clock()
        if questEvents and tick%60==0 then mock:FireEvent('QUEST_LOG_UPDATE') end
        if qtb.movementFrame:IsShown() then qtb:OnMovementUpdate(1/60) end
        local queued = pending
        pending={}
        for _,timer in ipairs(queued) do
            if not timer.cancelled then
                if timer.due<=now then timer.callback()
                else pending[#pending+1]=timer end
            end
        end
        local duration=os.clock()-started
        cpu=cpu+duration
        maxFrame=math.max(maxFrame,duration)
    end
    print(string.format('BENCH %s: 10s simulated, routes=%d graph-builds=%d totalCPU=%.2fms routeCPU=%.2fms maxFrame=%.2fms maxRoute=%.2fms',name,routeCalls-startCalls,graphCalls-startBuilds,cpu*1000,(routeTime-startTime)*1000,maxFrame*1000,maxRoute*1000))
end
qtb:InvalidateCache()
qtb:RefreshButtons()
phase('stationary warmup',false,false)
phase('stationary settled',false,false)
phase('moving hidden QR',true,false)
phase('stationary quest events',false,true)
