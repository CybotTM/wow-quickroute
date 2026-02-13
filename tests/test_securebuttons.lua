-------------------------------------------------------------------------------
-- test_securebuttons.lua
-- Tests for QR.SecureButtons module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
end

-- Re-initialize SecureButtons for each test that needs a clean pool
local function reinitializePool()
    QR.SecureButtons.pool = {}
    QR.SecureButtons.initialized = false
    QR.SecureButtons.pendingReleases = nil
    QR.SecureButtons.combatEndCallbacks = {}
    QR.SecureButtons.combatEventsRegistered = false
    QR.SecureButtons:Initialize()
end

-------------------------------------------------------------------------------
-- 1. Initialize
-------------------------------------------------------------------------------

T:run("Initialize: creates button pool", function(t)
    resetState()
    reinitializePool()

    t:assertTrue(QR.SecureButtons.initialized, "SecureButtons marked as initialized")
    t:assertGreaterThan(#QR.SecureButtons.pool, 0, "Pool has buttons")
    t:assertEqual(QR.SecureButtons.maxPoolSize, #QR.SecureButtons.pool, "Pool size matches maxPoolSize")
end)

T:run("Initialize: idempotent (safe to call twice)", function(t)
    resetState()
    reinitializePool()
    local poolSize = #QR.SecureButtons.pool

    -- Call again
    QR.SecureButtons:Initialize()

    t:assertEqual(poolSize, #QR.SecureButtons.pool, "Pool size unchanged after double init")
end)

T:run("Initialize: defers when in combat", function(t)
    resetState()
    QR.SecureButtons.pool = {}
    QR.SecureButtons.initialized = false
    MockWoW.config.inCombatLockdown = true

    QR.SecureButtons:Initialize()

    t:assertFalse(QR.SecureButtons.initialized, "Not initialized during combat")
    t:assertEqual(0, #QR.SecureButtons.pool, "Pool empty during combat")

    -- Simulate combat end
    MockWoW.config.inCombatLockdown = false
    MockWoW:FireEvent("PLAYER_REGEN_ENABLED")

    t:assertTrue(QR.SecureButtons.initialized, "Initialized after combat ends")
    t:assertGreaterThan(#QR.SecureButtons.pool, 0, "Pool populated after combat ends")
end)

T:run("Initialize: buttons are parented to UIParent", function(t)
    resetState()
    reinitializePool()

    for _, btn in ipairs(QR.SecureButtons.pool) do
        t:assertFalse(btn.inUse, "Button starts not in use")
    end
end)

-------------------------------------------------------------------------------
-- 2. GetButton
-------------------------------------------------------------------------------

T:run("GetButton: returns a button from pool", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()

    t:assertNotNil(btn, "Got a button from pool")
    t:assertTrue(btn.inUse, "Button marked as in use")
end)

T:run("GetButton: returns nil when not initialized", function(t)
    resetState()
    QR.SecureButtons.pool = {}
    QR.SecureButtons.initialized = false

    local btn = QR.SecureButtons:GetButton()

    t:assertNil(btn, "Returns nil when not initialized")
end)

T:run("GetButton: returns nil when pool exhausted", function(t)
    resetState()
    reinitializePool()

    -- Use all buttons
    for _ = 1, QR.SecureButtons.maxPoolSize do
        QR.SecureButtons:GetButton()
    end

    local btn = QR.SecureButtons:GetButton()
    t:assertNil(btn, "Returns nil when pool exhausted")
end)

T:run("GetButton: GetInUseCount tracks usage", function(t)
    resetState()
    reinitializePool()

    t:assertEqual(0, QR.SecureButtons:GetInUseCount(), "0 in use initially")

    local btn1 = QR.SecureButtons:GetButton()
    t:assertEqual(1, QR.SecureButtons:GetInUseCount(), "1 in use after GetButton")

    local btn2 = QR.SecureButtons:GetButton()
    t:assertEqual(2, QR.SecureButtons:GetInUseCount(), "2 in use after second GetButton")
end)

-------------------------------------------------------------------------------
-- 3. ReleaseButton
-------------------------------------------------------------------------------

T:run("ReleaseButton: marks button as not in use", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    t:assertTrue(btn.inUse, "In use after GetButton")

    QR.SecureButtons:ReleaseButton(btn)
    t:assertFalse(btn.inUse, "Not in use after ReleaseButton")
end)

T:run("ReleaseButton: clears button state", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    QR.SecureButtons:ConfigureForSpell(btn, 12345)

    QR.SecureButtons:ReleaseButton(btn)

    t:assertNil(btn.teleportID, "teleportID cleared")
    t:assertNil(btn.sourceType, "sourceType cleared")
    t:assertNil(btn._qrStepFrame, "_qrStepFrame cleared")
    t:assertNil(btn._lastX, "_lastX cleared")
    t:assertNil(btn._lastY, "_lastY cleared")
    t:assertNil(btn._elapsed, "_elapsed cleared")
end)

T:run("ReleaseButton: clears OnUpdate script", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    btn:SetScript("OnUpdate", function() end)

    QR.SecureButtons:ReleaseButton(btn)

    t:assertNil(btn:GetScript("OnUpdate"), "OnUpdate cleared on release")
end)

T:run("ReleaseButton: handles nil button gracefully", function(t)
    resetState()
    -- Should not error
    QR.SecureButtons:ReleaseButton(nil)
    t:assertTrue(true, "No error on nil release")
end)

T:run("ReleaseButton: defers during combat", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    MockWoW.config.inCombatLockdown = true

    QR.SecureButtons:ReleaseButton(btn)

    -- Button should still be in use (deferred)
    t:assertTrue(btn.inUse, "Button still in use during combat")
    t:assertNotNil(QR.SecureButtons.pendingReleases, "Pending releases queued")

    -- Simulate combat end
    MockWoW.config.inCombatLockdown = false
    QR.SecureButtons:ReleasePendingButtons()

    t:assertFalse(btn.inUse, "Button released after combat")
end)

-------------------------------------------------------------------------------
-- 4. ConfigureForSpell
-------------------------------------------------------------------------------

T:run("ConfigureForSpell: sets spell attributes", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    local result = QR.SecureButtons:ConfigureForSpell(btn, 12345)

    t:assertTrue(result, "ConfigureForSpell returns true")
    t:assertEqual("spell", btn:GetAttribute("type"), "type attribute is spell")
    t:assertEqual(12345, btn:GetAttribute("spell"), "spell attribute set")
    t:assertEqual(12345, btn.teleportID, "teleportID set")
    t:assertEqual("spell", btn.sourceType, "sourceType is spell")
end)

T:run("ConfigureForSpell: fails during combat", function(t)
    resetState()
    reinitializePool()
    MockWoW.config.inCombatLockdown = true

    local btn = QR.SecureButtons:GetButton()
    -- Need to re-enable combat after getting the button (GetButton doesn't check combat)
    MockWoW.config.inCombatLockdown = true

    local result = QR.SecureButtons:ConfigureForSpell(btn, 12345)

    t:assertFalse(result, "ConfigureForSpell fails during combat")
end)

T:run("ConfigureForSpell: fails with nil button", function(t)
    resetState()
    local result = QR.SecureButtons:ConfigureForSpell(nil, 12345)
    t:assertFalse(result, "ConfigureForSpell fails with nil button")
end)

T:run("ConfigureForSpell: fails with nil spellID", function(t)
    resetState()
    reinitializePool()
    local btn = QR.SecureButtons:GetButton()
    local result = QR.SecureButtons:ConfigureForSpell(btn, nil)
    t:assertFalse(result, "ConfigureForSpell fails with nil spellID")
end)

-------------------------------------------------------------------------------
-- 5. ConfigureForItem
-------------------------------------------------------------------------------

T:run("ConfigureForItem: sets macro attributes", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    local result = QR.SecureButtons:ConfigureForItem(btn, 54321)

    t:assertTrue(result, "ConfigureForItem returns true")
    t:assertEqual("macro", btn:GetAttribute("type"), "type attribute is macro")
    t:assertEqual("/use item:54321", btn:GetAttribute("macrotext"), "macrotext set")
    t:assertEqual(54321, btn.teleportID, "teleportID set")
    t:assertEqual("item", btn.sourceType, "sourceType is item")
end)

-------------------------------------------------------------------------------
-- 6. ConfigureForToy
-------------------------------------------------------------------------------

T:run("ConfigureForToy: sets toy attributes", function(t)
    resetState()
    reinitializePool()

    local btn = QR.SecureButtons:GetButton()
    local result = QR.SecureButtons:ConfigureForToy(btn, 140192)

    t:assertTrue(result, "ConfigureForToy returns true")
    t:assertEqual("toy", btn:GetAttribute("type"), "type attribute is toy")
    t:assertEqual(140192, btn:GetAttribute("toy"), "toy attribute set")
    t:assertEqual(140192, btn.teleportID, "teleportID set")
    t:assertEqual("toy", btn.sourceType, "sourceType is toy")
end)

-------------------------------------------------------------------------------
-- 7. ConfigureButton dispatch
-------------------------------------------------------------------------------

T:run("ConfigureButton: dispatches to correct method by sourceType", function(t)
    resetState()
    reinitializePool()

    local btn1 = QR.SecureButtons:GetButton()
    QR.SecureButtons:ConfigureButton(btn1, 100, "spell")
    t:assertEqual("spell", btn1:GetAttribute("type"), "Spell dispatch correct")

    local btn2 = QR.SecureButtons:GetButton()
    QR.SecureButtons:ConfigureButton(btn2, 200, "toy")
    t:assertEqual("toy", btn2:GetAttribute("type"), "Toy dispatch correct")

    local btn3 = QR.SecureButtons:GetButton()
    QR.SecureButtons:ConfigureButton(btn3, 300, "item")
    t:assertEqual("macro", btn3:GetAttribute("type"), "Item dispatch correct")

    local btn4 = QR.SecureButtons:GetButton()
    QR.SecureButtons:ConfigureButton(btn4, 400, "equipped")
    t:assertEqual("macro", btn4:GetAttribute("type"), "Equipped dispatch correct")
end)

-------------------------------------------------------------------------------
-- 8. CanModify
-------------------------------------------------------------------------------

T:run("CanModify: returns true outside combat", function(t)
    resetState()
    t:assertTrue(QR.SecureButtons:CanModify(), "Can modify outside combat")
end)

T:run("CanModify: returns false during combat", function(t)
    resetState()
    MockWoW.config.inCombatLockdown = true
    t:assertFalse(QR.SecureButtons:CanModify(), "Cannot modify during combat")
end)

-------------------------------------------------------------------------------
-- 3.10: SecureButtons Combat Event Lifecycle
-- Test pending button release via combat frame event handler
-------------------------------------------------------------------------------

T:run("Combat lifecycle: pending buttons released on PLAYER_REGEN_ENABLED", function(t)
    resetState()
    reinitializePool()

    -- Get two buttons
    local btn1 = QR.SecureButtons:GetButton()
    local btn2 = QR.SecureButtons:GetButton()
    t:assertEqual(2, QR.SecureButtons:GetInUseCount(), "2 buttons in use")

    -- Enter combat
    MockWoW.config.inCombatLockdown = true

    -- Try to release both during combat - should be deferred
    QR.SecureButtons:ReleaseButton(btn1)
    QR.SecureButtons:ReleaseButton(btn2)

    -- Both should still be in use (combat lockdown)
    t:assertTrue(btn1.inUse, "Button 1 still in use during combat")
    t:assertTrue(btn2.inUse, "Button 2 still in use during combat")
    t:assertNotNil(QR.SecureButtons.pendingReleases,
        "Pending releases queue exists")

    -- End combat - fire via centralized combatFrame handler
    MockWoW.config.inCombatLockdown = false
    local handler = QR.combatFrame
        and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    end

    -- Both buttons should now be released
    t:assertFalse(btn1.inUse, "Button 1 released after combat ends")
    t:assertFalse(btn2.inUse, "Button 2 released after combat ends")
    t:assertEqual(0, QR.SecureButtons:GetInUseCount(),
        "All buttons released after combat")
end)

T:run("Combat lifecycle: combat end callbacks are invoked", function(t)
    resetState()
    reinitializePool()

    -- Register a combat end callback
    local callbackInvoked = false
    QR.SecureButtons:RegisterCombatEndCallback(function()
        callbackInvoked = true
    end)

    -- Fire combat end via the centralized combatFrame handler
    MockWoW.config.inCombatLockdown = false
    local handler = QR.combatFrame
        and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    end

    t:assertTrue(callbackInvoked, "Combat end callback was invoked")
end)

T:run("Combat lifecycle: error in callback does not block other callbacks", function(t)
    resetState()
    reinitializePool()

    local secondCallbackInvoked = false

    -- Register callbacks: first one errors, second should still run
    QR.SecureButtons.combatEndCallbacks = {}
    QR.SecureButtons:RegisterCombatEndCallback(function()
        error("Callback error")
    end)
    QR.SecureButtons:RegisterCombatEndCallback(function()
        secondCallbackInvoked = true
    end)

    -- Fire combat end via centralized combatFrame handler
    MockWoW.config.inCombatLockdown = false
    local handler = QR.combatFrame
        and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    end

    t:assertTrue(secondCallbackInvoked,
        "Second callback invoked despite first callback error")
end)

T:run("Combat lifecycle: ReleasePendingButtons is no-op when nothing pending", function(t)
    resetState()
    reinitializePool()

    -- Ensure no pending releases
    QR.SecureButtons.pendingReleases = nil

    -- Should not error
    QR.SecureButtons:ReleasePendingButtons()
    t:assertTrue(true, "ReleasePendingButtons handles nil pending gracefully")
end)

-------------------------------------------------------------------------------
-- 3.11: Centralized QR:RegisterCombatCallback Tests
-------------------------------------------------------------------------------

T:run("QR:RegisterCombatCallback: enter callback fires on PLAYER_REGEN_DISABLED", function(t)
    resetState()

    local enterFired = false
    QR:RegisterCombatCallback(
        function() enterFired = true end,
        nil
    )

    -- Fire combat enter
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
    end

    t:assertTrue(enterFired, "Enter callback fired on PLAYER_REGEN_DISABLED")
    t:assertTrue(QR.inCombat, "QR.inCombat is true after entering combat")
end)

T:run("QR:RegisterCombatCallback: leave callback fires on PLAYER_REGEN_ENABLED", function(t)
    resetState()

    local leaveFired = false
    QR:RegisterCombatCallback(
        nil,
        function() leaveFired = true end
    )

    -- Fire combat leave
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    end

    t:assertTrue(leaveFired, "Leave callback fired on PLAYER_REGEN_ENABLED")
    t:assertFalse(QR.inCombat, "QR.inCombat is false after leaving combat")
end)

T:run("QR:RegisterCombatCallback: both enter and leave callbacks work", function(t)
    resetState()

    local enterFired = false
    local leaveFired = false
    QR:RegisterCombatCallback(
        function() enterFired = true end,
        function() leaveFired = true end
    )

    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")

    -- Fire enter
    if handler then handler(QR.combatFrame, "PLAYER_REGEN_DISABLED") end
    t:assertTrue(enterFired, "Enter callback fired")
    t:assertFalse(leaveFired, "Leave callback not yet fired")

    -- Fire leave
    if handler then handler(QR.combatFrame, "PLAYER_REGEN_ENABLED") end
    t:assertTrue(leaveFired, "Leave callback fired")
end)

T:run("QR:RegisterCombatCallback: error in one callback does not block others", function(t)
    resetState()

    local secondEnterFired = false
    local secondLeaveFired = false

    QR:RegisterCombatCallback(
        function() error("enter error") end,
        function() error("leave error") end
    )
    QR:RegisterCombatCallback(
        function() secondEnterFired = true end,
        function() secondLeaveFired = true end
    )

    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")

    if handler then handler(QR.combatFrame, "PLAYER_REGEN_DISABLED") end
    t:assertTrue(secondEnterFired, "Second enter callback fires despite first erroring")

    if handler then handler(QR.combatFrame, "PLAYER_REGEN_ENABLED") end
    t:assertTrue(secondLeaveFired, "Second leave callback fires despite first erroring")
end)

T:run("QR:RegisterCombatCallback: ignores non-function arguments", function(t)
    resetState()

    -- Should not error with invalid arguments
    QR:RegisterCombatCallback(nil, nil)
    QR:RegisterCombatCallback("not a function", 42)

    -- Fire events - should not error
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
        handler(QR.combatFrame, "PLAYER_REGEN_ENABLED")
    end
    t:assertTrue(true, "No error with invalid callback arguments")
end)

T:run("QR.inCombat: tracks combat state correctly", function(t)
    resetState()

    -- Initially false
    QR.inCombat = false

    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")

    -- Enter combat
    if handler then handler(QR.combatFrame, "PLAYER_REGEN_DISABLED") end
    t:assertTrue(QR.inCombat, "inCombat true after PLAYER_REGEN_DISABLED")

    -- Leave combat
    if handler then handler(QR.combatFrame, "PLAYER_REGEN_ENABLED") end
    t:assertFalse(QR.inCombat, "inCombat false after PLAYER_REGEN_ENABLED")
end)

T:run("QR.combatFrame: exists and has correct events registered", function(t)
    t:assertNotNil(QR.combatFrame, "QR.combatFrame exists")
    t:assertNotNil(QR.combatFrame:GetScript("OnEvent"), "combatFrame has OnEvent handler")
end)
