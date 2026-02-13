-- MapSidebar.lua
-- Collapsible sidebar panel in the World Map's quest/event sidebar,
-- showing available teleports for the currently viewed zone.
-- Secure action buttons are overlayed on UIParent (same pattern as TeleportPanel).
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local table_insert, table_sort = table.insert, table.sort
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-- Constants
local MAX_ROWS = 5
local ROW_HEIGHT = 28
local ICON_SIZE = 24
local HEADER_HEIGHT = 22
local PANEL_PAD = 4

-------------------------------------------------------------------------------
-- MapSidebar Module
-------------------------------------------------------------------------------
QR.MapSidebar = {
    frame = nil,         -- Panel frame (parented to QuestMapFrame)
    header = nil,        -- Header bar (collapse toggle)
    content = nil,       -- Content container
    rows = {},           -- Row frames (non-secure display)
    overlayButtons = {}, -- SecureActionButton overlays (on UIParent)
    noTeleportText = nil,
    initialized = false,
    collapsed = false,   -- Persisted in QR.db.sidebarCollapsed
    currentMapID = nil,
}

local MapSidebar = QR.MapSidebar

-- Localization (set during init)
local L

-------------------------------------------------------------------------------
-- Localized Name Helper (shared with MapTeleportButton)
-------------------------------------------------------------------------------

local function GetLocalizedName(id, sourceType, fallbackName)
    if sourceType == "spell" then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info and info.name then return info.name end
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            if name then return name end
        end
    else
        if GetItemInfo then
            local name = GetItemInfo(id)
            if name then return name end
        end
    end
    return fallbackName or (QR.L and QR.L["TELEPORT_FALLBACK"] or "Teleport")
end

local function GetIconTexture(id, sourceType)
    if sourceType == "spell" and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(id)
        if tex then return tex end
    end
    if C_Item and C_Item.GetItemIconByID then
        local tex = C_Item.GetItemIconByID(id)
        if tex then return tex end
    end
    if GetItemIcon then
        local tex = GetItemIcon(id)
        if tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-------------------------------------------------------------------------------
-- Teleport Lookup (returns up to MAX_ROWS results)
-------------------------------------------------------------------------------

