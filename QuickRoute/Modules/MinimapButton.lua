-- MinimapButton.lua
-- Minimap button for quick access to QuickRoute
local ADDON_NAME, QR = ...

local math_cos, math_sin, math_atan2 = math.cos, math.sin, math.atan2
local math_pi = math.pi
local CreateFrame = CreateFrame

-------------------------------------------------------------------------------
-- MinimapButton Module
-------------------------------------------------------------------------------
QR.MinimapButton = {
    button = nil,
    initialized = false,
}

local MinimapButton = QR.MinimapButton

-- Constants
local BUTTON_SIZE = 32
local ICON_SIZE = 20
local MINIMAP_RADIUS = 80
local DEFAULT_ANGLE = math_pi * 0.75  -- Top-left area

--- Calculate button position from angle
-- @param angle number Angle in radians
-- @return number, number x and y offsets from Minimap center
local function GetPositionFromAngle(angle)
    return math_cos(angle) * MINIMAP_RADIUS, math_sin(angle) * MINIMAP_RADIUS
end

--- Calculate angle from cursor position relative to Minimap center
-- @return number Angle in radians
local function GetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx or not my then return DEFAULT_ANGLE end
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    return math_atan2(cy - my, cx - mx)
end

--- Create the minimap button frame
-- @return Button The created button
function MinimapButton:Create()
    if self.button then return self.button end

    -- Minimap must exist
    if not Minimap then
        QR:Debug("MinimapButton: Minimap frame not found")
        return nil
    end

    local btn = CreateFrame("Button", "QRMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Icon texture (same as addon .toc IconTexture)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")
    btn.icon = icon

    -- Border overlay (standard minimap button border)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(54, 54)
    overlay:SetPoint("TOPLEFT")
    btn.overlay = overlay

    -- Highlight texture
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Click handlers
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "MiddleButton" then
            if QR.MiniTeleportPanel then
                local isOpen = QR.MiniTeleportPanel.isShowing
                PlaySound(isOpen and SOUNDKIT.IG_MAINMENU_CLOSE or SOUNDKIT.IG_MAINMENU_OPEN)
                QR.MiniTeleportPanel:Toggle()
            end
        elseif mouseButton == "RightButton" then
            if QR.MainFrame then
                local isOpen = QR.MainFrame.isShowing and QR.MainFrame.activeTab == "teleports"
                PlaySound(isOpen and SOUNDKIT.IG_MAINMENU_CLOSE or SOUNDKIT.IG_MAINMENU_OPEN)
                QR.MainFrame:Toggle("teleports")
            end
        else
            if QR.MainFrame then
                local isOpen = QR.MainFrame.isShowing and QR.MainFrame.activeTab == "route"
                PlaySound(isOpen and SOUNDKIT.IG_MAINMENU_CLOSE or SOUNDKIT.IG_MAINMENU_OPEN)
                QR.MainFrame:Toggle("route")
            end
        end
    end)

    -- Tooltip
    local L = QR.L
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["ADDON_TITLE"])
        GameTooltip:AddLine(L["TOOLTIP_MINIMAP_LEFT"] or "Left-click: Toggle route window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["TOOLTIP_MINIMAP_MIDDLE"] or "Middle-click: Quick teleports", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["TOOLTIP_MINIMAP_RIGHT"] or "Right-click: Teleport inventory", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["TOOLTIP_MINIMAP_DRAG"] or "Drag: Move button", 0.5, 0.5, 0.5)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    -- Dragging around minimap border
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self._dragging = true
        self:SetScript("OnUpdate", function(self)
            local angle = GetAngleFromCursor()
            local x, y = GetPositionFromAngle(angle)
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)
            if QR.db then
                QR.db.minimapAngle = angle
            end
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self._dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    self.button = btn
    return btn
end

--- Update button position from saved angle
function MinimapButton:UpdatePosition()
    if not self.button then return end
    local angle = QR.db and QR.db.minimapAngle or DEFAULT_ANGLE
    local x, y = GetPositionFromAngle(angle)
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

--- Show the minimap button
function MinimapButton:Show()
    if not self.button then
        self:Create()
    end
    if self.button then
        self:UpdatePosition()
        self.button:Show()
    end
end

--- Hide the minimap button
function MinimapButton:Hide()
    if self.button then
        self.button:Hide()
    end
end

--- Apply visibility based on QR.db.showMinimap setting
function MinimapButton:ApplyVisibility()
    if QR.db and QR.db.showMinimap then
        self:Show()
    else
        self:Hide()
    end
end

--- Initialize the minimap button module
function MinimapButton:Initialize()
    if self.initialized then return end
    self.initialized = true

    self:Create()
    self:ApplyVisibility()

    QR:Debug("MinimapButton initialized")
end
