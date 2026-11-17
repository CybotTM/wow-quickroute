-------------------------------------------------------------------------------
-- RouteTracker.lua
-- The compact view of a route (design F of 2026-11-17): a small block on the
-- screen, like Blizzard's objective tracker, with the current step, its one
-- action and the steps ahead grouped by continent. "Window" switches back to
-- the full route window. The block keeps its own position, apart from the
-- window's.
-------------------------------------------------------------------------------

local ADDON_NAME, QR = ...

local string_format = string.format
local table_insert = table.insert

local RouteTracker = {
    isShowing = false,
    lines = {},      -- FontStrings on screen
    linePool = {},
}
QR.RouteTracker = RouteTracker

local L
local C = QR.Colors

local WIDTH = 270
local PADDING = 8
local LINE_GAP = 3
local ACTION_SIZE = 28
local MAX_AHEAD = 5          -- steps listed after the current one
local NAV_ICON_PATH = "Interface\\Icons\\INV_Misc_Map_01"

local MODE_WINDOW, MODE_COMPACT = "window", "compact"
RouteTracker.MODE_WINDOW, RouteTracker.MODE_COMPACT = MODE_WINDOW, MODE_COMPACT

-------------------------------------------------------------------------------
-- Mode
-------------------------------------------------------------------------------

--- Which view a route request opens: the window or this tracker.
-- @return string "window" or "compact"
function RouteTracker:GetMode()
    return QR.db and QR.db.routeViewMode == MODE_COMPACT and MODE_COMPACT or MODE_WINDOW
end

--- Switch to the tracker: the window closes, the tracker shows the route.
function RouteTracker:SwitchToCompact()
    if QR.db then QR.db.routeViewMode = MODE_COMPACT end
    if QR.MainFrame and QR.MainFrame.isShowing then QR.MainFrame:Hide("switch-compact") end
    self:Show()
    if QR.UI and QR.UI.displayedResult then
        self:Update(QR.UI.displayedResult)
    end
end

--- Switch to the window: the tracker closes, the window opens on the route.
function RouteTracker:SwitchToWindow()
    if QR.db then QR.db.routeViewMode = MODE_WINDOW end
    self:Hide()
    if QR.MainFrame then QR.MainFrame:Show("route", "switch-window") end
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------

local function SavePosition(frame)
    if not QR.db then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    QR.db.trackerPoint, QR.db.trackerRelPoint, QR.db.trackerX, QR.db.trackerY = point, relPoint, x, y
end

local function SmallButton(parent, text, width)
    local button = QR.CreateModernButton(parent, width, 20)
    button:SetText(text)
    return button
end

