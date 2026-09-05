-- MiniTeleportPanel.lua
-- Compact teleport popup for middle-click on minimap button
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type = pairs, ipairs, type
local string_format = string.format
local string_byte, string_sub = string.byte, string.sub
local table_insert, table_sort = table.insert, table.sort
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- MiniTeleportPanel Module
-------------------------------------------------------------------------------
QR.MiniTeleportPanel = {
    frame = nil,
    isShowing = false,
    rows = {},
    rowPool = {},
    secureButtons = {},
}

local MiniTeleportPanel = QR.MiniTeleportPanel

-- Constants
local PANEL_WIDTH = 380
local ROW_HEIGHT = 24
local ICON_SIZE = 18
local PADDING = 6
local MAX_VISIBLE_ROWS = 12
local TITLE_HEIGHT = 22
local ELLIPSIS = "..."

-- Row layout. The name and destination columns were fixed at 100 px each
-- regardless of the panel, which left them narrower than the space the row
-- actually has. They are derived from it instead, so widening the panel widens
-- them. GAPS is the 2 px before the icon, 4 px after it, and 2 px after the
-- status column.
local SCROLLBAR_WIDTH = 18
local STATUS_WIDTH = 52
local COLUMN_GAP = 4
local GAPS = 8
local ROW_WIDTH = PANEL_WIDTH - PADDING * 2 - SCROLLBAR_WIDTH
local LABEL_AREA = ROW_WIDTH - ICON_SIZE - STATUS_WIDTH - GAPS - COLUMN_GAP
local NAME_WIDTH = math.floor(LABEL_AREA / 2)
local DEST_WIDTH = LABEL_AREA - NAME_WIDTH

--- Put text on a fixed-width label, ending it with an ellipsis when it is too
-- long. The labels have word wrap off, so an over-long name is cut mid-word
-- with nothing to show that anything was removed. The row's tooltip carries the
-- full name; the ellipsis is what tells the reader to go and look at it.
-- @param label FontString sized with SetWidth
-- @param text string|nil
function MiniTeleportPanel.SetTextFitted(label, text)
    text = text or ""
    label:SetText(text)

    local limit = label:GetWidth() or 0
    if limit <= 0 or label:GetStringWidth() <= limit then
        return
    end

    local bytes = #text
    while bytes > 0 do
        bytes = bytes - 1
        -- Never cut inside a multi-byte character: back off over continuation
        -- bytes, which are the ones in 0x80..0xBF.
        while bytes > 0 do
            local b = string_byte(text, bytes + 1)
            if not b or b < 0x80 or b >= 0xC0 then
                break
            end
            bytes = bytes - 1
        end
        label:SetText(string_sub(text, 1, bytes) .. ELLIPSIS)
        if label:GetStringWidth() <= limit then
            return
        end
    end
end

local SetTextFitted = MiniTeleportPanel.SetTextFitted

-- Hidden container for recycled frames (avoids SetParent(nil) taint)
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

-- Localization shorthand
local L

-- Status definitions (mirrors TeleportPanel STATUS)
local STATUS = {
    READY = { key = "STATUS_READY", color = "|cFF00FF00", sortOrder = 1 },
    ON_CD = { key = "STATUS_ON_CD", color = "|cFFFF6600", sortOrder = 2 },
    OWNED = { key = "STATUS_OWNED", color = "|cFF00CC00", sortOrder = 3 },
    UNAVAILABLE = { key = "STATUS_UNAVAILABLE", color = QR.Colors.GRAY, sortOrder = 4 },
    MISSING = { key = "STATUS_MISSING", color = "|cFFFFFF00", sortOrder = 4 },
    NA = { key = "STATUS_NA", color = "|cFF666666", sortOrder = 5 },
    -- Owned, but the game only accepts it on certain maps and the player is elsewhere
    ZONE = { key = "STATUS_ZONE", color = "|cFF888888", sortOrder = 4 },
}

