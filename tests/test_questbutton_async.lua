local T, QR, MockWoW = ...

local function withRefresh(fn)
    local qtb = QR.QuestTeleportButtons
    local saved = {pool=qtb.pool, active=qtb.activeButtons, cache=qtb.questCache,
        initialized=qtb.initialized, enabled=qtb.enabled, update=qtb.updateFrame,
        generation=qtb._refreshGeneration, cooldownState=qtb.cooldownState,
        cooldownExpiry=qtb._nextCooldownExpiry,
        movement=qtb.movementFrame, elapsed=qtb._movementElapsed, running=qtb._refreshRunning,
        lastPosition=qtb._lastRefreshPosition, lastGraph=qtb._lastRefreshGraph,
        pendingRefresh=qtb._pendingRefreshAt,
        flightChoices=qtb.flightChoices, flying=_G.IsFlying,
        inCombat=MockWoW.config.inCombatLockdown, baseTime=MockWoW.config.baseTime,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition,
        inventory=QR.PlayerInventory, cooldown=QR.CooldownTracker, pc=QR.PathCalculator,
        wi=QR.WaypointIntegration, configure=QR.SecureButtons.ConfigureButton,
        spellTexture=C_Spell.GetSpellTexture, legacySpellTexture=GetSpellTexture,
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
    qtb.cooldownState={}
    qtb._pendingRefreshAt=nil
    qtb._nextCooldownExpiry=nil
    qtb.flightChoices={}
    _G.IsFlying=function()return false end
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
    -- A stand-in that behaves like the real one: it remembers answers for the
    -- duration of a batch. Without that, nothing routed through it can tell a
    -- remembered answer from a fresh one, and a guard on the readiness check
    -- passes whether or not the code is correct.
    QR.CooldownTracker = {
        batchOpen = false, memo = {}, liveReads = 0,
        BeginBatch = function(self) self.batchOpen = true; self.memo = {} end,
        EndBatch = function(self) self.batchOpen = false; self.memo = {} end,
        SuspendBatch = function(self)
            local wasOpen = self.batchOpen or false
            self.batchOpen = false
            return wasOpen
        end,
        ResumeBatch = function(self, wasOpen) if wasOpen then self.batchOpen = true end end,
        GetCooldown = function(self, id, sourceType)
            local key = tostring(sourceType) .. ":" .. tostring(id)
            if self.batchOpen and self.memo[key] then return self.memo[key] end
            self.liveReads = self.liveReads + 1
            -- remaining, not only ready: the readiness check treats anything
            -- within a global cooldown of usable as ready, so an answer with no
            -- remaining reads as ready whatever `ready` says -- and every flip
            -- of state.cooldownReady below was invisible to it.
            local ready = state.cooldownReady ~= false
            local answer = { ready = ready, remaining = ready and 0 or 900 }
            if self.batchOpen then self.memo[key] = answer end
            return answer
        end,
    }
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
    qtb._nextCooldownExpiry=saved.cooldownExpiry
    qtb.movementFrame,qtb._movementElapsed,qtb._refreshRunning=saved.movement,saved.elapsed,saved.running
    qtb._lastRefreshPosition,qtb._lastRefreshGraph=saved.lastPosition,saved.lastGraph
    qtb._pendingRefreshAt=saved.pendingRefresh
    qtb.flightChoices,_G.IsFlying=saved.flightChoices,saved.flying
    MockWoW.config.inCombatLockdown=saved.inCombat
    MockWoW.config.baseTime=saved.baseTime
    C_Map.GetBestMapForUnit,C_Map.GetPlayerMapPosition=saved.map,saved.position
    QR.PlayerInventory,QR.CooldownTracker,QR.PathCalculator,QR.WaypointIntegration = saved.inventory,saved.cooldown,saved.pc,saved.wi
    QR.SecureButtons.ConfigureButton = saved.configure
    C_Spell.GetSpellTexture, _G.GetSpellTexture = saved.spellTexture, saved.legacySpellTexture
    C_Timer.After,_G.InCombatLockdown = saved.after,saved.combat
    C_QuestLog.GetNumQuestWatches,C_QuestLog.GetQuestIDForQuestWatchIndex = saved.watches,saved.watchID
    if not ok then error(err) end
end

local function refreshOne(qtb, state)
    qtb:RefreshButtons()
    local callback = table.remove(state.pending, 1)
    if callback then callback() end
end

local function useCloakCooldown(qtb, state, seconds, duration)
    state.watched = {10001}
    local expires = GetTime() + (seconds or 5)
    QR.PlayerInventory.GetAllTeleports = function()
        return {
            [50977]={sourceType="spell",data={name="Death Gate"}},
            [65360]={sourceType="item",data={name="Cloak of Coordination"}},
        }
    end
    QR.CooldownTracker.GetCooldown = function(_, id)
        local remaining = id == 65360 and math.max(0, expires - GetTime()) or 0
        return {ready=remaining == 0, remaining=remaining, duration=id == 65360 and duration or 0}
    end
    QR.PathCalculator.CalculatePath = function()
        state.calls = state.calls + 1
        local ready = GetTime() >= expires
        return {steps={{type="teleport",teleportID=ready and 65360 or 50977,
            sourceType=ready and "item" or "spell"}}}
    end
    refreshOne(qtb, state)
end

T:run("Quest button cooldowns: a cloak becoming ready refreshes a stationary player's route", function(t)
    withRefresh(function(qtb, state)
        useCloakCooldown(qtb, state)
        t:assertEqual(50977, qtb.activeButtons[10001].teleportID, "Alternative is shown while the cloak is cooling down")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 6
        qtb:OnMovementUpdate(1)
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(65360, qtb.activeButtons[10001].teleportID, "The ready cloak replaces the old route without an event or movement")
        t:assertEqual(2, state.calls, "The expiry causes exactly one new route")
        qtb:OnMovementUpdate(1)
        t:assertEqual(0, #state.pending, "An expired cooldown does not cause repeated refreshes")
    end)
end)

T:run("Quest button cooldowns: an event near personal expiry does not misclassify it as GCD", function(t)
    withRefresh(function(qtb, state)
        useCloakCooldown(qtb, state)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 4
        qtb.eventFrame:GetScript("OnEvent")(qtb.eventFrame, "SPELL_UPDATE_COOLDOWN")
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(1, state.calls, "One second left on a known personal cooldown does not prematurely replan")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 2
        qtb:OnMovementUpdate(1)
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(65360, qtb.activeButtons[10001].teleportID, "The real expiry remains observable after the near-expiry event")
    end)
end)

T:run("Quest button cooldowns: a long cooldown first observed in its last second still expires", function(t)
    withRefresh(function(qtb, state)
        useCloakCooldown(qtb, state, 1, 3600)
        t:assertEqual(50977, qtb.activeButtons[10001].teleportID, "A cloak in its last second is not usable yet")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 2
        qtb:OnMovementUpdate(1)
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(65360, qtb.activeButtons[10001].teleportID, "The total personal duration distinguishes the last second from GCD")
    end)
end)

T:run("Quest button cooldowns: short personal spell cooldowns are not mistaken for global recovery", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        local expires = GetTime() + 1
        QR.CooldownTracker.GetCooldown = function()
            local remaining = math.max(0, expires - GetTime())
            return {ready=remaining == 0, remaining=remaining, duration=1, isPersonal=true}
        end
        refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "A real spell cooldown cannot offer a ready button")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 2
        qtb:OnMovementUpdate(1)
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertNotNil(qtb.activeButtons[10001], "The personal spell expiry replaces its cached unavailable result")
    end)
end)

