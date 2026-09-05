-------------------------------------------------------------------------------
-- test_settingspanel.lua
-- Tests for the SettingsPanel module (native Settings API)
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Helper: reinitialize the settings panel module
local function reinitialize()
    QR.SettingsPanel.category = nil
    QR.SettingsPanel.controls = {}
    QR.SettingsPanel.initialized = false
end

T:run("SettingsPanel: module exists", function(t)
    t:assertNotNil(QR.SettingsPanel)
    t:assertEqual(type(QR.SettingsPanel.Register), "function")
    t:assertEqual(type(QR.SettingsPanel.Initialize), "function")
    t:assertEqual(type(QR.SettingsPanel.Open), "function")
end)

T:run("SettingsPanel: Initialize sets initialized flag", function(t)
    reinitialize()
    t:assertFalse(QR.SettingsPanel.initialized)
    QR.SettingsPanel:Initialize()
    t:assertTrue(QR.SettingsPanel.initialized)
end)

T:run("SettingsPanel: Initialize is idempotent", function(t)
    reinitialize()
    QR.SettingsPanel:Initialize()
    local cat = QR.SettingsPanel.category
    QR.SettingsPanel:Initialize()
    t:assertEqual(QR.SettingsPanel.category, cat, "Category unchanged on second init")
end)

T:run("SettingsPanel: Register creates category", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.category, "Category created")
    t:assertNotNil(QR.SettingsPanel.category.GetID, "Category has GetID")
end)

T:run("SettingsPanel: controls populated after Register", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertNotNil(QR.SettingsPanel.controls.showMinimap, "showMinimap control")
    t:assertNotNil(QR.SettingsPanel.controls.autoWaypoint, "autoWaypoint control")
    t:assertNotNil(QR.SettingsPanel.controls.considerCooldowns, "considerCooldowns control")
    t:assertNotNil(QR.SettingsPanel.controls.autoDestination, "autoDestination control")
    t:assertNotNil(QR.SettingsPanel.controls.waypointPriority, "waypointPriority control")
    t:assertNotNil(QR.SettingsPanel.controls.maxCooldownHours, "maxCooldownHours control")
    t:assertNotNil(QR.SettingsPanel.controls.loadingScreenTime, "loadingScreenTime control")
    t:assertNotNil(QR.SettingsPanel.controls.windowScale, "windowScale control")
    t:assertNotNil(QR.SettingsPanel.controls.useIconButtons, "useIconButtons control")
end)

T:run("SettingsPanel: controls have dbKey", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    t:assertEqual(QR.SettingsPanel.controls.showMinimap.dbKey, "showMinimap")
    t:assertEqual(QR.SettingsPanel.controls.autoWaypoint.dbKey, "autoWaypoint")
    t:assertEqual(QR.SettingsPanel.controls.considerCooldowns.dbKey, "considerCooldowns")
    t:assertEqual(QR.SettingsPanel.controls.waypointPriority.dbKey, "waypointPriority")
    t:assertEqual(QR.SettingsPanel.controls.maxCooldownHours.dbKey, "maxCooldownHours")
    t:assertEqual(QR.SettingsPanel.controls.useIconButtons.dbKey, "useIconButtons")
end)

T:run("SettingsPanel: controls have setting with proxy getter/setter", function(t)
    reinitialize()
    QR.db.showMinimap = true
    QR.SettingsPanel:Register()

    local ctrl = QR.SettingsPanel.controls.showMinimap
    t:assertNotNil(ctrl.setting, "Has setting object")
    t:assertNotNil(ctrl.setting._getValue, "Setting has getValue proxy")
    t:assertNotNil(ctrl.setting._setValue, "Setting has setValue proxy")

    -- Test getter reads from QR.db
    t:assertTrue(ctrl.setting._getValue(), "Proxy getter reads QR.db.showMinimap")

    -- Test setter writes to QR.db
    ctrl.setting._setValue(false)
    t:assertFalse(QR.db.showMinimap, "Proxy setter updates QR.db.showMinimap")
end)

