-- TeleportPanel.lua
-- Teleport Inventory Panel - shows all available teleport items, toys, and spells
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local math_max = math.max
local string_format = string.format
local table_insert, table_sort, table_concat = table.insert, table.sort, table.concat
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- TeleportPanel Module
-------------------------------------------------------------------------------
QR.TeleportPanel = {
    frame = nil,
    isShowing = false,
    teleportRows = {},
    headerRows = {},  -- Pool-separate: zone group header frames
    headerPool = {},  -- Pool of reusable header frames
    rowPool = {},  -- Pool of reusable row frames
    iconPool = {},   -- Pool of reusable icon frames for grid mode
    iconFrames = {}, -- Active icon frames (parallel to teleportRows for grid mode)
    currentFilter = "All",
    sortedTeleports = {},
    groupByDestination = false,
    -- Throttle tracking
    lastRefreshClickTime = 0,
    -- State tracking
    isScanning = false,
}

-- Bag scan cache (avoids scanning 150+ slots on every tooltip hover)
local bagScanCache = {}
local bagScanCacheTime = 0
local BAG_CACHE_TTL = 5  -- seconds

-- Hidden container for recycled frames (avoids SetParent(nil) taint)
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

local TeleportPanel = QR.TeleportPanel

-- Localization shorthand (accessed after addon loads)
local L

-- Color constants shorthand
local C = QR.Colors

-- Constants
local PANEL_MIN_WIDTH = 500
local PANEL_HEIGHT = 500
local ROW_HEIGHT = 36
local ICON_SIZE = 32
local PADDING = 10

-- Grid icon constants (grouped mode)
local GRID_ICON_SIZE = 36
local GRID_ICON_GAP = 4
local GRID_ROW_PADDING = 6

-------------------------------------------------------------------------------
-- Localized Name Helpers
-------------------------------------------------------------------------------

--- Map of English destination strings (nil-mapID entries) to L[] keys.
-- Used for destinations that cannot be resolved via C_Map.GetMapInfo.
local DEST_L_KEYS = {
    ["Bound Location"]             = "DEST_BOUND_LOCATION",
    ["Garrison"]                   = "DEST_GARRISON",
    ["Garrison Shipyard"]          = "DEST_GARRISON_SHIPYARD",
    ["Camp Location"]              = "DEST_CAMP_LOCATION",
    ["Random location"]            = "DEST_RANDOM",
    ["Illidari Camp"]              = "DEST_ILLIDARI_CAMP",
    ["Random Northrend Location"]  = "DEST_RANDOM_NORTHREND",
    ["Random Pandaria Location"]   = "DEST_RANDOM_PANDARIA",
    ["Random Draenor Location"]    = "DEST_RANDOM_DRAENOR",
    ["Random Argus Location"]      = "DEST_RANDOM_ARGUS",
    ["Random Kul Tiras Location"]  = "DEST_RANDOM_KUL_TIRAS",
    ["Random Zandalar Location"]   = "DEST_RANDOM_ZANDALAR",
    ["Random Shadowlands Location"] = "DEST_RANDOM_SHADOWLANDS",
    ["Random Dragon Isles Location"] = "DEST_RANDOM_DRAGON_ISLES",
    ["Random Khaz Algar Location"] = "DEST_RANDOM_KHAZ_ALGAR",
    ["Homestead"]                  = "DEST_HOMESTEAD",
}

--- Map of English acquisition strings to L[] keys.
local ACQ_L_KEYS = {
    ["Quest reward from initial Legion intro questline"]                            = "ACQ_LEGION_INTRO",
    ["Quest reward from Warlords of Draenor intro questline"]                       = "ACQ_WOD_INTRO",
    ["Kyrian covenant feature"]                                                     = "ACQ_KYRIAN",
    ["Venthyr covenant feature"]                                                    = "ACQ_VENTHYR",
    ["Night Fae covenant feature"]                                                  = "ACQ_NIGHT_FAE",
    ["Necrolord covenant feature"]                                                  = "ACQ_NECROLORD",
    ["Exalted with Argent Crusade + Champion of faction at Argent Tournament"]      = "ACQ_ARGENT_TOURNAMENT",
    ["Exalted with Hellscream's Reach (Tol Barad dailies)"]                         = "ACQ_HELLSCREAMS_REACH",
    ["Exalted with Baradin's Wardens (Tol Barad dailies)"]                          = "ACQ_BARADINS_WARDENS",
    ["Drop from The Big Bad Wolf (Opera event) in Karazhan"]                        = "ACQ_KARAZHAN_OPERA",
    ["Drop from heroic Lich King 25 in Icecrown Citadel"]                           = "ACQ_ICC_LK25",
}

--- Get localized name for a teleport entry via WoW API.
-- Falls back to data.name if the API doesn't return a result.
-- @param entry table The teleport entry (with .id, .isSpell, .data)
-- @return string The localized name
local function GetLocalizedTeleportName(entry)
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
    return entry.data.name
end

--- Get localized destination for a teleport entry.
-- Uses C_Map.GetMapInfo when mapID is available, otherwise L[] keys.
-- @param entry table The teleport entry (with .data.mapID, .data.destination)
-- @return string The localized destination
local function GetLocalizedDestination(entry)
    local data = entry and entry.data
    if not data then return "" end
    -- Try C_Map for entries with a mapID
    if data.mapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(data.mapID)
        if mapInfo and mapInfo.name then return mapInfo.name end
    end
    -- For dynamic hearthstone-type items, show actual bind location
    if data.isDynamic and data.destination == "Bound Location" then
        if GetBindLocation then
            local bindLoc = GetBindLocation()
            if bindLoc and bindLoc ~= "" then return bindLoc end
        end
    end
    -- For nil-mapID entries, use L[] keys
    local dest = data.destination
    if dest then
        local lKey = DEST_L_KEYS[dest]
        if lKey and QR.L then
            return QR.L[lKey]
        end
    end
    return dest
end

--- Get localized acquisition text via L[] keys.
-- @param acquisition string The English acquisition text from data
-- @return string The localized acquisition text
local function GetLocalizedAcquisition(acquisition)
    if not acquisition then return nil end
    local lKey = ACQ_L_KEYS[acquisition]
    if lKey and QR.L then
        return QR.L[lKey]
    end
    return acquisition
end

-- Status constants with colors and sort order (text will be localized on init)
local STATUS = {
    READY = { key = "STATUS_READY", color = "|cFF00FF00", sortOrder = 1 },     -- Bright green
    ON_CD = { key = "STATUS_ON_CD", color = "|cFFFF6600", sortOrder = 2 },     -- Orange
    OWNED = { key = "STATUS_OWNED", color = "|cFF00CC00", sortOrder = 3 },     -- Green (fallback)
    MISSING = { key = "STATUS_MISSING", color = "|cFFFFFF00", sortOrder = 4 }, -- Yellow
    NA = { key = "STATUS_NA", color = "|cFF666666", sortOrder = 5 },          -- Gray
}

-- Initialize localized status text
local function InitializeStatusText()
    L = QR.L
    STATUS.READY.text = L["STATUS_READY"]
    STATUS.ON_CD.text = L["STATUS_ON_CD"]
    STATUS.OWNED.text = L["STATUS_OWNED"]
    STATUS.MISSING.text = L["STATUS_MISSING"]
    STATUS.NA.text = L["STATUS_NA"]