T:run("Quest button cooldowns: combat defers expiry until the next permitted refresh", function(t)
    withRefresh(function(qtb, state)
        useCloakCooldown(qtb, state)
        MockWoW.config.inCombatLockdown = true
        MockWoW.config.baseTime = MockWoW.config.baseTime + 6
        local writes = state.writes
        qtb:OnMovementUpdate(1)
        t:assertEqual(writes, state.writes, "Cooldown expiry causes no protected writes in combat")
        MockWoW.config.inCombatLockdown = false
        refreshOne(qtb, state)
        t:assertEqual(65360, qtb.activeButtons[10001].teleportID, "The combat-exit refresh discards the older alternative")
    end)
end)

T:run("Quest button cooldowns: changed bag cooldowns retire unusable shortcuts", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        t:assertTrue(qtb.eventFrame._events.BAG_UPDATE_COOLDOWN, "Quest buttons subscribe to actual item cooldown events")
        local event = qtb.eventFrame:GetScript("OnEvent")
        event(qtb.eventFrame, "BAG_UPDATE_COOLDOWN")
        t:assertEqual(0, #state.pending, "An unrelated bag cooldown does not schedule routes")
        state.cooldownReady = false
        event(qtb.eventFrame, "BAG_UPDATE_COOLDOWN")
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertNil(qtb.activeButtons[10001], "A newly active item cooldown clears the unavailable shortcut")
    end)
end)