--- Find the best teleports for a given map ID, returning up to MAX_ROWS.
-- Prioritizes: direct map match > same continent; ready > on cooldown.
-- @param viewedMapID number The map ID the player is viewing
-- @return table Array of { id, data, sourceType, isReady, isDirect }
function MapSidebar:FindTeleportsForMap(viewedMapID)
    local results = {}
    if not viewedMapID then return results end
    if not QR.PlayerInventory then return results end

    local teleports = QR.PlayerInventory:GetAllTeleports()
    if not teleports then return results end

    local viewedContinent = QR.GetContinentForZone and QR.GetContinentForZone(viewedMapID)

    -- Collect candidates
    local candidates = {}
    for id, entry in pairs(teleports) do
        if entry.data and entry.data.mapID
            and not entry.data.isDynamic and not entry.data.isRandom then
            local isReady = false
            if QR.CooldownTracker then
                local cdInfo = QR.CooldownTracker:GetCooldown(id, entry.sourceType)
                isReady = cdInfo and cdInfo.ready or false
            end
            local isDirect = entry.data.mapID == viewedMapID
            local isSameContinent = false
            if not isDirect and viewedContinent then
                local teleContinent = QR.GetContinentForZone(entry.data.mapID)
                isSameContinent = teleContinent == viewedContinent
            end
            if isDirect or isSameContinent then
                table_insert(candidates, {
                    id = id,
                    data = entry.data,
                    sourceType = entry.sourceType,
                    isReady = isReady,
                    isDirect = isDirect,
                })
            end
        end
    end

    -- Sort: direct first, then ready first
    table_sort(candidates, function(a, b)
        if a.isDirect ~= b.isDirect then return a.isDirect end
        if a.isReady ~= b.isReady then return a.isReady end
        return a.id < b.id  -- stable tiebreaker
    end)

    -- Return up to MAX_ROWS
    for i = 1, math.min(#candidates, MAX_ROWS) do
        results[i] = candidates[i]
    end
    return results
end

-------------------------------------------------------------------------------
-- Panel Creation
-------------------------------------------------------------------------------

--- Create the sidebar panel (non-secure, parented to QuestMapFrame).
function MapSidebar:CreatePanel()
    if self.frame then return self.frame end

    local sidebar = QuestMapFrame
    if not sidebar then return nil end

    -- Main panel frame
    local panel = CreateFrame("Frame", "QRMapSidebar", sidebar, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", sidebar, "BOTTOMLEFT", 0, -PANEL_PAD)
    panel:SetPoint("TOPRIGHT", sidebar, "BOTTOMRIGHT", 0, -PANEL_PAD)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    panel:Hide()
    self.frame = panel

    -- Header bar (collapse toggle)
    local header = CreateFrame("Button", nil, panel)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

    -- Header background
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.15, 0.15, 0.2, 0.8)

    -- Collapse arrow
    local arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", 6, 0)
    arrow:SetText("\226\150\188")  -- ▼
    header.arrow = arrow

    -- Title text
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetText(L["SIDEBAR_TITLE"])
    title:SetTextColor(1, 0.82, 0)
    header.title = title

    -- Refresh button (small icon in header)
    local refreshBtn = QR.CreateModernIconButton(header, 16, "\226\134\187")  -- ↻
    refreshBtn:SetPoint("RIGHT", -4, 0)
    refreshBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if MapSidebar.currentMapID then
            MapSidebar:UpdateForMap(MapSidebar.currentMapID, true)
        end
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["REFRESH"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)
    header.refreshBtn = refreshBtn

    -- Collapse tooltip
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["SIDEBAR_COLLAPSE_TT"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    -- Toggle on click
    header:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        MapSidebar:Toggle()
    end)
    self.header = header

    -- Content container (below header)
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    self.content = content

    -- "No teleports" text
    local noText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noText:SetPoint("CENTER", content, "CENTER", 0, 0)
    noText:SetText(L["SIDEBAR_NO_TELEPORTS"])
    noText:Hide()
    self.noTeleportText = noText

    -- Create row frames
    for i = 1, MAX_ROWS do
        self:CreateRow(i)
    end

    -- Set initial height
    self:UpdatePanelHeight()

    return panel
end

--- Create a single teleport row (non-secure display frame).
-- @param index number Row index (1-based)
function MapSidebar:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 2, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -2, -((index - 1) * ROW_HEIGHT))
    row:Hide()

    -- Row background (alternating)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(0.1, 0.1, 0.15, 0.5)
    else
        bg:SetColorTexture(0.08, 0.08, 0.12, 0.3)
    end

    -- Icon placeholder (the actual icon is the secure overlay button)
    local iconPlaceholder = row:CreateTexture(nil, "ARTWORK")
    iconPlaceholder:SetSize(ICON_SIZE, ICON_SIZE)
    iconPlaceholder:SetPoint("LEFT", 4, 0)
    iconPlaceholder:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconPlaceholder = iconPlaceholder

    -- Teleport name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", iconPlaceholder, "RIGHT", 6, 4)
    nameText:SetPoint("RIGHT", row, "RIGHT", -60, 4)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- Destination name (smaller, below name)
    local destText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    destText:SetPoint("LEFT", iconPlaceholder, "RIGHT", 6, -6)
    destText:SetPoint("RIGHT", row, "RIGHT", -60, -6)
    destText:SetJustifyH("LEFT")
    destText:SetWordWrap(false)
    row.destText = destText

    -- Status text (right side)
    local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("RIGHT", -6, 0)
    statusText:SetJustifyH("RIGHT")
    row.statusText = statusText

    self.rows[index] = row
end

--- Update the panel height based on visible content.
function MapSidebar:UpdatePanelHeight()
    if not self.frame then return end

    if self.collapsed then
        self.frame:SetHeight(HEADER_HEIGHT + 4)
        return
    end

    local visibleRows = 0
    for _, row in ipairs(self.rows) do
        if row:IsShown() then
            visibleRows = visibleRows + 1
        end
    end

    local contentHeight = math.max(visibleRows * ROW_HEIGHT, ROW_HEIGHT)
    if self.content then
        self.content:SetHeight(contentHeight)
    end
    -- Header + padding + content
    self.frame:SetHeight(HEADER_HEIGHT + 4 + contentHeight + 4)
end

-------------------------------------------------------------------------------
-- Overlay Button Management
-------------------------------------------------------------------------------

--- Release all overlay buttons back to the SecureButtons pool.
function MapSidebar:ReleaseOverlays()
    if InCombatLockdown() then return end
    if not QR.SecureButtons then return end

    for _, btn in ipairs(self.overlayButtons) do
        QR.SecureButtons:ReleaseButton(btn)
    end
    self.overlayButtons = {}
