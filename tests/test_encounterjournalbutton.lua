-------------------------------------------------------------------------------
-- test_encounterjournalbutton.lua
-- Tests for EncounterJournalButton: QR button on the Encounter Journal frame
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}
    MockWoW.config.tooltipHideCalls = 0

    -- Reset EJB state
    local EJB = QR.EncounterJournalButton
    EJB.button = nil
    EJB.initialized = false
    EJB.hookedEJ = false

    -- Ensure EncounterJournal mock exists
    if not _G.EncounterJournal then
        _G.EncounterJournal = CreateFrame("Frame", "EncounterJournal")
    end
    _G.EncounterJournal.instanceID = nil
    _G.EncounterJournal._shown = false

    -- Ensure EncounterJournal_DisplayInstance exists
    _G.EncounterJournal_DisplayInstance = function(instanceID)
        _G.EncounterJournal.instanceID = instanceID
    end

    -- Re-initialize DungeonData so we have instance data
    local DD = QR.DungeonData
    DD.instances = {}
    DD.byZone = {}
    DD.byTier = {}
    DD.tierNames = {}
    DD.numTiers = 0
    DD.scanned = false
    DD.entrancesScanned = false
    DD:Initialize()
end

-------------------------------------------------------------------------------
-- 1. Module Structure
-------------------------------------------------------------------------------

T:run("EJButton: module exists", function(t)
    t:assertNotNil(QR.EncounterJournalButton, "QR.EncounterJournalButton exists")
end)

T:run("EJButton: has expected methods", function(t)
    local EJB = QR.EncounterJournalButton
    t:assertNotNil(EJB.CreateButton, "CreateButton exists")
    t:assertNotNil(EJB.RouteToCurrentInstance, "RouteToCurrentInstance exists")
    t:assertNotNil(EJB.UpdateButton, "UpdateButton exists")
    t:assertNotNil(EJB.HookEncounterJournal, "HookEncounterJournal exists")
    t:assertNotNil(EJB.Initialize, "Initialize exists")
end)

-------------------------------------------------------------------------------
-- 2. Button Creation
-------------------------------------------------------------------------------

T:run("EJButton: CreateButton creates a button frame", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    local btn = EJB:CreateButton()
    t:assertNotNil(btn, "Button created")
    t:assertNotNil(EJB.button, "Button stored on module")
end)

T:run("EJButton: button is initially hidden", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    t:assertFalse(EJB.button:IsShown(), "Button is hidden after creation")
end)

T:run("EJButton: CreateButton is idempotent", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    local btn1 = EJB:CreateButton()
    local btn2 = EJB:CreateButton()
    t:assert(btn1 == btn2, "Second call returns same button")
end)

T:run("EJButton: button has text from localization", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    local text = EJB.button:GetText()
    local L = QR.L
    t:assertEqual(L["DUNGEON_ROUTE_TO"], text, "Button text matches L['DUNGEON_ROUTE_TO']")
end)

T:run("EJButton: button has correct size", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    t:assertEqual(120, EJB.button:GetWidth(), "Button width is 120")
    t:assertEqual(22, EJB.button:GetHeight(), "Button height is 22")
end)

-------------------------------------------------------------------------------
-- 3. UpdateButton shows/hides based on EJ state
-------------------------------------------------------------------------------

T:run("EJButton: UpdateButton shows button when EJ visible with valid instanceID", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- Show EJ and set a valid instanceID (Ragefire Chasm, 226)
    _G.EncounterJournal._shown = true
    _G.EncounterJournal.instanceID = 226

    EJB:UpdateButton()
    t:assertTrue(EJB.button:IsShown(), "Button shown when EJ visible with valid instanceID")
end)

T:run("EJButton: UpdateButton hides button when EJ hidden", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- EJ hidden
    _G.EncounterJournal._shown = false
    _G.EncounterJournal.instanceID = 226

    EJB:UpdateButton()
    t:assertFalse(EJB.button:IsShown(), "Button hidden when EJ not shown")
end)

T:run("EJButton: UpdateButton hides button when no instanceID", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- EJ shown but no instanceID
    _G.EncounterJournal._shown = true
    _G.EncounterJournal.instanceID = nil

    EJB:UpdateButton()
    t:assertFalse(EJB.button:IsShown(), "Button hidden when no instanceID")
end)

