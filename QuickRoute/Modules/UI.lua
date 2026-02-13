-- UI.lua
-- User interface for displaying route information
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local math_max, math_min = math.max, math.min
local string_format = string.format
local table_insert, table_concat = table.insert, table.concat
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

-- Debug: confirm file loaded (guard for load order - Debug defined in QuickRoute.lua)
if QR.Debug then QR:Debug("UI.lua loading...") end

-------------------------------------------------------------------------------
-- UI Module
-------------------------------------------------------------------------------
QR.UI = {
    frame = nil,
    stepLabels = {},
    stepLabelPool = {},  -- Pool of reusable step label frames
    combatDisabledButtons = {},  -- Track buttons disabled during combat
    -- Cache tables for localized names (reduces repeated API calls)
    itemInfoCache = {},
    spellInfoCache = {},
    -- LRU tracking for caches
    itemInfoAccessOrder = {},
    spellInfoAccessOrder = {},
    -- Throttle tracking
    lastRefreshClickTime = 0,
    -- State tracking
    isCalculating = false,
}

local UI = QR.UI

-- Localization shorthand
local L = QR.L

-- Color constants shorthand
local C = QR.Colors

-- Hidden container for recycled frames (SetParent(nil) can cause issues in WoW)
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

-- Constants
local FRAME_MIN_WIDTH = 500
local FRAME_HEIGHT = 400
local STEP_HEIGHT = 24
local PADDING = 10
local BUTTON_HEIGHT = 22
local BUTTON_PADDING = 4
local BUTTON_MIN_WIDTH = 50
local CACHE_MAX_SIZE = 100  -- Max entries in item/spell caches (LRU eviction)