T:run("SettingsPanel: controls have initializer", function(t)
    reinitialize()
    QR.SettingsPanel:Register()

    local checkbox = QR.SettingsPanel.controls.showMinimap
    t:assertNotNil(checkbox.initializer, "Checkbox has initializer")
    t:assertEqual("checkbox", checkbox.initializer._type, "Checkbox type correct")

    local slider = QR.SettingsPanel.controls.maxCooldownHours
    t:assertNotNil(slider.initializer, "Slider has initializer")
    t:assertEqual("slider", slider.initializer._type, "Slider type correct")

    local dropdown = QR.SettingsPanel.controls.waypointPriority
    t:assertNotNil(dropdown.initializer, "Dropdown has initializer")
    t:assertEqual("dropdown", dropdown.initializer._type, "Dropdown type correct")
end)

T:run("SettingsPanel: scale slider preserves access to the whole window", function(t)
    reinitialize()
    QR.SettingsPanel:Register()
    QR.MainFrame:CreateFrame()
    local frame = QR.MainFrame.frame
    local oldWidth, oldHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local oldScale, oldSetting = frame:GetScale(), QR.db.windowScale
    UIParent:SetSize(1024, 640)
    QR.SettingsPanel.controls.windowScale.setting._setValue(1.5)
    t:assertTrue(frame:GetHeight() * frame:GetScale() <= 616.01,
        "Moving the slider to 150 percent keeps the tabs on screen")
    t:assertEqual(QR.db.windowScale, 1.5, "The slider retains the preferred value")
    UIParent:SetSize(oldWidth, oldHeight)
    frame:SetScale(oldScale or 1)
    QR.db.windowScale = oldSetting
end)

T:run("SettingsPanel: Open does not error", function(t)
    reinitialize()
    QR.SettingsPanel:Initialize()
    -- Should not error even without full WoW UI
    QR.SettingsPanel:Open()
end)

-------------------------------------------------------------------------------
-- The section header
--
-- Settings.RegisterVerticalLayoutCategory returns the category AND its layout.
-- Checkboxes, sliders and dropdowns take the category and register themselves;
-- a section header does not, so it has to be handed to the layout. It used not
-- to be: the initializer was built and the return value dropped, which left ten
-- translations of SETTINGS_GENERAL with nowhere to appear. See issue #44.
-------------------------------------------------------------------------------

T:run("SettingsPanel: the General section header reaches the layout", function(t)
    MockWoW:Reset()
    QR.SettingsPanel.initialized = false
    QR.SettingsPanel.category = nil
    QR.SettingsPanel.layout = nil
    QR.SettingsPanel:Initialize()

    local layout = QR.SettingsPanel.layout
    t:assertNotNil(layout, "the layout was captured, not thrown away")
    if not layout then return end

    local found
    for _, init in ipairs(layout._initializers or {}) do
        if init._type == "sectionHeader" then found = init end
    end
    t:assertNotNil(found, "a section header was added to the layout")
    if not found then return end
    t:assertEqual(QR.L["SETTINGS_GENERAL"], found._name,
        "and it carries the localised name")
end)

T:run("SettingsPanel: without its template the header element stays out of the layout", function(t)
    MockWoW:Reset()
    MockWoW.config.unknownTemplates = { QuickRouteSettingsHeaderTemplate = true }
    QR.SettingsPanel.initialized = false
    QR.SettingsPanel.category = nil
    QR.SettingsPanel.layout = nil
    QR.SettingsPanel.headerInitializer = nil
    QR.SettingsPanel:Initialize()
    MockWoW.config.unknownTemplates = nil

    t:assertNil(QR.SettingsPanel.headerInitializer, "no initializer for a template the client does not know")
    for _, init in ipairs(QR.SettingsPanel.layout._initializers or {}) do
        t:assertTrue(init._template ~= "QuickRouteSettingsHeaderTemplate", "and none reached the layout")
    end
end)