T:run("Quest button scan batching: queued quests share one context that the next refresh releases", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001, 10002}
        local contexts = {}
        QR.WaypointIntegration.GetQuestWaypoint = function(_, id, _, context)
            contexts[#contexts + 1] = context
            return {mapID=84,x=.5,y=.5,title=tostring(id)}
        end
        qtb:RefreshButtons()
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertNotNil(contexts[1], "The first queued quest receives a map scan context")
        t:assertEqual(contexts[1], contexts[2], "Successive frames share the same native map answers")
        qtb:RefreshButtons()
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertTrue(contexts[1] ~= contexts[3], "The next refresh starts with fresh map answers")
        t:assertEqual(contexts[3], contexts[4], "The new refresh shares its own context")
    end)
end)

T:run("Quest button graph freshness: a bind change between frames repairs earlier real routes once", function(t)
    local realCalculator, changes = QR.PathCalculator, {}
    local function replace(owner, key, value)
        changes[#changes + 1] = {owner, key, owner[key]}
        owner[key] = value
    end
    local ok, err = pcall(function()
        withRefresh(function(qtb, state)
            state.watched = {10001, 10002}
            replace(_G, "UnitGUID", function() return "Player-Integrated-Bind" end)
            replace(_G, "GetBindLocation", function() return "Observed Inn" end)
            replace(_G, "UnitFactionGroup", function() return "Alliance" end)
            replace(_G, "UnitLevel", function() return 90 end)
            replace(_G, "C_TaxiMap", {})
            replace(QR.PlayerInfo, "GetFaction", function() return "Alliance" end)
            replace(QR.PlayerInfo, "GetClass", function() return "MAGE" end)
            replace(QR.TravelTime, "CanFly", function() return false end)
            replace(QR.db, "considerCooldowns", true)
            replace(QR.db, "maxCooldownHours", 24)
            replace(QR.db, "hearthstoneBinds", { ["Player-Integrated-Bind"] = {
                mapID=84,x=.6,y=.7,bindName="Observed Inn",source="HEARTHSTONE_ARRIVAL",
            } })
            replace(QR.Hearthstone, "pendingArrival", nil)
            C_Map.GetBestMapForUnit = function() return 627 end
            C_Map.GetPlayerMapPosition = function() return {GetXY=function() return .5,.5 end} end
            QR.PlayerInventory.GetAllTeleports = function()
                return {
                    [6948]={sourceType="item",data=QR.TeleportItemsData[6948]},
                    [65360]={sourceType="item",data=QR.TeleportItemsData[65360]},
                }
            end
            QR.WaypointIntegration.GetQuestWaypoint = function()
                return {mapID=84,x=.6,y=.7,title="Destination beside the old inn"}
            end
            local calculator, calls = {graphDirty=true}, 0
            for key, value in pairs(realCalculator) do
                if type(value) == "function" then calculator[key] = value end
            end
            calculator.CalculatePath = function(self, ...)
                calls = calls + 1
                return realCalculator.CalculatePath(self, ...)
            end
            QR.PathCalculator = calculator
            qtb:RefreshButtons()
            local generation = qtb._refreshGeneration
            if state.pending[1] then table.remove(state.pending, 1)() end
            t:assertEqual(6948, qtb.activeButtons[10001] and qtb.activeButtons[10001].teleportID,
                "The first real route initially selects the old observed hearth")
            t:assertTrue(QR.Hearthstone:RecordBind(), "The actual bind observer changes the destination and dirties the graph")
            while state.pending[1] do table.remove(state.pending, 1)() end
            for _, id in ipairs(state.watched) do
                t:assertEqual(65360, qtb.activeButtons[id] and qtb.activeButtons[id].teleportID,
                    "Quest " .. id .. " uses the guild cloak after the hearth location changes")
            end
            t:assertEqual(generation + 1, qtb._refreshGeneration, "One changed graph causes exactly one replacement batch")
            t:assertEqual(3, calls, "The initial dirty build and repair do not restart every quest")
            qtb:OnMovementUpdate(1)
            t:assertEqual(0, #state.pending, "The settled graph schedules no repeated repair")
        end)
    end)
    for index = #changes, 1, -1 do
        local change = changes[index]
        change[1][change[2]] = change[3]
    end
    if not ok then error(err) end
end)

T:run("Quest button destinations: POI updates refresh a stationary quest's changed objective", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        local destinationX = .5
        QR.WaypointIntegration.GetQuestWaypoint = function()
            return {mapID=84,x=destinationX,y=.5,title="Moving objective"}
        end
        refreshOne(qtb, state)
        destinationX = .8
        t:assertTrue(qtb.eventFrame._events.QUEST_POI_UPDATE, "Quest buttons subscribe to streamed objective changes")
        qtb.eventFrame:GetScript("OnEvent")(qtb.eventFrame, "QUEST_POI_UPDATE")
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(2, state.calls, "Changed POI coordinates recalculate the destination without player movement")
    end)
end)

T:run("Quest button recovery: a brief missing player position keeps the icon but clears its action", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        local btn = qtb.activeButtons[10001]
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetTexture(123)
        btn:Show()
        local hide, hides = btn.Hide, 0
        btn.Hide = function(self) hides = hides + 1; return hide(self) end
        btn:SetAttribute("house-guid", "old-house")
        btn:SetScript("PreClick", function() end)
        local position = C_Map.GetPlayerMapPosition
        C_Map.GetPlayerMapPosition = function() return nil end
        refreshOne(qtb, state)
        t:assertEqual(btn, qtb.activeButtons[10001], "Transient position failure retains the existing quest slot")
        t:assertTrue(btn:IsShown(), "Pending route keeps its icon visible")
        t:assertNil(btn:GetAttribute("type"), "Pending route cannot activate the old teleport")
        t:assertNil(btn:GetAttribute("house-guid"), "Pending route clears old housing attributes")
        t:assertNil(btn:GetScript("PreClick"), "Pending route cannot run old equipment callbacks")
        t:assertEqual(QR.L["CALCULATING"], btn.tooltipText, "Pending route explains that it is being recalculated")
        C_Map.GetPlayerMapPosition = position
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        qtb:OnMovementUpdate(1)
        local callback = table.remove(state.pending, 1)
        if callback then callback() end
        t:assertEqual(btn, qtb.activeButtons[10001], "Recovered route reuses the same button")
        t:assertEqual("spell", btn:GetAttribute("type"), "Recovered route restores its confirmed action")
        t:assertEqual(0, hides, "A brief position gap causes no hide/show flicker")
    end)
end)