T:run("EJButton: UpdateButton hides button for unknown instanceID", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- EJ shown with unknown instanceID
    _G.EncounterJournal._shown = true
    _G.EncounterJournal.instanceID = 99999

    EJB:UpdateButton()
    t:assertFalse(EJB.button:IsShown(), "Button hidden for unknown instanceID")
end)

T:run("EJButton: UpdateButton does nothing without button", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    -- Don't create button
    local ok, err = pcall(function()
        EJB:UpdateButton()
    end)
    t:assertTrue(ok, "UpdateButton without button does not crash: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- 4. RouteToCurrentInstance
-------------------------------------------------------------------------------

T:run("EJButton: RouteToCurrentInstance calls POIRouting for known instance", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    -- Track POIRouting calls
    local routeCalled = false
    local routeMapID, routeX, routeY
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routeCalled = true
        routeMapID = mapID
        routeX = x
        routeY = y
    end

    -- Set up EJ with Ragefire Chasm
    _G.EncounterJournal.instanceID = 226

    EJB:RouteToCurrentInstance()

    local inst = QR.DungeonData:GetInstance(226)
    if inst and inst.zoneMapID and inst.x and inst.y then
        t:assertTrue(routeCalled, "POIRouting:RouteToMapPosition was called")
        t:assertEqual(inst.zoneMapID, routeMapID, "Route mapID matches RFC zone")
        t:assertEqual(inst.x, routeX, "Route x matches RFC entrance")
        t:assertEqual(inst.y, routeY, "Route y matches RFC entrance")
    end

    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("EJButton: RouteToCurrentInstance handles missing data gracefully", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    -- Set up EJ with unknown instanceID
    _G.EncounterJournal.instanceID = 99999

    local ok, err = pcall(function()
        EJB:RouteToCurrentInstance()
    end)
    t:assertTrue(ok, "RouteToCurrentInstance with unknown instanceID does not crash: " .. tostring(err))
end)

T:run("EJButton: RouteToCurrentInstance handles nil instanceID", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    _G.EncounterJournal.instanceID = nil

    local ok, err = pcall(function()
        EJB:RouteToCurrentInstance()
    end)
    t:assertTrue(ok, "RouteToCurrentInstance with nil instanceID does not crash: " .. tostring(err))
end)

T:run("EJButton: RouteToCurrentInstance handles missing EncounterJournal", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    local savedEJ = _G.EncounterJournal
    _G.EncounterJournal = nil

    local ok, err = pcall(function()
        EJB:RouteToCurrentInstance()
    end)
    t:assertTrue(ok, "RouteToCurrentInstance without EJ does not crash: " .. tostring(err))

    _G.EncounterJournal = savedEJ
end)

-------------------------------------------------------------------------------
-- 5. Combat Lockdown
-------------------------------------------------------------------------------

T:run("EJButton: UpdateButton does not show button during combat", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    _G.EncounterJournal._shown = true
    _G.EncounterJournal.instanceID = 226

    -- Enable combat lockdown
    MockWoW.config.inCombatLockdown = true

    EJB:UpdateButton()
    t:assertFalse(EJB.button:IsShown(), "Button not shown during combat lockdown")
end)

-------------------------------------------------------------------------------
-- 6. HookEncounterJournal
-------------------------------------------------------------------------------

T:run("EJButton: HookEncounterJournal sets hookedEJ flag", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    t:assertFalse(EJB.hookedEJ, "hookedEJ is false before hook")

    EJB:HookEncounterJournal()
    t:assertTrue(EJB.hookedEJ, "hookedEJ is true after hook")
end)

T:run("EJButton: HookEncounterJournal is idempotent", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    EJB:HookEncounterJournal()
    t:assertTrue(EJB.hookedEJ, "hookedEJ true after first call")

    -- Second call should not error
    local ok, err = pcall(function()
        EJB:HookEncounterJournal()
    end)
    t:assertTrue(ok, "Second HookEncounterJournal does not crash: " .. tostring(err))
    t:assertTrue(EJB.hookedEJ, "hookedEJ still true after second call")
end)

T:run("EJButton: HookEncounterJournal does nothing without EncounterJournal", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    local savedEJ = _G.EncounterJournal
    _G.EncounterJournal = nil

    EJB:HookEncounterJournal()
    t:assertFalse(EJB.hookedEJ, "hookedEJ false when EJ not available")

    _G.EncounterJournal = savedEJ
end)

-------------------------------------------------------------------------------
-- 7. Initialize
-------------------------------------------------------------------------------

T:run("EJButton: Initialize is idempotent", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:Initialize()
    t:assertTrue(EJB.initialized, "initialized true after first call")

    local btn = EJB.button

    EJB:Initialize()
    t:assertTrue(EJB.initialized, "initialized still true after second call")
    t:assert(btn == EJB.button, "Button not recreated on second initialize")
end)

T:run("EJButton: Initialize creates button and hooks EJ when available", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:Initialize()
    t:assertNotNil(EJB.button, "Button created during Initialize")
    t:assertTrue(EJB.hookedEJ, "EJ hooked during Initialize (EJ already loaded)")
end)

T:run("EJButton: Initialize registers ADDON_LOADED when EJ not available", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    local savedEJ = _G.EncounterJournal
    _G.EncounterJournal = nil

    EJB:Initialize()
    t:assertNotNil(EJB.button, "Button created even without EJ")
    t:assertFalse(EJB.hookedEJ, "EJ not hooked when not available")

    -- Simulate Blizzard_EncounterJournal loading
    _G.EncounterJournal = savedEJ
    MockWoW:FireEvent("ADDON_LOADED", "Blizzard_EncounterJournal")

    t:assertTrue(EJB.hookedEJ, "EJ hooked after ADDON_LOADED fires")
end)

-------------------------------------------------------------------------------
-- 8. UX Consistency: Tooltip Branding
-------------------------------------------------------------------------------

T:run("EJButton: tooltip branding on OnEnter", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- Trigger OnEnter
    GameTooltip._calls = {}
    local onEnter = EJB.button:GetScript("OnEnter")
    if onEnter then
        onEnter(EJB.button)
    end

    -- Check AddTooltipBranding was called
    local tooltipBranded = false
    for _, call in ipairs(GameTooltip._calls or {}) do
        if call.method == "AddLine" and call.text then
            local lineText = tostring(call.text)
            if lineText:find("QuickRoute") then
                tooltipBranded = true
            end
        end
    end
    t:assertTrue(tooltipBranded, "Button tooltip has QR branding")
end)

-------------------------------------------------------------------------------
-- 9. UX Consistency: GameTooltip_Hide on OnLeave
-------------------------------------------------------------------------------

T:run("EJButton: GameTooltip_Hide called on OnLeave", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    local before = MockWoW.config.tooltipHideCalls or 0
    local onLeave = EJB.button:GetScript("OnLeave")
    if onLeave then
        onLeave(EJB.button)
    end
    local after = MockWoW.config.tooltipHideCalls or 0

    t:assertGreaterThan(after, before, "GameTooltip_Hide called on OnLeave")
end)

-------------------------------------------------------------------------------
-- 10. UX Consistency: PlaySound on Click
-------------------------------------------------------------------------------

T:run("EJButton: PlaySound on click", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()

    -- Stub routing to avoid side effects
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function() end

    -- Set up valid EJ state
    _G.EncounterJournal.instanceID = 226

    MockWoW.config.playedSounds = {}
    local onClick = EJB.button:GetScript("OnClick")
    if onClick then
        onClick(EJB.button, "LeftButton")
    end

    t:assertGreaterThan(#MockWoW.config.playedSounds, 0,
        "PlaySound called on button click")

    QR.POIRouting.RouteToMapPosition = origRoute
end)

-------------------------------------------------------------------------------
-- 11. EJ Hook Integration
-------------------------------------------------------------------------------

T:run("EJButton: EJ Show hook triggers UpdateButton", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    EJB:HookEncounterJournal()

    -- Set up valid instance
    _G.EncounterJournal.instanceID = 226

    -- Show EJ (triggers hooked Show)
    _G.EncounterJournal:Show()

    t:assertTrue(EJB.button:IsShown(), "Button shown after EJ Show hook fires")
end)

T:run("EJButton: EJ Hide hook hides button", function(t)
    resetState()
    local EJB = QR.EncounterJournalButton

    EJB:CreateButton()
    EJB:HookEncounterJournal()

    -- Show EJ and button first
    _G.EncounterJournal.instanceID = 226
    _G.EncounterJournal:Show()
    t:assertTrue(EJB.button:IsShown(), "Button shown after EJ shown")

    -- Hide EJ (triggers hooked Hide)
    _G.EncounterJournal:Hide()
    t:assertFalse(EJB.button:IsShown(), "Button hidden after EJ Hide hook fires")
end)