end

-- Filter options (will be localized on init)
local FILTERS = { "All", "Items", "Toys", "Spells" }
local FILTER_KEYS = { "ALL", "ITEMS", "TOYS", "SPELLS" }

local function InitializeFilters()
    L = QR.L
    FILTERS = { L["ALL"], L["ITEMS"], L["TOYS"], L["SPELLS"] }
end

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

--- Determine the status of a teleport for the current player
-- @param id number The item/spell ID
-- @param data table The teleport data
-- @param isSpell boolean Whether this is a spell (vs item/toy)
-- @return table Status info with text, color, sortOrder, and cooldownRemaining
local function GetTeleportStatus(id, data, isSpell)
    local playerFaction = QR.PlayerInfo:GetFaction()
    local playerClass = QR.PlayerInfo:GetClass()

    -- Check faction restriction
    if data.faction and data.faction ~= "both" and data.faction ~= playerFaction then
        return STATUS.NA, nil
    end

    -- Check class restriction
    if data.class and data.class ~= playerClass then
        return STATUS.NA, nil
    end

    -- Check profession restriction
    if data.profession then
        if data.profession == "Engineering" and not QR.PlayerInfo:HasEngineering() then
            return STATUS.NA, nil
        end
    end

    -- Check ownership
    local owned = false
    local sourceType = "item"

    if isSpell then
        owned = IsSpellKnown and IsSpellKnown(id) or false
        sourceType = "spell"
    elseif data.type == QR.TeleportTypes.TOY then
        owned = PlayerHasToy and PlayerHasToy(id) or false
        sourceType = "toy"
    else
        -- Check via PlayerInventory for items (with defensive nil check)
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

    -- Fallback if cooldown check unavailable
    return STATUS.OWNED, nil
end

--- Determine filter category for a teleport type
-- @param teleportType string The type from TeleportTypes
-- @return string Filter category: "Items", "Toys", or "Spells"
local function GetFilterCategory(teleportType)
    if teleportType == QR.TeleportTypes.SPELL then
        return "Spells"
    elseif teleportType == QR.TeleportTypes.TOY then
        return "Toys"
    else
        -- HEARTHSTONE, ITEM, ENGINEER all count as Items
        return "Items"
    end
end

-------------------------------------------------------------------------------
-- Data Collection
-------------------------------------------------------------------------------

--- Collect all teleports from all data sources
-- @return table Array of teleport entries with id, data, isSpell, status, etc.
function TeleportPanel:CollectAllTeleports()
    local teleports = {}
    local seen = {} -- Track IDs to avoid duplicates

    -- Collect from TeleportItemsData (items, toys, hearthstones, engineering)
    for id, data in pairs(QR.TeleportItemsData or {}) do
        if not seen[id] then
            seen[id] = true
            local status, cooldownRemaining = GetTeleportStatus(id, data, false)
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = false,
                status = status,
                cooldownRemaining = cooldownRemaining,
                filterCategory = GetFilterCategory(data.type),
            })
        end
    end

    -- Collect from ClassTeleportSpells
    for id, data in pairs(QR.ClassTeleportSpells or {}) do
        if not seen[id] then
            seen[id] = true
            local status, cooldownRemaining = GetTeleportStatus(id, data, true)
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = true,
                status = status,
                cooldownRemaining = cooldownRemaining,
                filterCategory = "Spells",
            })
        end
    end

    -- Collect from MageTeleports (Alliance, Horde, Shared)
    for faction, spells in pairs(QR.MageTeleports or {}) do
        for id, data in pairs(spells) do
            if not seen[id] then
                seen[id] = true
                -- Add faction info if not already present
                local dataWithFaction = data
                if faction == "Alliance" or faction == "Horde" then
                    dataWithFaction = setmetatable({ faction = faction }, { __index = data })
                end
                local status, cooldownRemaining = GetTeleportStatus(id, dataWithFaction, true)
                table_insert(teleports, {
                    id = id,
                    data = data,
                    isSpell = true,
                    status = status,
                    cooldownRemaining = cooldownRemaining,
                    filterCategory = "Spells",
                    mageFaction = faction, -- Track which faction table it came from
                })
            end
        end
    end

    -- Collect from RacialTeleportSpells
    for id, data in pairs(QR.RacialTeleportSpells or {}) do
        if not seen[id] then
            seen[id] = true
            local status, cooldownRemaining = GetTeleportStatus(id, data, true)
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = true,
                status = status,
                cooldownRemaining = cooldownRemaining,
                filterCategory = "Spells",
            })
        end
    end

    -- Collect from GeneralTeleportSpells (available to all players)
    for id, data in pairs(QR.GeneralTeleportSpells or {}) do
        if not seen[id] then
            seen[id] = true
            local status, cooldownRemaining = GetTeleportStatus(id, data, true)
            table_insert(teleports, {
                id = id,
                data = data,
                isSpell = true,
                status = status,
                cooldownRemaining = cooldownRemaining,
                filterCategory = "Spells",
            })
        end
    end

    return teleports
end

--- Sort teleports by status (READY > ON_CD > MISSING > N/A), then by name
-- @param teleports table Array of teleport entries
-- @return table Sorted array
function TeleportPanel:SortTeleports(teleports)
    table_sort(teleports, function(a, b)
        -- First sort by status sort order
        if a.status.sortOrder ~= b.status.sortOrder then
            return a.status.sortOrder < b.status.sortOrder
        end
        -- Then by name
        local nameA = a.data.name or ""
        local nameB = b.data.name or ""
        return nameA < nameB
    end)
    return teleports
end

--- Filter teleports by current filter setting
-- @param teleports table Array of teleport entries
-- @return table Filtered array
function TeleportPanel:FilterTeleports(teleports)
    -- Check if current filter is "All" (or localized equivalent)
    local allFilter = L and L["ALL"] or "All"
    if self.currentFilter == allFilter or self.currentFilter == "All" then
        return teleports
    end

    -- Map localized filter names to category keys
    local itemsFilter = L and L["ITEMS"] or "Items"
    local toysFilter = L and L["TOYS"] or "Toys"
    local spellsFilter = L and L["SPELLS"] or "Spells"

    local categoryMap = {
        [itemsFilter] = "Items",
        [toysFilter] = "Toys",
        [spellsFilter] = "Spells",
        -- Fallbacks for English
        ["Items"] = "Items",
        ["Toys"] = "Toys",
        ["Spells"] = "Spells",
    }

    local targetCategory = categoryMap[self.currentFilter] or self.currentFilter

    local filtered = {}
    for _, entry in ipairs(teleports) do
        if entry.filterCategory == targetCategory then
            table_insert(filtered, entry)
        end
    end
    return filtered
end

-------------------------------------------------------------------------------
-- Destination Grouping
-------------------------------------------------------------------------------