T:run("Quest button recovery: a stationary retry bypasses only the pending target's negative cache", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        local btn = qtb.activeButtons[10001]
        local ready, retries = false, 0
        QR.WaypointIntegration.GetQuestWaypoint = function(_, _, retry)
            if retry then retries = retries + 1 end
            if ready and retry then return {mapID=84, x=.5, y=.5} end
        end
        qtb:InvalidateCache()
        refreshOne(qtb, state)
        ready = true
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        qtb:OnMovementUpdate(1)
        local callback = table.remove(state.pending, 1)
        if callback then callback() end
        t:assertEqual(1, retries, "Only recovery explicitly retries the pending quest's unavailable coordinates")
        t:assertEqual(btn, qtb.activeButtons[10001], "Stationary target recovery keeps the original button")
        t:assertEqual("spell", btn:GetAttribute("type"), "Recovered target restores the current teleport")
    end)
end)

T:run("Quest button recovery: repeated missing routes expire without extending the grace period", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        local btn = qtb.activeButtons[10001]
        btn:Show()
        QR.PathCalculator.CalculatePath = function() state.calls=state.calls+1; return nil end
        qtb:InvalidateCache()
        refreshOne(qtb, state)
        t:assertEqual(btn, qtb.activeButtons[10001], "First unavailable result enters the grace period")
        for index = 1, 2 do
            MockWoW.config.baseTime = MockWoW.config.baseTime + 1
            qtb:OnMovementUpdate(1)
            local callback = table.remove(state.pending, 1)
            if callback then callback() end
            if index == 1 then
                t:assertEqual(btn, qtb.activeButtons[10001], "A second failure does not prematurely hide the pending slot")
            end
        end
        t:assertNil(qtb.activeButtons[10001], "A route unavailable for two seconds releases its slot")
        t:assertFalse(btn:IsShown(), "Expired pending route is no longer displayed")
        t:assertNil(qtb._pendingRefreshAt, "Expired pending route schedules no endless retries")
    end)
end)