--- Get teleport status for a given ID (simplified from TeleportPanel)
-- @param id number The item or spell ID
-- @param data table The teleport data entry
-- @param isSpell boolean Whether this is a spell
-- @return table status, number|nil cooldownRemaining
local function GetTeleportStatus(id, data, isSpell)
    if not QR.PlayerInfo:CanUseTeleport(data) then
        return STATUS.NA, nil
    end

    -- Check ownership
    local owned = false
    local sourceType = "item"

    if isSpell then
        owned = QR.PlayerInventory and QR.PlayerInventory:KnowsTeleportSpell(id, data) or false
        sourceType = "spell"
    elseif data.type == QR.TeleportTypes.TOY then
        owned = PlayerHasToy and PlayerHasToy(id) or false
        sourceType = "toy"
    else
        if QR.PlayerInventory then
            owned = QR.PlayerInventory:HasTeleport(id)
        else
            owned = false
        end
        sourceType = "item"
    end

    if not owned then
        return STATUS.MISSING, nil
    end

    -- Zone restriction (Kirin Tor Beacon: Isle of Thunder only, and so on)
    if data.usableOnMaps and not QR.PlayerInfo:IsOnAnyMap(data.usableOnMaps) then
        return STATUS.ZONE, nil
    end

    if sourceType == "toy" and not QR.PlayerInventory:IsToyUsable(id, data) then
        return STATUS.UNAVAILABLE, nil
    end

    -- Check cooldown
    if QR.CooldownTracker then
        local cooldown = QR.CooldownTracker:GetCooldown(id, sourceType)
        if cooldown then
            if cooldown.ready then
                return STATUS.READY, 0
            else
                return STATUS.ON_CD, cooldown.remaining
            end
        end
    end

    return STATUS.OWNED, nil
end

--- Get localized name for a teleport entry via WoW API
-- @param entry table The teleport entry
-- @return string The localized name
local function GetLocalizedName(entry)
    if not entry then return "" end
    local id = entry.id
    if entry.isSpell then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info and info.name then return info.name end
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            if name then return name end
        end
    else
        if C_Item and C_Item.GetItemInfo then
            local name = C_Item.GetItemInfo(id)
            if name then return name end
        end
        if GetItemInfo then
            local name = GetItemInfo(id)
            if name then return name end
        end
    end
    return entry.data and entry.data.name or ""
end

--- Get localized destination for a teleport entry
-- @param entry table The teleport entry
-- @return string The localized destination
local function GetLocalizedDestination(entry)
    local data = entry and entry.data
    if not data then return "" end
    if data.mapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(data.mapID)
        if mapInfo and mapInfo.name then return mapInfo.name end
    end
    if data.isDynamic and data.destination == "Bound Location" then
        if GetBindLocation then
            local bindLoc = GetBindLocation()
            if bindLoc and bindLoc ~= "" then return bindLoc end
        end
    end
    -- For nil-mapID entries, use L[] keys (same as TeleportPanel)
    local dest = data.destination
    if dest and QR.DEST_L_KEYS then
        local lKey = QR.DEST_L_KEYS[dest]
        if lKey then return L[lKey] end
    end
    return dest or ""
end