--- Group teleports by destination zone name
-- @param teleports table Array of teleport entries
-- @return table Array of groups, each with name, mapID, and sorted teleports
function TeleportPanel:GroupTeleportsByDestination(teleports)
    local groups = {} -- keyed by destination name
    local groupOrder = {} -- preserve insertion order for deterministic sort

    for _, entry in ipairs(teleports) do
        local dest = GetLocalizedDestination(entry) or entry.data.name or L["UNKNOWN"]
        if not groups[dest] then
            groups[dest] = { name = dest, teleports = {}, mapID = entry.data.mapID }
            table_insert(groupOrder, dest)
        end
        -- Adopt mapID from later entries if group has none
        if not groups[dest].mapID and entry.data.mapID then
            groups[dest].mapID = entry.data.mapID
        end
        table_insert(groups[dest].teleports, entry)
    end

    -- Build sorted array of groups
    local sorted = {}
    for _, destName in ipairs(groupOrder) do
        table_insert(sorted, groups[destName])
    end
    table_sort(sorted, function(a, b)
        -- Sort by best (lowest sortOrder) status within each group
        local bestA = 999
        for _, t in ipairs(a.teleports) do
            if t.status.sortOrder < bestA then bestA = t.status.sortOrder end
        end
        local bestB = 999
        for _, t in ipairs(b.teleports) do
            if t.status.sortOrder < bestB then bestB = t.status.sortOrder end
        end
        if bestA ~= bestB then return bestA < bestB end
        return a.name < b.name
    end)

    -- Sort teleports within each group by status then name
    for _, group in ipairs(sorted) do
        self:SortTeleports(group.teleports)
    end

    return sorted
end

--- Get a header frame from the pool or create a new one
-- @return Frame A header frame
function TeleportPanel:GetHeaderFrame()
    local header = table.remove(self.headerPool)
    if not header then
        header = CreateFrame("Frame", nil, nil)
        header:SetHeight(24)

        -- Zone name text (gold)
        local zoneText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zoneText:SetPoint("LEFT", header, "LEFT", 5, 0)
        zoneText:SetJustifyH("LEFT")
        header.zoneText = zoneText

        -- Count text (gray, right-aligned)
        local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("RIGHT", header, "RIGHT", -5, 0)
        countText:SetJustifyH("RIGHT")
        header.countText = countText

        -- Background texture
        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        header.bg = bg

        -- Bottom separator line
        local sep = header:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", 0, 0)
        header.sep = sep
    end
    return header
end

--- Release a header frame back to the pool
-- @param header Frame The header frame to release
function TeleportPanel:ReleaseHeaderFrame(header)
    if not header then return end
    header:Hide()
    header:SetParent(recycleContainer)
    header:ClearAllPoints()
    table_insert(self.headerPool, header)
end

--- Clear all header rows (releases frames to pool)
function TeleportPanel:ClearHeaders()
    for _, header in ipairs(self.headerRows) do
        self:ReleaseHeaderFrame(header)
    end
    wipe(self.headerRows)
end

-------------------------------------------------------------------------------
-- Icon Grid (grouped mode)
-------------------------------------------------------------------------------

--- Get an icon frame from the pool or create a new one
-- @return Frame A square icon frame for grid display
function TeleportPanel:GetIconFrame()
    local icon = table.remove(self.iconPool)
    if not icon then
        icon = CreateFrame("Frame", nil, nil)
        icon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        icon:EnableMouse(true)

        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        icon.iconTexture = tex

        local border = icon:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.4, 0.4, 0.4, 0.8)
        border:SetDrawLayer("OVERLAY", -1)
        icon.border = border

        local cdText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cdText:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
        cdText:SetTextColor(1, 1, 1)
        icon.cooldownText = cdText
    end
    return icon
end

--- Release an icon frame back to the pool
-- @param icon Frame The icon frame to release
function TeleportPanel:ReleaseIconFrame(icon)
    if not icon then return end

    -- Release secure button back to pool
    if icon.useButton and QR.SecureButtons then
        QR.SecureButtons:ReleaseButton(icon.useButton)
        icon.useButton = nil
    end

    icon:Hide()
    icon:SetParent(recycleContainer)
    icon:ClearAllPoints()
    icon:SetScript("OnEnter", nil)
    icon:SetScript("OnLeave", nil)

    -- Reset textures
    if icon.iconTexture then
        icon.iconTexture:SetDesaturated(false)
        icon.iconTexture:SetAlpha(1.0)
        icon.iconTexture:SetTexture(nil)
    end
    if icon.border then
        icon.border:SetColorTexture(0.4, 0.4, 0.4, 0.8)
        icon.border:Show()
    end
    if icon.cooldownText then
        icon.cooldownText:SetText("")
    end

    -- Clear stored data
    icon.teleportID = nil
    icon.isSpell = nil
    icon.data = nil
    icon.entry = nil

    table_insert(self.iconPool, icon)
end

--- Clear all active icon frames (releases to pool)
function TeleportPanel:ClearIcons()
    for _, icon in ipairs(self.iconFrames) do
        self:ReleaseIconFrame(icon)
    end
    wipe(self.iconFrames)
end


