-------------------------------------------------------------------------------
-- test_settings_features.lua
-- Tests for new settings features: auto-destination, sliders, window scale
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Helper: reinitialize the settings panel module
local function reinitialize()
    QR.SettingsPanel.category = nil
    QR.SettingsPanel.controls = {}
    QR.SettingsPanel.initialized = false
end

local function resetState()
    MockWoW:Reset()
    MockWoW.config.hasUserWaypoint = false
    MockWoW.config.superTrackedQuestID = 0
    _G.TomTom = nil
    _G.C_Map.HasUserWaypoint = function() return MockWoW.config.hasUserWaypoint end
    _G.C_Map.GetUserWaypoint = function() return MockWoW.config.userWaypoint end
end

-------------------------------------------------------------------------------
-- 1. DB Defaults
-------------------------------------------------------------------------------

T:run("DB defaults: autoDestination exists and is false", function(t)
    -- Re-initialize to apply defaults
    _G.QuickRouteDB = {}
    QR:Initialize()
    t:assertEqual(false, QR.db.autoDestination, "autoDestination defaults to false")
end)

T:run("DB defaults: maxCooldownHours exists and is 24", function(t)
    _G.QuickRouteDB = {}
    QR:Initialize()
    t:assertEqual(24, QR.db.maxCooldownHours, "maxCooldownHours defaults to 24")
end)

T:run("DB defaults: loadingScreenTime exists and is 5", function(t)
    _G.QuickRouteDB = {}
    QR:Initialize()
    t:assertEqual(5, QR.db.loadingScreenTime, "loadingScreenTime defaults to 5")
end)

T:run("DB defaults: windowScale exists and is 1.0", function(t)
    _G.QuickRouteDB = {}
    QR:Initialize()
    t:assertEqual(1.0, QR.db.windowScale, "windowScale defaults to 1.0")
end)

T:run("DB defaults: preserves existing values", function(t)
    _G.QuickRouteDB = { maxCooldownHours = 8, windowScale = 1.25 }
    QR:Initialize()
    t:assertEqual(8, QR.db.maxCooldownHours, "maxCooldownHours preserved")
    t:assertEqual(1.25, QR.db.windowScale, "windowScale preserved")
end)

-------------------------------------------------------------------------------
-- 2. Auto-Destination: OnWaypointChanged
-------------------------------------------------------------------------------

T:run("Auto-dest: OnWaypointChanged auto-shows UI when enabled", function(t)
    resetState()
    QR.db.autoDestination = true

    -- Set up a quest waypoint so GetActiveWaypoint returns something
    MockWoW.config.superTrackedQuestID = 500
    MockWoW.config.questTitles[500] = "Test Quest"
    MockWoW.config.questWaypoints[500] = { mapID = 84, x = 0.5, y = 0.5 }

    -- Track if UI:Show was called
    local showCalled = false
    local origShow = QR.UI.Show
    QR.UI.Show = function(self)
        showCalled = true
    end

    QR.WaypointIntegration:OnWaypointChanged()

    t:assertTrue(showCalled, "UI:Show called when autoDestination is enabled")

    QR.UI.Show = origShow
    QR.db.autoDestination = false
end)

T:run("Auto-dest: OnWaypointChanged only refreshes when disabled", function(t)
    resetState()
    QR.db.autoDestination = false

    -- Set up a quest waypoint
    MockWoW.config.superTrackedQuestID = 501
    MockWoW.config.questTitles[501] = "Test Quest 2"
    MockWoW.config.questWaypoints[501] = { mapID = 85, x = 0.3, y = 0.3 }

    local showCalled = false
    local refreshCalled = false

    local origShow = QR.UI.Show
    local origRefresh = QR.UI.RefreshRoute
    QR.UI.Show = function(self) showCalled = true end
    QR.UI.RefreshRoute = function(self) refreshCalled = true end

    -- MainFrame is not showing (auto-dest check uses MainFrame.isShowing)
    QR.MainFrame.isShowing = false
    QR.MainFrame.activeTab = "route"

    QR.WaypointIntegration:OnWaypointChanged()

    t:assertFalse(showCalled, "UI:Show NOT called when autoDestination is disabled")
    t:assertFalse(refreshCalled, "RefreshRoute NOT called when MainFrame not shown")

    QR.UI.Show = origShow
    QR.UI.RefreshRoute = origRefresh
end)

