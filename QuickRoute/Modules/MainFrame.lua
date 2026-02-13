-- MainFrame.lua
-- Unified container window with portrait header, tab bar, and content switching.
-- Hosts Route (UI.lua) and Teleport Inventory (TeleportPanel.lua) as tab content.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local math_max = math.max
local table_insert = table.insert
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- MainFrame Module
-------------------------------------------------------------------------------
QR.MainFrame = {
    frame = nil,
    isShowing = false,
    activeTab = "route",
    tabs = {},           -- { route = tabButton, teleports = tabButton }
    contentFrames = {},  -- { route = frame, teleports = frame }
    subtitle = nil,      -- FontString from portrait header
    header = nil,        -- { portrait, title, subtitle } from CreatePortraitHeader
    initialized = false,
    wasShowingBeforeCombat = false,
}

local MainFrame = QR.MainFrame

-- Localization shorthand
local L

-- Constants
local FRAME_WIDTH = 500
local FRAME_HEIGHT = 550
local HEADER_HEIGHT = 52
local TAB_HEIGHT = 28
local PADDING = 10

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create the main container frame
function MainFrame:CreateFrame()
    if self.frame then
        return self.frame
    end

    L = QR.L

    -- Calculate width based on localized title (same logic as TeleportPanel)
    local titleStr = L["TELEPORT_INVENTORY"] or "Teleport Inventory"
    local frameWidth = math_max(FRAME_WIDTH, (#titleStr * 8) + 100)

    -- Create the main frame with backdrop
    local frame = CreateFrame("Frame", "QuickRouteMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(frameWidth, FRAME_HEIGHT)

    -- Restore saved position or use default
    local db = QR.db or {}
    if type(db.mainFrameX) == "number" and type(db.mainFrameY) == "number"
        and type(db.mainFramePoint) == "string" and type(db.mainFrameRelPoint) == "string" then
        frame:SetPoint(db.mainFramePoint, UIParent, db.mainFrameRelPoint, db.mainFrameX, db.mainFrameY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Movable / draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if QR.db then
            local point, _, relPoint, x, y = self:GetPoint()
            QR.db.mainFramePoint = point
            QR.db.mainFrameRelPoint = relPoint
            QR.db.mainFrameX = x
            QR.db.mainFrameY = y
        end
    end)
    frame:SetClampedToScreen(true)

    -- ESC to close
    table_insert(UISpecialFrames, "QuickRouteMainFrame")

    -- Sync isShowing when hidden by any means (ESC, frame:Hide(), etc.)
    frame:SetScript("OnHide", function()
        MainFrame.isShowing = false
    end)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.95)

    -- Brand accent border
    QR.AddBrandAccent(frame, 1)

    -- Portrait header
    self.header = QR.CreatePortraitHeader(frame, {
        icon = "Interface\\Icons\\INV_Misc_Map02",
        title = L["ADDON_TITLE"] or "QuickRoute",
    })
    self.subtitle = self.header.subtitle

    -- Close button (modern flat style, same as CreateStandardWindow)
    local closeButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    closeButton:SetBackdropColor(0, 0, 0, 0)

    local closeTxt = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeTxt:SetPoint("CENTER", 0, 0)
    closeTxt:SetText("\195\151")  -- multiplication sign (×)
    closeTxt:SetTextColor(0.6, 0.6, 0.6)

    if closeButton.HookScript then
        closeButton:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.6, 0.15, 0.15, 0.8)
            closeTxt:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(CLOSE or "Close")
            QR.AddTooltipBranding(GameTooltip)
            GameTooltip:Show()
        end)
        closeButton:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
            closeTxt:SetTextColor(0.6, 0.6, 0.6)
            GameTooltip_Hide()
        end)
    end

    closeButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        MainFrame:Hide()
    end)

    -- Tab bar at bottom
    self.tabs = QR.CreateTabBar(frame, {
        { key = "route",     label = L["TAB_ROUTE"] or "Route" },
        { key = "teleports", label = L["TAB_TELEPORTS"] or "Teleports" },
    }, function(tabKey)
        MainFrame:SetActiveTab(tabKey)
    end)

    -- Content area frames (between header and tab bar)
    local routeContent = CreateFrame("Frame", "QuickRouteContentRoute", frame)
    routeContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_HEIGHT)
    routeContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, TAB_HEIGHT + 2)
    routeContent:Hide()
    self.contentFrames.route = routeContent

    local teleportContent = CreateFrame("Frame", "QuickRouteContentTeleports", frame)
    teleportContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_HEIGHT)
    teleportContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, TAB_HEIGHT + 2)
    teleportContent:Hide()
    self.contentFrames.teleports = teleportContent

    -- Hide initially
    frame:Hide()

    self.frame = frame
    return frame
