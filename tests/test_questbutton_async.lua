local T, QR, MockWoW = ...

local function withRefresh(fn)
    local qtb = QR.QuestTeleportButtons
    local saved = {pool=qtb.pool, active=qtb.activeButtons, cache=qtb.questCache,
        initialized=qtb.initialized, enabled=qtb.enabled, update=qtb.updateFrame,
        generation=qtb._refreshGeneration, cooldownState=qtb.cooldownState,
        movement=qtb.movementFrame, elapsed=qtb._movementElapsed, running=qtb._refreshRunning,
        lastPosition=qtb._lastRefreshPosition, lastGraph=qtb._lastRefreshGraph,
        inCombat=MockWoW.config.inCombatLockdown,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition,
        inventory=QR.PlayerInventory, cooldown=QR.CooldownTracker, pc=QR.PathCalculator,
        wi=QR.WaypointIntegration, configure=QR.SecureButtons.ConfigureButton,
        after=C_Timer.After, combat=InCombatLockdown,
        watches=C_QuestLog.GetNumQuestWatches, watchID=C_QuestLog.GetQuestIDForQuestWatchIndex}
    local state = {pending={}, watched={}, calls=0, writes=0, configured=0, x=0.3}
    MockWoW.config.inCombatLockdown=false
    C_Map.GetBestMapForUnit=function()return 84 end
    C_Map.GetPlayerMapPosition=function()return {x=state.x,y=0.5}end
    for index=1,25 do state.watched[index]=10000+index end
    qtb.pool, qtb.activeButtons, qtb.questCache = {}, {}, {}
    qtb.initialized, qtb.enabled = true, true
    qtb.updateFrame = CreateFrame("Frame")
    qtb.updateFrame:Hide()
    qtb.movementFrame=CreateFrame("Frame")
    qtb.movementFrame:Hide()
    qtb._movementElapsed=0
    for index=1,qtb:GetPoolSize() do
        local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        local setAttribute = btn.SetAttribute
        btn.SetAttribute = function(self, ...)
            state.writes = state.writes + 1
            return setAttribute(self, ...)
        end
        btn.inUse = false
        qtb.pool[index] = btn
    end
    QR.PlayerInventory = {GetAllTeleports=function()return {[3561]={sourceType="spell",data={name="Stormwind"}}}end}
    QR.CooldownTracker = {GetCooldown=function()return {ready=true}end}
    QR.WaypointIntegration = {GetQuestWaypoint=function(_,id)return {mapID=84,x=0.5,y=0.5,title=tostring(id)}end}
    QR.PathCalculator = {graph={},CalculatePath=function()
        state.calls = state.calls + 1
        return {steps={{type="teleport",teleportID=3561,sourceType="spell"}}}
    end}
    QR.SecureButtons.ConfigureButton = function(_,btn,id)
        state.configured = state.configured + 1
        btn:SetAttribute("type","spell")
        btn:SetAttribute("spell",id)
        return true
    end
    C_Timer.After = function(_,callback)state.pending[#state.pending+1]=callback end
    C_QuestLog.GetNumQuestWatches = function()return #state.watched end
    C_QuestLog.GetQuestIDForQuestWatchIndex = function(index)return state.watched[index]end
    local ok, err = pcall(fn,qtb,state)
    qtb:CancelRefresh()
    MockWoW.config.inCombatLockdown = false
    qtb:ReleaseAllButtons()
    qtb.pool,qtb.activeButtons,qtb.questCache = saved.pool,saved.active,saved.cache
    qtb.initialized,qtb.enabled,qtb.updateFrame = saved.initialized,saved.enabled,saved.update
    qtb._refreshGeneration,qtb.cooldownState = saved.generation,saved.cooldownState
    qtb.movementFrame,qtb._movementElapsed,qtb._refreshRunning=saved.movement,saved.elapsed,saved.running
    qtb._lastRefreshPosition,qtb._lastRefreshGraph=saved.lastPosition,saved.lastGraph
    MockWoW.config.inCombatLockdown=saved.inCombat
    C_Map.GetBestMapForUnit,C_Map.GetPlayerMapPosition=saved.map,saved.position
    QR.PlayerInventory,QR.CooldownTracker,QR.PathCalculator,QR.WaypointIntegration = saved.inventory,saved.cooldown,saved.pc,saved.wi
    QR.SecureButtons.ConfigureButton = saved.configure
    C_Timer.After,_G.InCombatLockdown = saved.after,saved.combat
    C_QuestLog.GetNumQuestWatches,C_QuestLog.GetQuestIDForQuestWatchIndex = saved.watches,saved.watchID
    if not ok then error(err) end
end

T:run("Quest button batching: one route per frame preserves the secure pool bound", function(t)
    withRefresh(function(qtb,state)
        qtb:RefreshButtons()
        t:assertEqual(0,state.calls,"Quest-log refresh handler performs no route calculations")
        t:assertFalse(qtb.updateFrame:IsShown(),"No positioning updates before a usable button exists")
        local index=1
        while state.pending[index] do
            local before=state.calls
            state.pending[index]()
            t:assertEqual(before+1,state.calls,"Each callback computes exactly one uncached quest")
            index=index+1
        end
        t:assertEqual(qtb:GetPoolSize(),state.configured,"No buttons beyond the fixed secure pool are configured")
        t:assertEqual(qtb:GetPoolSize(),state.calls,"Remaining quests are not calculated once the pool is full")
        t:assertTrue(qtb.updateFrame:IsShown(),"Usable buttons enable positioning updates")
    end)
end)

T:run("Quest button batching: a newer refresh prevents stale quest configuration", function(t)
    withRefresh(function(qtb,state)
        qtb:RefreshButtons()
        local stale=state.pending[1]
        state.watched={20001}
        qtb:RefreshButtons()
        stale()
        t:assertEqual(0,state.calls,"Superseded callback does no path work")
        t:assertEqual(0,state.configured,"Superseded callback never configures a protected button")
        state.pending[2]()
        t:assertNotNil(qtb.activeButtons[20001],"Only the latest tracked quest obtains a button")
        t:assertNil(qtb.activeButtons[10001],"Old quest cannot reappear after refresh")
    end)
end)

T:run("Quest button batching: queued combat callbacks make no protected writes", function(t)
    withRefresh(function(qtb,state)
        qtb:RefreshButtons()
        MockWoW.config.inCombatLockdown=true
        state.pending[1]()
        t:assertEqual(0,state.calls,"Combat callback skips route work")
        t:assertEqual(0,state.writes,"Combat callback cannot mutate secure attributes")
        t:assertEqual(0,state.configured,"Combat callback cannot configure secure actions")
        t:assertFalse(qtb.updateFrame:IsShown(),"Combat callback does not reactivate positioning")
    end)
end)

T:run("Quest button batching: invalidation during route calculation prevents configuration", function(t)
    withRefresh(function(qtb,state)
        QR.PathCalculator.CalculatePath=function()
            state.calls=state.calls+1
            MockWoW.config.inCombatLockdown=true
            return {steps={{type="teleport",teleportID=3561,sourceType="spell"}}}
        end
        qtb:RefreshButtons()
        state.pending[1]()
        t:assertEqual(1,state.calls,"Candidate was calculated before combat became active")
        t:assertEqual(0,state.writes,"Post-calculation guard prevents protected writes")
        t:assertEqual(0,state.configured,"Post-calculation guard prevents secure configuration")
    end)
end)

T:run("Quest button batching: disabled and uninitialized generations stop queued work", function(t)
    withRefresh(function(qtb,state)
        qtb:RefreshButtons()
        qtb:SetEnabled(false)
        state.pending[1]()
        t:assertEqual(0,state.calls,"Disabling buttons cancels pending route calculation")
        t:assertEqual(0,state.configured,"Disabled work never configures buttons")
        qtb.enabled=true
        qtb:RefreshButtons()
        qtb.initialized=false
        state.pending[2]()
        t:assertEqual(0,state.calls,"Uninitialized module cannot process queued quests")
    end)
end)

T:run("Quest button batching: unavailable quests leave positioning hidden", function(t)
    withRefresh(function(qtb,state)
        state.watched={10001,10002}
        QR.PathCalculator.CalculatePath=function()state.calls=state.calls+1;return nil end
        qtb:RefreshButtons()
        state.pending[1]()
        state.pending[2]()
        t:assertEqual(2,state.calls,"Unusable quests are evaluated separately")
        t:assertFalse(qtb.updateFrame:IsShown(),"No usable teleport keeps update frame hidden")
        t:assertEqual(0,state.configured,"Unavailable routes do not populate the secure pool")
        state.watched={}
        qtb:RefreshButtons()
        t:assertFalse(qtb.updateFrame:IsShown(),"Empty watch list keeps update frame hidden")
    end)
end)

T:run("Quest button cache: movement and graph replacement re-evaluate the fastest option", function(t)
    withRefresh(function(qtb,state)
        state.watched={10001}
        qtb:RefreshButtons()
        state.pending[1]()
        qtb:RefreshButtons()
        state.pending[2]()
        t:assertEqual(1,state.calls,"Stable origin and graph reuse the cached route choice")
        state.x=0.7
        QR.PathCalculator.CalculatePath=function()state.calls=state.calls+1;return {steps={{type="walk"}}}end
        qtb:RefreshButtons()
        state.pending[3]()
        t:assertEqual(2,state.calls,"Same-map movement re-evaluates a previous teleport")
        t:assertNil(qtb.activeButtons[10001],"Walking now wins, so stale teleport button is removed")
        QR.PathCalculator.graph={}
        qtb:RefreshButtons()
        state.pending[4]()
        t:assertEqual(3,state.calls,"Replacing the graph invalidates a cached no-teleport result")
        C_Map.GetPlayerMapPosition=function()return nil end
        qtb:RefreshButtons()
        state.pending[5]()
        t:assertNil(qtb.questCache[10001],"Unavailable player position clears the cached choice")
    end)
end)

T:run("Quest button movement probe: coalesces active batches and runs without visible buttons", function(t)
    withRefresh(function(qtb,state)
        state.watched={10001,10002}
        QR.PathCalculator.CalculatePath=function()state.calls=state.calls+1;return {steps={{type="walk"}}}end
        qtb:RefreshButtons()
        local generation=qtb._refreshGeneration
        state.x=0.7
        qtb:OnMovementUpdate(1)
        t:assertEqual(generation,qtb._refreshGeneration,"Movement does not repeatedly cancel an active batch")
        t:assertEqual(0,state.calls,"Movement probe performs no path work")
        state.pending[1]()
        state.pending[2]()
        t:assertFalse(qtb.updateFrame:IsShown(),"Walking results require no secure positioning frame")
        t:assertTrue(qtb.movementFrame:IsShown(),"Tracked quests keep the lightweight movement probe active")
        qtb:OnMovementUpdate(0.5)
        t:assertEqual(generation,qtb._refreshGeneration,"Movement probe respects its one-second interval")
        qtb:OnMovementUpdate(0.5)
        t:assertTrue(qtb._refreshGeneration>generation,"Movement after batch completion schedules a fresh comparison")
        t:assertEqual(2,state.calls,"Fresh comparison remains queued instead of running inside probe")
        state.pending[3]()
        state.pending[4]()
        state.watched={}
        qtb:RefreshButtons()
        t:assertFalse(qtb.movementFrame:IsShown(),"No tracked quests stops the movement probe")
    end)
end)

T:run("Quest button cache: quest events during combat invalidate targets without secure work", function(t)
    withRefresh(function(qtb,state)
        state.watched={10001}
        qtb:RefreshButtons()
        state.pending[1]()
        t:assertNotNil(qtb.questCache[10001],"Usable target was cached before combat")
        local oldEvent=qtb.eventFrame
        qtb.eventFrame=nil
        qtb:RegisterEvents()
        local frame=qtb.eventFrame
        local callback=frame:GetScript("OnEvent")
        local writes=state.writes
        MockWoW.config.inCombatLockdown=true
        callback(frame,"QUEST_LOG_UPDATE")
        t:assertNil(qtb.questCache[10001],"Quest changes in combat invalidate stale target coordinates")
        t:assertEqual(writes,state.writes,"Combat quest events perform no protected attribute writes")
        t:assertEqual(1,state.calls,"Combat quest event schedules no route calculation")
        frame:UnregisterAllEvents()
        qtb.eventFrame=oldEvent
    end)
end)
