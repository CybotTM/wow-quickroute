-------------------------------------------------------------------------------
-- test_ui.lua
-- Tests for QR.UI module: RefreshRoute re-entrancy guard, UpdateRoute error
-- handling, secure button anchoring, and auto-waypoint deferral.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper: reset mock state and rebuild graph
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
end

--- Helper: set up a map pin waypoint the UI can detect
local function setMapPinWaypoint(mapID, x, y, title)
    MockWoW.config.hasUserWaypoint = true
    MockWoW.config.userWaypointMapID = mapID or 84
    MockWoW.config.userWaypointX = x or 0.5
    MockWoW.config.userWaypointY = y or 0.5
    -- Ensure GetUserWaypoint returns it
    if _G.C_Map then
        _G.C_Map.HasUserWaypoint = function() return true end
        _G.C_Map.GetUserWaypoint = function()
            return {
                uiMapID = MockWoW.config.userWaypointMapID,
                position = {
                    x = MockWoW.config.userWaypointX,
                    y = MockWoW.config.userWaypointY,
                    GetXY = function()
                        return MockWoW.config.userWaypointX, MockWoW.config.userWaypointY
                    end,
                },
            }
        end
    end
end

--- Helper: ensure MainFrame + UI content frame is created for testing
local function ensureUIFrame()
    -- Initialize MainFrame first (creates container + content frames)
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true
    -- Create UI content inside MainFrame's route content area
    if not QR.UI.frame then
        local contentFrame = QR.MainFrame:GetContentFrame("route")
        QR.UI:CreateContent(contentFrame)
    end
    QR.UI.initialized = true
    -- Reset calculating state
    QR.UI.isCalculating = false
    if QR.UI.frame and QR.UI.frame.refreshButton then
        QR.UI.frame.refreshButton:SetText("Refresh")
    end
end

-------------------------------------------------------------------------------
-- 1. Re-entrancy Guard
-------------------------------------------------------------------------------

T:run("RefreshRoute re-entrancy guard prevents double execution", function(t)
    resetState()
    ensureUIFrame()

    -- Simulate a waypoint so RefreshRoute actually calculates
    setMapPinWaypoint(84, 0.5, 0.5)

    -- Manually set isCalculating to true (simulating already running)
    QR.UI.isCalculating = true

    -- Track if CalculatePathToWaypoint gets called
    local originalCalc = QR.WaypointIntegration.CalculatePathToWaypoint
    local calcCallCount = 0
    QR.WaypointIntegration.CalculatePathToWaypoint = function(self)
        calcCallCount = calcCallCount + 1
        return originalCalc(self)
    end

    -- Call RefreshRoute while isCalculating is true
    QR.UI:RefreshRoute()

    -- Should NOT have called CalculatePathToWaypoint
    t:assertEqual(0, calcCallCount, "CalculatePathToWaypoint was not called during re-entrant RefreshRoute")

    -- isCalculating should still be true (the guard returned early, not resetting)
    t:assertTrue(QR.UI.isCalculating, "isCalculating still true after guarded return")

    -- Restore
    QR.WaypointIntegration.CalculatePathToWaypoint = originalCalc
    QR.UI.isCalculating = false
end)

T:run("RefreshRoute executes normally when isCalculating is false", function(t)
    resetState()
    ensureUIFrame()

    -- Provide a same-map waypoint so path is found quickly
    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.3, 0.3)

    QR.UI.isCalculating = false

    -- Track if CalculatePathToWaypoint gets called
    local originalCalc = QR.WaypointIntegration.CalculatePathToWaypoint
    local calcCalled = false
    QR.WaypointIntegration.CalculatePathToWaypoint = function(self)
        calcCalled = true
        return originalCalc(self)
    end

    QR.UI:RefreshRoute()

    t:assertTrue(calcCalled, "CalculatePathToWaypoint was called when not calculating")
    -- After completion, isCalculating should be false again
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset to false after RefreshRoute completes")

    -- Restore
    QR.WaypointIntegration.CalculatePathToWaypoint = originalCalc
end)

-------------------------------------------------------------------------------
-- 2. UpdateRoute pcall Safety
-------------------------------------------------------------------------------

T:run("RefreshRoute resets calculating state even when UpdateRoute errors", function(t)
    resetState()
    ensureUIFrame()

    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.3, 0.3)

    -- Override UpdateRoute to throw an error
    local originalUpdateRoute = QR.UI.UpdateRoute
    QR.UI.UpdateRoute = function()
        error("Simulated UpdateRoute failure")
    end

    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Despite the error, isCalculating must be reset
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset to false after UpdateRoute error")

    -- Refresh button text should be restored
    local btnText = QR.UI.frame.refreshButton:GetText()
    t:assertNotNil(btnText, "Refresh button text is set")
    -- Should not be "..." (the calculating indicator)
    local isStuck = (btnText == "...")
    t:assertFalse(isStuck, "Refresh button is not stuck on '...' after error")

    -- Restore
    QR.UI.UpdateRoute = originalUpdateRoute
end)

T:run("RefreshRoute logs error when UpdateRoute fails", function(t)
    resetState()
    ensureUIFrame()

    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.3, 0.3)

    -- Override UpdateRoute to throw
    local originalUpdateRoute = QR.UI.UpdateRoute
    QR.UI.UpdateRoute = function()
        error("Test error message")
    end

    -- Track error log
    local originalError = QR.Error
    local errorLogged = false
    local errorMsg = ""
    QR.Error = function(self, msg)
        errorLogged = true
        errorMsg = msg or ""
    end

    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    t:assertTrue(errorLogged, "Error was logged when UpdateRoute failed")
    t:assertTrue(errorMsg ~= "", "The logged error carries a message (got: " .. tostring(errorMsg) .. ")")

    -- Restore
    QR.UI.UpdateRoute = originalUpdateRoute
    QR.Error = originalError
end)

-------------------------------------------------------------------------------
-- 3. Auto-waypoint Deferral
-------------------------------------------------------------------------------