-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create teleport panel content inside a parent content frame (from MainFrame).
-- @param parentFrame Frame The content frame to parent all elements to
-- @return Frame The parent frame (with panel elements attached)
function TeleportPanel:CreateContent(parentFrame)
    if self.frame then
        return self.frame
    end

    local frame = parentFrame

    -- Row 1 (top): Filter dropdown (left) + Refresh (right)
    self.availabilityFilter = QR.db and QR.db.availabilityFilter or "all"
    self.groupByDestination = QR.db and QR.db.groupByDestination or false

    -- Filter dropdown (replaces availability button + group-by checkbox)
    local filterDropdown = CreateFrame("DropdownButton", "QRTeleportFilterDropdown", frame, "WowStyle1DropdownTemplate")
    filterDropdown:SetPoint("TOPLEFT", PADDING + 5, -4)
    filterDropdown:SetDefaultText(L["FILTER_OPTIONS"] or "Filter Options")
    filterDropdown:SetupMenu(function(_, rootDescription)
        -- Availability section
        rootDescription:CreateTitle(L["FILTER"] or "Filter:")
        rootDescription:CreateRadio(
            L["AVAIL_ALL"],
            function() return TeleportPanel.availabilityFilter == "all" end,
            function()
                TeleportPanel.availabilityFilter = "all"
                if QR.db then QR.db.availabilityFilter = "all" end
                TeleportPanel:RefreshList()
            end
        )
        rootDescription:CreateRadio(
            L["AVAIL_USABLE"],
            function() return TeleportPanel.availabilityFilter == "usable" end,
            function()
                TeleportPanel.availabilityFilter = "usable"
                if QR.db then QR.db.availabilityFilter = "usable" end
                TeleportPanel:RefreshList()
            end
        )
        rootDescription:CreateRadio(
            L["AVAIL_OBTAINABLE"],
            function() return TeleportPanel.availabilityFilter == "obtainable" end,
            function()
                TeleportPanel.availabilityFilter = "obtainable"
                if QR.db then QR.db.availabilityFilter = "obtainable" end
                TeleportPanel:RefreshList()
            end
        )

        rootDescription:CreateDivider()

        -- Display section
        rootDescription:CreateCheckbox(
            L["GROUP_BY_DEST"],
            function() return TeleportPanel.groupByDestination end,
            function()
                TeleportPanel.groupByDestination = not TeleportPanel.groupByDestination
                if QR.db then QR.db.groupByDestination = TeleportPanel.groupByDestination end
                TeleportPanel:RefreshList()
            end
        )
    end)
    frame.filterDropdown = filterDropdown

    -- Refresh button (right-anchored on row 1)
    local refreshText = L and L["REFRESH"] or "Refresh"
    local refreshWidth = math_max(70, (#refreshText * 7) + 16)
    local refreshButton = QR.CreateModernButton(frame, refreshWidth, 22)
    refreshButton:SetPoint("TOPRIGHT", -PADDING - 5, -4)
    refreshButton:SetText(refreshText)
    refreshButton:SetScript("OnClick", function()
        local success, err = pcall(function()
            local now = GetTime()
            if now - TeleportPanel.lastRefreshClickTime < 1 then return end
            TeleportPanel.lastRefreshClickTime = now
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

            TeleportPanel.isScanning = true
            refreshButton:SetText("...")
            frame.statusSummary:SetText(C.YELLOW .. L["SCANNING"] .. C.R)

            QR.PlayerInventory:ScanAll()
            TeleportPanel:RefreshList()

            TeleportPanel.isScanning = false
            refreshButton:SetText(L["REFRESH"])
        end)
        if not success then
            QR:Error(tostring(err))
        end
    end)
    refreshButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOOLTIP_RESCAN"])
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    refreshButton:SetScript("OnLeave", GameTooltip_Hide)
    frame.refreshButton = refreshButton

    -- Column headers
    local headerY = -32
    local nameHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHeader:SetPoint("TOPLEFT", PADDING + ICON_SIZE + 10, headerY)
    nameHeader:SetText(C.WHITE .. L["NAME"] .. C.R)

    local statusHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHeader:SetPoint("TOPRIGHT", -PADDING - 5, headerY)
    statusHeader:SetText(C.WHITE .. L["STATUS"] .. C.R)

    -- Header separator
    local headerSep = frame:CreateTexture(nil, "ARTWORK")
    headerSep:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", PADDING, headerY - 12)
    headerSep:SetPoint("TOPRIGHT", -PADDING, headerY - 12)

    -- Create scroll frame for teleport list
    local scrollFrame = CreateFrame("ScrollFrame", "QRTeleportScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, headerY - 15)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 12, PADDING + 5)
    frame.scrollFrame = scrollFrame
    QR.SkinScrollBar(scrollFrame)

    -- Content frame inside scroll frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_MIN_WIDTH - 40, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild

    -- Status summary at bottom
    local statusSummary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusSummary:SetPoint("BOTTOMLEFT", PADDING + 5, PADDING - 8)
    statusSummary:SetTextColor(0.7, 0.7, 0.7)
    statusSummary:SetText("")
    frame.statusSummary = statusSummary

    self.frame = frame
    return frame
end

--- Configure hover highlight and tooltip with extended info on a row
-- @param row Frame The row frame to configure
function TeleportPanel:ConfigureRowTooltip(row)
    -- Reuse or create highlight texture
    local highlight = row.highlight
    if not highlight then
        highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
        row.highlight = highlight
    end
    highlight:Hide()

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        -- Show tooltip with extended info
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isSpell then
            GameTooltip:SetSpellByID(self.teleportID)
        else
            GameTooltip:SetItemByID(self.teleportID)
            -- Suppress comparison tooltips for equipped items
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end
        -- Add location info for items
        if self.entry and not self.isSpell then
            local locInfo = TeleportPanel:GetItemLocationInfo(self.teleportID, self.entry)
            if locInfo then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(locInfo, 0.7, 0.7, 1.0, true)
            end
        end
        -- Add acquisition info for missing items
        if self.entry and self.entry.status == STATUS.MISSING then
            local acqInfo = TeleportPanel:GetAcquisitionInfo(self.teleportID, self.entry)
            if acqInfo then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(C.YELLOW .. L["HOW_TO_OBTAIN"] .. C.R, 1, 1, 0)
                GameTooltip:AddLine(acqInfo, 0.8, 0.8, 0.8, true)
            end
        end
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip_Hide()
    end)
end

--- Get icon texture ID for a teleport entry
-- @param entry table The teleport entry
-- @return number|string Icon texture ID or fallback path
local function GetIconTexture(entry)
    if entry.isSpell then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
        if spellInfo then
            return spellInfo.iconID
        end
        local _, _, spellIcon = GetSpellInfo(entry.id)
        if spellIcon then return spellIcon end
    else
        local itemIcon = GetItemIcon(entry.id)
        if itemIcon then return itemIcon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

--- Configure the icon on a row - for owned items the icon IS the secure action button
-- @param row Frame The row frame
-- @param entry table The teleport entry
function TeleportPanel:ConfigureRowIcon(row, entry)
    local iconTexture = GetIconTexture(entry)
    local isOwned = entry.status == STATUS.READY or entry.status == STATUS.ON_CD or entry.status == STATUS.OWNED

    if isOwned and QR.SecureButtons and not InCombatLockdown() then
        -- Icon IS the secure action button
        local iconBtn = QR.SecureButtons:GetButton()
        if iconBtn then
            local sourceType = entry.isSpell and "spell" or (entry.data.type == QR.TeleportTypes.TOY and "toy" or "item")
            local configured = QR.SecureButtons:ConfigureButton(iconBtn, entry.id, sourceType)
            if configured then
                iconBtn:SetFrameStrata("DIALOG")
                iconBtn:SetFrameLevel(100)
                iconBtn:SetSize(ICON_SIZE, ICON_SIZE)
                QR.SecureButtons:AttachOverlay(iconBtn, row, self.frame and self.frame.scrollFrame, 2, true)

                -- Create icon texture on the secure button
                if not iconBtn.iconTexture then
                    iconBtn.iconTexture = iconBtn:CreateTexture(nil, "ARTWORK")
                    iconBtn.iconTexture:SetAllPoints()
                end
                iconBtn.iconTexture:SetTexture(iconTexture)
                iconBtn.iconTexture:Show()

                -- Hide any leftover border from recycled buttons
                if iconBtn.border then
                    iconBtn.border:Hide()
                end

                -- Highlight on hover
                iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

                -- Dim if on cooldown
                if entry.status == STATUS.ON_CD then
                    iconBtn:SetAlpha(0.5)
                else
                    iconBtn:SetAlpha(1.0)
                end

                -- Tooltip on the icon button
                iconBtn:SetScript("OnEnter", function(self)
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
                        GameTooltip:AddLine("|cFFFF0000" .. L["CANNOT_USE_IN_COMBAT"] .. "|r")
                    end
                    QR.AddTooltipBranding(GameTooltip)
                    GameTooltip:Show()
                end)
                iconBtn:SetScript("OnLeave", function()
                    GameTooltip_Hide()
                end)

                iconBtn:Show()
                row.useButton = iconBtn

                -- Hide the static icon (secure button replaces it)
                if row.icon then row.icon:Hide() end
                return
            else
                QR.SecureButtons:ReleaseButton(iconBtn)
            end
        end
    end

    -- Fallback: static icon texture (non-owned or no button available)
    local icon = row.icon
    if not icon then
        icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.icon = icon
    end
    icon:SetTexture(iconTexture)
    -- Desaturate non-owned items
    if entry.status == STATUS.MISSING or entry.status == STATUS.NA then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.5)
    else
        icon:SetDesaturated(false)
        icon:SetAlpha(1.0)
    end
    icon:Show()
end

--- Configure the name, destination, and status text columns on a row
-- @param row Frame The row frame
-- @param entry table The teleport entry
function TeleportPanel:ConfigureRowTexts(row, entry)
    local textLeftOffset = ICON_SIZE + 8

    -- Reuse or create name text (top line, next to icon)
    local nameText = row.nameText
    if not nameText then
        nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", row, "TOPLEFT", textLeftOffset, -2)
        nameText:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText
    end

    -- Apply status color to name (localized via WoW API)
    local name = GetLocalizedTeleportName(entry) or ("ID: " .. entry.id)
    nameText:SetText(entry.status.color .. name .. "|r")
    if nameText.SetTextToFit then nameText:SetTextToFit() end
    nameText:Show()

    -- Reuse or create destination text (bottom line, below name)
    local destText = row.destText
    if not destText then
        destText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        destText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeftOffset, 2)
        destText:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        destText:SetJustifyH("LEFT")
        destText:SetWordWrap(false)
        row.destText = destText
    end
    destText:SetTextColor(0.6, 0.6, 0.6)
    destText:SetText(GetLocalizedDestination(entry) or L["UNKNOWN"])
    if destText.SetTextToFit then destText:SetTextToFit() end
    destText:Show()

    -- Reuse or create status text (right-aligned, vertically centered)
    local statusText = row.statusText
    if not statusText then
        statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        statusText:SetJustifyH("RIGHT")
        row.statusText = statusText
    end

    -- Format status with cooldown time if applicable
    local statusStr = entry.status.text or entry.status.key or "?"
    if entry.status == STATUS.ON_CD and entry.cooldownRemaining then
        local timeStr = QR.CooldownTracker:FormatTime(entry.cooldownRemaining)
        statusStr = statusStr .. " " .. timeStr
    end
    statusText:SetText(entry.status.color .. statusStr .. "|r")
    statusText:Show()
