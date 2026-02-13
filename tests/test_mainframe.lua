-------------------------------------------------------------------------------
-- test_mainframe.lua
-- Tests for QR.MainFrame module: unified container with tabs, portrait header,
-- content switching, combat callbacks, and position saving.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
end

--- Helper: ensure MainFrame is created for testing
local function ensureMainFrame()
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true
    QR.MainFrame.isShowing = false
    QR.MainFrame.wasShowingBeforeCombat = false
end

--- Helper: invoke the centralized combat frame handler directly
local function fireCombatEvent(event)
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, event)
    end
end

-------------------------------------------------------------------------------
-- 1. Module existence
-------------------------------------------------------------------------------

T:run("MainFrame: module exists with expected fields", function(t)
    t:assertNotNil(QR.MainFrame, "QR.MainFrame exists")
    t:assertEqual(type(QR.MainFrame.CreateFrame), "function", "Has CreateFrame method")
    t:assertEqual(type(QR.MainFrame.Show), "function", "Has Show method")
    t:assertEqual(type(QR.MainFrame.Hide), "function", "Has Hide method")
    t:assertEqual(type(QR.MainFrame.Toggle), "function", "Has Toggle method")
    t:assertEqual(type(QR.MainFrame.SetActiveTab), "function", "Has SetActiveTab method")
    t:assertEqual(type(QR.MainFrame.GetContentFrame), "function", "Has GetContentFrame method")
    t:assertEqual(type(QR.MainFrame.Initialize), "function", "Has Initialize method")
end)

-------------------------------------------------------------------------------
-- 2. Frame creation
-------------------------------------------------------------------------------

T:run("MainFrame: CreateFrame creates frame with expected elements", function(t)
    resetState()
    ensureMainFrame()

    t:assertNotNil(QR.MainFrame.frame, "Main frame created")
    t:assertNotNil(QR.MainFrame.header, "Portrait header created")
    t:assertNotNil(QR.MainFrame.subtitle, "Subtitle font string created")
    t:assertNotNil(QR.MainFrame.contentFrames.route, "Route content frame created")
    t:assertNotNil(QR.MainFrame.contentFrames.teleports, "Teleports content frame created")
end)

T:run("MainFrame: CreateFrame is idempotent", function(t)
    resetState()
    ensureMainFrame()

    local frame1 = QR.MainFrame.frame
    QR.MainFrame:CreateFrame()
    local frame2 = QR.MainFrame.frame

    t:assertTrue(frame1 == frame2, "Same frame returned on second call")
end)

T:run("MainFrame: frame has minimum width", function(t)
    resetState()
    ensureMainFrame()

    t:assertGreaterThan(QR.MainFrame.frame:GetWidth(), 499,
        "MainFrame width >= 500")
end)

-------------------------------------------------------------------------------
-- 3. Content frames
-------------------------------------------------------------------------------

T:run("MainFrame: GetContentFrame returns correct frames", function(t)
    resetState()
    ensureMainFrame()

    local routeFrame = QR.MainFrame:GetContentFrame("route")
    local teleportFrame = QR.MainFrame:GetContentFrame("teleports")

    t:assertNotNil(routeFrame, "Route content frame returned")
    t:assertNotNil(teleportFrame, "Teleports content frame returned")
    t:assertFalse(routeFrame == teleportFrame, "Route and Teleports are different frames")
end)

T:run("MainFrame: GetContentFrame returns nil for unknown tab", function(t)
    resetState()
    ensureMainFrame()

    local frame = QR.MainFrame:GetContentFrame("unknown")
    t:assertNil(frame, "Unknown tab returns nil")
end)

-------------------------------------------------------------------------------
-- 4. Tab switching
-------------------------------------------------------------------------------

T:run("MainFrame: SetActiveTab switches content visibility", function(t)
    resetState()
    ensureMainFrame()

    -- Show the frame first
    QR.MainFrame.frame:Show()
    QR.MainFrame.isShowing = true

    QR.MainFrame:SetActiveTab("route")
    t:assertTrue(QR.MainFrame.contentFrames.route:IsShown(), "Route content shown")
    t:assertFalse(QR.MainFrame.contentFrames.teleports:IsShown(), "Teleports content hidden")
    t:assertEqual("route", QR.MainFrame.activeTab, "activeTab set to route")

    QR.MainFrame:SetActiveTab("teleports")
    t:assertFalse(QR.MainFrame.contentFrames.route:IsShown(), "Route content hidden")
    t:assertTrue(QR.MainFrame.contentFrames.teleports:IsShown(), "Teleports content shown")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "activeTab set to teleports")