end

-------------------------------------------------------------------------------
-- Tab Switching
-------------------------------------------------------------------------------

--- Set the active tab and update visuals
-- @param tabName string "route" or "teleports"
function MainFrame:SetActiveTab(tabName)
    if not self.frame then return end
    self.activeTab = tabName

    -- Show/hide content frames
    for name, contentFrame in pairs(self.contentFrames) do
        if name == tabName then
            contentFrame:Show()
        else
            contentFrame:Hide()
        end
    end

    -- Update tab button styles
    QR.UpdateTabBarState(self.tabs, tabName)

    -- Update subtitle and refresh content for the active tab
    if tabName == "teleports" then
        if self.subtitle then
            self.subtitle:SetText(L["TELEPORT_INVENTORY"] or "Teleport Inventory")
        end
        if QR.TeleportPanel and QR.TeleportPanel.initialized then
            QR.PlayerInventory:ScanAll()
            QR.TeleportPanel:RefreshList()
        end
    elseif tabName == "route" then
        -- Trigger route refresh to update subtitle + content
        if QR.UI and QR.UI.initialized then
            QR.UI:RefreshRoute()
        elseif self.subtitle then
            self.subtitle:SetText(L["TAB_ROUTE"] or "Route")
        end
    end

    -- Save preference
    if QR.db then
        QR.db.activeTab = tabName
    end
end

--- Get the content frame for a specific tab
-- @param tabName string "route" or "teleports"
-- @return Frame The content frame
function MainFrame:GetContentFrame(tabName)
    return self.contentFrames[tabName]
end

-------------------------------------------------------------------------------
-- Show/Hide/Toggle
-------------------------------------------------------------------------------

--- Show the main frame, optionally switching to a specific tab
-- @param tabName string|nil "route" or "teleports" (nil = use last active)
function MainFrame:Show(tabName)
    if not self.initialized then
        self:Initialize()
    end
    if not self.frame then
        self:CreateFrame()
    end

    local tab = tabName or self.activeTab or "route"

    self.frame:Show()
    self.isShowing = true
    self:SetActiveTab(tab)  -- SetActiveTab handles content refresh + subtitle
end

--- Hide the main frame
function MainFrame:Hide()
    if self.frame then
        self.frame:Hide()
    end
    self.isShowing = false
    self.wasShowingBeforeCombat = false
end

--- Toggle the main frame, optionally targeting a specific tab
-- @param tabName string|nil "route" or "teleports"
function MainFrame:Toggle(tabName)
    if self.isShowing then
        -- If showing the same tab, hide; if different tab, switch
        if tabName and tabName ~= self.activeTab then
            self:SetActiveTab(tabName)  -- SetActiveTab handles content refresh + subtitle
        else
            self:Hide()
        end
    else
        self:Show(tabName)
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the MainFrame module
function MainFrame:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

    L = QR.L

    self:CreateFrame()

    -- Apply saved window scale
    if QR.db and QR.db.windowScale and QR.db.windowScale ~= 1.0 then
        self.frame:SetScale(QR.db.windowScale)
    end

    -- Restore last active tab
    if QR.db and QR.db.activeTab then
        self.activeTab = QR.db.activeTab
    end

    -- Register combat callbacks via centralized manager
    QR:RegisterCombatCallback(
        function()  -- enter combat
            if MainFrame.isShowing then
                MainFrame:Hide()
                MainFrame.wasShowingBeforeCombat = true  -- Set after Hide() since Hide() resets this
            end
        end,
        function()  -- leave combat
            if MainFrame.wasShowingBeforeCombat then
                MainFrame.wasShowingBeforeCombat = false
                MainFrame:Show()
            end
        end
    )

    QR:Debug("MainFrame initialized")
end