end

--- Create a row for a single teleport entry
-- @param entry table The teleport entry
-- @param yOffset number Vertical offset for the row
-- @return Frame The created row frame
function TeleportPanel:CreateTeleportRow(entry, yOffset)
    local scrollChild = self.frame.scrollChild
    local panelWidth = self.frame:GetWidth()

    -- Get row frame from pool (or create new)
    local row = self:GetRowFrame()
    row:SetParent(scrollChild)
    row:SetSize(panelWidth - 50, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    row:EnableMouse(true)
    row:Show()

    -- Store data for tooltip
    row.teleportID = entry.id
    row.isSpell = entry.isSpell
    row.data = entry.data
    row.entry = entry

    self:ConfigureRowTooltip(row)
    self:ConfigureRowIcon(row, entry)
    self:ConfigureRowTexts(row, entry)

    return row
end

--- Get item location information (bags, bank, etc.)
-- @param itemID number The item ID
-- @param entry table The teleport entry
-- @return string|nil Location description or nil
function TeleportPanel:GetItemLocationInfo(itemID, entry)
    if not itemID then return nil end

    local data = entry and entry.data
    local itemType = data and data.type

    -- Toys are account-wide, no specific location
    if itemType == QR.TeleportTypes.TOY then
        if PlayerHasToy and PlayerHasToy(itemID) then
            return L["LOC_TOY_COLLECTION"]
        end
        return nil
    end

    -- Check bag scan cache to avoid scanning 150+ slots on every tooltip hover
    local now = GetTime()
    if now - bagScanCacheTime < BAG_CACHE_TTL and bagScanCache[itemID] ~= nil then
        return bagScanCache[itemID]
    end

    -- Use shared container API helpers from PlayerInventory (DRY)
    local safeNumSlots = QR.PlayerInventory.SafeGetContainerNumSlots
    local safeItemID = QR.PlayerInventory.SafeGetContainerItemID

    -- Check bags
    local result = nil
    for bag = 0, 4 do
        local numSlots = safeNumSlots(bag)
        for slot = 1, numSlots do
            if safeItemID(bag, slot) == itemID then
                result = string_format(L["LOC_IN_BAGS"], bag, slot)
                bagScanCache[itemID] = result
                bagScanCacheTime = now
                return result
            end
        end
    end

    -- Check bank (if we can access it)
    if IsAtBank and IsAtBank() then
        -- Main bank slots (bag -1)
        local numBankSlots = safeNumSlots(-1)
        for slot = 1, numBankSlots do
            if safeItemID(-1, slot) == itemID then
                result = L["LOC_IN_BANK_MAIN"]
                bagScanCache[itemID] = result
                bagScanCacheTime = now
                return result
            end
        end
        -- Bank bags (5-11)
        for bag = 5, 11 do
            local numSlots = safeNumSlots(bag)
            for slot = 1, numSlots do
                if safeItemID(bag, slot) == itemID then
                    result = string_format(L["LOC_IN_BANK_BAG"], bag - 4)
                    bagScanCache[itemID] = result
                    bagScanCacheTime = now
                    return result
                end
            end
        end
    end

    -- If owned but not found, might be in bank (not at bank NPC)
    if entry and (entry.status == STATUS.OWNED or entry.status == STATUS.READY or entry.status == STATUS.ON_CD) then
        result = L["LOC_BANK_OR_BAGS"]
        bagScanCache[itemID] = result
        bagScanCacheTime = now
        return result
    end

    -- Cache nil result too (as false, since cache uses ~= nil check)
    bagScanCache[itemID] = false
    bagScanCacheTime = now
    return nil
end

--- Check if a reputation requirement is satisfied
-- @param factionName string The faction name (English)
-- @param requiredLevel string The required standing (e.g., "Exalted", "Revered")
-- @return boolean, number, string Whether met, current standing value, standing name
local function CheckReputationRequirement(factionName, requiredLevel)
    if not factionName then return false, 0, L["UNKNOWN"] end

    -- Map standing names (English keys from data) to numeric values
    local standingValues = {
        ["Hated"] = 1, ["Hostile"] = 2, ["Unfriendly"] = 3, ["Neutral"] = 4,
        ["Friendly"] = 5, ["Honored"] = 6, ["Revered"] = 7, ["Exalted"] = 8,
    }
    local requiredValue = standingValues[requiredLevel] or 5
    -- Localized standing name for display (WoW provides FACTION_STANDING_LABEL1..8)
    local localizedRequiredLevel = _G and _G["FACTION_STANDING_LABEL" .. requiredValue] or requiredLevel

    -- Find the faction ID by name (iterate through known factions)
    local numFactions = GetNumFactions and GetNumFactions() or 0
    for i = 1, numFactions do
        local name, _, standingID = GetFactionInfo(i)
        if name and name:lower() == factionName:lower() then
            local standingName = _G["FACTION_STANDING_LABEL" .. standingID] or L["UNKNOWN"]
            return standingID >= requiredValue, standingID, standingName
        end
    end

    -- Faction not found in player's known factions
    return false, 0, L["UNKNOWN"]
end

--- Check if a quest requirement is satisfied
-- @param questID number The quest ID
-- @return boolean, boolean Whether completed, whether on quest log
local function CheckQuestRequirement(questID)
    if not questID then return false, false end

    local isComplete = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(questID)
    local isOnLog = C_QuestLog and C_QuestLog.IsOnQuest
        and C_QuestLog.IsOnQuest(questID)

    return isComplete or false, isOnLog or false
end

--- Check if an achievement requirement is satisfied
-- @param achievementID number The achievement ID
-- @return boolean, string Whether completed, achievement name
local function CheckAchievementRequirement(achievementID)
    if not achievementID then return false, L["UNKNOWN"] end

    local id, name, _, completed = GetAchievementInfo(achievementID)
    return completed or false, name or L["REQ_ACHIEVEMENT"]
end

--- Get acquisition information for missing items with requirement checks
-- @param itemID number The item ID
-- @param entry table The teleport entry
-- @return string|nil Acquisition info or nil
function TeleportPanel:GetAcquisitionInfo(itemID, entry)
    if not itemID or not entry then return nil end

    local data = entry.data
    if not data then return nil end

    local lines = {}

    -- Check for reputation requirement
    if data.requiredRep then
        local factionName = data.requiredRep.faction or L["UNKNOWN"]
        local requiredLevel = data.requiredRep.level or "Friendly"
        local isMet, currentStanding, standingName = CheckReputationRequirement(factionName, requiredLevel)

        local statusIcon = isMet and "|cFF00FF00\226\156\147|r" or "|cFFFF0000\226\156\151|r"
        local statusColor = isMet and "|cFF00FF00" or "|cFFFFFF00"

        -- Use localized standing name from WoW globals (FACTION_STANDING_LABEL1..8)
        local standingValues = {
            ["Hated"] = 1, ["Hostile"] = 2, ["Unfriendly"] = 3, ["Neutral"] = 4,
            ["Friendly"] = 5, ["Honored"] = 6, ["Revered"] = 7, ["Exalted"] = 8,
        }
        local reqVal = standingValues[requiredLevel] or 5
        local localizedLevel = _G and _G["FACTION_STANDING_LABEL" .. reqVal] or requiredLevel

        table_insert(lines, string_format("%s %s: %s%s|r - %s",
            statusIcon, L["REQ_REPUTATION"], statusColor, localizedLevel, factionName))
        if not isMet and standingName ~= L["UNKNOWN"] then
            table_insert(lines, string_format("   %s: %s", L["REQ_CURRENT"], standingName))
        end
    end

    -- Check for quest requirement
    if data.requiredQuest then
        local questID = data.requiredQuest.id
        local questName = data.requiredQuest.name or string_format(L["QUEST_FALLBACK"], questID)
        local isComplete, isOnLog = CheckQuestRequirement(questID)

        local statusIcon = isComplete and "|cFF00FF00✓|r" or "|cFFFF0000✗|r"
        local questLink = questID and GetQuestLink and GetQuestLink(questID)
        local displayName = questLink or questName

        if isComplete then
            table_insert(lines, string_format("%s %s: %s (%s)", statusIcon, L["REQ_QUEST"], displayName, L["REQ_COMPLETE"]))
        elseif isOnLog then
            table_insert(lines, string_format("%s %s: %s (%s)", statusIcon, L["REQ_QUEST"], displayName, L["REQ_IN_PROGRESS"]))
        else
            table_insert(lines, string_format("%s %s: %s (%s)", statusIcon, L["REQ_QUEST"], displayName, L["REQ_NOT_STARTED"]))
        end
    end

    -- Check for achievement requirement
    if data.requiredAchievement then
        local achievementID = data.requiredAchievement.id
        local isComplete, achievementName = CheckAchievementRequirement(achievementID)

        local statusIcon = isComplete and "|cFF00FF00✓|r" or "|cFFFF0000✗|r"
        local achievementLink = achievementID and GetAchievementLink and GetAchievementLink(achievementID)
        local displayName = achievementLink or achievementName

        table_insert(lines, string_format("%s %s: %s", statusIcon, L["REQ_ACHIEVEMENT"], displayName))
    end

    -- Add vendor/NPC info if available
    if data.vendor then
        local vendorName = data.vendor.name or L["UNKNOWN_VENDOR"]
        local vendorLocation = data.vendor.location or ""
        local vendorMapID = data.vendor.mapID
        local vendorX = data.vendor.x
        local vendorY = data.vendor.y

        local locationStr = vendorLocation
        if vendorMapID and C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(vendorMapID)
            if mapInfo then
                locationStr = mapInfo.name
                if vendorX and vendorY then
                    locationStr = locationStr .. string_format(" (%.1f, %.1f)", vendorX * 100, vendorY * 100)
                end
            end
        end

        table_insert(lines, string_format(C.WHITE .. L["LOC_VENDOR"] .. C.R .. " %s", vendorName))
        if locationStr and locationStr ~= "" then
            table_insert(lines, string_format("   %s %s", L["LOC_LOCATION"], locationStr))
        end

        -- Store vendor info for Nav button
        entry.vendorMapID = vendorMapID
        entry.vendorX = vendorX
        entry.vendorY = vendorY
        entry.vendorName = vendorName
    end

    -- Add specific acquisition text (localized via L[] keys)
    if data.acquisition then
        local localizedAcq = GetLocalizedAcquisition(data.acquisition)
        table_insert(lines, C.GRAY .. localizedAcq .. C.R)
    end

    -- Generic hints based on item type (only if no specific info)
    if #lines == 0 then
        local itemType = data.type
        if itemType == QR.TeleportTypes.TOY then
            return L["HINT_CHECK_TOY_VENDORS"]
        elseif itemType == QR.TeleportTypes.ENGINEERING then
            return L["HINT_REQUIRES_ENGINEERING"]
        end
        return L["HINT_CHECK_WOWHEAD"]
    end

    return table_concat(lines, "\n")
end

--- Get vendor location for Nav button
-- @param entry table The teleport entry
-- @return number|nil, number|nil, number|nil, string|nil mapID, x, y, name
function TeleportPanel:GetVendorLocation(entry)
    if not entry or not entry.data then return nil end

    local data = entry.data
    if data.vendor and data.vendor.mapID then
        return data.vendor.mapID, data.vendor.x or 0.5, data.vendor.y or 0.5, data.vendor.name
    end

    return nil
end

-------------------------------------------------------------------------------
-- Grid Icon Configuration (grouped mode) — must be after GetIconTexture
-------------------------------------------------------------------------------

--- Configure a single grid icon for a teleport entry
-- @param iconFrame Frame The icon frame to configure
-- @param entry table The teleport entry
function TeleportPanel:ConfigureGridIcon(iconFrame, entry)
    local iconTexture = GetIconTexture(entry)
    local isOwned = entry.status == STATUS.READY or entry.status == STATUS.ON_CD or entry.status == STATUS.OWNED

    -- Store data for tooltip
    iconFrame.teleportID = entry.id
    iconFrame.isSpell = entry.isSpell
    iconFrame.data = entry.data
    iconFrame.entry = entry

    if isOwned and QR.SecureButtons and not InCombatLockdown() then
        local iconBtn = QR.SecureButtons:GetButton()
        if iconBtn then
            local sourceType = entry.isSpell and "spell" or (entry.data.type == QR.TeleportTypes.TOY and "toy" or "item")
            local configured = QR.SecureButtons:ConfigureButton(iconBtn, entry.id, sourceType)
            if configured then
                iconBtn:SetFrameStrata("DIALOG")
                iconBtn:SetFrameLevel(100)
                iconBtn:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
                QR.SecureButtons:AttachOverlay(iconBtn, iconFrame, self.frame and self.frame.scrollFrame, 0, true)

                if not iconBtn.iconTexture then
                    iconBtn.iconTexture = iconBtn:CreateTexture(nil, "ARTWORK")
                    iconBtn.iconTexture:SetAllPoints()
                end
                iconBtn.iconTexture:SetTexture(iconTexture)
                iconBtn.iconTexture:Show()

                if iconBtn.border then
                    iconBtn.border:Hide()
                end

                iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

                if entry.status == STATUS.ON_CD then
                    iconBtn:SetAlpha(0.5)
                else
                    iconBtn:SetAlpha(1.0)
                end

                -- Tooltip on the secure button
                iconBtn:SetScript("OnEnter", function(self)
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
                        GameTooltip:AddLine("|cFFFF0000" .. L["CANNOT_USE_IN_COMBAT"] .. "|r")
                    end
                    QR.AddTooltipBranding(GameTooltip)
                    GameTooltip:Show()
                end)
                iconBtn:SetScript("OnLeave", function()
                    GameTooltip_Hide()
                end)

                iconBtn:Show()
                iconFrame.useButton = iconBtn

                -- Hide static icon (secure button replaces it)
                if iconFrame.iconTexture then iconFrame.iconTexture:Hide() end
                return
            else
                QR.SecureButtons:ReleaseButton(iconBtn)
            end
        end
    end

    -- Fallback: static icon (non-owned or no button available)
    iconFrame.iconTexture:SetTexture(iconTexture)
    iconFrame.iconTexture:Show()

    if entry.status == STATUS.MISSING then
        iconFrame.iconTexture:SetDesaturated(true)
        iconFrame.iconTexture:SetAlpha(0.7)
    elseif entry.status == STATUS.NA then
        iconFrame.iconTexture:SetDesaturated(true)
        iconFrame.iconTexture:SetAlpha(0.5)
    elseif entry.status == STATUS.ON_CD then
        iconFrame.iconTexture:SetDesaturated(false)
        iconFrame.iconTexture:SetAlpha(0.6)
    else
        iconFrame.iconTexture:SetDesaturated(false)
        iconFrame.iconTexture:SetAlpha(1.0)
    end

    -- Border by status: subtle green for owned, dark for cooldown, hidden for unowned
    if iconFrame.border then
        if entry.status == STATUS.READY or entry.status == STATUS.OWNED then
            iconFrame.border:SetColorTexture(0, 0.6, 0, 0.6)
            iconFrame.border:Show()
        elseif entry.status == STATUS.ON_CD then
            iconFrame.border:SetColorTexture(0.3, 0.3, 0.3, 0.6)
            iconFrame.border:Show()
        else
            iconFrame.border:Hide()
        end
    end

    -- Cooldown text overlay
    if entry.status == STATUS.ON_CD and entry.cooldownRemaining and QR.CooldownTracker then
        iconFrame.cooldownText:SetText(QR.CooldownTracker:FormatTime(entry.cooldownRemaining))
    else
        iconFrame.cooldownText:SetText("")
    end

    -- Tooltip on the static icon frame
    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isSpell then
            GameTooltip:SetSpellByID(self.teleportID)
        else
            GameTooltip:SetItemByID(self.teleportID)
            -- Suppress comparison tooltips for equipped items
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end
        if self.entry and not self.isSpell then
            local locInfo = TeleportPanel:GetItemLocationInfo(self.teleportID, self.entry)
            if locInfo then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(locInfo, 0.7, 0.7, 1.0, true)
            end
        end
        if self.entry and self.entry.status == STATUS.MISSING then
            local acqInfo = TeleportPanel:GetAcquisitionInfo(self.teleportID, self.entry)
            if acqInfo then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(C.YELLOW .. L["HOW_TO_OBTAIN"] .. C.R, 1, 1, 0)
                GameTooltip:AddLine(acqInfo, 0.8, 0.8, 0.8, true)
            end
        end
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)
end