end

--- Hide overlay buttons (for combat).
function MapSidebar:HideOverlays()
    for _, btn in ipairs(self.overlayButtons) do
        if not InCombatLockdown() then
            btn:Hide()
        end
    end
end

--- Refresh overlay visibility after combat.
function MapSidebar:RefreshOverlays()
    if self.frame and self.frame:IsVisible() and not self.collapsed then
        if self.currentMapID then
            self:UpdateForMap(self.currentMapID, true)
        end
    end
end

-------------------------------------------------------------------------------
-- Content Update
-------------------------------------------------------------------------------

--- Update the sidebar to show teleports for the given map.
-- @param mapID number The map ID to show teleports for
-- @param force boolean|nil Force refresh even if same map
function MapSidebar:UpdateForMap(mapID, force)
    if not mapID then return end
    if not force and mapID == self.currentMapID then return end
    if not self.frame then return end
    if self.collapsed then return end
    if InCombatLockdown() then return end

    self.currentMapID = mapID

    -- Release old overlays
    self:ReleaseOverlays()

    -- Find teleports for this map
    local teleports = self:FindTeleportsForMap(mapID)

    -- Hide all rows first
    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    if #teleports == 0 then
        -- Show "no teleports" message
        if self.noTeleportText then
            self.noTeleportText:Show()
        end
        self:UpdatePanelHeight()
        return
    end

    if self.noTeleportText then
        self.noTeleportText:Hide()
    end

    -- Populate rows
    for i, entry in ipairs(teleports) do
        local row = self.rows[i]
        if not row then break end

        row:Show()

        -- Name (localized)
        local localizedName = GetLocalizedName(entry.id, entry.sourceType, entry.data.name)
        row.nameText:SetText(localizedName)
        if row.nameText.SetTextToFit then row.nameText:SetTextToFit() end

        -- Destination (localized via map API)
        local destName = entry.data.destination or ""
        if entry.data.mapID and C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(entry.data.mapID)
            if mapInfo and mapInfo.name then
                destName = mapInfo.name
            end
        end
        row.destText:SetText(destName)
        if row.destText.SetTextToFit then row.destText:SetTextToFit() end

        -- Status / cooldown
        local statusStr = ""
        local statusR, statusG, statusB = 0, 1, 0
        if entry.isReady then
            statusStr = L["STATUS_READY"]
            statusR, statusG, statusB = 0, 1, 0
        elseif QR.CooldownTracker then
            local cdInfo = QR.CooldownTracker:GetCooldown(entry.id, entry.sourceType)
            if cdInfo and not cdInfo.ready and cdInfo.remaining > 0 then
                statusStr = QR.CooldownTracker:FormatTime(cdInfo.remaining)
                statusR, statusG, statusB = 1, 0.5, 0
            else
                statusStr = L["STATUS_READY"]
            end
        end
        row.statusText:SetText(statusStr)
        row.statusText:SetTextColor(statusR, statusG, statusB)

        -- Icon texture on placeholder
        local iconTex = GetIconTexture(entry.id, entry.sourceType)
        row.iconPlaceholder:SetTexture(iconTex)

        -- Create secure overlay button for the icon
        if QR.SecureButtons and not InCombatLockdown() then
            local iconBtn = QR.SecureButtons:GetButton()
            if iconBtn then
                local configured = QR.SecureButtons:ConfigureButton(iconBtn, entry.id, entry.sourceType)
                if configured then
                    iconBtn:SetFrameStrata("DIALOG")
                    iconBtn:SetFrameLevel(100)
                    iconBtn:SetSize(ICON_SIZE, ICON_SIZE)
                    QR.SecureButtons:AttachOverlay(iconBtn, row, nil, 4, true)

                    -- Icon texture on the secure button
                    if not iconBtn.iconTexture then
                        iconBtn.iconTexture = iconBtn:CreateTexture(nil, "ARTWORK")
                        iconBtn.iconTexture:SetAllPoints()
                    end
                    iconBtn.iconTexture:SetTexture(iconTex)
                    iconBtn.iconTexture:Show()

                    if iconBtn.border then
                        iconBtn.border:Hide()
                    end

                    iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

                    -- Dim if on cooldown
                    if not entry.isReady then
                        iconBtn:SetAlpha(0.5)
                    else
                        iconBtn:SetAlpha(1.0)
                    end

                    -- Brand micro-icon (matches QuestTeleportButtons/MapTeleportButton)
                    QR.AddMicroIcon(iconBtn, 6)

                    -- Tooltip
                    iconBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(localizedName)
                        if destName ~= "" then
                            GameTooltip:AddLine(destName, 0.8, 0.8, 0.8)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(L["MAP_BTN_LEFT_CLICK"], 0.5, 0.8, 1.0)
                        QR.AddTooltipBranding(GameTooltip)
                        GameTooltip:Show()
                    end)
                    iconBtn:SetScript("OnLeave", function()
                        GameTooltip_Hide()
                    end)

                    table_insert(self.overlayButtons, iconBtn)
                end
            end
        end
    end

    self:UpdatePanelHeight()
