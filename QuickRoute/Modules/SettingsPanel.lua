-- SettingsPanel.lua
-- Settings panel for WoW Interface Options
-- Uses native Settings API (vertical layout) for pixel-perfect match with Game Settings.
local ADDON_NAME, QR = ...

local CreateFrame = CreateFrame

-------------------------------------------------------------------------------
-- SettingsPanel Module
-------------------------------------------------------------------------------
QR.SettingsPanel = {
    panel = nil,
    category = nil,
    controls = {},
    initialized = false,
}

local SettingsPanel = QR.SettingsPanel

-- Localization shorthand (set during init)
local L

-------------------------------------------------------------------------------
-- Native Settings API
-- Uses RegisterVerticalLayoutCategory + RegisterProxySetting + CreateCheckbox/
-- CreateSlider/CreateDropdown for pixel-perfect Game Settings appearance.
-------------------------------------------------------------------------------

--- Register a proxy checkbox that reads/writes QR.db[key]
local function RegisterCheckbox(category, label, tooltip, dbKey, onChange)
    local setting = Settings.RegisterProxySetting(
        category,
        "QuickRoute_" .. dbKey,
        Settings.VarType.Boolean,
        label,
        false,
        function() return QR.db[dbKey] or false end,
        function(value)
            QR.db[dbKey] = value
            if onChange then onChange(value) end
        end
    )
    local initializer = Settings.CreateCheckbox(category, setting, tooltip)
    -- Store reference for test introspection
    SettingsPanel.controls[dbKey] = { dbKey = dbKey, setting = setting, initializer = initializer }
    return initializer
end