--- Create a group's icon row (grid of icons for grouped mode)
-- @param group table The group data with teleports array
-- @param yOffset number Vertical offset for the icon row
-- @return number The new yOffset after the icon row
function TeleportPanel:CreateGroupIconRow(group, yOffset)
    local scrollChild = self.frame.scrollChild
    local panelWidth = self.frame:GetWidth()
    local availWidth = panelWidth - 50
    local iconsPerRow = math.floor((availWidth + GRID_ICON_GAP) / (GRID_ICON_SIZE + GRID_ICON_GAP))
    if iconsPerRow < 1 then iconsPerRow = 1 end

    local rowStartY = yOffset + GRID_ROW_PADDING
    local currentRow = 0

    for i, entry in ipairs(group.teleports) do
        local col = (i - 1) % iconsPerRow
        if col == 0 and i > 1 then
            currentRow = currentRow + 1
        end

        local iconFrame = self:GetIconFrame()
        iconFrame:SetParent(scrollChild)
        iconFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
            col * (GRID_ICON_SIZE + GRID_ICON_GAP),
            -(rowStartY + currentRow * (GRID_ICON_SIZE + GRID_ICON_GAP)))
        iconFrame:Show()

        self:ConfigureGridIcon(iconFrame, entry)
        table_insert(self.iconFrames, iconFrame)
    end

    local numRows = math.ceil(#group.teleports / iconsPerRow)
    local totalHeight = GRID_ROW_PADDING * 2 + numRows * (GRID_ICON_SIZE + GRID_ICON_GAP) - GRID_ICON_GAP
    return yOffset + totalHeight
end

-------------------------------------------------------------------------------
-- List Management
-------------------------------------------------------------------------------

--- Release a row frame back to the pool
-- @param row Frame The row frame to release
function TeleportPanel:ReleaseRowFrame(row)
    if not row then return end

    -- Release secure button back to pool
    if row.useButton and QR.SecureButtons then
        QR.SecureButtons:ReleaseButton(row.useButton)
        row.useButton = nil
    end

    row:Hide()
    row:SetParent(recycleContainer)
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)

    -- Hide all child elements to prevent ghost text
    if row.icon then
        row.icon:Hide()
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1.0)
    end
    if row.nameText then row.nameText:Hide() end
    if row.destText then row.destText:Hide() end
    if row.statusText then row.statusText:Hide() end
    if row.highlight then row.highlight:Hide() end

    -- Clear stored data
    row.teleportID = nil
    row.isSpell = nil
    row.data = nil
    row.entry = nil

    table_insert(self.rowPool, row)