T:run("Quest button recovery: a confirmed walking route removes a pending teleport immediately", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        QR.PathCalculator.CalculatePath = function() return nil end
        qtb:InvalidateCache()
        refreshOne(qtb, state)
        QR.PathCalculator.CalculatePath = function() return {steps={{type="walk"}}} end
        refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "A known better direct route does not retain a pending teleport")
        t:assertNil(qtb._pendingRefreshAt, "A confirmed result clears the recovery retry")
    end)
end)

T:run("Quest button flight: a near-tied teleport must remain best before reappearing", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        _G.IsFlying = function() return true end
        local direct = false
        QR.PathCalculator.CalculatePath = function()
            state.calls = state.calls + 1
            return {steps={{type=direct and "walk" or "teleport", teleportID=3561, sourceType="spell"}}}
        end
        refreshOne(qtb, state)
        t:assertNotNil(qtb.activeButtons[10001], "The first confirmed teleport is shown immediately")
        direct = true; qtb:InvalidateCache(); refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "A faster direct flight removes the teleport immediately")
        direct = false; state.x=state.x+.01; refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "One returning teleport sample does not flash the button")
        direct = true; state.x=state.x+.01; refreshOne(qtb, state)
        direct = false; state.x=state.x+.01; refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "Alternating flight speed restarts confirmation without flashing")
        local before = state.calls
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        qtb:OnMovementUpdate(1)
        local callback = table.remove(state.pending, 1)
        if callback then callback() end
        t:assertEqual(before+1, state.calls, "Confirmation computes a fresh route even without further movement")
        t:assertNotNil(qtb.activeButtons[10001], "Two stable recommendations restore the teleport button")
        t:assertEqual("spell", qtb.activeButtons[10001] and qtb.activeButtons[10001]:GetAttribute("type"), "Confirmed recommendation restores a valid action")
    end)
end)

T:run("Quest button flight: ending flight or untracking clears delayed recommendations", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        local flying, direct = true, false
        _G.IsFlying = function() return flying end
        QR.PathCalculator.CalculatePath = function()
            return {steps={{type=direct and "walk" or "teleport", teleportID=3561, sourceType="spell"}}}
        end
        refreshOne(qtb, state)
        direct=true; qtb:InvalidateCache(); refreshOne(qtb, state)
        direct=false; state.x=state.x+.01; refreshOne(qtb, state)
        flying=false; refreshOne(qtb, state)
        t:assertNotNil(qtb.activeButtons[10001], "Ground recommendations do not inherit flight confirmation delays")
        t:assertTableCount(qtb.flightChoices, 0, "Ending flight clears temporary choice history")
        flying=true; direct=true; qtb:InvalidateCache(); refreshOne(qtb, state)
        direct=false; state.x=state.x+.01; refreshOne(qtb, state)
        state.watched={}; qtb:RefreshButtons()
        t:assertTableCount(qtb.flightChoices, 0, "Untracking clears delayed flight recommendations")
        t:assertNil(qtb._pendingRefreshAt, "Untracked candidates do not keep scheduling retries")
    end)
end)

T:run("Quest button recovery: a missing position cannot preserve a known unusable action's icon", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        C_Map.GetPlayerMapPosition=function()return nil end
        QR.CooldownTracker.GetCooldown=function()return {ready=false}end
        refreshOne(qtb, state)
        t:assertNil(qtb.activeButtons[10001], "A known cooldown retires the icon despite a simultaneous position gap")
    end)
end)

T:run("Quest button flight: a cancelled calculation cannot supply the confirming recommendation", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        _G.IsFlying = function() return true end
        refreshOne(qtb, state)
        QR.PathCalculator.CalculatePath = function()return {steps={{type="walk"}}}end
        qtb:InvalidateCache(); refreshOne(qtb, state)
        QR.PathCalculator.CalculatePath = function()
            return {steps={{type="teleport",teleportID=3561,sourceType="spell"}}}
        end
        state.x=state.x+.01; refreshOne(qtb, state)
        MockWoW.config.baseTime=MockWoW.config.baseTime+.5
        QR.PathCalculator.CalculatePath = function()
            qtb:InvalidateCache()
            return {steps={{type="teleport",teleportID=3561,sourceType="spell"}}}
        end
        state.x=state.x+.01; refreshOne(qtb, state)
        t:assertNil(qtb.questCache[10001], "Cancelled work cannot refill the invalidated quest cache")
        local calls=0
        QR.PathCalculator.CalculatePath = function()
            calls=calls+1
            return {steps={{type="walk"}}}
        end
        MockWoW.config.baseTime=MockWoW.config.baseTime+.5
        refreshOne(qtb, state)
        t:assertEqual(1, calls, "A fresh query decides the current recommendation after cancellation")
        t:assertNil(qtb.activeButtons[10001], "A cancelled teleport cannot reappear when direct flight now wins")
    end)