--- Helper to calculate button width based on text (for localization flexibility)
-- @param text string The button label text
-- @return number The calculated width
local function CalculateButtonWidth(text)
    -- Approximate: 7 pixels per character + 16 padding
    local width = (#text * 7) + 16
    return math_max(width, BUTTON_MIN_WIDTH)
end

--- Calculate total width needed for a row of buttons
-- @param buttonTexts table Array of button text strings
-- @return number Total width including padding between buttons
local function CalculateButtonRowWidth(buttonTexts)
    local total = 0
    for i, text in ipairs(buttonTexts) do
        total = total + CalculateButtonWidth(text)
        if i < #buttonTexts then
            total = total + BUTTON_PADDING
        end
    end
    return total + (PADDING * 2)  -- Add frame padding
end

--- Set dropdown display text
-- @param dropdown Frame The dropdown frame (WowStyle1DropdownTemplate)
-- @param text string The display text to set
local function SetDropdownText(dropdown, text)
    if not dropdown then return end
    if dropdown.OverrideText then
        dropdown:OverrideText(text)
    elseif dropdown.GenerateMenu then
        dropdown:GenerateMenu()
    end
end

-- Icon textures for different step types
local STEP_ICONS = {
    teleport = "|TInterface\\Icons\\INV_Misc_Rune_01:16:16|t",
    portal = "|TInterface\\Icons\\Spell_Arcane_PortalStormwind:16:16|t",
    walk = "|TInterface\\Icons\\Ability_Tracking:16:16|t",
    flight = "|TInterface\\Icons\\Ability_Mount_RocketMount:16:16|t",
    hearthstone = "|TInterface\\Icons\\INV_Misc_Rune_01:16:16|t",
}

-- Button icon textures (used when useIconButtons is enabled)
local BUTTON_ICONS = {
    refresh = "Interface\\Icons\\Spell_Nature_Reincarnation",
    debug = "Interface\\Icons\\INV_Misc_Gear_01",
    zone = "Interface\\Icons\\INV_Misc_Map02",
    inventory = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    nav = "Interface\\Icons\\Ability_Spy",
    use = "Interface\\Icons\\Spell_Nature_Astralrecalgroup",
    close = "Interface\\Icons\\Spell_ChargeNegative",
}

-- Registry of styled buttons for live style updates
local styledButtons = {}

--- Apply icon or text to a button based on settings
-- @param button Frame The button frame
-- @param textLabel string The text label (used when icons disabled)
-- @param iconKey string Key into BUTTON_ICONS table
-- @param size number|nil Icon size (default 16)
local function ApplyButtonStyle(button, textLabel, iconKey, size)
    size = size or 16
    -- Register button for live style updates
    styledButtons[button] = { textLabel = textLabel, iconKey = iconKey, size = size }
    local useIcons = QR.db and QR.db.useIconButtons
    if useIcons and BUTTON_ICONS[iconKey] then
        -- Icon mode: show icon texture string as text
        local iconStr = string_format("|T%s:%d:%d|t", BUTTON_ICONS[iconKey], size, size)
        button:SetText(iconStr)
        -- Make button square-ish for icon
        button:SetWidth(size + 12)
    else
        -- Text mode: show text label
        button:SetText(textLabel)
        -- Calculate width based on text
        local width = (#textLabel * 7) + 16
        if width < BUTTON_MIN_WIDTH then width = BUTTON_MIN_WIDTH end
        button:SetWidth(width)
    end
end

--- Re-apply styles to all registered buttons (called when useIconButtons changes)
function UI:UpdateAllButtonStyles()
    for button, info in pairs(styledButtons) do
        ApplyButtonStyle(button, info.textLabel, info.iconKey, info.size)
    end
end

-------------------------------------------------------------------------------
-- Localized Name and Link Helpers
-------------------------------------------------------------------------------

-- Position tracking tables for O(1) LRU operations
local itemPosTracker = {}
local spellPosTracker = {}

--- Helper to update LRU order using position tracking for fast lookup
-- Lookup is O(1) via posTracker; removal/insertion involves O(n) array shifts.
-- Acceptable for CACHE_MAX_SIZE=100.
-- @param accessOrder table The access order array
-- @param posTracker table Position tracker (id -> index)
-- @param cache table The cache table
-- @param id number The item/spell ID
local function updateLRUOrder(accessOrder, posTracker, cache, id)
    -- Remove existing entry if present (O(1) lookup via posTracker)
    local existingPos = posTracker[id]
    if existingPos then
        -- Shift subsequent entries back and update their positions
        for i = existingPos, #accessOrder - 1 do
            accessOrder[i] = accessOrder[i + 1]
            posTracker[accessOrder[i]] = i
        end
        accessOrder[#accessOrder] = nil
    end
    -- Add to end (most recently accessed)
    table_insert(accessOrder, id)
    posTracker[id] = #accessOrder
    -- Evict oldest if over limit
    while #accessOrder > CACHE_MAX_SIZE do
        local oldestID = accessOrder[1]
        posTracker[oldestID] = nil
        cache[oldestID] = nil
        -- Shift all entries back
        for i = 1, #accessOrder - 1 do
            accessOrder[i] = accessOrder[i + 1]
            if accessOrder[i] then
                posTracker[accessOrder[i]] = i
            end
        end
        accessOrder[#accessOrder] = nil
    end
end

--- Get localized item info including clickable link (cached with LRU)
-- @param itemID number The item ID
-- @return string|nil name The localized item name
-- @return string|nil link The clickable item link
function UI:GetLocalizedItemInfo(itemID)
    if not itemID then
        return nil, nil
    end
    -- Check cache first
    local cached = self.itemInfoCache[itemID]
    if cached then
        updateLRUOrder(self.itemInfoAccessOrder, itemPosTracker, self.itemInfoCache, itemID)
        return cached.name, cached.link
    end
    -- Fetch from API
    local name, link = GetItemInfo(itemID)
    -- Only cache if we got valid data (item info may not be available immediately)
    if name then
        self.itemInfoCache[itemID] = { name = name, link = link }
        updateLRUOrder(self.itemInfoAccessOrder, itemPosTracker, self.itemInfoCache, itemID)
    end
    return name, link
end

--- Get localized spell info including clickable link (cached with LRU)
-- @param spellID number The spell ID
-- @return string|nil name The localized spell name
-- @return string|nil link The clickable spell link
function UI:GetLocalizedSpellInfo(spellID)
    if not spellID then
        return nil, nil
    end
    -- Check cache first
    local cached = self.spellInfoCache[spellID]
    if cached then
        updateLRUOrder(self.spellInfoAccessOrder, spellPosTracker, self.spellInfoCache, spellID)
        return cached.name, cached.link
    end
    local name, link
    -- Use C_Spell.GetSpellInfo for name (returns table in modern API)
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if spellInfo then
        name = spellInfo.name
    else
        -- Fallback to older GetSpellInfo API
        name = GetSpellInfo and GetSpellInfo(spellID)
    end
    -- Get clickable link
    link = GetSpellLink and GetSpellLink(spellID)
    -- Cache the result if we got a name
    if name then
        self.spellInfoCache[spellID] = { name = name, link = link }
        updateLRUOrder(self.spellInfoAccessOrder, spellPosTracker, self.spellInfoCache, spellID)
    end
    return name, link
end

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create UI content elements inside a parent content frame (from MainFrame).
-- @param parentFrame Frame The content frame to parent all UI elements to
-- @return Frame The parent frame (with UI elements attached)
function UI:CreateContent(parentFrame)
    if self.frame then
        return self.frame
    end

    local frame = parentFrame

    -- Toolbar row at top: sourceDropdown + buttons
    -- Waypoint source dropdown (left side of toolbar)
    local sourceDropdown = CreateFrame("DropdownButton", "QRWaypointSourceDropdown", frame, "WowStyle1DropdownTemplate")
    sourceDropdown:SetPoint("TOPLEFT", PADDING + 5, -4)
    sourceDropdown:SetDefaultText(L["WAYPOINT_AUTO"])
    frame.sourceDropdown = sourceDropdown

    -- Calculate button widths based on localized text
    local refreshText = L["REFRESH"]
    local debugText = L["COPY_DEBUG"]
    local zoneText = L["ZONE_INFO"]

    local refreshWidth = CalculateButtonWidth(refreshText)
    local debugWidth = CalculateButtonWidth(debugText)
    local zoneWidth = CalculateButtonWidth(zoneText)

    -- Refresh button (right of dropdown in toolbar)
    local refreshButton = QR.CreateModernButton(frame, refreshWidth, BUTTON_HEIGHT)
    refreshButton:SetPoint("LEFT", sourceDropdown, "RIGHT", BUTTON_PADDING, 0)
    ApplyButtonStyle(refreshButton, refreshText, "refresh")
    refreshButton:SetScript("OnClick", function()
        local now = GetTime()
        if now - UI.lastRefreshClickTime < 1 then return end
        UI.lastRefreshClickTime = now
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:RefreshRoute()
    end)
    refreshButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOOLTIP_REFRESH"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    refreshButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.refreshButton = refreshButton

    -- Copy Debug button (right of refresh)
    local copyDebugButton = QR.CreateModernButton(frame, debugWidth, BUTTON_HEIGHT)
    copyDebugButton:SetPoint("LEFT", refreshButton, "RIGHT", BUTTON_PADDING, 0)
    ApplyButtonStyle(copyDebugButton, debugText, "debug")
    copyDebugButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:CopyDebugToClipboard()
    end)
    copyDebugButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOOLTIP_DEBUG"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    copyDebugButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.copyDebugButton = copyDebugButton

    -- Zone Debug button (right of debug)
    local zoneDebugButton = QR.CreateModernButton(frame, zoneWidth, BUTTON_HEIGHT)
    zoneDebugButton:SetPoint("LEFT", copyDebugButton, "RIGHT", BUTTON_PADDING, 0)
    ApplyButtonStyle(zoneDebugButton, zoneText, "zone")
    zoneDebugButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UI:CopyZoneDebugToClipboard()
    end)
    zoneDebugButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOOLTIP_ZONE"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    zoneDebugButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.zoneDebugButton = zoneDebugButton

    -- Separator line below toolbar
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", PADDING, -30)
    separator:SetPoint("TOPRIGHT", -PADDING, -30)

    -- Time estimate label below separator
    local timeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeLabel:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 5, -5)
    timeLabel:SetPoint("TOPRIGHT", separator, "BOTTOMRIGHT", -5, -5)
    timeLabel:SetJustifyH("LEFT")
    timeLabel:SetText(C.GRAY .. "--:--" .. C.R)
    frame.timeLabel = timeLabel

    -- Create scroll frame for steps (modern thin scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", "QuickRouteScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", -5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, PADDING)
    frame.scrollFrame = scrollFrame
    QR.SkinScrollBar(scrollFrame)

    -- Content frame inside scroll frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(FRAME_MIN_WIDTH - 50, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild

    self.frame = frame

    -- Initialize the waypoint source dropdown
    self:InitializeSourceDropdown()

    return frame
end

-------------------------------------------------------------------------------
-- Show/Hide/Toggle
-------------------------------------------------------------------------------

--- Show the UI (delegates to MainFrame)
function UI:Show()
    if QR.MainFrame then
        QR.MainFrame:Show("route")
    end
end

--- Hide the UI (delegates to MainFrame)
function UI:Hide()
    if QR.MainFrame then
        QR.MainFrame:Hide()
    end
end

--- Toggle the UI (delegates to MainFrame)
function UI:Toggle()
    if QR.MainFrame then
        QR.MainFrame:Toggle("route")
    end
end

-------------------------------------------------------------------------------
-- Route Display
-------------------------------------------------------------------------------

--- Refresh the route display by calculating path to current waypoint
function UI:RefreshRoute()
    if not self.frame then
        return
    end

    -- Re-entrancy guard: auto-waypoint triggers TomTom callback which re-enters here
    if self.isCalculating then
        return
    end

    -- Show calculating state
    self.isCalculating = true
    self.frame.timeLabel:SetText(C.YELLOW .. L["CALCULATING"] .. C.R)
    self.frame.refreshButton:SetText("...")

    QR:Log("INFO", "RefreshRoute started")

    -- First check if there's a waypoint at all
    local waypoint, waypointSource = nil, nil
    local wpSuccess, wpErr = pcall(function()
        waypoint, waypointSource = QR.WaypointIntegration:GetActiveWaypoint()
    end)

    if not wpSuccess then
        self.frame.timeLabel:SetText(C.ERROR_RED .. L["WAYPOINT_DETECTION_FAILED"] .. C.R)
        if QR.MainFrame and QR.MainFrame.subtitle and QR.MainFrame.activeTab == "route" then
            QR.MainFrame.subtitle:SetText(L["TAB_ROUTE"] or "Route")
        end
        QR:Error("Waypoint detection: " .. tostring(wpErr))
        self:ResetCalculatingState()
        return
    end

    if not waypoint then
        -- Fallback: try super-tracked quest directly
        if QR.WaypointIntegration and QR.WaypointIntegration.GetSuperTrackedWaypoint then
            local questWP = QR.WaypointIntegration:GetSuperTrackedWaypoint()
            if questWP then
                waypoint = questWP
                waypointSource = "quest"
            end
        end
        if not waypoint then
            self:ClearRoute()
            self:ResetCalculatingState()
            return
        end
    end

    -- We have a waypoint - show destination in subtitle
    local destName = waypoint.title or L["UNKNOWN"]
    local destZone = ""
    if waypoint.mapID then
        local mapInfo = C_Map.GetMapInfo(waypoint.mapID)
        if mapInfo then
            destZone = " (" .. mapInfo.name .. ")"
        end
    end

    -- Update MainFrame subtitle with destination
    if QR.MainFrame and QR.MainFrame.subtitle and QR.MainFrame.activeTab == "route" then
        QR.MainFrame.subtitle:SetText(destName .. destZone)
    end

    -- Now try to calculate path
    local success, errOrResult = pcall(function()
        return QR.WaypointIntegration:CalculatePathToWaypoint()
    end)

    if not success then
        -- Show error in UI
        self.frame.timeLabel:SetText(C.ERROR_RED .. L["PATH_CALCULATION_ERROR"] .. C.R)
        self:ClearStepLabels()
        self:ResetCalculatingState()
        QR:Error(tostring(errOrResult))
        return
    end

    local result = errOrResult
    if result then
        local updateOk, updateErr = pcall(function()
            self:UpdateRoute(result)
        end)
        if not updateOk then
            QR:Error("UpdateRoute error: " .. tostring(updateErr))
        end
        self.lastRefreshTime = GetTime()
        QR:Log("INFO", string_format("Route found: %d steps, %ds total",
            result.steps and #result.steps or 0, result.totalTime or 0))
    else
        -- Waypoint exists but no path found - give helpful feedback
        self.frame.timeLabel:SetText(C.WARN_ORANGE .. L["NO_PATH_FOUND"] .. "\n" .. C.GRAY .. L["NO_ROUTE_HINT"] .. C.R)
        self:ClearStepLabels()
        QR:Log("WARN", string_format("No route found to map %d", waypoint.mapID or 0))
    end

    self:ResetCalculatingState()
end

--- Reset the calculating state (button text and flag)
function UI:ResetCalculatingState()
    self.isCalculating = false
    if self.frame and self.frame.refreshButton then
        ApplyButtonStyle(self.frame.refreshButton, L["REFRESH"], "refresh")
    end
end

--- Initialize the waypoint source dropdown menu
function UI:InitializeSourceDropdown()
    if not self.frame or not self.frame.sourceDropdown then return end
    local dropdown = self.frame.sourceDropdown

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio(
            L["WAYPOINT_AUTO"],
            function() local c = QR.db and QR.db.selectedWaypointSource or "auto"; return c == "auto" or c == nil end,
            function()
                QR.db.selectedWaypointSource = "auto"
                UI:RefreshRoute()
            end,
            "auto"
        )

        local available = QR.WaypointIntegration:GetAllAvailableWaypoints()
        for _, entry in ipairs(available) do
            rootDescription:CreateRadio(
                entry.label,
                function() return QR.db and QR.db.selectedWaypointSource == entry.key end,
                function()
                    QR.db.selectedWaypointSource = entry.key
                    UI:RefreshRoute()
                end,
                entry.key
            )
        end

        if #available == 0 then
            local disabled = rootDescription:CreateButton(L["NO_WAYPOINTS_AVAILABLE"])
            disabled:SetEnabled(false)
        end
    end)
end

--- Determine the current step index based on player's current map zone
-- @param steps table The route steps
-- @return number The 1-based index of the current step
function UI:GetCurrentStepIndex(steps)
    if not steps or #steps == 0 then return 1 end
    local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not currentMapID then return 1 end

    -- Find the last step whose destMapID matches the player's current map.
    -- All steps up to and including that one are "completed".
    for i = #steps, 1, -1 do
        if steps[i].destMapID == currentMapID then
            return math_min(i + 1, #steps)
        end
    end

    -- No destMapID match: find the last step whose fromMapID matches (player is on that step's starting map)
    for i = #steps, 1, -1 do
        if steps[i].fromMapID == currentMapID then
            return i
        end
    end

    return 1
end

--- Update the route display with calculation result
-- @param result table The result from CalculatePathToWaypoint
function UI:UpdateRoute(result)
    if not self.frame then
        return
    end

    -- Clear combat disabled buttons tracking to prevent duplicates on refresh
    wipe(self.combatDisabledButtons)

    local waypoint = result.waypoint
    local steps = result.steps

    -- Update time label
    if result.totalTime then
        local timeStr = QR.CooldownTracker:FormatTime(result.totalTime)
        self.frame.timeLabel:SetText(C.GRAY .. string_format(L["ESTIMATED_TRAVEL_TIME"], timeStr) .. C.R)
    else
        self.frame.timeLabel:SetText(C.GRAY .. "--:--" .. C.R)
    end

    -- Clear existing step labels
    self:ClearStepLabels()

    -- Determine current step for progress highlighting
    local currentStepIndex = self:GetCurrentStepIndex(steps)

    -- Create step labels
    if steps and #steps > 0 then
        local yOffset = 0

        for i, step in ipairs(steps) do
            local status = (i < currentStepIndex) and "completed"
                or (i == currentStepIndex) and "current"
                or "upcoming"
            local stepFrame = self:CreateStepLabel(i, step, yOffset, status)
            table_insert(self.stepLabels, stepFrame)
            yOffset = yOffset + (stepFrame:GetHeight() or STEP_HEIGHT)
        end

        -- Update scroll child height
        self.frame.scrollChild:SetHeight(yOffset + PADDING)
    end

    -- Auto-set waypoint for current actionable step (opt-in, deferred to avoid re-entrant RefreshRoute)
    if QR.db and QR.db.autoWaypoint and result.steps and #result.steps > 0 then
        local stepIdx = self:GetCurrentStepIndex(result.steps)
        local activeStep = result.steps[stepIdx] or result.steps[1]
        local navMapID = activeStep.navMapID or activeStep.destMapID
        local navX = activeStep.navX or activeStep.destX
        local navY = activeStep.navY or activeStep.destY
        local navTitle = activeStep.navTitle or activeStep.to or "Next step"
        if navMapID and navX and navY then
            C_Timer.After(0, function()
                local ok, err = pcall(function()
                    QR.WaypointIntegration:SetTomTomWaypoint(navMapID, navX, navY, navTitle)
                end)
                if not ok then
                    QR:Warn("Auto-waypoint failed: " .. tostring(err))
                end
            end)
        end
    end

    -- Update dropdown text with active source
    if result.waypointSource and self.frame.sourceDropdown then
        local selected = QR.db and QR.db.selectedWaypointSource or "auto"
        if selected == "auto" or selected == nil then
            -- Show which source auto-selected
            local friendlySource = result.waypointSource
            if friendlySource == "mappin" then
                friendlySource = L["SOURCE_MAP_PIN"] or "Map Pin"
            elseif friendlySource == "tomtom" then
                friendlySource = "TomTom"
            elseif friendlySource == "quest" then
                friendlySource = L["SOURCE_QUEST"] or "Quest Objective"
            end
            SetDropdownText(self.frame.sourceDropdown,
                L["WAYPOINT_AUTO"] .. " (" .. friendlySource .. ")")
        end
    end
end

--- Build the action text for a route step, using localized names and cooldown info
-- @param step table The step data
-- @return string actionText The formatted action text
function UI:BuildStepActionText(step)
    local actionText = step.action or L["UNKNOWN"]
    if step.type == "teleport" and step.teleportID then
        local localizedName, link
        if step.sourceType == "spell" then
            localizedName, link = self:GetLocalizedSpellInfo(step.teleportID)
        else
            -- "item" or "toy" both use item API
            localizedName, link = self:GetLocalizedItemInfo(step.teleportID)
        end
        -- Use localized link if available (clickable), otherwise localized name, otherwise fallback to original action
        if link then
            actionText = string_format(L["ACTION_USE_TELEPORT"], link, step.to or L["UNKNOWN"])
        elseif localizedName then
            actionText = string_format(L["ACTION_USE_TELEPORT"], localizedName, step.to or L["UNKNOWN"])
        end
    end

    -- Add cooldown indication for teleport steps
    if step.type == "teleport" and step.teleportID and QR.CooldownTracker then
        local cdInfo = QR.CooldownTracker:GetCooldown(step.teleportID, step.sourceType)
        if cdInfo and cdInfo.remaining and cdInfo.remaining > 0 then
            local cdStr = QR.CooldownTracker:FormatTime(cdInfo.remaining)
            actionText = C.ERROR_RED .. actionText .. " (" .. L["COOLDOWN_SHORT"] .. ": " .. cdStr .. ")" .. C.R
        end
    end

    return actionText
end

--- Set up the Nav button for a step (creates or reuses, configures click/tooltip)
-- @param stepFrame Frame The step container frame
-- @param step table The step data
-- @return Button navButton The configured Nav button
function UI:SetupStepNavButton(stepFrame, step)
    -- Reuse or create Nav button for setting waypoint to step destination
    local navButton = stepFrame.navButton
    if not navButton then
        navButton = QR.CreateModernButton(stepFrame, 40, 18)
        navButton:SetPoint("RIGHT", stepFrame, "RIGHT", -5, 0)
        stepFrame.navButton = navButton
    end
    ApplyButtonStyle(navButton, L["NAV"], "nav")
    navButton.stepTo = step.navTitle or step.to  -- Store navigation title
    navButton.destMapID = step.navMapID or step.destMapID  -- Store nav coordinates (from node for portals)
    navButton.destX = step.navX or step.destX
    navButton.destY = step.navY or step.destY
    navButton:Show()

    navButton:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local success, err = pcall(function()
            local nodeName = self.stepTo
            if not nodeName then
                QR:Error(L["NO_DESTINATION"])
                return
            end

            -- First try to use the coordinates stored directly in the step
            local mapID = self.destMapID
            local x = self.destX or 0.5
            local y = self.destY or 0.5

            -- If no direct coordinates, try looking up in graph
            if not mapID then
                local nodeData = nil
                if QR.PathCalculator and QR.PathCalculator.graph and QR.PathCalculator.graph.nodes then
                    nodeData = QR.PathCalculator.graph.nodes[nodeName]
                end
                if nodeData then
                    mapID = nodeData.mapID
                    x = nodeData.x or 0.5
                    y = nodeData.y or 0.5
                end
            end

            if mapID then
                QR.WaypointIntegration:SetTomTomWaypoint(mapID, x, y, nodeName)
            else
                QR:Error(string_format(L["CANNOT_FIND_LOCATION"], nodeName))
            end
        end)
        if not success then
            QR:Error(tostring(err))
        end
    end)

    -- Tooltip for Nav button
    navButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOOLTIP_NAV"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    navButton:SetScript("OnLeave", GameTooltip_Hide)

    return navButton
end

--- Configure a secure "Use" button for a teleport step
-- @param stepFrame Frame The step container frame
-- @param step table The step data
-- @return Button|nil useButton The configured button, or nil if not applicable
function UI:ConfigureStepUseButton(stepFrame, step)
    -- Create "Use" secure button for teleport steps
    -- Must check InCombatLockdown BEFORE GetButton to avoid wasting pool slots
    if not (step.type == "teleport" and step.teleportID and QR.SecureButtons and not InCombatLockdown()) then
        return nil
    end

    local useButton = QR.SecureButtons:GetButton()
    if not useButton then
        return nil
    end

    -- Configure the secure button based on source type
    local configured = QR.SecureButtons:ConfigureButton(useButton, step.teleportID, step.sourceType)

    if not configured then
        -- Configuration failed (likely in combat), release button
        QR.SecureButtons:ReleaseButton(useButton)
        return nil
    end

    -- Overlay positioning: keep on UIParent, track stepFrame position
    -- Cannot use SetParent/SetPoint to anchor secure frames to non-secure frames (WoW 11.x restriction)
    useButton:SetFrameStrata("DIALOG")
    useButton:SetFrameLevel(100)
    useButton:SetSize(38, 22)
    QR.SecureButtons:AttachOverlay(useButton, stepFrame, nil, -48)

    -- Create button text
    if not useButton.text then
        useButton.text = useButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        useButton.text:SetPoint("CENTER")
    end
    useButton.text:SetText(L["USE"])

    -- Style the button with modern flat textures
    if not useButton.styled then
        if useButton.SetNormalTexture then
            useButton:SetNormalTexture("Interface\\Buttons\\WHITE8x8")
            local nt = useButton.GetNormalTexture and useButton:GetNormalTexture()
            if nt and nt.SetVertexColor then nt:SetVertexColor(0.12, 0.12, 0.15, 0.9) end
        end
        if useButton.SetHighlightTexture then
            useButton:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
            local ht = useButton.GetHighlightTexture and useButton:GetHighlightTexture()
            if ht and ht.SetVertexColor then ht:SetVertexColor(1, 1, 1, 0.08) end
        end
        if useButton.SetPushedTexture then
            useButton:SetPushedTexture("Interface\\Buttons\\WHITE8x8")
            local pt = useButton.GetPushedTexture and useButton:GetPushedTexture()
            if pt and pt.SetVertexColor then pt:SetVertexColor(0.08, 0.08, 0.1, 0.95) end
        end
        useButton.styled = true
    end

    -- Create icon texture showing the item/spell icon
    if not useButton.iconTexture then
        useButton.iconTexture = useButton:CreateTexture(nil, "OVERLAY")
        useButton.iconTexture:SetPoint("LEFT", useButton, "LEFT", 2, 0)
    end
    useButton.iconTexture:SetSize(20, 20)

    -- Get and set the icon
    local iconID = nil
    if step.sourceType == "spell" then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(step.teleportID)
        if spellInfo then
            iconID = spellInfo.iconID
        end
    else
        iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(step.teleportID)
            or GetItemIcon and GetItemIcon(step.teleportID)
    end
    if iconID then
        useButton.iconTexture:SetTexture(iconID)
        useButton.iconTexture:Show()
        -- Adjust text position to make room for icon
        useButton.text:SetPoint("CENTER", 8, 0)
    else
        useButton.iconTexture:Hide()
        useButton.text:SetPoint("CENTER", 0, 0)
    end

    -- Set initial button appearance (always active here;
    -- combat state is already checked at the top of this block)
    useButton:SetAlpha(1.0)
    useButton.text:SetTextColor(1, 0.82, 0)  -- Gold color

    -- Set up tooltip
    useButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.sourceType == "spell" then
            GameTooltip:SetSpellByID(self.teleportID)
        else
            GameTooltip:SetItemByID(self.teleportID)
            -- Suppress comparison tooltips for equipped items
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end
        if InCombatLockdown() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(C.ERROR_RED .. L["CANNOT_USE_IN_COMBAT"] .. C.R)
        end
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    useButton:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    useButton:Show()
    stepFrame.useButton = useButton

    return useButton
end

--- Create a label for a single step
-- @param index number The step index
-- @param step table The step data
-- @param yOffset number The vertical offset
-- @param status string "completed", "current", or "upcoming"
-- @return FontString The created label
function UI:CreateStepLabel(index, step, yOffset, status)
    local scrollChild = self.frame.scrollChild

    -- Get container frame for the step from pool (or create new)
    local stepFrame = self:GetStepLabelFrame()
    stepFrame:SetParent(scrollChild)
    stepFrame:SetSize(scrollChild:GetWidth(), STEP_HEIGHT)
    stepFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    stepFrame:Show()

    -- Store teleportID and sourceType in frame for tooltip access
    stepFrame.teleportID = step.teleportID
    stepFrame.sourceType = step.sourceType

    -- Get icon for step type
    local icon = STEP_ICONS[step.type] or STEP_ICONS.walk
    local timeStr = ""
    if step.time and QR.CooldownTracker then
        timeStr = " |cFF888888(" .. QR.CooldownTracker:FormatTime(step.time) .. ")|r"
    end

    -- Build action text with localized names and cooldown indication
    local actionText = self:BuildStepActionText(step)

    -- Set up Nav button for waypoint navigation
    local navButton = self:SetupStepNavButton(stepFrame, step)

    -- Configure secure "Use" button for teleport steps
    local useButton = self:ConfigureStepUseButton(stepFrame, step)

    -- Reuse or create the text label (shortened to make room for Nav button and Use button)
    local label = stepFrame.label
    if not label then
        label = stepFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", stepFrame, "LEFT", 5, 0)
        label:SetJustifyH("LEFT")
        stepFrame.label = label
    end

    -- Update label anchor based on button presence
    label:ClearAllPoints()
    label:SetPoint("LEFT", stepFrame, "LEFT", 5, 0)
    -- UseButton is an overlay on UIParent, so it doesn't take space in the layout
    label:SetPoint("RIGHT", navButton, "LEFT", -5, 0)
    label:SetWordWrap(true)

    -- Apply route progress styling
    local stepText = string_format("%d. %s %s%s", index, icon, actionText, timeStr)
    if status == "completed" then
        label:SetText(C.GRAY .. stepText .. C.R)
        stepFrame:SetAlpha(0.6)
    elseif status == "current" then
        label:SetText(C.LIGHT_BLUE .. ">" .. C.R .. " " .. stepText)
        stepFrame:SetAlpha(1.0)
    else
        label:SetText(stepText)
        stepFrame:SetAlpha(1.0)
    end
    label:Show()

    -- Dynamic height: grow the step frame if text wraps to multiple lines
    local textHeight = label:GetStringHeight()
    if textHeight then
        local actualHeight = math_max(STEP_HEIGHT, textHeight + 8)
        stepFrame:SetHeight(actualHeight)
    end

    -- Enable mouse for nav button clicks (tooltip is on the icon/use button only)
    stepFrame:EnableMouse(true)

    return stepFrame
end

--- Release a step label frame back to the pool
-- @param stepFrame Frame The step frame to release
function UI:ReleaseStepLabelFrame(stepFrame)
    if not stepFrame then return end

    -- Release secure button back to SecureButtons pool
    if stepFrame.useButton and QR.SecureButtons then
        QR.SecureButtons:ReleaseButton(stepFrame.useButton)
        stepFrame.useButton = nil
    end

    -- Hide child elements (but keep them for reuse)
    if stepFrame.label then stepFrame.label:Hide() end
    if stepFrame.navButton then
        stepFrame.navButton:Hide()
        stepFrame.navButton:SetScript("OnClick", nil)
        stepFrame.navButton:SetScript("OnEnter", nil)
        stepFrame.navButton:SetScript("OnLeave", nil)
    end

    -- Clear stored data
    stepFrame.teleportID = nil
    stepFrame.sourceType = nil

    -- Hide and unparent
    stepFrame:Hide()
    stepFrame:SetParent(recycleContainer)
    stepFrame:ClearAllPoints()

    -- Clear scripts to avoid stale references
    stepFrame:SetScript("OnEnter", nil)
    stepFrame:SetScript("OnLeave", nil)

    -- Add to pool
    table_insert(self.stepLabelPool, stepFrame)
end

--- Get a step label frame from the pool or create a new one
-- @return Frame A step label frame
function UI:GetStepLabelFrame()
    local stepFrame = table.remove(self.stepLabelPool)
    if not stepFrame then
        -- Create new frame if pool is empty
        stepFrame = CreateFrame("Frame", nil, nil)
        stepFrame:SetSize(1, STEP_HEIGHT)  -- Width set dynamically in CreateStepLabel
    end
    return stepFrame
end

--- Clear all step labels (releases frames to pool)
function UI:ClearStepLabels()
    for _, stepFrame in ipairs(self.stepLabels) do
        self:ReleaseStepLabelFrame(stepFrame)
    end
    wipe(self.stepLabels)
    wipe(self.combatDisabledButtons)
end

--- Clear the route display to default empty state
function UI:ClearRoute()
    if not self.frame then
        return
    end

    -- Hint text in body (timeLabel), not in subtitle
    self.frame.timeLabel:SetText(
        C.GRAY .. L["SET_WAYPOINT_HINT"] .. "\n" ..
        L["QUEST_TRACK_HINT"] .. "\n" ..
        L["MAP_BTN_CTRL_RIGHT"] .. C.R
    )

    -- Subtitle shows generic "Route" when no target
    if QR.MainFrame and QR.MainFrame.subtitle and QR.MainFrame.activeTab == "route" then
        QR.MainFrame.subtitle:SetText(L["TAB_ROUTE"] or "Route")
    end

    -- Reset dropdown text
    if self.frame.sourceDropdown then
        local selected = QR.db and QR.db.selectedWaypointSource or "auto"
        if selected == "auto" or selected == nil then
            SetDropdownText(self.frame.sourceDropdown, L["WAYPOINT_AUTO"])
        end
    end

    self:ClearStepLabels()
end

-------------------------------------------------------------------------------
-- Debug Copy Functionality
-------------------------------------------------------------------------------

--- Append player class/faction/map info to debug lines
-- @param lines table The lines table to append to
function UI:AppendPlayerDebugInfo(lines)
    table_insert(lines, "--- Player Info ---")
    local _, playerClass = UnitClass("player")
    local playerFaction = UnitFactionGroup("player")
    table_insert(lines, "Class: " .. tostring(playerClass))
    table_insert(lines, "Faction: " .. tostring(playerFaction))
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    table_insert(lines, "Current MapID: " .. tostring(playerMapID))
    local mapInfo = playerMapID and C_Map.GetMapInfo(playerMapID)
    if mapInfo then
        table_insert(lines, "Current Zone: " .. tostring(mapInfo.name))
    end
    table_insert(lines, "")
end

--- Append waypoint detection info to debug lines
-- @param lines table The lines table to append to
-- @return table|nil waypoint The active waypoint (for use by other debug sections)
function UI:AppendWaypointDebugInfo(lines)
    table_insert(lines, "--- Waypoint Detection ---")
    local hasUserWP = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
    table_insert(lines, "C_Map.HasUserWaypoint(): " .. tostring(hasUserWP))

    if hasUserWP then
        local point = C_Map.GetUserWaypoint()
        if point then
            table_insert(lines, "  uiMapID: " .. tostring(point.uiMapID))
            if point.position then
                table_insert(lines, string_format("  position: (%.4f, %.4f)", point.position.x or 0, point.position.y or 0))
            end
            -- Get destination zone name
            if point.uiMapID then
                local destMapInfo = C_Map.GetMapInfo(point.uiMapID)
                if destMapInfo then
                    table_insert(lines, "  Zone name: " .. tostring(destMapInfo.name))
                end
            end
        end
    end

    -- TomTom
    table_insert(lines, "TomTom loaded: " .. tostring(TomTom ~= nil))
    if TomTom then
        local uid = TomTom.GetClosestWaypoint and TomTom:GetClosestWaypoint()
        table_insert(lines, "  GetClosestWaypoint: " .. tostring(uid) .. " (type: " .. type(uid) .. ")")
    end

    -- Super-tracked quest
    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    table_insert(lines, "Super-tracked quest: " .. tostring(questID))

    -- Final waypoint result
    table_insert(lines, "")
    table_insert(lines, "--- Active Waypoint ---")
    local waypoint, source = QR.WaypointIntegration:GetActiveWaypoint()
    if waypoint then
        table_insert(lines, "Source: " .. tostring(source))
        table_insert(lines, "Title: " .. tostring(waypoint.title))
        table_insert(lines, "MapID: " .. tostring(waypoint.mapID))
        table_insert(lines, string_format("Position: (%.4f, %.4f)", waypoint.x or 0, waypoint.y or 0))
        local destMapInfo = C_Map.GetMapInfo(waypoint.mapID)
        if destMapInfo then
            table_insert(lines, "Destination Zone: " .. tostring(destMapInfo.name))
        end
    else
        table_insert(lines, "No waypoint detected")
    end

    return waypoint
end

--- Append available teleports listing to debug lines
-- @param lines table The lines table to append to
function UI:AppendTeleportDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Available Teleports (Detailed) ---")
    if QR.PlayerInventory then
        -- First, check data sources
        local dataCount = 0
        if QR.TeleportItemsData then
            for _ in pairs(QR.TeleportItemsData) do dataCount = dataCount + 1 end
        end
        table_insert(lines, "TeleportItemsData entries: " .. dataCount)

        local classSpellCount = 0
        if QR.ClassTeleportSpells then
            for _ in pairs(QR.ClassTeleportSpells) do classSpellCount = classSpellCount + 1 end
        end
        table_insert(lines, "ClassTeleportSpells entries: " .. classSpellCount)

        -- Count raw inventory
        local rawItems, rawToys, rawSpells = 0, 0, 0
        if QR.PlayerInventory.teleportItems then
            for _ in pairs(QR.PlayerInventory.teleportItems) do rawItems = rawItems + 1 end
        end
        if QR.PlayerInventory.toys then
            for _ in pairs(QR.PlayerInventory.toys) do rawToys = rawToys + 1 end
        end
        if QR.PlayerInventory.spells then
            for _ in pairs(QR.PlayerInventory.spells) do rawSpells = rawSpells + 1 end
        end
        table_insert(lines, string_format("Raw inventory: %d items, %d toys, %d spells", rawItems, rawToys, rawSpells))
        table_insert(lines, "")

        -- List all teleports with full details
        local teleports = QR.PlayerInventory:GetAllTeleports()
        local count = 0
        for id, entry in pairs(teleports) do
            count = count + 1
            local cdInfo = ""
            if QR.CooldownTracker then
                local cdData = QR.CooldownTracker:GetItemCooldown(id)
                if cdData and cdData.remaining and cdData.remaining > 0 then
                    cdInfo = " [CD: " .. QR.CooldownTracker:FormatTime(cdData.remaining) .. "]"
                else
                    cdInfo = " [READY]"
                end
            end
            -- entry.data contains the actual teleport info
            local teleportData = entry.data
            if teleportData then
                local name = teleportData.name or "nil"
                local dest = teleportData.destination or "nil"
                local destMap = teleportData.mapID
                local teleType = teleportData.type or "nil"
                table_insert(lines, string_format("  %d. ID=%s src=%s type=%s",
                    count, tostring(id), entry.sourceType or "?", tostring(teleType)))
                table_insert(lines, string_format("      name=%s dest=%s mapID=%s%s",
                    name, dest, tostring(destMap), cdInfo))
            else
                table_insert(lines, string_format("  %d. ID=%s src=%s DATA=NIL%s",
                    count, tostring(id), entry.sourceType or "?", cdInfo))
                -- Try to look up in data tables directly
                local directLookup = QR.TeleportItemsData and QR.TeleportItemsData[id]
                local spellLookup = QR.ClassTeleportSpells and QR.ClassTeleportSpells[id]
                if directLookup then
                    table_insert(lines, "      (Found in TeleportItemsData: " .. tostring(directLookup.name) .. ")")
                elseif spellLookup then
                    table_insert(lines, "      (Found in ClassTeleportSpells: " .. tostring(spellLookup.name) .. ")")
                else
                    table_insert(lines, "      (NOT found in any data table)")
                end
            end
        end
        table_insert(lines, "")
        table_insert(lines, "Total teleports: " .. count)
    else
        table_insert(lines, "PlayerInventory module not loaded")
    end
end

--- Append available portals info to debug lines
-- @param lines table The lines table to append to
function UI:AppendPortalDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Available Portals ---")
    if QR.GetAvailablePortals then
        local portals = QR:GetAvailablePortals()
        if portals.hubs then
            local hubCount = 0
            for hubName, hubData in pairs(portals.hubs) do
                hubCount = hubCount + 1
                table_insert(lines, string_format("  Hub: %s (MapID: %s) - %d portals",
                    hubName, tostring(hubData.mapID), #hubData.portals))
            end
            table_insert(lines, "Total hubs: " .. hubCount)
        end
        if portals.standalone then
            table_insert(lines, "Standalone portals: " .. #portals.standalone)
        end
    else
        table_insert(lines, "GetAvailablePortals not available")
    end
end

--- Append graph info and path calculation to debug lines
-- @param lines table The lines table to append to
-- @param waypoint table|nil The active waypoint
function UI:AppendPathDebugInfo(lines, waypoint)
    table_insert(lines, "")
    table_insert(lines, "--- Path Calculation ---")
    if waypoint then
        -- Read existing graph state (debug should be read-only, no rebuild)
        if QR.PathCalculator and not QR.PathCalculator.graph then
            table_insert(lines, "Graph not yet built (run Refresh to build)")
        end

        -- Try to calculate path
        if QR.PathCalculator then
            table_insert(lines, "Graph built: " .. tostring(QR.PathCalculator.graph ~= nil))

            if QR.PathCalculator.graph then
                -- Count nodes
                local nodeCount = 0
                for _ in pairs(QR.PathCalculator.graph.nodes or {}) do
                    nodeCount = nodeCount + 1
                end
                table_insert(lines, "Graph nodes: " .. nodeCount)

                -- Count edges and show same-map connections
                local edgeCount = 0
                local sameMapEdges = 0
                for fromNode, edges in pairs(QR.PathCalculator.graph.edges or {}) do
                    for toNode, edge in pairs(edges) do
                        edgeCount = edgeCount + 1
                        if edge.data and edge.data.autoConnected then
                            sameMapEdges = sameMapEdges + 1
                        end
                    end
                end
                table_insert(lines, "Graph edges: " .. edgeCount .. " (same-map auto: " .. sameMapEdges .. ")")

                -- Show nodes on destination map and Stormwind (84) for debugging path
                table_insert(lines, "")
                table_insert(lines, "Nodes on key maps:")
                local keyMaps = {84, 371, waypoint.mapID}  -- Stormwind, Jade Forest, destination
                for _, checkMapID in ipairs(keyMaps) do
                    local nodesOnMap = {}
                    for nodeName, nodeData in pairs(QR.PathCalculator.graph.nodes) do
                        if nodeData.mapID == checkMapID then
                            table_insert(nodesOnMap, nodeName)
                        end
                    end
                    local mapInfo = C_Map.GetMapInfo(checkMapID)
                    table_insert(lines, string_format("  MapID %d (%s): %d nodes",
                        checkMapID, mapInfo and mapInfo.name or "?", #nodesOnMap))
                    for _, name in ipairs(nodesOnMap) do
                        table_insert(lines, "    - " .. name)
                    end
                end
            end

            table_insert(lines, "")
            local success, result = pcall(function()
                return QR.PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y)
            end)

            if not success then
                table_insert(lines, "ERROR calculating path: " .. tostring(result))
            elseif result then
                table_insert(lines, "Path found!")
                table_insert(lines, "Total time: " .. (QR.CooldownTracker and QR.CooldownTracker:FormatTime(result.totalTime) or tostring(result.totalTime)))
                table_insert(lines, "Steps: " .. (result.steps and #result.steps or 0))
                if result.steps then
                    for i, step in ipairs(result.steps) do
                        local timeStr = step.time and QR.CooldownTracker and QR.CooldownTracker:FormatTime(step.time) or "?"
                        table_insert(lines, string_format("  %d. [%s] %s (%s)",
                            i, step.type or "?", step.action or "?", timeStr))
                    end
                end
            else
                table_insert(lines, "No path found (result is nil)")
                table_insert(lines, "Reason: Destination may not be reachable with current teleports")
            end
        else
            table_insert(lines, "PathCalculator module not loaded")
        end
    else
        table_insert(lines, "Skipped - no waypoint to calculate path to")
    end
end

--- Append cooldown status to debug lines
-- @param lines table The lines table to append to
function UI:AppendCooldownDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Cooldown Status ---")
    if QR.CooldownTracker then
        local ready = QR.CooldownTracker:GetReadyTeleports()
        local readyCount = 0
        for _ in pairs(ready) do readyCount = readyCount + 1 end
        table_insert(lines, "Ready teleports: " .. readyCount)
    else
        table_insert(lines, "CooldownTracker not loaded")
    end
end

--- Append zone adjacency info to debug lines
-- @param lines table The lines table to append to
-- @param waypoint table|nil The active waypoint
function UI:AppendZoneDebugInfo(lines, waypoint)
    table_insert(lines, "")
    table_insert(lines, "--- Zone Adjacency Info ---")
    table_insert(lines, "QR.Continents: " .. tostring(QR.Continents ~= nil))
    table_insert(lines, "QR.ZoneToContinent: " .. tostring(QR.ZoneToContinent ~= nil))
    table_insert(lines, "QR.ZoneAdjacencies: " .. tostring(QR.ZoneAdjacencies ~= nil))

    if waypoint and waypoint.mapID then
        local destContinent = QR.GetContinentForZone and QR.GetContinentForZone(waypoint.mapID)
        table_insert(lines, "Destination continent: " .. tostring(destContinent))

        if destContinent and QR.Continents and QR.Continents[destContinent] then
            local contData = QR.Continents[destContinent]
            table_insert(lines, "  Continent name: " .. tostring(contData.name))
            table_insert(lines, "  Hub mapID: " .. tostring(contData.hub))
        end

        -- Adjacent zones for destination
        local adjacent = QR.GetAdjacentZones and QR.GetAdjacentZones(waypoint.mapID) or {}
        table_insert(lines, "Adjacent zones to destination: " .. #adjacent)
        for i, adj in ipairs(adjacent) do
            if i <= 5 then
                table_insert(lines, string_format("  -> MapID %d (%ds travel)", adj.zone, adj.travelTime))
            end
        end

        -- Nodes on same continent in graph
        if QR.PathCalculator and QR.PathCalculator.graph then
            local sameContinent = {}
            for nodeName, nodeData in pairs(QR.PathCalculator.graph.nodes) do
                if nodeData.mapID then
                    local nodeContinent = QR.GetContinentForZone and QR.GetContinentForZone(nodeData.mapID)
                    if nodeContinent == destContinent then
                        table_insert(sameContinent, string_format("%s (map %d)", nodeName, nodeData.mapID))
                    end
                end
            end
            table_insert(lines, "Graph nodes on destination continent: " .. #sameContinent)
            for i, name in ipairs(sameContinent) do
                if i <= 8 then
                    table_insert(lines, "  - " .. name)
                end
            end
            if #sameContinent > 8 then
                table_insert(lines, "  ... and " .. (#sameContinent - 8) .. " more")
            end
        end
    end
end

--- Append module status to debug lines
-- @param lines table The lines table to append to
function UI:AppendModuleDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Module Status ---")
    table_insert(lines, "QR.Graph: " .. tostring(QR.Graph ~= nil))
    table_insert(lines, "QR.PathCalculator: " .. tostring(QR.PathCalculator ~= nil))
    table_insert(lines, "QR.PlayerInventory: " .. tostring(QR.PlayerInventory ~= nil))
    table_insert(lines, "QR.CooldownTracker: " .. tostring(QR.CooldownTracker ~= nil))
    table_insert(lines, "QR.WaypointIntegration: " .. tostring(QR.WaypointIntegration ~= nil))
    table_insert(lines, "QR.SecureButtons: " .. tostring(QR.SecureButtons ~= nil))
    table_insert(lines, "QR.TeleportPanel: " .. tostring(QR.TeleportPanel ~= nil))
    table_insert(lines, "QR.UI: " .. tostring(QR.UI ~= nil))
    table_insert(lines, "QR.TeleportItemsData: " .. tostring(QR.TeleportItemsData ~= nil))
    table_insert(lines, "QR.ClassTeleportSpells: " .. tostring(QR.ClassTeleportSpells ~= nil))
    table_insert(lines, "QR.MageTeleports: " .. tostring(QR.MageTeleports ~= nil))
    table_insert(lines, "QR.PortalHubs: " .. tostring(QR.PortalHubs ~= nil))
    table_insert(lines, "QR.GetContinentForZone: " .. tostring(QR.GetContinentForZone ~= nil))
    table_insert(lines, "QR.GetAdjacentZones: " .. tostring(QR.GetAdjacentZones ~= nil))
end

--- Append WoW API availability to debug lines
-- @param lines table The lines table to append to
function UI:AppendAPIDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- WoW API Availability ---")
    table_insert(lines, "C_Map.GetBestMapForUnit: " .. tostring(C_Map and C_Map.GetBestMapForUnit ~= nil))
    table_insert(lines, "C_Map.GetMapInfo: " .. tostring(C_Map and C_Map.GetMapInfo ~= nil))
    table_insert(lines, "C_Map.HasUserWaypoint: " .. tostring(C_Map and C_Map.HasUserWaypoint ~= nil))
    table_insert(lines, "C_Map.GetUserWaypoint: " .. tostring(C_Map and C_Map.GetUserWaypoint ~= nil))
    table_insert(lines, "C_Map.SetUserWaypoint: " .. tostring(C_Map and C_Map.SetUserWaypoint ~= nil))
    table_insert(lines, "UiMapPoint.CreateFromCoordinates: " .. tostring(UiMapPoint and UiMapPoint.CreateFromCoordinates ~= nil))
    table_insert(lines, "C_SuperTrack.GetSuperTrackedQuestID: " .. tostring(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID ~= nil))
    table_insert(lines, "C_SuperTrack.SetSuperTrackedUserWaypoint: " .. tostring(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint ~= nil))
    table_insert(lines, "C_QuestLog.GetNextWaypointForMap: " .. tostring(C_QuestLog and C_QuestLog.GetNextWaypointForMap ~= nil))
    table_insert(lines, "C_QuestLog.GetQuestsOnMap: " .. tostring(C_QuestLog and C_QuestLog.GetQuestsOnMap ~= nil))
    table_insert(lines, "C_QuestLog.GetTitleForQuestID: " .. tostring(C_QuestLog and C_QuestLog.GetTitleForQuestID ~= nil))
    table_insert(lines, "C_Spell.GetSpellInfo: " .. tostring(C_Spell and C_Spell.GetSpellInfo ~= nil))
    table_insert(lines, "GetSpellLink: " .. tostring(GetSpellLink ~= nil))
    table_insert(lines, "GetItemInfo: " .. tostring(GetItemInfo ~= nil))
    table_insert(lines, "PlayerHasToy: " .. tostring(PlayerHasToy ~= nil))
    table_insert(lines, "IsSpellKnown: " .. tostring(IsSpellKnown ~= nil))
    table_insert(lines, "InCombatLockdown: " .. tostring(InCombatLockdown ~= nil))
end

--- Append SecureButtons pool status to debug lines
-- @param lines table The lines table to append to
function UI:AppendSecureButtonDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- SecureButtons Status ---")
    if QR.SecureButtons then
        local inUse = 0
        local total = #(QR.SecureButtons.pool or {})
        for _, btn in ipairs(QR.SecureButtons.pool or {}) do
            if btn.inUse then inUse = inUse + 1 end
        end
        table_insert(lines, "Pool size: " .. total)
        table_insert(lines, "In use: " .. inUse)
        table_insert(lines, "Available: " .. (total - inUse))
        table_insert(lines, "InCombatLockdown: " .. tostring(InCombatLockdown()))
    else
        table_insert(lines, "SecureButtons module not loaded")
    end
end

--- Append TeleportPanel status to debug lines
-- @param lines table The lines table to append to
function UI:AppendPanelDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- TeleportPanel Status ---")
    if QR.TeleportPanel then
        table_insert(lines, "Frame exists: " .. tostring(QR.TeleportPanel.frame ~= nil))
        table_insert(lines, "isShowing: " .. tostring(QR.TeleportPanel.isShowing))
        table_insert(lines, "currentFilter: " .. tostring(QR.TeleportPanel.currentFilter))
        table_insert(lines, "Row pool size: " .. #(QR.TeleportPanel.rowPool or {}))
        table_insert(lines, "Sorted teleports: " .. #(QR.TeleportPanel.sortedTeleports or {}))
    else
        table_insert(lines, "TeleportPanel module not loaded")
    end
end

--- Append localization check to debug lines
-- @param lines table The lines table to append to
function UI:AppendLocalizationCheckDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Localization ---")
    table_insert(lines, "GetLocale(): " .. tostring(GetLocale()))
    table_insert(lines, "QR.L exists: " .. tostring(QR.L ~= nil))
    if QR.L then
        table_insert(lines, "L['REFRESH']: " .. tostring(QR.L["REFRESH"]))
        table_insert(lines, "L['INVENTORY']: " .. tostring(QR.L["INVENTORY"]))
    end

    -- Combat button tracking
    if self.combatDisabledButtons then
        table_insert(lines, "")
        table_insert(lines, "--- Combat Button Tracking ---")
        local combatCount = 0
        for _ in pairs(self.combatDisabledButtons) do combatCount = combatCount + 1 end
        table_insert(lines, "Buttons disabled in combat: " .. combatCount)
    end
end

--- Append cache status to debug lines
-- @param lines table The lines table to append to
function UI:AppendCacheDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Cache Status ---")
    local itemCacheCount = 0
    for _ in pairs(self.itemInfoCache or {}) do itemCacheCount = itemCacheCount + 1 end
    local spellCacheCount = 0
    for _ in pairs(self.spellInfoCache or {}) do spellCacheCount = spellCacheCount + 1 end
    table_insert(lines, "Item info cache: " .. itemCacheCount .. " / " .. CACHE_MAX_SIZE)
    table_insert(lines, "Spell info cache: " .. spellCacheCount .. " / " .. CACHE_MAX_SIZE)
end

--- Append debug log entries to debug lines
-- @param lines table The lines table to append to
function UI:AppendLogDebugInfo(lines)
    table_insert(lines, "")
    table_insert(lines, "--- Debug Log (recent) ---")
    local logEntries = QR.GetLogEntries and QR:GetLogEntries() or {}
    if #logEntries > 0 then
        -- Show last 50 entries
        local startIdx = math_max(1, #logEntries - 49)
        for i = startIdx, #logEntries do
            local entry = logEntries[i]
            table_insert(lines, string_format("[%s] [%s] %s",
                entry.time or "?", entry.level or "?", entry.msg or ""))
        end
    else
        table_insert(lines, "(no log entries)")
    end
end

--- Generate debug info string
function UI:GenerateDebugInfo()
    local lines = {}
    table_insert(lines, "=== QuickRoute Debug Info ===")
    table_insert(lines, "Version: " .. (QR.version or "1.0.0"))
    table_insert(lines, "Interface: " .. tostring(select(4, GetBuildInfo())))
    table_insert(lines, "Date: " .. date("%Y-%m-%d %H:%M:%S"))
    table_insert(lines, "")

    self:AppendPlayerDebugInfo(lines)
    local waypoint = self:AppendWaypointDebugInfo(lines)
    self:AppendTeleportDebugInfo(lines)
    self:AppendPortalDebugInfo(lines)
    self:AppendPathDebugInfo(lines, waypoint)
    self:AppendCooldownDebugInfo(lines)
    self:AppendZoneDebugInfo(lines, waypoint)
    self:AppendModuleDebugInfo(lines)
    self:AppendAPIDebugInfo(lines)
    self:AppendSecureButtonDebugInfo(lines)
    self:AppendPanelDebugInfo(lines)
    self:AppendLocalizationCheckDebugInfo(lines)
    self:AppendCacheDebugInfo(lines)
    self:AppendLogDebugInfo(lines)

    table_insert(lines, "")
    table_insert(lines, "=== End Debug Info ===")

    -- Append zone debug info
    table_insert(lines, "")
    local zoneSuccess, zoneInfo = pcall(function()
        return self:GenerateZoneDebugInfo()
    end)
    if zoneSuccess and zoneInfo then
        table_insert(lines, zoneInfo)
    else
        table_insert(lines, "ERROR generating zone debug: " .. tostring(zoneInfo))
    end

    return table_concat(lines, "\n")
end

--- Copy debug info to clipboard via EditBox popup
function UI:CopyDebugToClipboard()
    local success, debugInfo = pcall(function()
        return self:GenerateDebugInfo()
    end)

    if not success then
        debugInfo = "ERROR generating debug info:\n" .. tostring(debugInfo)
        QR:Error(tostring(debugInfo))
    end

    -- Create or reuse popup frame
    if not self.copyFrame then
        local f = CreateFrame("Frame", "QuickRouteCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(450, 350)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
        if QR.AddBrandAccent then QR.AddBrandAccent(f, 1) end
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("DIALOG")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText(L["COPY_DEBUG_TITLE"])

        local scrollFrame = CreateFrame("ScrollFrame", "QRCopyScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 15, -40)
        scrollFrame:SetPoint("BOTTOMRIGHT", -25, 45)
        QR.SkinScrollBar(scrollFrame)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(380)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        f.editBox = editBox

        local closeBtn = QR.CreateModernButton(f, 80, 22)
        closeBtn:SetPoint("BOTTOM", 0, 12)
        closeBtn:SetText(L["CLOSE"])
        closeBtn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
            f:Hide()
        end)

        table_insert(UISpecialFrames, "QuickRouteCopyFrame")
        self.copyFrame = f
    end

    self.copyFrame.editBox:SetText(debugInfo)
    self.copyFrame:Show()
    self.copyFrame.editBox:HighlightText()
    self.copyFrame.editBox:SetFocus()
end

--- Generate zone-specific debug info for pathfinding
-- @return string Debug info text
function UI:GenerateZoneDebugInfo()
    local lines = {}
    table_insert(lines, "=== QuickRoute Zone/Path Debug ===")
    table_insert(lines, "Date: " .. date("%Y-%m-%d %H:%M:%S"))
    table_insert(lines, "")

    -- Get waypoint
    local waypoint = QR.WaypointIntegration and QR.WaypointIntegration:GetActiveWaypoint()
    local destMapID = waypoint and waypoint.mapID

    if not destMapID then
        table_insert(lines, "No waypoint set - using current map")
        destMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end

    local mapInfo = destMapID and C_Map.GetMapInfo(destMapID)
    table_insert(lines, string_format("Target MapID: %d (%s)", destMapID or 0, mapInfo and mapInfo.name or "unknown"))
    table_insert(lines, "")

    -- Zone Adjacency Data Check
    table_insert(lines, "--- Zone Adjacency Data ---")
    table_insert(lines, "QR.Continents loaded: " .. tostring(QR.Continents ~= nil))
    table_insert(lines, "QR.ZoneToContinent loaded: " .. tostring(QR.ZoneToContinent ~= nil))
    table_insert(lines, "QR.ZoneAdjacencies loaded: " .. tostring(QR.ZoneAdjacencies ~= nil))
    table_insert(lines, "QR.GetContinentForZone: " .. tostring(type(QR.GetContinentForZone)))
    table_insert(lines, "QR.GetAdjacentZones: " .. tostring(type(QR.GetAdjacentZones)))
    table_insert(lines, "")

    -- Continent info for target
    table_insert(lines, "--- Target Zone Continent ---")
    local continent = QR.GetContinentForZone and QR.GetContinentForZone(destMapID)
    table_insert(lines, "Continent key: " .. tostring(continent))

    if continent and QR.Continents and QR.Continents[continent] then
        local contData = QR.Continents[continent]
        table_insert(lines, "Continent name: " .. tostring(contData.name))
        table_insert(lines, "Hub mapID: " .. tostring(contData.hub))
        table_insert(lines, "Zone count: " .. (contData.zones and #contData.zones or 0))
    else
        table_insert(lines, "ERROR: Continent data not found for this mapID!")
        -- Try to find if mapID exists in any continent
        if QR.Continents then
            for contKey, contData in pairs(QR.Continents) do
                for _, zoneID in ipairs(contData.zones or {}) do
                    if zoneID == destMapID then
                        table_insert(lines, "  Found in continent: " .. contKey .. " but lookup failed!")
                    end
                end
            end
        end
    end
    table_insert(lines, "")

    -- Adjacent zones
    table_insert(lines, "--- Adjacent Zones ---")
    local adjacent = QR.GetAdjacentZones and QR.GetAdjacentZones(destMapID) or {}
    table_insert(lines, "Count: " .. #adjacent)
    for _, adj in ipairs(adjacent) do
        local adjMapInfo = C_Map.GetMapInfo(adj.zone)
        table_insert(lines, string_format("  MapID %d (%s) - %ds travel",
            adj.zone, adjMapInfo and adjMapInfo.name or "?", adj.travelTime))
    end
    if #adjacent == 0 then
        table_insert(lines, "  (none defined - check ZoneAdjacencies table)")
    end
    table_insert(lines, "")

    -- Graph nodes on same continent
    table_insert(lines, "--- Graph Nodes on Same Continent ---")
    if QR.PathCalculator then
        if not QR.PathCalculator.graph then
            table_insert(lines, "Graph not built yet - run Refresh to build")
        end

        local sameContinent = {}
        local adjacentNodeFound = false
        for nodeName, nodeData in pairs(QR.PathCalculator.graph.nodes or {}) do
            if nodeData.mapID then
                local nodeContinent = QR.GetContinentForZone and QR.GetContinentForZone(nodeData.mapID)
                if nodeContinent == continent then
                    local adjInfo = ""
                    -- Check if this node is in an adjacent zone
                    for _, adj in ipairs(adjacent) do
                        if nodeData.mapID == adj.zone then
                            adjInfo = " [ADJACENT - should connect!]"
                            adjacentNodeFound = true
                        end
                    end
                    table_insert(sameContinent, string_format("%s (map %d)%s", nodeName, nodeData.mapID, adjInfo))
                end
            end
        end
        table_insert(lines, "Total: " .. #sameContinent)
        for _, name in ipairs(sameContinent) do
            table_insert(lines, "  - " .. name)
        end

        if not adjacentNodeFound and #adjacent > 0 then
            table_insert(lines, "")
            table_insert(lines, "WARNING: No graph nodes in adjacent zones!")
            table_insert(lines, "This means destination cannot be connected via adjacency.")
        end
    else
        table_insert(lines, "PathCalculator not loaded")
    end
    table_insert(lines, "")

    -- Test path calculation
    table_insert(lines, "--- Path Calculation Test ---")
    if waypoint and QR.PathCalculator then
        local oldDebug = QR.debugMode
        local oldGraphDirty = QR.PathCalculator.graphDirty
        QR.debugMode = true
        QR.PathCalculator.graphDirty = true

        local success, result = pcall(function()
            return QR.PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y)
        end)

        QR.debugMode = oldDebug
        QR.PathCalculator.graphDirty = oldGraphDirty

        if not success then
            table_insert(lines, "ERROR: " .. tostring(result))
        elseif result then
            table_insert(lines, "SUCCESS! Path found.")
            table_insert(lines, "Total time: " .. tostring(result.totalTime) .. "s")
            table_insert(lines, "Steps:")
            for i, step in ipairs(result.steps or {}) do
                table_insert(lines, string_format("  %d. [%s] %s", i, step.type or "?", step.action or "?"))
            end
        else
            table_insert(lines, "FAILED: No path found (result is nil)")
            table_insert(lines, "")
            table_insert(lines, "Possible reasons:")
            table_insert(lines, "  - No portal goes to this continent")
            table_insert(lines, "  - No nodes in adjacent zones to connect to")
            table_insert(lines, "  - ZoneAdjacency data missing for this zone")
        end
    else
        table_insert(lines, "Skipped - no waypoint or PathCalculator")
    end

    table_insert(lines, "")
    table_insert(lines, "=== End Zone Debug ===")

    return table_concat(lines, "\n")
end

--- Copy zone debug info to clipboard
function UI:CopyZoneDebugToClipboard()
    local success, debugInfo = pcall(function()
        return self:GenerateZoneDebugInfo()
    end)

    if not success then
        debugInfo = "ERROR generating zone debug info:\n" .. tostring(debugInfo)
    end

    -- Reuse the same copy frame
    if not self.copyFrame then
        self:CopyDebugToClipboard()  -- This creates the frame
        self.copyFrame:Hide()
    end

    self.copyFrame.editBox:SetText(debugInfo)
    self.copyFrame:Show()
    self.copyFrame.editBox:HighlightText()
    self.copyFrame.editBox:SetFocus()
end

-------------------------------------------------------------------------------
-- Combat State Handling
-------------------------------------------------------------------------------

--- Called when combat ends (PLAYER_REGEN_ENABLED)
-- Re-enables any Use buttons that were disabled during combat
function UI:OnCombatEnd()
    for _, btn in ipairs(self.combatDisabledButtons) do
        if btn and btn.SetAlpha then
            btn:SetAlpha(1.0)
            if btn.text then
                btn.text:SetTextColor(1, 0.82, 0)  -- Gold color
            end
        end
    end
    wipe(self.combatDisabledButtons)
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the UI module
function UI:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

    -- Create content inside MainFrame's route content area
    if QR.MainFrame then
        local contentFrame = QR.MainFrame:GetContentFrame("route")
        if contentFrame then
            self:CreateContent(contentFrame)
        end
    end

    -- Re-initialize dropdown (QR.db may not have been available during CreateContent)
    self:InitializeSourceDropdown()

    -- Combat callback: re-enable Use buttons when combat ends
    QR:RegisterCombatCallback(
        nil,  -- enter combat handled by MainFrame
        function()  -- leave combat
            UI:OnCombatEnd()
        end
    )

    -- Event frame for zone-change auto-refresh (non-combat events)
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "ZONE_CHANGED_NEW_AREA" then
            if QR.MainFrame and QR.MainFrame.isShowing
                and QR.MainFrame.activeTab == "route"
                and not UI.isCalculating and not InCombatLockdown() then
                UI:RefreshRoute()
            end
        end
    end)

    QR:Debug("UI initialized")
end

-------------------------------------------------------------------------------
-- Slash Commands
-------------------------------------------------------------------------------

SLASH_QR1 = "/qr"
SLASH_QR2 = "/quickroute"
SlashCmdList["QR"] = function(msg)
    local cmd = msg and msg:lower():trim() or ""

    if not QR.db then QR:Error("Not initialized yet"); return end

    if cmd == "show" then
        if QR.MainFrame then QR.MainFrame:Show("route") end
    elseif cmd == "hide" then
        if QR.MainFrame then QR.MainFrame:Hide() end
    elseif cmd == "debug" then
        QR.debugMode = not QR.debugMode
        print("|cFF00FF00QuickRoute|r: Debug mode " .. (QR.debugMode and "enabled" or "disabled"))
    elseif cmd:match("^priority") then
        local newPriority = msg:lower():match("priority%s+(%S+)")
        if newPriority and (newPriority == "mappin" or newPriority == "quest" or newPriority == "tomtom") then
            QR.db.waypointPriority = newPriority
            print("|cFF00FF00QuickRoute|r: Waypoint priority set to '" .. newPriority .. "'")
            -- Refresh the UI if showing
            if QR.MainFrame and QR.MainFrame.isShowing and QR.MainFrame.activeTab == "route" then
                UI:RefreshRoute()
            end
        else
            print("|cFF00FF00QuickRoute|r: Usage: /qr priority mappin|quest|tomtom")
            print("  Current priority: " .. (QR.db and QR.db.waypointPriority or "mappin"))
        end
    elseif cmd == "autowaypoint" or cmd == "autowp" then
        QR.db.autoWaypoint = not QR.db.autoWaypoint
        print("|cFF00FF00QuickRoute|r: " .. L["AUTO_WAYPOINT_TOGGLE"]
            .. (QR.db.autoWaypoint and L["AUTO_WAYPOINT_ON"] or L["AUTO_WAYPOINT_OFF"]))
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        if QR.SettingsPanel then
            QR.SettingsPanel:Open()
        end
    elseif cmd == "minimap" then
        QR.db.showMinimap = not QR.db.showMinimap
        if QR.MinimapButton then
            QR.MinimapButton:ApplyVisibility()
        end
        print("|cFF00FF00QuickRoute|r: Minimap button " .. (QR.db.showMinimap and "shown" or "hidden"))
    elseif cmd == "" then
        if QR.MainFrame then QR.MainFrame:Toggle("route") end
    else
        -- Show help
        print("|cFF00FF00QuickRoute|r commands:")
        print("  /qr - Toggle route window")
        print("  /qr show - Show route window")
        print("  /qr hide - Hide route window")
        print("  /qr settings - Open settings panel")
        print("  /qr minimap - Toggle minimap button")
        print("  /qr debug - Toggle debug mode")
        print("  /qr priority mappin|quest|tomtom - Set waypoint source priority")
        print("  /qr autowaypoint - Toggle auto-waypoint for first route step")
    end
end