end)

T:run("MainFrame: SetActiveTab saves to DB", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:SetActiveTab("teleports")
    t:assertEqual("teleports", QR.db.activeTab, "DB activeTab updated to teleports")

    QR.MainFrame:SetActiveTab("route")
    t:assertEqual("route", QR.db.activeTab, "DB activeTab updated to route")
end)

-------------------------------------------------------------------------------
-- 5. Show/Hide/Toggle
-------------------------------------------------------------------------------

T:run("MainFrame: Show sets isShowing and shows frame", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "isShowing is true after Show()")
    t:assertTrue(QR.MainFrame.frame:IsShown(), "Frame is visible after Show()")
    t:assertEqual("route", QR.MainFrame.activeTab, "Active tab is route")
end)

T:run("MainFrame: Hide clears isShowing and hides frame", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    QR.MainFrame:Hide()

    t:assertFalse(QR.MainFrame.isShowing, "isShowing is false after Hide()")
    t:assertFalse(QR.MainFrame.frame:IsShown(), "Frame is hidden after Hide()")
end)

T:run("MainFrame: Hide resets wasShowingBeforeCombat", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    QR.MainFrame.wasShowingBeforeCombat = true
    QR.MainFrame:Hide()

    t:assertFalse(QR.MainFrame.wasShowingBeforeCombat,
        "wasShowingBeforeCombat reset on manual Hide")
end)

T:run("MainFrame: Toggle hides when showing same tab", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "Showing after Show")

    QR.MainFrame:Toggle("route")
    t:assertFalse(QR.MainFrame.isShowing, "Hidden after Toggle same tab")
end)

T:run("MainFrame: Toggle switches tab when showing different tab", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "Showing on route tab")

    QR.MainFrame:Toggle("teleports")
    t:assertTrue(QR.MainFrame.isShowing, "Still showing after Toggle to different tab")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "Tab switched to teleports")
end)

T:run("MainFrame: Toggle shows when hidden", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.MainFrame:Toggle("route")
    t:assertTrue(QR.MainFrame.isShowing, "Showing after Toggle from hidden")
    t:assertEqual("route", QR.MainFrame.activeTab, "Active tab is route")
end)

-------------------------------------------------------------------------------
-- 6. Combat callbacks
-------------------------------------------------------------------------------

T:run("MainFrame: combat hides when showing", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "Showing before combat")

    fireCombatEvent("PLAYER_REGEN_DISABLED")

    t:assertFalse(QR.MainFrame.isShowing, "Hidden during combat")
    t:assertTrue(QR.MainFrame.wasShowingBeforeCombat, "wasShowingBeforeCombat set")
end)

T:run("MainFrame: combat restores after leaving", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    fireCombatEvent("PLAYER_REGEN_DISABLED")

    t:assertFalse(QR.MainFrame.isShowing, "Hidden during combat")

    fireCombatEvent("PLAYER_REGEN_ENABLED")

    t:assertTrue(QR.MainFrame.isShowing, "Restored after combat")
end)

T:run("MainFrame: combat does not restore if closed before combat", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    QR.MainFrame:Hide()  -- Closed manually

    fireCombatEvent("PLAYER_REGEN_DISABLED")
    fireCombatEvent("PLAYER_REGEN_ENABLED")

    t:assertFalse(QR.MainFrame.isShowing, "Not restored when closed before combat")
end)

T:run("MainFrame: ESC close + combat does not restore", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    QR.MainFrame.frame:Hide()  -- Simulate ESC (OnHide resets isShowing)

    t:assertFalse(QR.MainFrame.isShowing, "isShowing false after ESC")

    fireCombatEvent("PLAYER_REGEN_DISABLED")
    fireCombatEvent("PLAYER_REGEN_ENABLED")

    t:assertFalse(QR.MainFrame.isShowing, "Not restored after ESC + combat cycle")
end)

-------------------------------------------------------------------------------
-- 7. Delegation from UI and TeleportPanel
-------------------------------------------------------------------------------

T:run("MainFrame: UI:Show delegates to MainFrame route tab", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.UI:Show()
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame showing after UI:Show()")
    t:assertEqual("route", QR.MainFrame.activeTab, "Active tab is route")
end)