end

-------------------------------------------------------------------------------
-- Collapse / Expand
-------------------------------------------------------------------------------

--- Toggle the collapsed state of the sidebar panel.
function MapSidebar:Toggle()
    self.collapsed = not self.collapsed

    if QR.db then
        QR.db.sidebarCollapsed = self.collapsed
    end

    if self.collapsed then
        if self.content then self.content:Hide() end
        if self.header and self.header.arrow then
            self.header.arrow:SetText("\226\150\182")  -- ▶
        end
        self:HideOverlays()
    else
        if self.content then self.content:Show() end
        if self.header and self.header.arrow then
            self.header.arrow:SetText("\226\150\188")  -- ▼
        end
        -- Refresh content
        if self.currentMapID then
            self:UpdateForMap(self.currentMapID, true)
        end
    end

    self:UpdatePanelHeight()
end

-------------------------------------------------------------------------------
-- Show / Hide
-------------------------------------------------------------------------------

--- Show the sidebar panel.
function MapSidebar:Show()
    if not self.frame then return end
    self.frame:Show()

    if self.collapsed then
        if self.content then self.content:Hide() end
    end
end

--- Hide the sidebar panel and release overlays.
function MapSidebar:Hide()
    if not self.frame then return end
    self.frame:Hide()

    if not InCombatLockdown() then
        self:ReleaseOverlays()
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the MapSidebar module.
-- Hooks WorldMapFrame and QuestMapFrame for show/hide and map changes.
function MapSidebar:Initialize()
    if self.initialized then return end
    self.initialized = true

    L = QR.L

    -- Restore persisted collapse state
    if QR.db and QR.db.sidebarCollapsed then
        self.collapsed = true
    end

    -- Defer panel creation until QuestMapFrame exists
    if not QuestMapFrame then
        QR:Debug("MapSidebar: QuestMapFrame not found, deferring")
        -- Try again when world map opens
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function()
                if QuestMapFrame and not MapSidebar.frame then
                    MapSidebar:CreatePanel()
                    MapSidebar:Show()
                    local mapID = WorldMapFrame:GetMapID()
                    if mapID then
                        MapSidebar:UpdateForMap(mapID)
                    end
                end
            end)
        end
        return
    end

    self:CreatePanel()

    -- Hook QuestMapFrame show/hide
    if QuestMapFrame then
        QuestMapFrame:HookScript("OnShow", function()
            MapSidebar:Show()
        end)
        QuestMapFrame:HookScript("OnHide", function()
            MapSidebar:Hide()
        end)
    end

    -- Hook WorldMapFrame for map changes
    if WorldMapFrame then
        if WorldMapFrame.SetMapID then
            hooksecurefunc(WorldMapFrame, "SetMapID", function()
                if not WorldMapFrame:IsVisible() then return end
                local mapID = WorldMapFrame:GetMapID()
                if mapID then
                    MapSidebar:UpdateForMap(mapID)
                end
            end)
        end

        -- Also update on show
        WorldMapFrame:HookScript("OnShow", function()
            if QuestMapFrame and not MapSidebar.frame then
                MapSidebar:CreatePanel()
            end
            local mapID = WorldMapFrame:GetMapID()
            if mapID then
                C_Timer.After(0, function()
                    if WorldMapFrame and WorldMapFrame:IsVisible() then
                        MapSidebar:UpdateForMap(mapID)
                    end
                end)
            end
        end)

        WorldMapFrame:HookScript("OnHide", function()
            MapSidebar:Hide()
        end)
    end

    -- Combat callbacks: hide overlays during combat, refresh after
    QR:RegisterCombatCallback(
        function()  -- enter combat
            MapSidebar:HideOverlays()
        end,
        function()  -- leave combat
            MapSidebar:RefreshOverlays()
        end
    )

    QR:Debug("MapSidebar initialized")
end