--- Build the tracker frame once.
function RouteTracker:CreateFrame()
    if self.frame then return self.frame end
    L = QR.L

    local frame = CreateFrame("Frame", "QuickRouteTracker", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 80)
    frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    frame:SetBackdropColor(0, 0, 0, 0.35)
    local db = QR.db or {}
    if QR.IsValidWindowPosition(db.trackerPoint, db.trackerRelPoint, db.trackerX, db.trackerY) then
        frame:SetPoint(db.trackerPoint, UIParent, db.trackerRelPoint, db.trackerX, db.trackerY)
    else
        -- Below the minimap, where the objective tracker starts.
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -260)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    title:SetJustifyH("LEFT")
    frame.title = title

    local closeButton = SmallButton(frame, "x", 20)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        RouteTracker:Hide()
    end)
    closeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TRACKER_CLOSE_TT"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    closeButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.closeButton = closeButton

    local windowButton = SmallButton(frame, L["TRACKER_WINDOW"], (#L["TRACKER_WINDOW"] * 7) + 16)
    windowButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    windowButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        RouteTracker:SwitchToWindow()
    end)
    windowButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TRACKER_WINDOW_TT"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    windowButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.windowButton = windowButton
    title:SetPoint("RIGHT", windowButton, "LEFT", -4, 0)

    -- The one action of the current step: the map pin, or for a teleport the
    -- secure overlay of its item or spell on top of it.
    local action = CreateFrame("Button", nil, frame)
    action:SetSize(ACTION_SIZE, ACTION_SIZE)
    action.icon = action:CreateTexture(nil, "ARTWORK")
    action.icon:SetAllPoints(action)
    action.highlight = action:CreateTexture(nil, "HIGHLIGHT")
    action.highlight:SetAllPoints(action)
    action.highlight:SetColorTexture(1, 1, 1, 0.15)
    action:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        RouteTracker:SetWaypoint()
    end)
    action:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["TOOLTIP_NAV"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    action:SetScript("OnLeave", GameTooltip_Hide)
    action:Hide()
    frame.action = action

    self.frame = frame
    return frame
end

-------------------------------------------------------------------------------
-- Show / Hide
-------------------------------------------------------------------------------

function RouteTracker:Show()
    self:CreateFrame()
    self.frame:Show()
    self.isShowing = true
end

function RouteTracker:Hide()
    if self.frame then self.frame:Hide() end
    self.isShowing = false
    self:ReleaseSecureAction()
end

function RouteTracker:Toggle()
    if self.isShowing then self:Hide() else self:Show() end
end

-------------------------------------------------------------------------------
-- Content
-------------------------------------------------------------------------------

function RouteTracker:ReleaseSecureAction()
    if self.secureAction and QR.SecureButtons then
        QR.SecureButtons:ReleaseButton(self.secureAction)
    end
    self.secureAction = nil
end

local function ReleaseLines(self)
    for _, line in ipairs(self.lines) do
        line:Hide()
        line:ClearAllPoints()
        table_insert(self.linePool, line)
    end
    wipe(self.lines)
end

local function AddLine(self, text, font, indent, previous, gap)
    local line = table.remove(self.linePool)
    if not line then
        line = self.frame:CreateFontString(nil, "OVERLAY")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
    end
    line:SetFontObject(font)
    -- A font object brings its own justification; set ours after it.
    line:SetJustifyH("LEFT")
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", previous or self.frame.title, "BOTTOMLEFT", previous and 0 or indent, -(gap or LINE_GAP))
    line:SetWidth(WIDTH - 2 * PADDING - indent - (self.reserveRight or 0))
    line:SetText(text)
    line:Show()
    table_insert(self.lines, line)
    line.indent = indent
    return line
end

--- Place a line at an indent, below the line before it.
local function NextLine(self, text, font, indent, gap)
    local previous = self.lines[#self.lines]
    local line = AddLine(self, text, font, indent, nil, gap)
    line:ClearAllPoints()
    if previous then
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", indent - (previous.indent or 0), -(gap or LINE_GAP))
    else
        line:SetPoint("TOPLEFT", self.frame.title, "BOTTOMLEFT", indent, -(gap or LINE_GAP))
    end
    return line
end

--- Show a message instead of steps: no destination, no route, calculating.
-- @param text string The message
function RouteTracker:ShowMessage(text)
    if not self.frame then return end
    self:ReleaseSecureAction()
    ReleaseLines(self)
    self.result, self.currentIndex, self.currentStep = nil, nil, nil
    self.frame.title:SetText(L["ADDON_TITLE"] or "QuickRoute")
    self.frame.action:Hide()
    NextLine(self, C.GRAY .. tostring(text) .. C.R, GameFontHighlightSmall, 0, 6)
    self:Resize()
end

--- Fit the frame's height to its lines.
function RouteTracker:Resize()
    local height = PADDING * 2 + (self.frame.title:GetStringHeight() or 14)
    for _, line in ipairs(self.lines) do
        height = height + (line:GetStringHeight() or 12) + LINE_GAP + 2
    end
    self.frame:SetHeight(math.max(height, 48))
end

--- Set the waypoint for the current step, as the row's map button does.
function RouteTracker:SetWaypoint()
    local step = self.currentStep
    if not step or not QR.PathCalculator or not QR.WaypointIntegration then return end
    local anchor = QR.PathCalculator:SelectStepAnchor(step)
    if anchor and anchor.mapID then
        QR.WaypointIntegration:SetTomTomWaypoint(anchor.mapID, anchor.x or 0.5, anchor.y or 0.5, anchor.title)
    end
end

--- Configure the action for the current step: a teleport's secure overlay
-- out of combat, otherwise the map pin.
local function ConfigureAction(self, step)
    local action = self.frame.action
    self:ReleaseSecureAction()
    action.icon:SetTexture(NAV_ICON_PATH)
    if step.type == "teleport" and step.teleportID and QR.SecureButtons and not InCombatLockdown() then
        local secure = QR.SecureButtons:GetButton()
        if secure and QR.SecureButtons:ConfigureButton(secure, step.teleportID, step.sourceType, step.teleportData) then
            secure:SetSize(ACTION_SIZE, ACTION_SIZE)
            QR.SecureButtons:AttachOverlay(secure, action, nil, 0, true)
            secure:SetAlpha(0)
            secure:Show()
            self.secureAction = secure
            local icon
            if step.sourceType == "spell" then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(step.teleportID)
                icon = info and info.iconID
            else
                icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(step.teleportID)
            end
            if icon then action.icon:SetTexture(icon) end
        elseif secure then
            QR.SecureButtons:ReleaseButton(secure)
        end
    end
    action:Show()
end

--- Show a route.
-- @param result table The route result (steps, totalTime, waypoint)
-- @param currentIndex number|nil The current step; defaults to the UI's choice
-- @param groups table|nil Continent groups; built when omitted
function RouteTracker:Update(result, currentIndex, groups)
    if not self.frame then return end
    local steps = result and result.steps
    if not steps or #steps == 0 then
        self:ShowMessage(L["SET_WAYPOINT_HINT"])
        return
    end
    currentIndex = currentIndex or (QR.UI and QR.UI:GetCurrentStepIndex(steps)) or 1
    groups = groups or (QR.UI and QR.UI:BuildContinentGroups(steps)) or {}
    self.result, self.currentIndex, self.currentStep = result, currentIndex, steps[currentIndex]

    ReleaseLines(self)
    local timeText = result.totalTime and QR.CooldownTracker:FormatTime(result.totalTime) or "--:--"
    self.frame.title:SetText((L["ADDON_TITLE"] or "QuickRoute") .. "  ·  " .. timeText)
    local dest = result.waypoint and result.waypoint.title
    if dest then NextLine(self, dest, GameFontHighlight, 0, 4) end

    local groupOf = {}
    for _, group in ipairs(groups) do
        for i = group.first, group.last do groupOf[i] = group end
    end
    local lastShown = math.min(#steps, currentIndex + MAX_AHEAD)
    local shownGroup
    for i = currentIndex, lastShown do
        local group = groupOf[i]
        if group and group ~= shownGroup and group.name then
            NextLine(self, C.YELLOW .. group.name .. C.R, GameFontNormalSmall, 0, 6)
            shownGroup = group
        end
        local text = QR.UI and (QR.UI:BuildStepCardTexts(steps[i])) or (steps[i].action or "")
        if i == currentIndex then
            self.reserveRight = ACTION_SIZE + 6
            local line = NextLine(self, C.YELLOW .. "> " .. C.R .. text, GameFontHighlight, 0, 3)
            self.reserveRight = nil
            local action = self.frame.action
            action:ClearAllPoints()
            action:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PADDING, 0)
            action:SetPoint("TOP", line, "TOP", 0, 2)
            ConfigureAction(self, steps[i])
        else
            NextLine(self, C.GRAY .. "- " .. text .. C.R, GameFontHighlightSmall, 10, 2)
        end
    end
    if #steps > lastShown then
        NextLine(self, C.GRAY .. string_format(L["TRACKER_MORE_STEPS"], #steps - lastShown) .. C.R,
            GameFontHighlightSmall, 10, 2)
    end
    self:Resize()
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function RouteTracker:Initialize()
    if self.initialized then return end
    self.initialized = true
    L = QR.L
    -- A secure overlay cannot be set up in combat; the visibility driver hides
    -- it there. Rebuild the action once combat ends.
    if QR.RegisterCombatCallback then
        QR:RegisterCombatCallback(nil, function()
            if RouteTracker.isShowing and RouteTracker.result then
                RouteTracker:Update(RouteTracker.result, RouteTracker.currentIndex)
            end
        end)
    end
    if self:GetMode() == MODE_COMPACT and QR.UI and QR.UI.displayedResult then
        self:Show()
        self:Update(QR.UI.displayedResult)
    end
end