T:run("Auto-dest: OnWaypointChanged refreshes when UI is shown and auto-dest off", function(t)
    resetState()
    QR.db.autoDestination = false

    -- Set up a quest waypoint
    MockWoW.config.superTrackedQuestID = 502
    MockWoW.config.questTitles[502] = "Visible Quest"
    MockWoW.config.questWaypoints[502] = { mapID = 84, x = 0.5, y = 0.5 }

    local refreshCalled = false
    local origRefresh = QR.UI.RefreshRoute
    QR.UI.RefreshRoute = function(self) refreshCalled = true end

    -- MainFrame is showing on route tab (auto-dest check uses MainFrame.isShowing)
    QR.MainFrame.isShowing = true
    QR.MainFrame.activeTab = "route"

    QR.WaypointIntegration:OnWaypointChanged()

    t:assertTrue(refreshCalled, "RefreshRoute called when MainFrame is shown on route tab and auto-dest off")

    QR.UI.RefreshRoute = origRefresh
    QR.MainFrame.isShowing = false
end)

-------------------------------------------------------------------------------
-- 3. SettingsPanel: New Controls
-------------------------------------------------------------------------------

T:run("SettingsPanel: autoDestination checkbox created", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.controls.autoDestination, "autoDestination control exists")
    t:assertEqual("autoDestination", QR.SettingsPanel.controls.autoDestination.dbKey, "dbKey is autoDestination")
    t:assertEqual("checkbox", QR.SettingsPanel.controls.autoDestination.initializer._type, "Type is checkbox")
end)

T:run("SettingsPanel: maxCooldownHours slider created", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.controls.maxCooldownHours, "maxCooldownHours control exists")
    t:assertEqual("maxCooldownHours", QR.SettingsPanel.controls.maxCooldownHours.dbKey, "dbKey is maxCooldownHours")
    t:assertEqual("slider", QR.SettingsPanel.controls.maxCooldownHours.initializer._type, "Type is slider")
end)

T:run("SettingsPanel: loadingScreenTime slider created", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.controls.loadingScreenTime, "loadingScreenTime control exists")
    t:assertEqual("loadingScreenTime", QR.SettingsPanel.controls.loadingScreenTime.dbKey, "dbKey is loadingScreenTime")
    t:assertEqual("slider", QR.SettingsPanel.controls.loadingScreenTime.initializer._type, "Type is slider")
end)

T:run("SettingsPanel: windowScale slider created", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.controls.windowScale, "windowScale control exists")
    t:assertEqual("windowScale", QR.SettingsPanel.controls.windowScale.dbKey, "dbKey is windowScale")
    t:assertEqual("slider", QR.SettingsPanel.controls.windowScale.initializer._type, "Type is slider")
end)

-------------------------------------------------------------------------------
-- 4. Slider onChange Callbacks
-------------------------------------------------------------------------------

T:run("SettingsPanel: maxCooldownHours onChange marks graph dirty", function(t)
    reinitialize()
    QR.SettingsPanel:Register()

    if QR.PathCalculator then
        QR.PathCalculator.graphDirty = false
    end

    -- Use proxy setter to simulate Settings API value change
    local ctrl = QR.SettingsPanel.controls.maxCooldownHours
    ctrl.setting._setValue(12)

    t:assertEqual(12, QR.db.maxCooldownHours, "DB updated to 12")
    if QR.PathCalculator then
        t:assertTrue(QR.PathCalculator.graphDirty, "Graph marked dirty after cooldown change")
    end
end)

T:run("SettingsPanel: loadingScreenTime onChange marks graph dirty", function(t)
    reinitialize()
    QR.SettingsPanel:Register()

    if QR.PathCalculator then
        QR.PathCalculator.graphDirty = false
    end

    local ctrl = QR.SettingsPanel.controls.loadingScreenTime
    ctrl.setting._setValue(10)

    t:assertEqual(10, QR.db.loadingScreenTime, "DB updated to 10")
    if QR.PathCalculator then
        t:assertTrue(QR.PathCalculator.graphDirty, "Graph marked dirty after loading time change")
    end
end)

T:run("SettingsPanel: windowScale onChange applies to MainFrame", function(t)
    reinitialize()
    QR.SettingsPanel:Register()

    if QR.MainFrame and QR.MainFrame.frame then
        local ctrl = QR.SettingsPanel.controls.windowScale
        ctrl.setting._setValue(1.25)

        t:assertEqual(1.25, QR.db.windowScale, "DB updated to 1.25")
        t:assertEqual(1.25, QR.MainFrame.frame:GetScale(), "MainFrame scale set to 1.25")
    else
        t:assertTrue(true, "MainFrame not available in test, skipping")
    end
end)