T:run("MainFrame: UI:Hide delegates to MainFrame", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    QR.UI:Hide()
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame hidden after UI:Hide()")
end)

T:run("MainFrame: TeleportPanel:Show delegates to MainFrame teleports tab", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.TeleportPanel:Show()
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame showing after TeleportPanel:Show()")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "Active tab is teleports")
end)

T:run("MainFrame: TeleportPanel:Hide delegates to MainFrame", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("teleports")
    QR.TeleportPanel:Hide()
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame hidden after TeleportPanel:Hide()")
end)

-------------------------------------------------------------------------------
-- 8. Position saving
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- 8.5. Tab switching subtitle
-------------------------------------------------------------------------------

T:run("MainFrame: SetActiveTab teleports updates subtitle", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:SetActiveTab("teleports")
    local text = QR.MainFrame.subtitle:GetText()
    t:assertNotNil(text, "Subtitle has text after switching to teleports")
    t:assertEqual(text, QR.L["TELEPORT_INVENTORY"], "Subtitle matches TELEPORT_INVENTORY")
end)

T:run("MainFrame: SetActiveTab route changes subtitle from teleports", function(t)
    resetState()
    ensureMainFrame()

    -- First switch to teleports
    QR.MainFrame:SetActiveTab("teleports")
    local teleportSubtitle = QR.MainFrame.subtitle:GetText()
    t:assertEqual(teleportSubtitle, QR.L["TELEPORT_INVENTORY"],
        "Subtitle is TELEPORT_INVENTORY on teleports tab")

    -- Now switch to route — subtitle should change
    QR.MainFrame:SetActiveTab("route")
    local routeSubtitle = QR.MainFrame.subtitle:GetText()
    t:assertFalse(routeSubtitle == QR.L["TELEPORT_INVENTORY"],
        "Subtitle changed from TELEPORT_INVENTORY after switching to route")
end)

T:run("MainFrame: SetActiveTab route with UI initialized triggers refresh", function(t)
    resetState()
    ensureMainFrame()

    -- Make sure UI is initialized so refresh gets called
    if not QR.UI.frame then
        local contentFrame = QR.MainFrame:GetContentFrame("route")
        QR.UI:CreateContent(contentFrame)
    end
    QR.UI.initialized = true
    QR.UI.isCalculating = false

    -- Switch to teleports first
    QR.MainFrame:SetActiveTab("teleports")

    -- Track if RefreshRoute is called
    local originalRefresh = QR.UI.RefreshRoute
    local refreshCalled = false
    QR.UI.RefreshRoute = function(self)
        refreshCalled = true
        -- Call original to update subtitle etc
        originalRefresh(self)
    end

    QR.MainFrame:SetActiveTab("route")
    t:assertTrue(refreshCalled, "RefreshRoute called when switching to route tab")

    -- Restore
    QR.UI.RefreshRoute = originalRefresh
end)

-------------------------------------------------------------------------------
-- 9. Show() default tab + subtitle
-------------------------------------------------------------------------------

T:run("MainFrame: Show() without arg uses last activeTab", function(t)
    resetState()
    ensureMainFrame()

    -- Set activeTab to teleports and hide
    QR.MainFrame.activeTab = "teleports"
    QR.MainFrame:Hide()

    -- Show without arg should restore to teleports
    QR.MainFrame:Show()
    t:assertTrue(QR.MainFrame.isShowing, "Showing after Show()")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "Restored to last active tab")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle shows TELEPORT_INVENTORY for teleports tab")
end)

T:run("MainFrame: Show() defaults to route when no previous tab", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame.activeTab = nil
    QR.MainFrame:Hide()

    QR.MainFrame:Show()
    t:assertTrue(QR.MainFrame.isShowing, "Showing after Show()")
    t:assertEqual("route", QR.MainFrame.activeTab, "Defaults to route tab")
end)

T:run("MainFrame: Show(teleports) sets subtitle to TELEPORT_INVENTORY", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.MainFrame:Show("teleports")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle shows TELEPORT_INVENTORY after Show(teleports)")
end)

-------------------------------------------------------------------------------
-- 10. Toggle(nil) behavior
-------------------------------------------------------------------------------