end)

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

-- The wipe this used to assert on QUEST_LOG_UPDATE was the blanket
-- invalidation removed for issue #66: every field a cached entry depends on is
-- checked when it is read, in combat as out of it, so emptying the cache here
-- bought no freshness and moved a full recompute of every tracked quest to the
-- moment the fight ended. What a fight can still change is which quests are
-- tracked, and that is asserted below.
T:run("Quest button cache: quest events during combat do no secure work and keep the cache", function(t)
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
        t:assertNotNil(qtb.questCache[10001],"An ordinary quest event in combat keeps the cached target")
        t:assertEqual(writes,state.writes,"Combat quest events perform no protected attribute writes")
        t:assertEqual(1,state.calls,"Combat quest event schedules no route calculation")
        callback(frame,"QUEST_WATCH_LIST_CHANGED")
        t:assertNotNil(qtb.questCache[10001],"A tracked-set change in combat keeps the entries it did not touch; PruneQuestCache drops what is no longer watched at the next refresh")
        t:assertEqual(writes,state.writes,"and still performs no protected attribute writes")
        t:assertEqual(1,state.calls,"and still schedules no route calculation")
        frame:UnregisterAllEvents()
        qtb.eventFrame=oldEvent
    end)
end)

T:run("Quest button refresh: unchanged actions remain visible throughout a movement batch", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001, 10002}
        qtb:RefreshButtons()
        state.pending[1]()
        state.pending[2]()
        local first, second = qtb.activeButtons[10001], qtb.activeButtons[10002]
        first:Show()
        second:Show()
        local hides, anchors = 0, 0
        for _, btn in ipairs({first, second}) do
            local hide, clear = btn.Hide, btn.ClearAllPoints
            btn.Hide = function(self) hides = hides + 1; hide(self) end
            btn.ClearAllPoints = function(self) anchors = anchors + 1; clear(self) end
        end
        state.x = 0.7
        qtb:RefreshButtons()
        t:assertTrue(first:IsShown() and second:IsShown(), "Existing quest buttons stay visible while replacements are calculated")
        state.pending[3]()
        t:assertTrue(first:IsShown() and second:IsShown(), "A partial movement batch does not blank the remaining buttons")
        state.pending[4]()
        t:assertEqual(first, qtb.activeButtons[10001], "First quest keeps its original secure button")
        t:assertEqual(second, qtb.activeButtons[10002], "Second quest keeps its original secure button")
        t:assertTrue(first:IsShown() and second:IsShown(), "Unchanged actions stay visible after reconciliation")
        t:assertEqual(0, hides, "Movement refresh produces no visibility flicker for unchanged quest actions")
        t:assertEqual(0, anchors, "Movement refresh does not detach unchanged buttons from their positions")
    end)
end)

T:run("Quest button refresh: remove obsolete choices without blanking a surviving quest", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001, 10002}
        qtb:RefreshButtons()
        state.pending[1]()
        state.pending[2]()
        local first, second = qtb.activeButtons[10001], qtb.activeButtons[10002]
        first:Show()
        second:Show()
        state.x = 0.7
        QR.PathCalculator.CalculatePath = function(_, _, _, _, title)
            state.calls = state.calls + 1
            if title == "10001" then return {steps={{type="walk"}}} end
            return {steps={{type="teleport", teleportID=3561, sourceType="spell"}}}
        end
        qtb:RefreshButtons()
        state.pending[3]()
        state.pending[4]()
        t:assertNil(qtb.activeButtons[10001], "Walking replaces the obsolete teleport choice")
        t:assertFalse(first:IsShown(), "Obsolete action is hidden when the new batch is applied")
        t:assertNil(first:GetAttribute("type"), "Removed action cannot retain a secure teleport")
        t:assertEqual(second, qtb.activeButtons[10002], "Unchanged second quest retains its button identity")
        t:assertTrue(second:IsShown(), "Unchanged second quest never needs to reappear")
        state.watched = {10002}
        qtb:RefreshButtons()
        t:assertNil(qtb.questCache[10001], "Unwatched quest cache releases its route and graph references")
    end)
end)

