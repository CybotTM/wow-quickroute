-- MapTeleportButton.lua
-- Shows a teleport shortcut button on the world map for the currently viewed zone.
-- Styled to match WoW's native map overlay controls.
-- Left-click: instant teleport (secure action)
-- Right-click: open QuickRoute route window
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, type, tostring = pairs, type, tostring
local string_format = string.format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-- Constants
local BUTTON_SIZE = 30
local ICON_SIZE = 24
local UPDATE_THROTTLE = 0.1
-- Position: bottom-right of map canvas, near sidebar toggle
local OFFSET_X = -38
local OFFSET_Y = 2

-------------------------------------------------------------------------------
-- MapTeleportButton Module
-------------------------------------------------------------------------------
QR.MapTeleportButton = {
    button = nil,
    initialized = false,
    currentMapID = nil,
    currentTeleportID = nil,
    currentSourceType = nil,
}

local MapTeleportButton = QR.MapTeleportButton

-- Localization (set during init/create)
local L

-------------------------------------------------------------------------------
-- Localized Name Helper
-------------------------------------------------------------------------------

--- Get the localized display name for a teleport via WoW API.
-- Falls back to data.name if the API doesn't return a result.
-- @param id number The spell or item ID
-- @param sourceType string "spell", "item", or "toy"
-- @param fallbackName string|nil Fallback name from static data
-- @return string The localized name
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

-------------------------------------------------------------------------------
-- Teleport Lookup
-------------------------------------------------------------------------------

--- Find the best available teleport for a given map ID.
-- Prefers teleports that land directly on the viewed zone, then same continent.
-- Among matches, prefers ready (off-cooldown) teleports.
-- @param viewedMapID number The map ID the player is viewing
-- @return number|nil bestID, table|nil bestData, string|nil bestSource
function MapTeleportButton:FindBestTeleportForMap(viewedMapID)
    if not viewedMapID then return nil, nil, nil end
    if not QR.PlayerInventory then return nil, nil, nil end

    local teleports = QR.PlayerInventory:GetAllTeleports()
    if not teleports then return nil, nil, nil end

    local bestID, bestData, bestSource = nil, nil, nil
    local bestReady = false

    -- Pass 1: direct map match
    for id, entry in pairs(teleports) do
        if entry.data and entry.data.mapID == viewedMapID
            and not entry.data.isDynamic and not entry.data.isRandom then
            local isReady = false
            if QR.CooldownTracker then
                local cdInfo = QR.CooldownTracker:GetCooldown(id, entry.sourceType)
                isReady = cdInfo and cdInfo.ready or false
            end
            if not bestID or (isReady and not bestReady) then
                bestID = id
                bestData = entry.data
                bestSource = entry.sourceType
                bestReady = isReady
            end
        end
    end

    if bestID then
        return bestID, bestData, bestSource
    end

    -- Pass 2: same continent
    local viewedContinent = QR.GetContinentForZone and QR.GetContinentForZone(viewedMapID)
    if viewedContinent then
        for id, entry in pairs(teleports) do
            if entry.data and entry.data.mapID
                and not entry.data.isDynamic and not entry.data.isRandom then
                local teleContinent = QR.GetContinentForZone(entry.data.mapID)
                if teleContinent == viewedContinent then
                    local isReady = false
                    if QR.CooldownTracker then
                        local cdInfo = QR.CooldownTracker:GetCooldown(id, entry.sourceType)
                        isReady = cdInfo and cdInfo.ready or false
                    end
                    if not bestID or (isReady and not bestReady) then
                        bestID = id
                        bestData = entry.data
                        bestSource = entry.sourceType
                        bestReady = isReady
                    end
                end
            end
        end
    end

    return bestID, bestData, bestSource
end

-------------------------------------------------------------------------------
-- Button Creation
-------------------------------------------------------------------------------