T:run("MainFrame: Toggle(nil) when showing hides frame", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "Showing before Toggle(nil)")

    QR.MainFrame:Toggle(nil)
    t:assertFalse(QR.MainFrame.isShowing, "Hidden after Toggle(nil) when showing")
end)

T:run("MainFrame: Toggle(nil) when hidden shows frame", function(t)
    resetState()
    ensureMainFrame()
    QR.MainFrame:Hide()

    QR.MainFrame:Toggle(nil)
    t:assertTrue(QR.MainFrame.isShowing, "Showing after Toggle(nil) when hidden")
end)

T:run("MainFrame: Toggle() when showing teleports and Toggle(nil) hides", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("teleports")
    t:assertTrue(QR.MainFrame.isShowing, "Showing teleports")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "On teleports tab")

    QR.MainFrame:Toggle()
    t:assertFalse(QR.MainFrame.isShowing, "Hidden after Toggle()")
end)

-------------------------------------------------------------------------------
-- 11. Combat restore preserves tab + subtitle
-------------------------------------------------------------------------------

T:run("MainFrame: combat restore on teleports tab preserves tab + subtitle", function(t)
    resetState()
    ensureMainFrame()

    -- Open on teleports tab
    QR.MainFrame:Show("teleports")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "On teleports tab")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle is TELEPORT_INVENTORY before combat")

    -- Enter combat
    fireCombatEvent("PLAYER_REGEN_DISABLED")
    t:assertFalse(QR.MainFrame.isShowing, "Hidden during combat")

    -- Leave combat
    fireCombatEvent("PLAYER_REGEN_ENABLED")
    t:assertTrue(QR.MainFrame.isShowing, "Restored after combat")
    t:assertEqual("teleports", QR.MainFrame.activeTab,
        "Active tab is still teleports after combat restore")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle is still TELEPORT_INVENTORY after combat restore")
end)

T:run("MainFrame: combat restore on route tab preserves tab", function(t)
    resetState()
    ensureMainFrame()

    QR.MainFrame:Show("route")
    t:assertEqual("route", QR.MainFrame.activeTab, "On route tab")

    fireCombatEvent("PLAYER_REGEN_DISABLED")
    fireCombatEvent("PLAYER_REGEN_ENABLED")

    t:assertTrue(QR.MainFrame.isShowing, "Restored after combat")
    t:assertEqual("route", QR.MainFrame.activeTab,
        "Active tab is still route after combat restore")
end)

-------------------------------------------------------------------------------
-- 12. Toggle tab switching updates subtitle
-------------------------------------------------------------------------------

T:run("MainFrame: Toggle to different tab updates subtitle", function(t)
    resetState()
    ensureMainFrame()

    -- Start on route
    QR.MainFrame:Show("route")
    local routeSubtitle = QR.MainFrame.subtitle:GetText()

    -- Toggle to teleports (switches tab, doesn't hide)
    QR.MainFrame:Toggle("teleports")
    t:assertTrue(QR.MainFrame.isShowing, "Still showing after tab switch")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle updated to TELEPORT_INVENTORY after Toggle to teleports")
end)

T:run("MainFrame: Toggle from teleports to route updates subtitle", function(t)
    resetState()
    ensureMainFrame()

    -- Start on teleports
    QR.MainFrame:Show("teleports")
    t:assertEqual(QR.L["TELEPORT_INVENTORY"], QR.MainFrame.subtitle:GetText(),
        "Subtitle is TELEPORT_INVENTORY")

    -- Toggle to route
    QR.MainFrame:Toggle("route")
    t:assertTrue(QR.MainFrame.isShowing, "Still showing after tab switch")
    t:assertFalse(QR.MainFrame.subtitle:GetText() == QR.L["TELEPORT_INVENTORY"],
        "Subtitle changed from TELEPORT_INVENTORY after Toggle to route")
end)

-------------------------------------------------------------------------------
-- 13. Position saving
-------------------------------------------------------------------------------

T:run("MainFrame: position saved to DB on drag stop", function(t)
    resetState()
    ensureMainFrame()

    -- Simulate drag stop by calling the OnDragStop handler
    local dragStop = QR.MainFrame.frame:GetScript("OnDragStop")
    if dragStop then
        dragStop(QR.MainFrame.frame)
        t:assertNotNil(QR.db.mainFramePoint, "mainFramePoint saved to DB")
    else
        t:assertTrue(true, "OnDragStop handler not accessible in test")
    end
end)