T:run("Quest button refresh: a reordered full pool preserves surviving quest buttons", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001,10002,10003,10004,10005,10006,10007,10008}
        qtb:RefreshButtons()
        for index = 1, 8 do state.pending[index]() end
        local surviving = {}
        for id, btn in pairs(qtb.activeButtons) do surviving[id] = btn; btn:Show() end
        state.watched = {20001,10008,10007,10006,10005,10004,10003,10002}
        qtb:RefreshButtons()
        t:assertNil(qtb.activeButtons[10001], "Unwatched quest is retired before queued work")
        for index = 9, 16 do state.pending[index]() end
        t:assertNotNil(qtb.activeButtons[20001], "New high-priority quest receives the freed pool slot")
        for id = 10002, 10008 do
            t:assertEqual(surviving[id], qtb.activeButtons[id], "Surviving quest " .. id .. " keeps its button after reordering")
            t:assertTrue(surviving[id]:IsShown(), "Surviving quest " .. id .. " does not flicker after reordering")
        end
        t:assertTableCount(qtb.activeButtons, 8, "Reconciled quest list stays within the secure pool bound")
    end)
end)

T:run("Quest button refresh: an uncached replacement action cannot show the previous icon", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        for _, btn in ipairs(qtb.pool) do btn.icon = btn:CreateTexture(nil, "ARTWORK") end
        C_Spell.GetSpellTexture = function(id) if id == 3561 then return 11111 end end
        _G.GetSpellTexture = C_Spell.GetSpellTexture
        qtb:RefreshButtons()
        state.pending[1]()
        local btn = qtb.activeButtons[10001]
        t:assertEqual(11111, btn.icon:GetTexture(), "Initial teleport has its loaded icon")
        QR.PlayerInventory.GetAllTeleports = function()
            return {[53140]={sourceType="spell", data={name="Dalaran"}}}
        end
        QR.PathCalculator.CalculatePath = function()
            return {steps={{type="teleport",teleportID=53140,sourceType="spell"}}}
        end
        qtb:InvalidateCache()
        qtb:RefreshButtons()
        state.pending[2]()
        t:assertEqual(btn, qtb.activeButtons[10001], "Replacement action reuses the same quest button")
        t:assertEqual(53140, btn:GetAttribute("spell"), "Button casts the newly selected teleport")
        t:assertEqual(134400, btn.icon:GetTexture(), "Unavailable new texture uses the neutral fallback instead of the old icon")
    end)
end)

T:run("Quest button refresh: a new first quest replaces only the full pool's last choice", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001,10002,10003,10004,10005,10006,10007,10008}
        qtb:RefreshButtons()
        for index = 1, 8 do state.pending[index]() end
        local surviving = {}
        for id, btn in pairs(qtb.activeButtons) do surviving[id] = btn; btn:Show() end
        state.watched = {20001,10001,10002,10003,10004,10005,10006,10007,10008}
        qtb:RefreshButtons()
        t:assertTableCount(qtb.activeButtons, 8, "All old quests remain watched when the full-pool refresh starts")
        for index = 9, 16 do state.pending[index]() end
        t:assertNotNil(qtb.activeButtons[20001], "New first quest receives a slot even though no old quest was untracked")
        t:assertNil(qtb.activeButtons[10008], "Only the last watched choice falls beyond the eight-button limit")
        for id = 10001, 10007 do
            t:assertEqual(surviving[id], qtb.activeButtons[id], "Retained quest " .. id .. " preserves its full-pool identity")
            t:assertTrue(surviving[id]:IsShown(), "Retained quest " .. id .. " stays visible during full-pool replacement")
        end
        t:assertTableCount(qtb.activeButtons, 8, "Adding a watched quest never exceeds the protected pool bound")
    end)
end)