--- Collect owned teleports (READY, ON_CD, or OWNED status only)
-- @return table Array of filtered/sorted teleport entries
local function CollectOwnedTeleports()
    local teleports = {}
    local seen = {}

    local function addEntry(id, data, isSpell)
        if seen[id] then return end
        seen[id] = true
        local status, cooldownRemaining = GetTeleportStatus(id, data, isSpell)
        if status == STATUS.READY or status == STATUS.ON_CD or status == STATUS.OWNED then
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = isSpell,
                status = status,
                cooldownRemaining = cooldownRemaining or 0,
            })
        end
    end

    -- Items, toys, hearthstones, engineering
    for id, data in pairs(QR.TeleportItemsData or {}) do
        addEntry(id, data, false)
    end

    -- Class spells
    for id, data in pairs(QR.ClassTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- Mage teleports
    for faction, spells in pairs(QR.MageTeleports or {}) do
        for id, data in pairs(spells) do
            addEntry(id, data, true)
        end
    end

    -- Racial spells
    for id, data in pairs(QR.RacialTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- General spells (housing, etc.)
    for id, data in pairs(QR.GeneralTeleportSpells or {}) do
        addEntry(id, data, true)
    end

    -- Sort: READY first, then by cooldown remaining ascending, then by name
    table_sort(teleports, function(a, b)
        if a.status.sortOrder ~= b.status.sortOrder then
            return a.status.sortOrder < b.status.sortOrder
        end
        if a.cooldownRemaining ~= b.cooldownRemaining then
            return a.cooldownRemaining < b.cooldownRemaining
        end
        return (a.data.name or "") < (b.data.name or "")
    end)

    -- Deduplicate by localized destination: keep best entry per destination
    local destMap = {}   -- destination string -> best entry
    local destOrder = {} -- maintain insertion order
    for _, entry in ipairs(teleports) do
        local dest = GetLocalizedDestination(entry)
        if not destMap[dest] then
            destMap[dest] = entry
            table_insert(destOrder, dest)
        else
            local existing = destMap[dest]
            -- Prefer better status (lower sortOrder = better), then shorter cooldown
            if entry.status.sortOrder < existing.status.sortOrder
                or (entry.status.sortOrder == existing.status.sortOrder
                    and entry.cooldownRemaining < existing.cooldownRemaining) then
                destMap[dest] = entry
            end
        end
    end
    -- Rebuild teleports from deduped map (preserving dest order)
    teleports = {}
    for _, dest in ipairs(destOrder) do
        table_insert(teleports, destMap[dest])
    end

    return teleports
end

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create the panel frame
-- @return Frame The panel frame
function MiniTeleportPanel:CreateFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "QRMiniTeleportPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, TITLE_HEIGHT + PADDING * 2)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    -- Backdrop (tooltip-style)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)
    title:SetJustifyH("LEFT")
    frame.title = title

    -- Scroll frame for rows (modern thin scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", "QRMiniTPScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + PADDING))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 10, PADDING)
    QR.SkinScrollBar(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(ROW_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- ESC to close
    table_insert(UISpecialFrames, "QRMiniTeleportPanel")

    -- Sync isShowing on hide. OnHide also fires when an ancestor is hidden
    -- (Alt+Z, a cinematic) and that is not a close: the panel comes back on its
    -- own with its rows and secure buttons intact. Clearing isShowing there
    -- disarmed the enter-combat callback, which is gated on it, so the panel
    -- and its overlay buttons stayed on screen for the whole next fight. The
    -- frame's own IsShown() is still true when an ancestor did the hiding.
    frame:SetScript("OnHide", function(f)
        if f:IsShown() then
            return
        end
        self.isShowing = false
    end)

    frame:Hide()
    self.frame = frame
    return frame
end

--- Create or recycle a row frame
-- @return Frame A row frame
function MiniTeleportPanel:GetRow()
    -- Recycle from pool
    for i, row in ipairs(self.rowPool) do
        if not row.inUse then
            row.inUse = true
            row:SetParent(self.frame.scrollChild)
            row:Show()
            return row
        end
    end

    -- Create new row
    local row = CreateFrame("Frame", nil, self.frame.scrollChild)
    row:SetHeight(ROW_HEIGHT)

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    -- Name label
    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameLabel:SetWidth(NAME_WIDTH)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    row.nameLabel = nameLabel

    -- Destination label
    local destLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    destLabel:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)
    destLabel:SetWidth(DEST_WIDTH)
    destLabel:SetJustifyH("LEFT")
    destLabel:SetWordWrap(false)
    row.destLabel = destLabel

    -- Status label
    local statusLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    statusLabel:SetJustifyH("RIGHT")
    statusLabel:SetWidth(STATUS_WIDTH)
    row.statusLabel = statusLabel

    -- Highlight on mouse over
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    row.inUse = true
    table_insert(self.rowPool, row)
    return row
end

--- Release all rows back to pool
function MiniTeleportPanel:ReleaseAllRows()
    if self.separator then
        self.separator:Hide()
    end
    -- Release secure buttons. No lockdown guard here: ReleaseButton queues the
    -- button in pendingReleases when it cannot touch it, and the leave-combat
    -- handler flushes that queue. Skipping the call under lockdown and then
    -- dropping self.secureButtons anyway lost the only reference to each held
    -- button, leaking two pool slots per combat start until all 60 were gone.
    if QR.SecureButtons then
        for _, btn in ipairs(self.secureButtons) do
            QR.SecureButtons:ReleaseButton(btn)
        end
    end
    self.secureButtons = {}

    -- Release rows
    for _, row in ipairs(self.rowPool) do
        if row.inUse then
            row.inUse = false
            row:Hide()
            row:SetParent(recycleContainer)
        end
    end
    self.rows = {}
end

--- Get the icon texture for a teleport entry
-- @param entry table The teleport entry
-- @return string|number The icon texture path or ID
local function GetTeleportIcon(entry)
    if entry.isSpell then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(entry.id)
            if info and info.iconID then return info.iconID end
        end
        if GetSpellInfo then
            local _, _, icon = GetSpellInfo(entry.id)
            if icon then return icon end
        end
    else
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(entry.id)
            if icon then return icon end
        end
        if GetItemIcon then
            local icon = GetItemIcon(entry.id)
            if icon then return icon end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-------------------------------------------------------------------------------
-- Refresh & Display
-------------------------------------------------------------------------------

--- Refresh the teleport list
function MiniTeleportPanel:RefreshList()
    if not self.frame then return end

    if QR.CooldownTracker then QR.CooldownTracker:WatchActiveCooldowns() end

    L = QR.L

    self:ReleaseAllRows()

    local teleports = CollectOwnedTeleports()

    -- Update title
    self.frame.title:SetText(L["MINI_PANEL_TITLE"])

    if #teleports == 0 then
        -- Show "no teleports" message
        local row = self:GetRow()
        row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
        row.icon:SetTexture(nil)
        row.nameLabel:SetWidth(LABEL_AREA + COLUMN_GAP)
        SetTextFitted(row.nameLabel, L["MINI_PANEL_NO_TELEPORTS"])
        row.nameLabel:SetTextColor(0.5, 0.5, 0.5)
        row.destLabel:SetText("")
        row.statusLabel:SetText("")
        table_insert(self.rows, row)

        local totalHeight = TITLE_HEIGHT + ROW_HEIGHT + PADDING * 3
        self.frame:SetHeight(totalHeight)
        self.frame.scrollChild:SetHeight(ROW_HEIGHT)
        return
    end

    -- Build rows
    local yOffset = 0
    for i, entry in ipairs(teleports) do
        local row = self:GetRow()
        row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)

        -- Icon
        local iconTexture = GetTeleportIcon(entry)
        row.icon:SetTexture(iconTexture)

        -- Name
        local name = GetLocalizedName(entry)
        row.nameLabel:SetWidth(NAME_WIDTH)
        SetTextFitted(row.nameLabel, name)
        row.nameLabel:SetTextColor(1, 1, 1)

        -- Destination
        local dest = GetLocalizedDestination(entry)
        SetTextFitted(row.destLabel, dest)

        -- Status / cooldown (READY/OWNED show nothing; ON_CD shows countdown)
        local statusText
        if entry.status == STATUS.READY or entry.status == STATUS.OWNED then
            statusText = ""
        elseif entry.status == STATUS.ON_CD then
            local timeStr = QR.CooldownTracker and QR.CooldownTracker:FormatTime(entry.cooldownRemaining) or "?"
            statusText = entry.status.color .. timeStr .. "|r"
        else
            statusText = entry.status.color .. (L[entry.status.key] or "?") .. "|r"
        end
        row.statusLabel:SetText(statusText)

        -- Secure button overlay for clicking to use teleport
        if QR.SecureButtons and not InCombatLockdown() then
            local secBtn = QR.SecureButtons:GetButton()
            if secBtn then
                local sourceType = entry.isSpell and "spell" or (entry.data.type == QR.TeleportTypes.TOY and "toy" or "item")
                local configured = QR.SecureButtons:ConfigureButton(secBtn, entry.id, sourceType, entry.data)
                if configured then
                    secBtn:SetSize(ROW_WIDTH, ROW_HEIGHT)
                    QR.SecureButtons:AttachOverlay(secBtn, row, self.frame.scrollFrame, 0, true)
                    secBtn:SetAlpha(0)  -- Invisible overlay, row provides visuals

                    -- Tooltip
                    secBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if self.sourceType == "spell" then
                            GameTooltip:SetSpellByID(self.teleportID)
                        else
                            GameTooltip:SetItemByID(self.teleportID)
                        end
                        QR.AddTooltipBranding(GameTooltip)
                        GameTooltip:Show()
                    end)
                    secBtn:SetScript("OnLeave", function()
                        GameTooltip_Hide()
                    end)

                    table_insert(self.secureButtons, secBtn)
                else
                    QR.SecureButtons:ReleaseButton(secBtn)
                end
            end
        end

        table_insert(self.rows, row)
        yOffset = yOffset + ROW_HEIGHT
    end

    -- Separator line before mount button. Created once and re-anchored: this
    -- used to build a fresh Frame on every refresh and never hide or reuse it,
    -- so each refresh left another 1px line behind in the scroll child.
    if not self.separator then
        local separator = CreateFrame("Frame", nil, self.frame.scrollChild)
        separator:SetHeight(1)
        local sepTex = separator:CreateTexture(nil, "ARTWORK")
        sepTex:SetAllPoints()
        sepTex:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        self.separator = separator
    end
    self.separator:ClearAllPoints()
    self.separator:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 4, -yOffset - 3)
    self.separator:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", -4, 0)
    self.separator:Show()
    yOffset = yOffset + 7  -- 3px gap + 1px line + 3px gap

    -- Mount button row
    local mountRow = self:GetRow()
    mountRow:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
    mountRow:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
    mountRow.icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    mountRow.nameLabel:SetWidth(NAME_WIDTH)
    SetTextFitted(mountRow.nameLabel, L["MINI_PANEL_SUMMON_MOUNT"])
    mountRow.nameLabel:SetTextColor(1, 1, 1)
    SetTextFitted(mountRow.destLabel, L["MINI_PANEL_RANDOM_FAVORITE"])
    mountRow.statusLabel:SetText("")

    -- Secure macro button for mount summon
    if QR.SecureButtons and not InCombatLockdown() then
        local secBtn = QR.SecureButtons:GetButton()
        if secBtn then
            secBtn:SetAttribute("type", "macro")
            secBtn:SetAttribute("macrotext", "/run C_MountJournal.SummonByID(0)")
            secBtn:SetSize(ROW_WIDTH, ROW_HEIGHT)
            QR.SecureButtons:AttachOverlay(secBtn, mountRow, self.frame.scrollFrame, 0, true)
            secBtn:SetAlpha(0)

            secBtn:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["MINI_PANEL_SUMMON_MOUNT"], 1, 0.82, 0)
                GameTooltip:AddLine(L["MINI_PANEL_RANDOM_FAVORITE"], 1, 1, 1)
                QR.AddTooltipBranding(GameTooltip)
                GameTooltip:Show()
            end)
            secBtn:SetScript("OnLeave", function()
                GameTooltip_Hide()
            end)

            table_insert(self.secureButtons, secBtn)
        end
    end

    table_insert(self.rows, mountRow)
    yOffset = yOffset + ROW_HEIGHT

    -- Set frame height based on number of rows (capped)
    local totalRows = #teleports + 1  -- +1 for mount row
    local visibleRows = totalRows <= MAX_VISIBLE_ROWS and totalRows or MAX_VISIBLE_ROWS
    local contentHeight = yOffset
    local frameHeight = TITLE_HEIGHT + visibleRows * ROW_HEIGHT + 7 + PADDING * 3
    self.frame:SetHeight(frameHeight)
    self.frame.scrollChild:SetHeight(contentHeight)