end

--- Get a row frame from the pool or create a new one
-- @return Frame A row frame
function TeleportPanel:GetRowFrame()
    local row = table.remove(self.rowPool)
    if not row then
        row = CreateFrame("Frame", nil, nil)
        row:SetSize(PANEL_MIN_WIDTH - 50, ROW_HEIGHT)
    end
    return row
end

--- Clear all teleport rows and headers (releases frames to pool)
function TeleportPanel:ClearRows()
    for _, row in ipairs(self.teleportRows) do
        self:ReleaseRowFrame(row)
    end
    wipe(self.teleportRows)
    self:ClearIcons()
    self:ClearHeaders()
end

--- Create a zone group header row
-- @param group table The group data with name, mapID, teleports
-- @param yOffset number Vertical offset for the header
-- @return Frame The created header frame
-- @return number The new yOffset after the header
function TeleportPanel:CreateGroupHeader(group, yOffset)
    local scrollChild = self.frame.scrollChild
    local panelWidth = self.frame:GetWidth()

    local header = self:GetHeaderFrame()
    header:SetParent(scrollChild)
    header:SetWidth(panelWidth - 50)
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    header:Show()

    -- Zone name in gold
    local zoneName = group.name
    local continentKey = group.mapID and QR.GetContinentForZone and QR.GetContinentForZone(group.mapID)
    local continentName = continentKey and QR.GetLocalizedContinentName and QR.GetLocalizedContinentName(continentKey)
    if continentName then
        header.zoneText:SetText(C.GOLD .. zoneName .. C.R .. "  " .. C.GRAY .. continentName .. C.R)
    else
        header.zoneText:SetText(C.GOLD .. zoneName .. C.R)
    end

    -- Count in gray
    header.countText:SetText(C.GRAY .. string_format(L["TELEPORTS_COUNT"], #group.teleports) .. C.R)

    table_insert(self.headerRows, header)
    return header, yOffset + 24
end

--- Refresh the teleport list
function TeleportPanel:RefreshList()
    if not self.frame then
        return
    end

    -- Invalidate bag scan cache on refresh
    wipe(bagScanCache)
    bagScanCacheTime = 0

    -- Clear existing rows
    self:ClearRows()

    -- Collect, filter, and sort teleports
    local allTeleports = self:CollectAllTeleports()
    local filtered = self:FilterTeleports(allTeleports)

    -- Apply availability filter (all → usable → obtainable)
    local availFilter = self.availabilityFilter or (QR.db and QR.db.availabilityFilter) or "all"
    if availFilter ~= "all" then
        local availFiltered = {}
        for _, entry in ipairs(filtered) do
            if availFilter == "usable" then
                -- Only off-cooldown, owned items
                if entry.status == STATUS.READY then
                    table_insert(availFiltered, entry)
                end
            elseif availFilter == "obtainable" then
                -- Owned + obtainable, exclude only faction/class-locked (NA)
                if entry.status ~= STATUS.NA then
                    table_insert(availFiltered, entry)
                end
            end
        end
        filtered = availFiltered
    end

    local yOffset = 0
    local readyCount = 0
    local ownedCount = 0
    local totalCount = 0

    if self.groupByDestination then
        -- Grouped display with icon grid
        local groups = self:GroupTeleportsByDestination(filtered)

        for _, group in ipairs(groups) do
            -- Create group header
            local _, newOffset = self:CreateGroupHeader(group, yOffset)
            yOffset = newOffset

            -- Icon grid instead of list rows
            yOffset = self:CreateGroupIconRow(group, yOffset)

            -- Count stats
            for _, entry in ipairs(group.teleports) do
                totalCount = totalCount + 1
                if entry.status == STATUS.READY or entry.status == STATUS.ON_CD or entry.status == STATUS.OWNED then
                    ownedCount = ownedCount + 1
                    if entry.status == STATUS.READY then
                        readyCount = readyCount + 1
                    end
                end
            end
        end

        self.sortedTeleports = filtered
    else
        -- Flat display (original behavior)
        local sorted = self:SortTeleports(filtered)
        self.sortedTeleports = sorted
        totalCount = #sorted

        for _, entry in ipairs(sorted) do
            local row = self:CreateTeleportRow(entry, yOffset)
            table_insert(self.teleportRows, row)
            yOffset = yOffset + ROW_HEIGHT

            -- Count stats
            if entry.status == STATUS.READY or entry.status == STATUS.ON_CD or entry.status == STATUS.OWNED then
                ownedCount = ownedCount + 1
                if entry.status == STATUS.READY then
                    readyCount = readyCount + 1
                end
            end
        end
    end

    -- Update scroll child height
    self.frame.scrollChild:SetHeight(yOffset + PADDING)

    -- Update status summary
    self.frame.statusSummary:SetText(string_format(
        L["SHOWING_TELEPORTS"],
        totalCount, ownedCount, readyCount
    ))
end

-------------------------------------------------------------------------------
-- Show/Hide/Toggle
-------------------------------------------------------------------------------

--- Show the teleport panel (delegates to MainFrame)
function TeleportPanel:Show()
    if QR.MainFrame then
        QR.MainFrame:Show("teleports")
    end
end

--- Hide the teleport panel (delegates to MainFrame)
function TeleportPanel:Hide()
    if QR.MainFrame then
        QR.MainFrame:Hide()
    end
end

--- Toggle the teleport panel (delegates to MainFrame)
function TeleportPanel:Toggle()
    if QR.MainFrame then
        QR.MainFrame:Toggle("teleports")
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the TeleportPanel module
function TeleportPanel:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

    -- Initialize localized strings
    InitializeStatusText()
    InitializeFilters()

    -- Create content inside MainFrame's teleports content area
    if QR.MainFrame then
        local contentFrame = QR.MainFrame:GetContentFrame("teleports")
        if contentFrame then
            self:CreateContent(contentFrame)
        end
    end

    -- Auto-refresh when inventory changes while panel is showing
    if QR.SecureButtons then
        QR.SecureButtons:RegisterCombatEndCallback(function()
            if QR.MainFrame and QR.MainFrame.isShowing
                and QR.MainFrame.activeTab == "teleports" and TeleportPanel.frame then
                TeleportPanel:RefreshList()
            end
        end)
    end

    -- Listen for inventory changes to auto-refresh
    local refreshFrame = CreateFrame("Frame")
    local refreshDebounceTimer = nil
    refreshFrame:RegisterEvent("BAG_UPDATE")
    refreshFrame:RegisterEvent("TOYS_UPDATED")
    refreshFrame:RegisterEvent("SPELLS_CHANGED")
    refreshFrame:SetScript("OnEvent", function()
        local isActive = QR.MainFrame and QR.MainFrame.isShowing and QR.MainFrame.activeTab == "teleports"
        if isActive and not InCombatLockdown() then
            if refreshDebounceTimer then
                refreshDebounceTimer:Cancel()
            end
            refreshDebounceTimer = C_Timer.NewTimer(0.7, function()
                refreshDebounceTimer = nil
                local stillActive = QR.MainFrame and QR.MainFrame.isShowing and QR.MainFrame.activeTab == "teleports"
                if stillActive and not InCombatLockdown() then
                    TeleportPanel:RefreshList()
                end
            end)
        end
    end)

    -- Combat handling is done by MainFrame (single combat callback)

    QR:Debug("TeleportPanel initialized")
end

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

SLASH_QRTELEPORTS1 = "/qrteleports"
SlashCmdList["QRTELEPORTS"] = function(msg)
    TeleportPanel:Toggle()
end