--- Register a proxy slider that reads/writes QR.db[key]
local function RegisterSlider(category, label, tooltip, dbKey, minVal, maxVal, step, onChange)
    local setting = Settings.RegisterProxySetting(
        category,
        "QuickRoute_" .. dbKey,
        Settings.VarType.Number,
        label,
        minVal,
        function() return QR.db[dbKey] or minVal end,
        function(value)
            QR.db[dbKey] = value
            if onChange then onChange(value) end
        end
    )
    local options = Settings.CreateSliderOptions(minVal, maxVal, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    local initializer = Settings.CreateSlider(category, setting, options, tooltip)
    SettingsPanel.controls[dbKey] = { dbKey = dbKey, setting = setting, initializer = initializer }
    return initializer
end

--- Register a proxy dropdown that reads/writes QR.db[key]
local function RegisterDropdown(category, label, tooltip, dbKey, opts, onChange)
    local setting = Settings.RegisterProxySetting(
        category,
        "QuickRoute_" .. dbKey,
        Settings.VarType.String,
        label,
        opts[1] and opts[1].value or "",
        function() return QR.db[dbKey] or "" end,
        function(value)
            QR.db[dbKey] = value
            if onChange then onChange(value) end
        end
    )
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        for _, opt in ipairs(opts) do
            container:Add(opt.value, opt.text)
        end
        return container:GetData()
    end
    local initializer = Settings.CreateDropdown(category, setting, GetOptions, tooltip)
    SettingsPanel.controls[dbKey] = { dbKey = dbKey, setting = setting, initializer = initializer }
    return initializer
end

--- Build the native vertical layout settings panel
local function RegisterNativeSettings()
    L = QR.L

    -- The layout is the second return value, and it is what anything other
    -- than a checkbox, slider or dropdown has to be added to. Those three take
    -- the category and register themselves; a section header does not, so it
    -- needs AddInitializer or it is simply built and dropped -- which is what
    -- used to happen here, leaving ten translations of SETTINGS_GENERAL with
    -- nowhere to appear.
    local category, layout = Settings.RegisterVerticalLayoutCategory(
        L["ADDON_TITLE"] or "QuickRoute"
    )
    SettingsPanel.layout = layout

    -- Older clients may expose the layout only through the native panel.
    if not layout and _G.SettingsPanel and _G.SettingsPanel.GetLayout then
        layout = _G.SettingsPanel:GetLayout(category)
        SettingsPanel.layout = layout
    end
    -- Branding lives above Blizzard's divider, outside the scrolling list.
    SettingsPanel.headerInitializer = nil

    -- General
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["SETTINGS_GENERAL"]))
    end

    RegisterCheckbox(category,
        L["SETTINGS_SHOW_MINIMAP"] or "Show Minimap Button",
        L["SETTINGS_SHOW_MINIMAP_TT"] or "Show or hide the minimap button",
        "showMinimap",
        function(checked)
            if QR.MinimapButton then QR.MinimapButton:ApplyVisibility() end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_AUTO_WAYPOINT"] or "Auto-set Waypoint for First Step",
        L["AUTO_WAYPOINT_ON"],
        "autoWaypoint")

    RegisterCheckbox(category,
        L["SETTINGS_CONSIDER_CD"] or "Consider Cooldowns in Routing",
        L["SETTINGS_CONSIDER_CD_TT"] or "Factor teleport cooldowns into route calculations",
        "considerCooldowns")

    RegisterCheckbox(category,
        L["SETTINGS_AUTO_DEST"] or "Auto-show route on quest tracking",
        L["SETTINGS_AUTO_DEST_TT"] or "Open the route window when a tracked quest leads to another zone",
        "autoDestination")

    -- Navigation
    RegisterDropdown(category,
        L["WAYPOINT_SOURCE"],
        L["TOOLTIP_WAYPOINT_SOURCE"],
        "waypointPriority",
        {
            { value = "mappin", text = L["WAYPOINT_MAP_PIN"] },
            { value = "tomtom", text = L["WAYPOINT_TOMTOM"] },
            { value = "quest",  text = L["WAYPOINT_QUEST"] },
        },
        function(value)
            if QR.MainFrame and QR.MainFrame.isShowing and QR.MainFrame.activeTab == "route" then QR.UI:RefreshRoute() end
        end)

    -- Routing
    RegisterSlider(category,
        L["SETTINGS_MAX_COOLDOWN"] or "Max Cooldown (hours)",
        L["SETTINGS_MAX_COOLDOWN_TT"] or "Exclude teleports with cooldowns longer than this",
        "maxCooldownHours", 1, 24, 1,
        function(v) if QR.PathCalculator then QR.PathCalculator.graphDirty = true end end)

    RegisterSlider(category,
        L["SETTINGS_LOADING_TIME"] or "Loading Screen Time (seconds)",
        L["SETTINGS_LOADING_TIME_TT"] or "Extra time to account for loading screens when using portals/teleports",
        "loadingScreenTime", 0, 30, 1,
        function(v) if QR.PathCalculator then QR.PathCalculator.graphDirty = true end end)

    -- Appearance
    RegisterSlider(category,
        L["SETTINGS_WINDOW_SCALE"] or "Window Scale",
        L["SETTINGS_WINDOW_SCALE_TT"] or "Scale of the route and teleport windows (75%-150%)",
        "windowScale", 0.75, 1.5, 0.05,
        function(v)
            if QR.MainFrame and QR.MainFrame.frame then QR.FitWindowScale(QR.MainFrame.frame, v) end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_ICON_BUTTONS"] or "Use Icon Buttons",
        L["SETTINGS_ICON_BUTTONS_TT"] or "Replace text labels on buttons with icons for a more compact UI",
        "useIconButtons",
        function(checked)
            if QR.UI and QR.UI.UpdateAllButtonStyles then QR.UI:UpdateAllButtonStyles() end
        end)

    -- Diagnostics
    RegisterCheckbox(category,
        L["SETTINGS_DIAGNOSTIC_TRACE"],
        L["SETTINGS_DIAGNOSTIC_TRACE_TT"],
        "diagnosticTrace",
        function(checked)
            if QR.Diagnostics and QR.Diagnostics.ApplyTraceSetting then
                QR.Diagnostics:ApplyTraceSetting()
            end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_ZONE_SURVEY"],
        L["SETTINGS_ZONE_SURVEY_TT"],
        "zoneSurveyEnabled",
        function(checked)
            if QR.ZoneSurvey and QR.ZoneSurvey.SetEnabled then QR.ZoneSurvey:SetEnabled(checked, true) end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_DATA_COLLECTION"],
        L["SETTINGS_DATA_COLLECTION_TT"],
        "dataCollection",
        function(checked)
            if QR.DataCollection and QR.DataCollection.SetEnabled then QR.DataCollection:SetEnabled(checked) end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_SAVE_REMINDER"],
        L["SETTINGS_SAVE_REMINDER_TT"],
        "saveReminder",
        function(checked)
            local reminder = QR.Diagnostics and QR.Diagnostics.Reminder
            if not checked and reminder and reminder.popup then reminder.popup:Hide() end
            if reminder and reminder.Refresh then reminder:Refresh() end
        end)

    RegisterSlider(category,
        L["SETTINGS_SAVE_REMINDER_MINUTES"],
        L["SETTINGS_SAVE_REMINDER_MINUTES_TT"],
        "saveReminderMinutes", 5, 120, 5)

    RegisterSlider(category,
        L["SETTINGS_SAVE_REMINDER_TIMEOUT"],
        L["SETTINGS_SAVE_REMINDER_TIMEOUT_TT"],
        "saveReminderTimeout", 10, 120, 5)

    Settings.RegisterAddOnCategory(category)
    return category
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Register the panel with Interface Options
function SettingsPanel:Register()
    self.category = RegisterNativeSettings()
    if QR.SettingsHeader then QR.SettingsHeader:Install(_G.SettingsPanel, self.category) end
end

--- Open the settings panel
function SettingsPanel:Open()
    if Settings and Settings.OpenToCategory and self.category then
        Settings.OpenToCategory(self.category:GetID())
    end
end

--- Initialize the settings panel
function SettingsPanel:Initialize()
    if self.initialized then return end
    self.initialized = true

    L = QR.L
    self:Register()

    QR:Debug("SettingsPanel initialized")
end