end

--- Anchor the panel to the minimap button
function MiniTeleportPanel:AnchorToMinimapButton()
    if not self.frame then return end

    local btn = QR.MinimapButton and QR.MinimapButton.button
    if btn then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPRIGHT", btn, "BOTTOMLEFT", 0, -4)
    else
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 0, -4)
    end
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------

function MiniTeleportPanel:Show()
    if InCombatLockdown() then
        QR:Print(L["CANNOT_USE_IN_COMBAT"])
        return
    end

    if not self.frame then
        self:CreateFrame()
    end

    self:AnchorToMinimapButton()
    self:RefreshList()
    self.frame:Show()
    self.isShowing = true
    if QR.CooldownTracker then QR.CooldownTracker:WatchActiveCooldowns() end
end

function MiniTeleportPanel:Hide()
    if self.frame then
        if not InCombatLockdown() then
            self:ReleaseAllRows()
        end
        self.frame:Hide()
    end
    self.isShowing = false
end

function MiniTeleportPanel:Toggle()
    if self.isShowing then
        self:Hide()
    else
        self:Show()
    end
end

-------------------------------------------------------------------------------
-- Combat Integration
-------------------------------------------------------------------------------

--- Initialize combat callbacks for auto-hide
function MiniTeleportPanel:RegisterCombat()
    QR:RegisterCombatCallback(
        -- Enter combat: release the rows, then hide the panel.
        -- Hiding the frame does not hide the secure overlay buttons: those are
        -- parented to UIParent, not to this panel, so they stayed on screen at
        -- alpha 0 for the whole fight and kept their slots in the 60-button
        -- pool. Lockdown is already active here -- PLAYER_REGEN_DISABLED marks
        -- its start -- so the releases queue and are flushed on leave.
        function()
            if MiniTeleportPanel.isShowing and MiniTeleportPanel.frame then
                MiniTeleportPanel:ReleaseAllRows()
                MiniTeleportPanel.frame:Hide()
                MiniTeleportPanel.isShowing = false
            end
        end
    )
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function MiniTeleportPanel:Initialize()
    L = QR.L
    self:RegisterCombat()
    if QR.CooldownTracker then
        QR.CooldownTracker:RegisterListener(self, function() self:RefreshList() end, function()
            return self.isShowing and self.frame and self.frame:IsVisible()
        end)
    end
    QR:Debug("MiniTeleportPanel initialized")
end