T:run("Quest button cache: choices below the pool cutoff cannot retain an obsolete graph", function(t)
    withRefresh(function(qtb, state)
        state.watched = {}
        for id = 10001, 10016 do state.watched[#state.watched + 1] = id end
        local firstBatch = true
        QR.PathCalculator.CalculatePath = function(_, _, _, _, title)
            if firstBatch and tonumber(title) <= 10008 then return {steps={{type="walk"}}} end
            return {steps={{type="teleport",teleportID=3561,sourceType="spell"}}}
        end
        local oldGraph = setmetatable({QR.PathCalculator.graph}, {__mode="v"})
        qtb:RefreshButtons()
        for index = 1, 16 do state.pending[index]() end
        t:assertTableCount(qtb.questCache, 16, "First batch caches all sixteen watched quests before filling the pool")
        firstBatch = false
        QR.PathCalculator.graph = {}
        qtb:RefreshButtons()
        for index = 17, 24 do state.pending[index]() end
        collectgarbage("collect")
        t:assertNil(oldGraph[1], "Unvisited lower-priority quests no longer keep the replaced graph alive")
        t:assertTableCount(qtb.questCache, 8, "Only choices evaluated against the current graph remain cached")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 31
        local callbacks = #state.pending
        qtb:OnMovementUpdate(1)
        t:assertTableCount(qtb.questCache, 0, "Idle movement probe removes expired cache entries without route calculations")
        t:assertEqual(callbacks, #state.pending, "Expiring idle cache entries does not schedule fresh route work")
    end)
end)

T:run("Quest button cache: disabling the feature releases all graph references", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        qtb:RefreshButtons()
        state.pending[1]()
        local oldGraph = setmetatable({QR.PathCalculator.graph}, {__mode="v"})
        QR.PathCalculator.graph = {}
        qtb:SetEnabled(false)
        collectgarbage("collect")
        t:assertNil(oldGraph[1], "Disabled quest buttons retain neither cached routes nor the previous movement graph")
        t:assertTableCount(qtb.questCache, 0, "Disabled feature has no route cache left to retain graphs")
    end)
end)

-- The readiness check that consumes SPELL_UPDATE_COOLDOWN decides whether a
-- cooldown moved. A refresh batch spans one frame per tracked quest, so a batch
-- can be open when the event arrives, and reading its remembered answers there
-- would report "nothing changed" about the very teleport the player just used.
-- Nothing could catch that before: the stand-in above had no memo, so the
-- assertion passed whether or not the code read past one.
T:run("Quest button cooldowns: the readiness check reads past an open batch", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001, 10002, 10003}
        qtb:RefreshButtons()
        state.pending[1]()                      -- one quest routed; batch is open
        local ct = QR.CooldownTracker
        t:assertTrue(ct.batchOpen, "the refresh opened a cooldown batch")
        ct:GetCooldown(3561, "spell")           -- remembered as ready
        state.cooldownReady = false             -- the player uses the teleport
        local before = ct.liveReads

        local frame = qtb.eventFrame
        if frame then frame:GetScript("OnEvent")(frame, "SPELL_UPDATE_COOLDOWN") end

        t:assertTrue(ct.liveReads > before,
            "the readiness check asked the client rather than the open batch")
    end)
end)

-- The same event, when nothing moved. It fires on every global cooldown, so
-- this is the common case: ending the batch here stripped the refresh that is
-- still running of its memo for all of its remaining frames, and every one of
-- those quests went back to asking the client.
T:run("Quest button cooldowns: an unrelated cooldown event leaves a running batch its memo", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001, 10002, 10003}
        qtb:RefreshButtons()
        state.pending[1]()                      -- one quest routed; batch is open
        local ct = QR.CooldownTracker
        t:assertTrue(ct.batchOpen, "the refresh opened a cooldown batch")

        local frame = qtb.eventFrame
        if frame then frame:GetScript("OnEvent")(frame, "SPELL_UPDATE_COOLDOWN") end
        t:assertTrue(ct.batchOpen, "a batch that was open is still open afterwards")

        local before = ct.liveReads
        while state.pending[1] do table.remove(state.pending, 1)() end
        t:assertEqual(before, ct.liveReads,
            "the rest of the refresh answered from the memo the event left alone")
    end)
end)

-- A cache hit used to be decided without the waypoint layer. Since the
-- destination joined the key it is consulted on every read, and a client that
-- cannot say where a quest points for one frame produced a nil that read as a
-- changed destination -- evicting an entry that was right.
T:run("Quest button routes: a momentary waypoint gap keeps the cached teleport", function(t)
    withRefresh(function(qtb, state)
        state.watched = {10001}
        refreshOne(qtb, state)
        local btn = qtb.activeButtons[10001]
        t:assertNotNil(qtb.questCache[10001], "the quest routed and cached")
        local calls = state.calls

        local waypoint = QR.WaypointIntegration.GetQuestWaypoint
        QR.WaypointIntegration.GetQuestWaypoint = function() return nil end
        refreshOne(qtb, state)
        QR.WaypointIntegration.GetQuestWaypoint = waypoint

        t:assertNotNil(qtb.questCache[10001], "the gap did not evict the cached route")
        t:assertEqual("spell", btn:GetAttribute("type"), "the button kept its action")
        t:assertEqual(calls, state.calls, "and no route was calculated over the gap")
    end)
end)