--- Create the secure action button (once, on UIParent).
-- Styled to match WoW's native map overlay buttons.
-- Left-click: secure teleport action. Right-click: open QR route window.
-- @return Button The created button frame
function MapTeleportButton:CreateButton()
    if self.button then return self.button end

    if InCombatLockdown() then
        QR:Debug("MapTeleportButton: cannot create during combat")
        return nil
    end

    L = QR.L

    local btn = CreateFrame("Button", "QRMapTeleportButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    btn:SetFrameStrata("HIGH")
    btn:Hide()

    -- Dark background (like action bar slot)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    btn.bg = bg

    -- Icon texture (centered, slightly inset)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")
    btn.icon = icon

    -- Highlight on hover
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- Cooldown text overlay
    local cdText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdText:SetPoint("BOTTOM", 0, 1)
    cdText:SetTextColor(1, 0.8, 0)
    btn.cdText = cdText

    -- Tooltip with click instructions
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self._qrTeleportName then
            GameTooltip:SetText(self._qrTeleportName)
            if self._qrDestination and self._qrDestination ~= "" then
                GameTooltip:AddLine(
                    string_format(L["STEP_TELEPORT_TO"], self._qrDestination),
                    0.8, 0.8, 0.8
                )
            end
            if self._qrCooldownText and self._qrCooldownText ~= "" then
                GameTooltip:AddLine(self._qrCooldownText, 1, 0.8, 0)
            end
            -- Click instructions
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["MAP_BTN_LEFT_CLICK"], 0.5, 0.8, 1.0)
            GameTooltip:AddLine(L["MAP_BTN_RIGHT_CLICK"], 0.5, 0.8, 1.0)
            GameTooltip:AddLine(L["MAP_BTN_CTRL_RIGHT"], 0.5, 0.8, 1.0)
        else
            GameTooltip:SetText(L["ADDON_TITLE"])
            GameTooltip:AddLine(L["NO_PATH_FOUND"], 0.8, 0.8, 0.8)
        end
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    -- Brand micro-icon (bottom-right corner, matches QuestTeleportButtons)
    QR.AddMicroIcon(btn, 8)

    self.button = btn
    return btn
end

-------------------------------------------------------------------------------
-- Button Update
-------------------------------------------------------------------------------

