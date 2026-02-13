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

    local category = Settings.RegisterVerticalLayoutCategory(
        L["ADDON_TITLE"] or "QuickRoute"
    )

    -- General
    Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = L["SETTINGS_GENERAL"] })

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
        L["SETTINGS_AUTO_DEST_TT"] or "Automatically calculate and show the route when you track a new quest",
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
            if QR.MainFrame and QR.MainFrame.frame then QR.MainFrame.frame:SetScale(v) end
        end)

    RegisterCheckbox(category,
        L["SETTINGS_ICON_BUTTONS"] or "Use Icon Buttons",
        L["SETTINGS_ICON_BUTTONS_TT"] or "Replace text labels on buttons with icons for a more compact UI",
        "useIconButtons",
        function(checked)
            if QR.UI and QR.UI.UpdateAllButtonStyles then QR.UI:UpdateAllButtonStyles() end
        end)

    Settings.RegisterAddOnCategory(category)
    return category
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Register the panel with Interface Options
function SettingsPanel:Register()
    self.category = RegisterNativeSettings()
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