T:run("Auto-waypoint uses C_Timer.After for deferred execution", function(t)
    resetState()
    ensureUIFrame()

    -- Enable auto-waypoint setting
    QR.db = QR.db or {}
    QR.db.autoWaypoint = true

    -- Track C_Timer.After calls
    local originalTimerAfter = C_Timer.After
    local timerCalls = {}
    C_Timer.After = function(delay, callback)
        timerCalls[#timerCalls + 1] = { delay = delay, callback = callback }
        -- Do NOT call callback immediately for this test
    end

    -- Mock CreateStepLabel to avoid frame hierarchy issues in test env
    local originalCreateStepLabel = QR.UI.CreateStepLabel
    QR.UI.CreateStepLabel = function(self, index, step, yOffset)
        local mockFrame = CreateFrame("Frame")
        mockFrame:SetSize(300, 24)
        return mockFrame
    end

    -- Create a mock result with steps
    local mockResult = {
        waypoint = { title = "Test", mapID = 84 },
        waypointSource = "mappin",
        totalTime = 30,
        steps = {
            {
                type = "walk",
                action = "Go to Test",
                time = 30,
                to = "Test Destination",
                destMapID = 84,
                destX = 0.3,
                destY = 0.3,
            },
        },
    }

    -- Track SetTomTomWaypoint calls
    local originalSetWaypoint = QR.WaypointIntegration.SetTomTomWaypoint
    local waypointSetCount = 0
    QR.WaypointIntegration.SetTomTomWaypoint = function(self, mapID, x, y, title)
        waypointSetCount = waypointSetCount + 1
    end

    -- Call UpdateRoute
    QR.UI:UpdateRoute(mockResult)

    -- Waypoint should NOT have been set synchronously (deferred via C_Timer.After)
    t:assertEqual(0, waypointSetCount, "Waypoint not set synchronously during UpdateRoute")

    -- C_Timer.After should have been called with delay 0
    t:assertGreaterThan(#timerCalls, 0, "C_Timer.After was called for deferred waypoint")
    t:assertEqual(0, timerCalls[1].delay, "C_Timer.After called with delay 0")

    -- Now execute the deferred callback
    if timerCalls[1] and timerCalls[1].callback then
        timerCalls[1].callback()
    end
    t:assertEqual(1, waypointSetCount, "Waypoint set after deferred callback executes")

    -- Restore
    C_Timer.After = originalTimerAfter
    QR.WaypointIntegration.SetTomTomWaypoint = originalSetWaypoint
    QR.UI.CreateStepLabel = originalCreateStepLabel
    QR.db.autoWaypoint = false
end)

T:run("Auto-waypoint skipped when first step has no coordinates", function(t)
    resetState()
    ensureUIFrame()

    -- Enable auto-waypoint setting
    QR.db = QR.db or {}
    QR.db.autoWaypoint = true

    -- Track C_Timer.After calls
    local originalTimerAfter = C_Timer.After
    local timerCalls = 0
    C_Timer.After = function(delay, callback)
        timerCalls = timerCalls + 1
    end

    local mockResult = {
        waypoint = { title = "Test", mapID = 84 },
        waypointSource = "mappin",
        totalTime = 30,
        steps = {
            {
                type = "walk",
                action = "Go somewhere",
                time = 30,
                to = "Unknown Place",
                -- No destMapID/destX/destY
            },
        },
    }

    QR.UI:UpdateRoute(mockResult)

    t:assertEqual(0, timerCalls, "C_Timer.After not called when step has no coordinates")

    -- Restore
    C_Timer.After = originalTimerAfter
    QR.db.autoWaypoint = false
end)

T:run("Auto-waypoint skipped when autoWaypoint setting is disabled", function(t)
    resetState()
    ensureUIFrame()

    -- Disable auto-waypoint setting (default)
    QR.db = QR.db or {}
    QR.db.autoWaypoint = false

    -- Track C_Timer.After calls
    local originalTimerAfter = C_Timer.After
    local timerCalls = 0
    C_Timer.After = function(delay, callback)
        timerCalls = timerCalls + 1
    end

    -- Mock CreateStepLabel
    local originalCreateStepLabel = QR.UI.CreateStepLabel
    QR.UI.CreateStepLabel = function(self, index, step, yOffset)
        local mockFrame = CreateFrame("Frame")
        mockFrame:SetSize(300, 24)
        return mockFrame
    end

    local mockResult = {
        waypoint = { title = "Test", mapID = 84 },
        waypointSource = "mappin",
        totalTime = 30,
        steps = {
            {
                type = "walk",
                action = "Go to Test",
                time = 30,
                to = "Test Destination",
                destMapID = 84,
                destX = 0.3,
                destY = 0.3,
            },
        },
    }

    QR.UI:UpdateRoute(mockResult)

    t:assertEqual(0, timerCalls, "C_Timer.After not called when autoWaypoint is disabled")

    -- Restore
    C_Timer.After = originalTimerAfter
    QR.UI.CreateStepLabel = originalCreateStepLabel
end)

-------------------------------------------------------------------------------
-- 4. Secure Button Anchoring
-------------------------------------------------------------------------------

T:run("Secure button uses overlay positioning via UIParent", function(t)
    resetState()
    ensureUIFrame()

    -- Mock SecureButtons with a mock button
    local originalGetButton = QR.SecureButtons.GetButton
    local originalConfigureButton = QR.SecureButtons.ConfigureButton
    local mockSecureBtn = CreateFrame("Button", "QRTestSecBtn", nil, "SecureActionButtonTemplate")

    QR.SecureButtons.GetButton = function() return mockSecureBtn end
    QR.SecureButtons.ConfigureButton = function() return true end

    -- Ensure not in combat
    MockWoW.config.inCombatLockdown = false

    local step = {
        type = "teleport",
        teleportID = 140192,
        sourceType = "toy",
        action = "Use Dalaran Hearthstone to teleport to Dalaran (Legion)",
        time = 5,
        to = "Dalaran (Legion)",
        destMapID = 627,
        destX = 0.5,
        destY = 0.5,
    }

    QR.UI:CreateStepLabel(1, step, 0)

    -- 1. Button must NOT be reparented to stepFrame
    -- (overlay positioning keeps it on its original parent, NOT stepFrame)
    -- stepFrame is the frame created inside CreateStepLabel
    local stepFrame = mockSecureBtn._qrStepFrame
    local notParentedToStepFrame = mockSecureBtn._parent ~= stepFrame
    t:assertTrue(notParentedToStepFrame, "Secure button NOT parented to stepFrame")

    -- 2. Button should be tracked by centralized overlay manager (no per-button OnUpdate)
    t:assertGreaterThan(QR.SecureButtons:GetActiveOverlayCount(), 0,
        "Secure button is tracked by overlay manager")

    -- 3. Button stores _qrStepFrame reference for overlay tracking (backward compat)
    t:assertNotNil(mockSecureBtn._qrStepFrame, "Secure button has _qrStepFrame reference")

    -- Restore
    QR.SecureButtons.GetButton = originalGetButton
    QR.SecureButtons.ConfigureButton = originalConfigureButton
end)

-------------------------------------------------------------------------------
-- 5. RefreshRoute Complete Flow
-------------------------------------------------------------------------------

T:run("RefreshRoute shows steps for a valid same-map waypoint", function(t)
    resetState()
    ensureUIFrame()

    -- Override C_Timer.After to not trigger re-entrant refresh
    local originalTimerAfter = C_Timer.After
    C_Timer.After = function() end  -- No-op

    -- Set player on map 84 with waypoint also on 84
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX = 0.5
    MockWoW.config.playerY = 0.5
    setMapPinWaypoint(84, 0.3, 0.3)

    QR.UI.isCalculating = false

    -- Mock CalculatePathToWaypoint to return a known result (UI test, not pathfinding test)
    local originalCalcPath = QR.WaypointIntegration.CalculatePathToWaypoint
    QR.WaypointIntegration.CalculatePathToWaypoint = function()
        return {
            waypoint = { title = "Map Pin", mapID = 84 },
            waypointSource = "mappin",
            totalTime = 30,
            steps = {
                {
                    type = "walk",
                    action = "Go to Map Pin",
                    time = 30,
                    to = "Map Pin",
                    destMapID = 84,
                    destX = 0.3,
                    destY = 0.3,
                },
            },
        }
    end

    -- Mock CreateStepLabel to avoid secure frame issues in test env
    local originalCreateStepLabel = QR.UI.CreateStepLabel
    QR.UI.CreateStepLabel = function(self, index, step, yOffset)
        local mockFrame = CreateFrame("Frame")
        mockFrame:SetSize(300, 24)
        return mockFrame
    end

    QR.UI:RefreshRoute()

    -- isCalculating should be reset
    t:assertFalse(QR.UI.isCalculating, "isCalculating is false after RefreshRoute")

    -- Step labels should have been created
    t:assertGreaterThan(#QR.UI.stepLabels, 0, "At least one step label was created")

    -- Time label should contain travel time, not "..."
    local timeText = QR.UI.frame.timeLabel:GetText()
    t:assertNotNil(timeText, "Time label has text")

    -- Restore
    C_Timer.After = originalTimerAfter
    QR.UI.CreateStepLabel = originalCreateStepLabel
    QR.WaypointIntegration.CalculatePathToWaypoint = originalCalcPath
end)

T:run("RefreshRoute handles no waypoint gracefully", function(t)
    resetState()
    ensureUIFrame()

    -- No waypoint set
    _G.C_Map.HasUserWaypoint = function() return false end
    _G.C_Map.GetUserWaypoint = function() return nil end

    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- isCalculating should be reset
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset when no waypoint")

    -- No step labels should exist
    t:assertEqual(0, #QR.UI.stepLabels, "No step labels when no waypoint")
end)

T:run("RefreshRoute handles path calculation error gracefully", function(t)
    resetState()
    ensureUIFrame()

    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.3, 0.3)

    -- Override CalculatePathToWaypoint to throw
    local originalCalc = QR.WaypointIntegration.CalculatePathToWaypoint
    QR.WaypointIntegration.CalculatePathToWaypoint = function()
        error("Simulated path calculation failure")
    end

    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Must still reset calculating state
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset after calculation error")

    -- Restore
    QR.WaypointIntegration.CalculatePathToWaypoint = originalCalc
end)

-------------------------------------------------------------------------------
-- Combat hiding / re-showing tests
-- Use centralized QR.combatFrame handler to fire combat events
-------------------------------------------------------------------------------

--- Helper: invoke the centralized combat frame handler directly
local function fireCombatEvent(event)
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, event)
    end
end

T:run("Combat: MainFrame closed via ESC does not reopen after combat", function(t)
    ensureUIFrame()

    -- Reset combat state
    QR.MainFrame.wasShowingBeforeCombat = false

    -- Open the MainFrame
    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame is showing after Show()")

    -- Simulate ESC close: WoW directly calls frame:Hide() via UISpecialFrames
    QR.MainFrame.frame:Hide()

    -- After ESC, isShowing should be false (OnHide syncs it)
    t:assertFalse(QR.MainFrame.isShowing, "isShowing is false after ESC (frame:Hide)")

    -- Enter combat - use direct handler invocation
    fireCombatEvent("PLAYER_REGEN_DISABLED")

    -- wasShowingBeforeCombat should be false since MainFrame was not showing
    t:assertFalse(QR.MainFrame.wasShowingBeforeCombat,
        "wasShowingBeforeCombat is false when MainFrame was closed before combat")

    -- Leave combat
    fireCombatEvent("PLAYER_REGEN_ENABLED")

    -- MainFrame should NOT reopen
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame does not reopen after combat when it was closed")
end)

T:run("Combat: MainFrame open before combat reopens after combat", function(t)
    ensureUIFrame()

    -- Reset combat state
    QR.MainFrame.wasShowingBeforeCombat = false

    -- Open the MainFrame
    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame is showing after Show()")

    -- Enter combat - MainFrame should be hidden
    fireCombatEvent("PLAYER_REGEN_DISABLED")
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame hidden during combat")
    t:assertTrue(QR.MainFrame.wasShowingBeforeCombat,
        "wasShowingBeforeCombat is true when MainFrame was open before combat")

    -- Leave combat - MainFrame should reopen
    fireCombatEvent("PLAYER_REGEN_ENABLED")
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame reopens after combat when it was open before")
end)

T:run("Combat: MainFrame never opened does not appear after combat", function(t)
    ensureUIFrame()

    -- Ensure MainFrame is closed and combat state clean
    QR.MainFrame:Hide()
    QR.MainFrame.wasShowingBeforeCombat = false
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame is not showing initially")

    -- Enter and leave combat
    fireCombatEvent("PLAYER_REGEN_DISABLED")
    fireCombatEvent("PLAYER_REGEN_ENABLED")

    -- MainFrame should not appear
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame does not appear after combat when never opened")
end)

T:run("Combat: Show/Hide delegates to MainFrame correctly", function(t)
    ensureUIFrame()

    -- Show via UI:Show() should open MainFrame on route tab
    QR.MainFrame:Hide()
    QR.UI:Show()
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame showing after UI:Show()")
    t:assertEqual("route", QR.MainFrame.activeTab, "Active tab is 'route' after UI:Show()")

    -- Hide via UI:Hide() should hide MainFrame
    QR.UI:Hide()
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame hidden after UI:Hide()")
end)

-------------------------------------------------------------------------------
-- 3.4: LRU Cache Eviction at Capacity
-------------------------------------------------------------------------------

T:run("LRU cache: item info cache basic add and retrieve", function(t)
    -- Clear caches
    QR.UI.itemInfoCache = {}
    QR.UI.itemInfoAccessOrder = {}

    -- Fetch an item (should cache it)
    local name1, link1 = QR.UI:GetLocalizedItemInfo(12345)
    t:assertNotNil(name1, "Item name returned for ID 12345")
    t:assertNotNil(QR.UI.itemInfoCache[12345], "Item 12345 cached")

    -- Fetch same item again (should come from cache)
    local name2, link2 = QR.UI:GetLocalizedItemInfo(12345)
    t:assertEqual(name1, name2, "Cached item name matches original")
end)

T:run("LRU cache: spell info cache basic add and retrieve", function(t)
    -- Clear caches
    QR.UI.spellInfoCache = {}
    QR.UI.spellInfoAccessOrder = {}

    -- Fetch a spell (should cache it)
    local name1 = QR.UI:GetLocalizedSpellInfo(53140)
    t:assertNotNil(name1, "Spell name returned for ID 53140")
    t:assertNotNil(QR.UI.spellInfoCache[53140], "Spell 53140 cached")

    -- Fetch same spell again (from cache)
    local name2 = QR.UI:GetLocalizedSpellInfo(53140)
    t:assertEqual(name1, name2, "Cached spell name matches original")
end)

T:run("LRU cache: eviction at capacity (CACHE_MAX_SIZE=100)", function(t)
    -- Clear caches
    QR.UI.itemInfoCache = {}
    QR.UI.itemInfoAccessOrder = {}

    -- Fill cache to capacity with 100 items
    for i = 1, 100 do
        QR.UI:GetLocalizedItemInfo(10000 + i)
    end

    t:assertEqual(100, #QR.UI.itemInfoAccessOrder,
        "Access order has 100 entries at capacity")
    t:assertNotNil(QR.UI.itemInfoCache[10001],
        "Oldest item (10001) still in cache at capacity")
    t:assertNotNil(QR.UI.itemInfoCache[10100],
        "Newest item (10100) still in cache at capacity")

    -- Add one more to trigger eviction
    QR.UI:GetLocalizedItemInfo(10101)

    t:assertEqual(100, #QR.UI.itemInfoAccessOrder,
        "Access order still 100 after eviction")
    t:assertNil(QR.UI.itemInfoCache[10001],
        "Oldest item (10001) evicted after capacity exceeded")
    t:assertNotNil(QR.UI.itemInfoCache[10101],
        "New item (10101) present after eviction")
    t:assertNotNil(QR.UI.itemInfoCache[10002],
        "Second-oldest item (10002) still present")
end)

T:run("LRU cache: accessing old item promotes it (avoids eviction)", function(t)
    -- Clear caches
    QR.UI.itemInfoCache = {}
    QR.UI.itemInfoAccessOrder = {}

    -- Fill cache with 100 items (IDs 20001-20100)
    for i = 1, 100 do
        QR.UI:GetLocalizedItemInfo(20000 + i)
    end

    -- Access the oldest item (20001) to promote it to most-recently-used
    QR.UI:GetLocalizedItemInfo(20001)

    -- Now add a new item to trigger eviction
    QR.UI:GetLocalizedItemInfo(20101)

    -- 20001 should still be in cache (was promoted)
    t:assertNotNil(QR.UI.itemInfoCache[20001],
        "Recently accessed item 20001 survives eviction")
    -- 20002 should be evicted (it was now the oldest)
    t:assertNil(QR.UI.itemInfoCache[20002],
        "Item 20002 evicted (was oldest after 20001 promoted)")
    -- New item should be present
    t:assertNotNil(QR.UI.itemInfoCache[20101],
        "New item 20101 present in cache")
    -- Total count should still be 100
    t:assertEqual(100, #QR.UI.itemInfoAccessOrder,
        "Access order still 100 entries")
end)

T:run("LRU cache: nil itemID returns nil without caching", function(t)
    QR.UI.itemInfoCache = {}
    QR.UI.itemInfoAccessOrder = {}

    local name, link = QR.UI:GetLocalizedItemInfo(nil)
    t:assertNil(name, "nil itemID returns nil name")
    t:assertNil(link, "nil itemID returns nil link")
    t:assertEqual(0, #QR.UI.itemInfoAccessOrder,
        "No entries added for nil ID")
end)

T:run("LRU cache: nil spellID returns nil without caching", function(t)
    QR.UI.spellInfoCache = {}
    QR.UI.spellInfoAccessOrder = {}

    local name, link = QR.UI:GetLocalizedSpellInfo(nil)
    t:assertNil(name, "nil spellID returns nil name")
    t:assertEqual(0, #QR.UI.spellInfoAccessOrder,
        "No entries added for nil spell ID")
end)

-------------------------------------------------------------------------------
-- Route Progress Tracking (Tier 1.4)
-------------------------------------------------------------------------------

T:run("GetCurrentStepIndex: returns 1 for nil/empty steps", function(t)
    t:assertEqual(1, QR.UI:GetCurrentStepIndex(nil),
        "nil steps returns 1")
    t:assertEqual(1, QR.UI:GetCurrentStepIndex({}),
        "empty steps returns 1")
end)

T:run("GetCurrentStepIndex: player on starting map returns first step", function(t)
    -- Player is on map 84 (Stormwind), route starts there
    MockWoW.config.currentMapID = 84
    local steps = {
        { fromMapID = 84, destMapID = 84, action = "Walk to portal" },
        { fromMapID = 84, destMapID = 2339, action = "Take portal to Dornogal" },
        { fromMapID = 2339, destMapID = 2339, action = "Walk to destination" },
    }
    local idx = QR.UI:GetCurrentStepIndex(steps)
    -- destMapID=84 matches step 1, so current = 2 (step 1 completed).
    -- But also fromMapID=84 matches step 2 in backward scan.
    -- The algorithm first checks destMapID: step 1 dest=84 matches -> current = 2
    t:assertEqual(2, idx, "Current step is 2 when player is on starting map")
end)

T:run("GetCurrentStepIndex: player on destination map returns last step", function(t)
    MockWoW.config.currentMapID = 2339
    local steps = {
        { fromMapID = 84, destMapID = 84, action = "Walk to portal" },
        { fromMapID = 84, destMapID = 2339, action = "Take portal to Dornogal" },
        { fromMapID = 2339, destMapID = 2339, action = "Walk to destination" },
    }
    local idx = QR.UI:GetCurrentStepIndex(steps)
    -- Last step with destMapID=2339 is step 3, so current = min(4, 3) = 3
    t:assertEqual(3, idx,
        "Current step is last when player is on final destination map")
end)

T:run("GetCurrentStepIndex: player on intermediate map", function(t)
    MockWoW.config.currentMapID = 2112  -- Valdrakken (intermediate)
    local steps = {
        { fromMapID = 84, destMapID = 84, action = "Walk to portal" },
        { fromMapID = 84, destMapID = 2112, action = "Portal to Valdrakken" },
        { fromMapID = 2112, destMapID = 2112, action = "Walk to portal" },
        { fromMapID = 2112, destMapID = 2339, action = "Portal to Dornogal" },
        { fromMapID = 2339, destMapID = 2339, action = "Walk to destination" },
    }
    local idx = QR.UI:GetCurrentStepIndex(steps)
    -- Last destMapID=2112 match is step 3, so current = 4
    t:assertEqual(4, idx,
        "Current step is 4 after arriving in intermediate zone")
end)

T:run("GetCurrentStepIndex: player off-route defaults to 1", function(t)
    MockWoW.config.currentMapID = 9999  -- Unknown map
    local steps = {
        { fromMapID = 84, destMapID = 84, action = "Walk" },
        { fromMapID = 84, destMapID = 2339, action = "Portal" },
    }
    local idx = QR.UI:GetCurrentStepIndex(steps)
    t:assertEqual(1, idx, "Off-route player defaults to step 1")
end)

-------------------------------------------------------------------------------
-- Route Layout Tests
-------------------------------------------------------------------------------

T:run("Route content: searchBox at top of content", function(t)
    resetState()
    ensureUIFrame()

    local frame = QR.UI.frame
    t:assertNotNil(frame.searchBox, "searchBox exists")
    t:assertNil(frame.sourceDropdown, "sourceDropdown removed")
    t:assertNil(frame.dungeonButton, "dungeonButton removed")
    t:assertNotNil(frame.refreshButton, "refreshButton exists")
    t:assertNotNil(frame.copyDebugButton, "copyDebugButton exists")
    t:assertNotNil(frame.zoneDebugButton, "zoneDebugButton exists")
    t:assertNotNil(frame.timeLabel, "timeLabel exists")
    t:assertNotNil(frame.scrollFrame, "scrollFrame exists")
end)

T:run("Route content: no destLabel (removed in layout restructure)", function(t)
    resetState()
    ensureUIFrame()

    local frame = QR.UI.frame
    t:assertNil(frame.destLabel, "destLabel no longer exists")
end)

T:run("Route content: no sourceLabel (removed in layout restructure)", function(t)
    resetState()
    ensureUIFrame()

    local frame = QR.UI.frame
    t:assertNil(frame.sourceLabel, "sourceLabel no longer exists")
    t:assertNil(frame.statusLabel, "statusLabel backward compat no longer exists")
end)

T:run("Route content: hint text in body when no target, not in subtitle", function(t)
    resetState()
    ensureUIFrame()

    QR.UI:ClearRoute()

    -- Subtitle should show generic "Route", NOT the hint text
    local subtitle = QR.MainFrame.subtitle:GetText()
    local hintText = QR.L["SET_WAYPOINT_HINT"]
    t:assertFalse(subtitle == hintText,
        "Subtitle does not contain hint text after ClearRoute")
    t:assertEqual(QR.L["TAB_ROUTE"], subtitle,
        "Subtitle shows TAB_ROUTE when no target")

    -- timeLabel should contain the hint text
    local timeText = QR.UI.frame.timeLabel:GetText()
    t:assertNotNil(timeText, "timeLabel has text after ClearRoute")
    -- Strip color codes for checking (hint text is wrapped in GRAY color)
    t:assertTrue(timeText:find(hintText) ~= nil,
        "timeLabel contains hint text after ClearRoute")
end)

-------------------------------------------------------------------------------
-- Subtitle Guard Tests
-------------------------------------------------------------------------------

T:run("ClearRoute does NOT update subtitle when on teleports tab", function(t)
    resetState()
    ensureUIFrame()

    -- Switch to teleports tab first
    QR.MainFrame:Show("teleports")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle is TELEPORT_INVENTORY on teleports tab")

    -- Call ClearRoute while on teleports tab — subtitle guard should prevent change
    QR.UI:ClearRoute()

    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle still TELEPORT_INVENTORY after ClearRoute on teleports tab")
end)

T:run("RefreshRoute does NOT update subtitle when on teleports tab", function(t)
    resetState()
    ensureUIFrame()

    -- Set up a waypoint so RefreshRoute has something to show
    _G.C_Map.HasUserWaypoint = function() return true end
    _G.C_Map.GetUserWaypoint = function()
        return {
            uiMapID = 84,
            position = {
                x = 0.5, y = 0.5,
                GetXY = function() return 0.5, 0.5 end,
            },
        }
    end
    MockWoW.config.currentMapID = 84

    -- Switch to teleports tab
    QR.MainFrame:Show("teleports")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle is TELEPORT_INVENTORY before RefreshRoute")

    -- Override C_Timer.After to no-op
    local origTimerAfter = C_Timer.After
    C_Timer.After = function() end

    -- Call RefreshRoute while on teleports tab
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Subtitle should still show TELEPORT_INVENTORY (guard at line 462)
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle still TELEPORT_INVENTORY after RefreshRoute on teleports tab")

    C_Timer.After = origTimerAfter
end)

T:run("RefreshRoute subtitle shows destination when waypoint found", function(t)
    resetState()
    ensureUIFrame()

    -- Override C_Timer.After to no-op
    local origTimerAfter = C_Timer.After
    C_Timer.After = function() end

    -- Set waypoint
    MockWoW.config.currentMapID = 84
    _G.C_Map.HasUserWaypoint = function() return true end
    _G.C_Map.GetUserWaypoint = function()
        return {
            uiMapID = 84,
            position = {
                x = 0.5, y = 0.5,
                GetXY = function() return 0.5, 0.5 end,
            },
        }
    end

    -- Mock CreateStepLabel to avoid frame issues
    local origCreateStepLabel = QR.UI.CreateStepLabel
    QR.UI.CreateStepLabel = function(self, index, step, yOffset)
        local mockFrame = CreateFrame("Frame")
        mockFrame:SetSize(300, 24)
        return mockFrame
    end

    -- Mock path calculation to return a result
    local origCalcPath = QR.WaypointIntegration.CalculatePathToWaypoint
    QR.WaypointIntegration.CalculatePathToWaypoint = function()
        return {
            waypoint = { title = "Map Pin", mapID = 84 },
            waypointSource = "mappin",
            totalTime = 30,
            steps = {
                { type = "walk", action = "Walk", time = 30, to = "Target",
                  destMapID = 84, destX = 0.3, destY = 0.3 },
            },
        }
    end

    -- Show on route tab and refresh
    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Subtitle should contain the zone name (resolved from mapID 84 = "Stormwind City")
    local subtitle = QR.MainFrame.subtitle:GetText()
    t:assertNotNil(subtitle, "Subtitle has text after RefreshRoute")
    t:assertTrue(subtitle:find("Stormwind") ~= nil,
        "Subtitle contains zone name after route found")

    -- Restore
    C_Timer.After = origTimerAfter
    QR.UI.CreateStepLabel = origCreateStepLabel
    QR.WaypointIntegration.CalculatePathToWaypoint = origCalcPath
end)

T:run("RefreshRoute subtitle shows TAB_ROUTE when no waypoint", function(t)
    resetState()
    ensureUIFrame()

    -- No waypoint
    _G.C_Map.HasUserWaypoint = function() return false end
    _G.C_Map.GetUserWaypoint = function() return nil end

    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    local subtitle = QR.MainFrame.subtitle:GetText()
    t:assertEqual(QR.L["TAB_ROUTE"], subtitle,
        "Subtitle shows TAB_ROUTE when no waypoint")
end)

T:run("RefreshRoute subtitle shows TAB_ROUTE on waypoint detection error", function(t)
    resetState()
    ensureUIFrame()

    -- Make waypoint detection fail
    local origGetActive = QR.WaypointIntegration.GetActiveWaypoint
    QR.WaypointIntegration.GetActiveWaypoint = function()
        error("Simulated waypoint detection failure")
    end

    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    local subtitle = QR.MainFrame.subtitle:GetText()
    t:assertEqual(QR.L["TAB_ROUTE"], subtitle,
        "Subtitle shows TAB_ROUTE on waypoint error")

    QR.WaypointIntegration.GetActiveWaypoint = origGetActive
end)

T:run("RefreshRoute timeLabel contains hint text when no waypoint", function(t)
    resetState()
    ensureUIFrame()
    QR.db.lastDestination = nil  -- No saved destination either

    -- No waypoint
    _G.C_Map.HasUserWaypoint = function() return false end
    _G.C_Map.GetUserWaypoint = function() return nil end

    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    local timeText = QR.UI.frame.timeLabel:GetText()
    t:assertNotNil(timeText, "timeLabel has text")
    t:assertTrue(timeText:find(QR.L["SET_WAYPOINT_HINT"]) ~= nil,
        "timeLabel contains hint text when no waypoint")
end)

T:run("RefreshRoute uses saved destination when no active waypoint", function(t)
    resetState()
    ensureUIFrame()

    -- No active waypoint
    _G.C_Map.HasUserWaypoint = function() return false end
    _G.C_Map.GetUserWaypoint = function() return nil end

    -- But a saved destination exists (Stormwind area)
    QR.db.lastDestination = { mapID = 84, x = 0.5, y = 0.5, title = "Stormwind City" }

    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Should NOT show hint text (route should be calculated from saved destination)
    local timeText = QR.UI.frame.timeLabel:GetText()
    t:assertNotNil(timeText, "timeLabel has text")
    t:assertTrue(timeText:find(QR.L["SET_WAYPOINT_HINT"]) == nil,
        "timeLabel should NOT show hint when saved destination exists")

    -- Subtitle should show the saved destination name
    local subtitle = QR.MainFrame.subtitle:GetText()
    t:assertTrue(subtitle:find("Stormwind") ~= nil,
        "Subtitle shows saved destination name")
end)

T:run("RefreshRoute uses _pendingPOIRoute when set", function(t)
    resetState()
    ensureUIFrame()

    -- Set up a pending POI route (as POIRouting would set before Show)
    local fakeResult = {
        waypoint = { mapID = 84, x = 0.5, y = 0.5, title = "Stormwind City" },
        waypointSource = "map_click",
        totalTime = 42,
        steps = {{ action = "Test step", time = 42, type = "walk" }},
    }
    QR.UI._pendingPOIRoute = fakeResult
    QR.UI.isCalculating = false

    -- Track whether GetActiveWaypoint is called
    local origGetActive = QR.WaypointIntegration.GetActiveWaypoint
    local getActiveCalled = false
    QR.WaypointIntegration.GetActiveWaypoint = function(self)
        getActiveCalled = true
        return origGetActive(self)
    end

    QR.UI:RefreshRoute()

    -- GetActiveWaypoint should NOT have been called (POI route used instead)
    t:assertFalse(getActiveCalled, "GetActiveWaypoint not called when _pendingPOIRoute is set")
    -- _pendingPOIRoute should be consumed (cleared)
    t:assertNil(QR.UI._pendingPOIRoute, "_pendingPOIRoute consumed after RefreshRoute")
    -- isCalculating should remain false (we returned early from POI path)
    t:assertFalse(QR.UI.isCalculating, "isCalculating remains false after POI route used")

    -- Restore
    QR.WaypointIntegration.GetActiveWaypoint = origGetActive
end)

T:run("RefreshRoute runs normally when _pendingPOIRoute is not set", function(t)
    resetState()
    ensureUIFrame()

    -- Set up a mappin waypoint
    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.5, 0.5)

    QR.UI._pendingPOIRoute = nil
    QR.UI.isCalculating = false
    -- Ensure no locked destination interferes
    QR.db.destinationLocked = false

    -- Track whether GetActiveWaypoint is called
    local origGetActive = QR.WaypointIntegration.GetActiveWaypoint
    local getActiveCalled = false
    QR.WaypointIntegration.GetActiveWaypoint = function(self)
        getActiveCalled = true
        return origGetActive(self)
    end

    QR.UI:RefreshRoute()

    -- GetActiveWaypoint SHOULD be called (normal flow)
    t:assertTrue(getActiveCalled, "GetActiveWaypoint called when _pendingPOIRoute is nil")
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset after normal RefreshRoute")

    -- Restore
    QR.WaypointIntegration.GetActiveWaypoint = origGetActive
end)

T:run("RefreshRoute uses locked destination instead of active waypoint", function(t)
    resetState()
    ensureUIFrame()

    -- Set up a quest waypoint that would normally be used
    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(84, 0.5, 0.5)

    -- Lock destination to a different location (e.g. Orgrimmar)
    QR.db.destinationLocked = true
    QR.db.lastDestination = { mapID = 85, x = 0.4, y = 0.6, title = "Orgrimmar" }
    QR.UI._pendingPOIRoute = nil
    QR.UI.isCalculating = false

    -- Track whether GetActiveWaypoint is called
    local origGetActive = QR.WaypointIntegration.GetActiveWaypoint
    local getActiveCalled = false
    QR.WaypointIntegration.GetActiveWaypoint = function(self)
        getActiveCalled = true
        return origGetActive(self)
    end

    QR.UI:RefreshRoute()

    -- GetActiveWaypoint should NOT be called (locked destination takes priority)
    t:assertFalse(getActiveCalled, "GetActiveWaypoint not called when destination is locked")
    t:assertFalse(QR.UI.isCalculating, "isCalculating reset after locked route")

    -- Restore
    QR.WaypointIntegration.GetActiveWaypoint = origGetActive
    QR.db.destinationLocked = false
end)

T:run("RefreshRoute refresh button clears destinationLocked", function(t)
    resetState()
    ensureUIFrame()

    QR.db.destinationLocked = true
    QR.db.lastDestination = { mapID = 85, x = 0.4, y = 0.6, title = "Orgrimmar" }

    -- Simulate Refresh button click
    local refreshBtn = QR.UI.frame.refreshButton
    t:assertTrue(refreshBtn ~= nil, "Refresh button exists")
    local onClick = refreshBtn:GetScript("OnClick")
    t:assertTrue(onClick ~= nil, "Refresh button has OnClick handler")

    -- Reset throttle and click the refresh button
    QR.UI.lastRefreshClickTime = 0
    QR.UI.isCalculating = false
    onClick()

    -- destinationLocked should be cleared
    t:assertFalse(QR.db.destinationLocked, "destinationLocked cleared after Refresh click")
end)

T:run("_pendingPOIRoute sets destinationLocked", function(t)
    resetState()
    ensureUIFrame()

    QR.db.destinationLocked = false

    -- Set up a pending POI route
    QR.UI._pendingPOIRoute = {
        waypoint = { mapID = 84, x = 0.5, y = 0.5, title = "Stormwind City" },
        waypointSource = "map_click",
        totalTime = 42,
        steps = {{ action = "Test step", time = 42, type = "walk" }},
    }
    QR.UI.isCalculating = false

    QR.UI:RefreshRoute()

    -- destinationLocked should be set
    t:assertTrue(QR.db.destinationLocked, "destinationLocked set after consuming _pendingPOIRoute")

    -- Clean up
    QR.db.destinationLocked = false
end)

T:run("RefreshRoute clears route when no waypoint AND no saved destination", function(t)
    resetState()
    ensureUIFrame()

    -- No active waypoint, no saved destination
    _G.C_Map.HasUserWaypoint = function() return false end
    _G.C_Map.GetUserWaypoint = function() return nil end
    QR.db.lastDestination = nil

    QR.MainFrame:Show("route")
    QR.UI.isCalculating = false
    QR.UI:RefreshRoute()

    -- Should show hint text
    local timeText = QR.UI.frame.timeLabel:GetText()
    t:assertTrue(timeText:find(QR.L["SET_WAYPOINT_HINT"]) ~= nil,
        "Shows hint when no waypoint and no saved destination")
end)

-------------------------------------------------------------------------------
-- 14. BuildStepCardTexts
-------------------------------------------------------------------------------

T:run("BuildStepCardTexts returns action and destination for teleport", function(t)
    resetState()
    ensureUIFrame()

    local step = {
        type = "teleport",
        teleportID = 6948,
        sourceType = "item",
        action = "Use Hearthstone to teleport to Stormwind",
        to = "Stormwind",
        localizedTo = "Sturmwind",
        time = 180,
        navMapID = 84,  -- Stormwind City
        navX = 0.452,
        navY = 0.631,
        destX = 0.452,
        destY = 0.631,
    }

    local actionLine, destLine = QR.UI:BuildStepCardTexts(step)
    t:assertNotNil(actionLine, "action line not nil")
    t:assertNotNil(destLine, "dest line not nil")
    -- Action line should contain destination name (via _TO format)
    t:assertTrue(actionLine:find("Sturmwind") ~= nil, "action line contains localized destination")
    -- Detail line should contain zone name, continent, and coordinates
    t:assertTrue(destLine:find("Stormwind City") ~= nil, "dest line contains zone name")
    t:assertTrue(destLine:find("Eastern Kingdoms") ~= nil, "dest line contains continent name")
    t:assertTrue(destLine:find("45.2") ~= nil, "dest line contains X coordinate")
    t:assertTrue(destLine:find("63.1") ~= nil, "dest line contains Y coordinate")
end)

T:run("BuildStepCardTexts returns action and destination for walk", function(t)
    resetState()
    ensureUIFrame()

    local step = {
        type = "walk",
        action = "Go to Goldshire",
        to = "Goldshire",
        localizedTo = "Goldhain",
        time = 60,
        navMapID = 37,  -- Elwynn Forest
        navX = 0.423,
        navY = 0.658,
        destX = 0.423,
        destY = 0.658,
    }

    local actionLine, destLine = QR.UI:BuildStepCardTexts(step)
    t:assertNotNil(actionLine, "action line not nil")
    t:assertNotNil(destLine, "dest line not nil")
    -- Action should include destination (new _TO format)
    local expected = string.format(QR.L["ACTION_TRAVEL_TO"], "Goldhain")
    t:assertEqual(expected, actionLine, "walk step uses ACTION_TRAVEL_TO with destination")
    -- Detail line should contain zone, continent, and coordinates
    t:assertTrue(destLine:find("Elwynn Forest") ~= nil, "dest line contains zone name")
    t:assertTrue(destLine:find("Eastern Kingdoms") ~= nil, "dest line contains continent name")
    t:assertTrue(destLine:find("42.3") ~= nil, "dest line contains X coordinate")
end)

T:run("BuildStepCardTexts shows cooldown for teleport steps", function(t)
    resetState()
    ensureUIFrame()

    -- Mock cooldown tracker with active cooldown
    local origGetCooldown = QR.CooldownTracker.GetCooldown
    QR.CooldownTracker.GetCooldown = function(self, id, sourceType)
        return { remaining = 120 }
    end

    local step = {
        type = "teleport",
        teleportID = 6948,
        sourceType = "item",
        action = "Use Hearthstone",
        to = "Stormwind",
        localizedTo = "Stormwind",
    }

    local actionLine, destLine = QR.UI:BuildStepCardTexts(step)
    t:assertTrue(actionLine:find(QR.L["COOLDOWN_SHORT"]) ~= nil,
        "action line contains cooldown indicator")

    QR.CooldownTracker.GetCooldown = origGetCooldown
end)

T:run("BuildStepCardTexts handles all step types", function(t)
    resetState()
    ensureUIFrame()

    local types = {
        { type = "portal", expected = string.format(QR.L["ACTION_PORTAL_TO"], "TestDest") },
        { type = "boat", expected = string.format(QR.L["ACTION_BOAT_TO"], "TestDest") },
        { type = "zeppelin", expected = string.format(QR.L["ACTION_ZEPPELIN_TO"], "TestDest") },
        { type = "tram", expected = string.format(QR.L["ACTION_TRAM_TO"], "TestDest") },
        { type = "flight", expected = string.format(QR.L["ACTION_FLY_TO"], "TestDest") },
    }

    for _, tc in ipairs(types) do
        local step = {
            type = tc.type,
            action = "Action",
            to = "TestDest",
            localizedTo = "TestDest",
        }
        local actionLine = QR.UI:BuildStepCardTexts(step)
        t:assertEqual(tc.expected, actionLine,
            tc.type .. " step uses correct action label with destination")
    end
end)

T:run("BuildStepCardTexts handles teleport without teleportID", function(t)
    resetState()
    ensureUIFrame()

    local step = {
        type = "teleport",
        -- no teleportID
        action = "Teleport to Stormwind",
        to = "Stormwind",
        localizedTo = "Sturmwind",
    }

    local actionLine = QR.UI:BuildStepCardTexts(step)
    local expected = string.format(QR.L["ACTION_TELEPORT_TO"], "Sturmwind")
    t:assertEqual(expected, actionLine,
        "teleport without teleportID uses ACTION_TELEPORT_TO")
end)

T:run("BuildStepCardTexts detail line shows nav zone for portals", function(t)
    resetState()
    ensureUIFrame()

    -- Portal to Ironforge: the portal entrance is in Stormwind (navMapID=84),
    -- but the destination is Ironforge (destMapID=87)
    local step = {
        type = "portal",
        action = "Take portal",
        to = "Ironforge",
        localizedTo = "Ironforge",
        navMapID = 84,   -- Stormwind City (portal entrance)
        navX = 0.49,
        navY = 0.87,
        destMapID = 87,  -- Ironforge (destination)
        destX = 0.50,
        destY = 0.50,
        time = 5,
    }

    local _, destLine = QR.UI:BuildStepCardTexts(step)
    -- Detail line should show nav location (Stormwind), not destination (Ironforge)
    t:assertTrue(destLine:find("Stormwind City") ~= nil,
        "portal detail line shows source zone (where portal entrance is)")
    -- Coordinates should be nav coords (49.0, 87.0), not dest coords
    t:assertTrue(destLine:find("49.0") ~= nil, "portal detail uses nav X coordinate")
    t:assertTrue(destLine:find("87.0") ~= nil, "portal detail uses nav Y coordinate")
end)

T:run("BuildStepCardTexts falls back to step.to when localizedTo missing", function(t)
    resetState()
    ensureUIFrame()

    local step = {
        type = "walk",
        action = "Go to TestZone",
        to = "TestZone",
        -- no localizedTo
    }

    local actionLine = QR.UI:BuildStepCardTexts(step)
    -- Should fall back to step.to in the action line
    t:assertTrue(actionLine:find("TestZone") ~= nil,
        "falls back to step.to when localizedTo is nil")
end)

-------------------------------------------------------------------------------
-- /qrscreenshot command tests
-------------------------------------------------------------------------------

T:run("/qrscreenshot registers slash command", function(t)
    t:assertNotNil(SlashCmdList["QRSCREENSHOT"], "QRSCREENSHOT handler exists")
    t:assertEqual(SLASH_QRSCREENSHOT1, "/qrscreenshot", "slash alias registered")
end)

T:run("/qrscreenshot (no args) takes screenshot", function(t)
    resetState()
    ensureUIFrame()
    MockWoW.config.screenshotsTaken = 0

    SlashCmdList["QRSCREENSHOT"]("")

    -- C_Timer.After executes immediately in mock
    t:assertTrue(MockWoW.config.screenshotsTaken > 0,
        "Screenshot() was called")
end)

T:run("/qrscreenshot route opens route tab and takes screenshot", function(t)
    resetState()
    ensureUIFrame()
    MockWoW.config.screenshotsTaken = 0

    SlashCmdList["QRSCREENSHOT"]("route")

    t:assertTrue(QR.MainFrame.isShowing, "MainFrame is showing")
    t:assertEqual(QR.MainFrame.activeTab, "route", "route tab active")
    t:assertTrue(MockWoW.config.screenshotsTaken > 0,
        "Screenshot() was called")
end)

T:run("/qrscreenshot teleport opens teleport tab", function(t)
    resetState()
    ensureUIFrame()

    SlashCmdList["QRSCREENSHOT"]("teleport")

    t:assertTrue(QR.MainFrame.isShowing, "MainFrame is showing")
    t:assertEqual(QR.MainFrame.activeTab, "teleports", "teleports tab active")
end)

T:run("/qrscreenshot blocked in combat", function(t)
    resetState()
    ensureUIFrame()
    MockWoW.config.inCombatLockdown = true
    MockWoW.config.screenshotsTaken = 0

    SlashCmdList["QRSCREENSHOT"]("route")

    t:assertEqual(0, MockWoW.config.screenshotsTaken or 0,
        "Screenshot() not called during combat")
    MockWoW.config.inCombatLockdown = false
end)

T:run("/qrscreenshot all cycles through panels", function(t)
    resetState()
    ensureUIFrame()
    MockWoW.config.screenshotsTaken = 0

    SlashCmdList["QRSCREENSHOT"]("all")

    -- C_Timer.After executes immediately in mock, so all 4 panels fire
    t:assertTrue(MockWoW.config.screenshotsTaken >= 4,
        "Screenshot() called for each panel")
end)

-------------------------------------------------------------------------------
-- A route rendered during combat has no Use buttons
-------------------------------------------------------------------------------

-- Regression: ConfigureStepUseButton refuses to take a secure button under
-- lockdown, so a route rendered during a fight -- the window opened with /qr
-- mid-combat, or the waypoint changed while it was open -- gets none. Nothing
-- rebuilt it afterwards: MainFrame only restores a window that combat itself
-- hid, and UI:OnCombatEnd restored alpha on a list nothing ever fills. The
-- buttons stayed missing until the player toggled the window by hand.
T:run("UI: a route rendered in combat gets its Use buttons back afterwards", function(t)
    resetState()
    ensureUIFrame()
    QR.SecureButtons:Initialize()
    for _, btn in ipairs(QR.SecureButtons.pool or {}) do
        btn.inUse = false
    end

    -- A teleport step needs an owned teleport and a destination it serves.
    MockWoW.config.ownedToys[140192] = true  -- Dalaran Hearthstone
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 84         -- Stormwind
    setMapPinWaypoint(627, 0.5, 0.5)         -- Dalaran (Broken Isles)

    QR.MainFrame.isShowing = true
    QR.MainFrame.activeTab = "route"

    local function stepsWithButtons()
        local n = 0
        for _, stepFrame in ipairs(QR.UI.stepLabels or {}) do
            if stepFrame.useButton then n = n + 1 end
        end
        return n
    end

    MockWoW.config.inCombatLockdown = true
    QR.UI:RefreshRoute()
    local rendered = #(QR.UI.stepLabels or {})
    t:assertGreaterThan(rendered, 0, "the route rendered its steps in combat")
    -- Precondition, not a guard: three layers enforce this independently
    -- (ConfigureStepUseButton, GetButton and ConfigureButton), so neutralising
    -- any one of them leaves it green. It establishes the starting state the
    -- assertion below measures against; the regression is caught there.
    t:assertEqual(0, stepsWithButtons(),
        "no step got a secure button under lockdown (got: "
            .. tostring(stepsWithButtons()) .. ")")

    MockWoW.config.inCombatLockdown = false
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    t:assertNotNil(handler, "the combat manager is reachable")
    if not handler then return end
    handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")

    t:assertGreaterThan(stepsWithButtons(), 0,
        "the route is re-rendered with its Use buttons once combat ends "
            .. "(steps with a button: " .. tostring(stepsWithButtons()) .. ")")

    QR.MainFrame.isShowing = false
    QR.UI:ClearStepLabels()
end)

-- Regression: the fix above first refreshed unconditionally. MainFrame's
-- leave-combat callback is registered before UI's and already rebuilds a window
-- that combat hid, so the common case -- window open, fight starts, fight ends
-- -- ran pathfinding twice and released and re-acquired every secure button in
-- the same frame.
T:run("UI: combat exit re-renders the route once, not twice", function(t)
    resetState()
    ensureUIFrame()
    QR.SecureButtons:Initialize()
    MockWoW.config.ownedToys[140192] = true
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(627, 0.5, 0.5)

    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    t:assertNotNil(handler, "the combat manager is reachable")
    if not handler then return end

    -- Open before the fight, let combat hide it: this is the path where
    -- MainFrame restores the window itself.
    MockWoW.config.inCombatLockdown = false
    QR.MainFrame:Show("route")
    MockWoW.config.inCombatLockdown = true
    handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
    t:assertTrue(QR.MainFrame.wasShowingBeforeCombat,
        "combat hid the window, so MainFrame will restore it")

    local original = QR.UI.RefreshRoute
    local calls = 0
    QR.UI.RefreshRoute = function(self, ...)
        calls = calls + 1
        return original(self, ...)
    end

    MockWoW.config.inCombatLockdown = false
    handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")

    QR.UI.RefreshRoute = original

    t:assertEqual(1, calls,
        "the route is rendered exactly once on combat exit (rendered "
            .. tostring(calls) .. " times)")

    QR.MainFrame:Hide()
end)

-------------------------------------------------------------------------------
-- Item info that is not cached yet
-------------------------------------------------------------------------------

-- The mock grew an `uncachedItems` flag alongside `uncachedSpells` so the
-- "item info is not available immediately" branch could be exercised, but
-- nothing ever set it: the branch never ran, and the flag was decoration.
-- Right after login is exactly when that branch is live.
T:run("GetLocalizedItemInfo: an item that is not cached yet returns nil, uncached", function(t)
    resetState()
    local itemID = 6948  -- Hearthstone
    MockWoW.config.uncachedItems[itemID] = true
    QR.UI.itemInfoCache = {}
    QR.UI.itemInfoAccessOrder = {}

    local name, link = QR.UI:GetLocalizedItemInfo(itemID)
    t:assertNil(name, "no name while the client has not cached the item")
    t:assertNil(link, "and no link either")
    t:assertNil(QR.UI.itemInfoCache[itemID],
        "and the miss is not cached, so a later call can still succeed")

    -- The client answers on a later frame; the same call must now work.
    MockWoW.config.uncachedItems[itemID] = nil
    local name2 = QR.UI:GetLocalizedItemInfo(itemID)
    t:assertNotNil(name2, "the second call gets the name once the client has it")
    t:assertNotNil(QR.UI.itemInfoCache[itemID], "and that one is cached")
end)

-------------------------------------------------------------------------------
-- Teleport steps rendered during combat are dimmed, not silently button-less
-------------------------------------------------------------------------------

-- Regression: UI.combatDisabledButtons was wiped in three places and iterated in
-- one, and nothing ever inserted into it. The dimming it was named for did not
-- exist, so a teleport step rendered under lockdown looked exactly like a step
-- whose teleport is unavailable -- same text, no Use button, no signal which of
-- the two it was.
T:run("UI: a teleport step rendered in combat is dimmed", function(t)
    resetState()
    ensureUIFrame()
    QR.SecureButtons:Initialize()
    MockWoW.config.ownedToys[140192] = true
    QR.PlayerInventory:ScanAll()
    MockWoW.config.currentMapID = 84
    setMapPinWaypoint(627, 0.5, 0.5)
    QR.MainFrame.isShowing = true
    QR.MainFrame.activeTab = "route"

    MockWoW.config.inCombatLockdown = true
    QR.UI:RefreshRoute()

    local teleportSteps, dimmed = 0, 0
    for _, stepFrame in ipairs(QR.UI.stepLabels or {}) do
        if stepFrame.teleportID then
            teleportSteps = teleportSteps + 1
            if stepFrame:GetAlpha() < 1.0 then dimmed = dimmed + 1 end
        end
    end
    t:assertGreaterThan(teleportSteps, 0, "the route has a teleport step")
    t:assertEqual(teleportSteps, dimmed,
        "every teleport step is dimmed while combat blocks its button ("
            .. tostring(dimmed) .. " of " .. tostring(teleportSteps) .. ")")
    t:assertGreaterThan(#QR.UI.combatDimmedSteps, 0,
        "and each one is recorded so it can be undimmed")

    MockWoW.config.inCombatLockdown = false
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    t:assertNotNil(handler, "the combat manager is reachable")
    if not handler then return end
    handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")

    local stillDim = 0
    for _, stepFrame in ipairs(QR.UI.stepLabels or {}) do
        if stepFrame:GetAlpha() < 1.0 then stillDim = stillDim + 1 end
    end
    t:assertEqual(0, stillDim,
        "and nothing stays dim once combat ends (still dim: " .. tostring(stillDim) .. ")")

    QR.MainFrame.isShowing = false
end)

-- A dimmed frame goes back into the pool like any other. Without resetting its
-- alpha it comes back dim on a route rendered out of combat, which is the same
-- wrong signal in the opposite direction.
T:run("UI: a step frame does not come back from the pool dimmed", function(t)
    resetState()
    ensureUIFrame()

    local frame = QR.UI:GetStepLabelFrame()
    QR.UI:MarkStepCombatDimmed(frame)
    t:assert(frame:GetAlpha() < 1.0, "the frame is dimmed")

    QR.UI:ReleaseStepLabelFrame(frame)
    local reused = QR.UI:GetStepLabelFrame()
    t:assertEqual(frame, reused, "the pool handed back the same frame")
    t:assertEqual(1.0, reused:GetAlpha(),
        "at full alpha (got: " .. tostring(reused:GetAlpha()) .. ")")
    QR.UI:ReleaseStepLabelFrame(reused)
end)

-------------------------------------------------------------------------------
-- /qrverifymap
-------------------------------------------------------------------------------

-- Two open questions cannot be settled from the repository: which map Zen
-- Pilgrimage actually lands on (#5), and whether the Darnassus and Undercity
-- services still exist (#3). Both need a character standing in the place. This
-- command is what they stand there and run: it prints what the client says
-- about the map, what the addon believes about it, and everything in the data
-- that points at it, so the answer comes back in one paste instead of a round
-- trip per question.
T:run("GenerateMapVerification: reports the client's view of the current map", function(t)
    resetState()
    MockWoW.config.currentMapID = 84

    local report = QR.UI:GenerateMapVerification()
    t:assertNotNil(report, "a report is produced")
    if not report then return end
    t:assert(report:find("map 84", 1, true) ~= nil,
        "it names the map the client reports")
    t:assert(report:find("Stormwind City", 1, true) ~= nil,
        "and the name the client gives it")
    t:assert(report:find("client", 1, true) ~= nil, "the client's chain is labelled")
    t:assert(report:find("addon", 1, true) ~= nil, "and the addon's belief separately")
end)

T:run("GenerateMapVerification: lists what the addon points at that map", function(t)
    resetState()
    -- 2393 is the revamped Silvermoon, which several teleports target.
    local report = QR.UI:GenerateMapVerification(2393)
    t:assertNotNil(report, "a report is produced")
    if not report then return end
    t:assert(report:find("Silvermoon", 1, true) ~= nil,
        "it names the destination the data claims (got: " .. tostring(report:sub(1, 200)) .. ")")
end)

T:run("GenerateMapVerification: says so when nothing points at a map", function(t)
    resetState()
    local report = QR.UI:GenerateMapVerification(99999)
    t:assertNotNil(report, "a report is produced for an unknown map")
    if not report then return end
    t:assert(report:find("Nothing in the addon's data", 1, true) ~= nil,
        "and says nothing points at it rather than printing an empty list")
end)

T:run("/qrverifymap is registered", function(t)
    t:assertEqual("/qrverifymap", _G.SLASH_QRVERIFYMAP1, "the command exists")
    t:assertNotNil(SlashCmdList and SlashCmdList["QRVERIFYMAP"], "and has a handler")
end)