--- Update the button to show the best teleport for a given map.
-- Sets secure attributes and visual state. Uses localized names from WoW API.
-- @param mapID number The map ID to find a teleport for
function MapTeleportButton:UpdateForMap(mapID)
    if InCombatLockdown() then return end
    if not self.button then return end

    local btn = self.button

    local teleportID, data, sourceType = self:FindBestTeleportForMap(mapID)

    if not teleportID or not data then
        btn:Hide()
        self.currentTeleportID = nil
        self.currentSourceType = nil
        self.currentMapID = mapID
        return
    end

    -- Configure secure attributes via SecureButtons helper (left-click teleport)
    if QR.SecureButtons then
        QR.SecureButtons:ConfigureButton(btn, teleportID, sourceType)
    end

    -- Re-set PostClick after ConfigureButton (which overwrites it with debug logging)
    btn:SetScript("PostClick", function(self, button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if button == "RightButton" then
            if QR.UI then
                QR.UI:Show()
            end
        end
    end)

    -- Update icon
    local iconTexture
    if sourceType == "spell" and C_Spell and C_Spell.GetSpellTexture then
        iconTexture = C_Spell.GetSpellTexture(teleportID)
    elseif C_Item and C_Item.GetItemIconByID then
        iconTexture = C_Item.GetItemIconByID(teleportID)
    elseif GetItemIcon then
        iconTexture = GetItemIcon(teleportID)
    end
    if btn.icon then
        btn.icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_Map02")
        btn.icon:Show()
    end

    -- Update cooldown text
    local cdStr = ""
    if QR.CooldownTracker then
        local cdInfo = QR.CooldownTracker:GetCooldown(teleportID, sourceType)
        if cdInfo and not cdInfo.ready and cdInfo.remaining > 0 then
            cdStr = QR.CooldownTracker:FormatTime(cdInfo.remaining)
        end
    end
    if btn.cdText then
        btn.cdText:SetText(cdStr)
    end

    -- Get localized name from WoW API (not static English data.name)
    local localizedName = GetLocalizedName(teleportID, sourceType, data.name)

    -- Get localized destination name via map API
    local localizedDest = data.destination or ""
    if data.mapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(data.mapID)
        if mapInfo and mapInfo.name then
            localizedDest = mapInfo.name
        end
    end

    -- Store tooltip data on the button
    btn._qrTeleportName = localizedName
    btn._qrDestination = localizedDest
    btn._qrCooldownText = cdStr ~= "" and (QR.L["COOLDOWN_SHORT"] .. ": " .. cdStr) or ""

    self.currentTeleportID = teleportID
    self.currentSourceType = sourceType
    self.currentMapID = mapID

    -- Show immediately (don't rely on OnUpdate to show)
    btn:Show()

    QR:Debug(string_format("MapTeleportButton: showing %s (%s) for map %d",
        localizedName, sourceType, mapID))
end

-------------------------------------------------------------------------------
-- Positioning
-------------------------------------------------------------------------------

local posThrottle = 0

--- Reposition the button relative to WorldMapFrame canvas (called from OnUpdate).
-- Cannot anchor a SecureActionButtonTemplate to WorldMapFrame (non-secure),
-- so we read the canvas container position and place on UIParent.
-- Positioned at bottom-right of map canvas, near the sidebar toggle.
local function UpdateButtonPosition(self, elapsed)
    posThrottle = posThrottle + elapsed
    if posThrottle < UPDATE_THROTTLE then return end
    posThrottle = 0

    local btn = MapTeleportButton.button
    if not btn then return end

    if InCombatLockdown() then
        btn:Hide()
        return
    end

    if not WorldMapFrame or not WorldMapFrame:IsVisible() then
        btn:Hide()
        return
    end

    -- Hide floating button when sidebar panel is visible (sidebar provides same functionality)
    if QR.MapSidebar and QR.MapSidebar.frame and QR.MapSidebar.frame:IsVisible() then
        btn:Hide()
        return
    end

    -- Use canvas container for accurate positioning within the map area
    local canvas = WorldMapFrame.ScrollContainer or (WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer())
    local anchor = canvas or WorldMapFrame
    local right = anchor:GetRight()
    local bottom = anchor:GetBottom()
    if right and bottom then
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right + OFFSET_X, bottom + OFFSET_Y)
    end
end

-------------------------------------------------------------------------------
-- Hooks & Events
-------------------------------------------------------------------------------

local positionFrame = nil

--- Start tracking WorldMapFrame position via OnUpdate.
local function StartPositionTracking()
    if not positionFrame then
        positionFrame = CreateFrame("Frame")
        positionFrame:SetScript("OnUpdate", UpdateButtonPosition)
    end
    positionFrame:Show()
end

--- Stop tracking WorldMapFrame position.
local function StopPositionTracking()
    if positionFrame then
        positionFrame:Hide()
    end
    if MapTeleportButton.button and not InCombatLockdown() then
        MapTeleportButton.button:Hide()
    end
end

--- Handle world map being shown.
local function OnWorldMapShow()
    if InCombatLockdown() then return end
    if not WorldMapFrame then return end

    local mapID = WorldMapFrame:GetMapID()
    if mapID then
        MapTeleportButton:UpdateForMap(mapID)
    end
    StartPositionTracking()
end

--- Handle world map being hidden.
local function OnWorldMapHide()
    StopPositionTracking()
end

--- Handle map ID change (player browses to different zone).
local function OnMapChanged()
    if InCombatLockdown() then return end
    if not WorldMapFrame or not WorldMapFrame:IsVisible() then return end

    local mapID = WorldMapFrame:GetMapID()
    if mapID and mapID ~= MapTeleportButton.currentMapID then
        MapTeleportButton:UpdateForMap(mapID)
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the MapTeleportButton module.
-- Creates the button, hooks WorldMapFrame events, registers combat callbacks.
function MapTeleportButton:Initialize()
    if self.initialized then return end
    self.initialized = true

    L = QR.L

    -- Create button (outside combat)
    if InCombatLockdown() then
        -- Defer creation until combat ends
        QR:RegisterCombatCallback(nil, function()
            MapTeleportButton:CreateButton()
        end)
    else
        self:CreateButton()
    end

    -- Hook WorldMapFrame show/hide
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", OnWorldMapShow)
        WorldMapFrame:HookScript("OnHide", OnWorldMapHide)

        -- Hook SetMapID for map changes
        if WorldMapFrame.SetMapID then
            hooksecurefunc(WorldMapFrame, "SetMapID", function()
                OnMapChanged()
            end)
        end
    end

    -- Register combat callback: hide during combat, refresh after
    QR:RegisterCombatCallback(
        function()  -- enter combat
            if MapTeleportButton.button and not InCombatLockdown() then
                MapTeleportButton.button:Hide()
            end
            StopPositionTracking()
        end,
        function()  -- leave combat
            if WorldMapFrame and WorldMapFrame:IsVisible() then
                OnWorldMapShow()
            end
        end
    )

    QR:Debug("MapTeleportButton initialized")
end
