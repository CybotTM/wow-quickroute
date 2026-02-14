-- DungeonPicker.lua
-- Popup panel for browsing and selecting dungeon/raid instances grouped by expansion tier.
-- Supports search filtering and routes to the selected entrance.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local string_lower = string.lower
local string_find = string.find
local table_insert, table_sort = table.insert, table.sort
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- DungeonPicker Module
-------------------------------------------------------------------------------
QR.DungeonPicker = {
    frame = nil,
    isShowing = false,
    rows = {},
    rowPool = {},
    collapsedTiers = {},  -- tier -> true if collapsed
}

local DungeonPicker = QR.DungeonPicker

-- Constants
local PANEL_WIDTH = 340
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 24
local SEARCH_HEIGHT = 24
local PADDING = 6
local MAX_VISIBLE_ROWS = 14
local TITLE_HEIGHT = 22

-- Hidden container for recycled frames
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

-- Localization shorthand
local L

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create the picker frame
-- @return Frame The picker frame
function DungeonPicker:CreatePickerFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "QRDungeonPickerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, TITLE_HEIGHT + SEARCH_HEIGHT + PADDING * 3)
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
    title:SetTextColor(1, 0.82, 0) -- Gold title color
    frame.title = title

    -- Search EditBox
    local searchBox = CreateFrame("EditBox", "QRDungeonPickerSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(PANEL_WIDTH - PADDING * 2 - 10, SEARCH_HEIGHT)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 6, -(TITLE_HEIGHT + PADDING))
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetScript("OnTextChanged", function(self)
        DungeonPicker:RefreshList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    frame.searchBox = searchBox

    -- Scroll frame for rows
    local scrollFrame = CreateFrame("ScrollFrame", "QRDungeonPickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + SEARCH_HEIGHT + PADDING * 2))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 10, PADDING)
    QR.SkinScrollBar(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(PANEL_WIDTH - PADDING * 2 - 18)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- ESC to close
    table_insert(UISpecialFrames, "QRDungeonPickerFrame")

    -- Sync isShowing on hide
    frame:SetScript("OnHide", function()
        self.isShowing = false
    end)

    frame:Hide()
    self.frame = frame
    return frame
end

-------------------------------------------------------------------------------
-- Row Pool
-------------------------------------------------------------------------------

--- Create or recycle a row frame
-- @return Frame A row frame
function DungeonPicker:GetRow()
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
    local row = CreateFrame("Button", nil, self.frame.scrollChild)
    row:SetHeight(ROW_HEIGHT)

    -- Name label
    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("LEFT", row, "LEFT", 4, 0)
    nameLabel:SetWidth(220)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    row.nameLabel = nameLabel

    -- Tag label (Dungeon/Raid)
    local tagLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    tagLabel:SetJustifyH("RIGHT")
    tagLabel:SetWidth(60)
    row.tagLabel = tagLabel

    -- Highlight on mouse over
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    row.inUse = true
    table_insert(self.rowPool, row)
    return row
end

--- Release all rows back to pool
function DungeonPicker:ReleaseAllRows()
    for _, row in ipairs(self.rowPool) do
        if row.inUse then
            row.inUse = false
            row:Hide()
            row:SetParent(recycleContainer)
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        end
    end
    self.rows = {}
end

-------------------------------------------------------------------------------
-- Tier Header Creation
-------------------------------------------------------------------------------

--- Create a tier header row
-- @param tier number The tier index
-- @param tierName string The expansion name
-- @param yOffset number The vertical offset
-- @return Frame headerRow, number newYOffset
function DungeonPicker:CreateTierHeader(tier, tierName, yOffset)
    local row = self:GetRow()
    row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
    row:SetHeight(HEADER_HEIGHT)

    -- Style as header: gold text, separator line
    local collapsed = self.collapsedTiers[tier]
    local arrow = collapsed and "|cFFAAAAAA+ |r" or "|cFFAAAAAA- |r"
    row.nameLabel:SetText(arrow .. tierName)
    row.nameLabel:SetTextColor(1, 0.82, 0) -- Gold header color
    row.nameLabel:SetWidth(260)
    row.tagLabel:SetText("")

    -- Click to toggle collapse
    row:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self.collapsedTiers[tier] = not self.collapsedTiers[tier]
        self:RefreshList()
    end)

    -- Tooltip for header
    row:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tierName, 1, 0.82, 0)
        local tipText = collapsed and "Click to expand" or "Click to collapse"
        GameTooltip:AddLine(tipText, 1, 1, 1)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    table_insert(self.rows, row)
    return row, yOffset + HEADER_HEIGHT
end

-------------------------------------------------------------------------------
-- Instance Row Creation
-------------------------------------------------------------------------------

--- Create an instance row
-- @param inst table Instance data (from DungeonData)
-- @param yOffset number The vertical offset
-- @return Frame row, number newYOffset
function DungeonPicker:CreateInstanceRow(inst, yOffset)
    local row = self:GetRow()
    row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)

    -- Instance name (indented under tier header)
    row.nameLabel:SetText("  " .. (inst.name or "?"))
    row.nameLabel:SetTextColor(1, 1, 1)
    row.nameLabel:SetWidth(220)

    -- Tag: Dungeon or Raid
    local tag = inst.isRaid and (L and L["DUNGEON_RAID_TAG"] or "Raid") or (L and L["DUNGEON_TAG"] or "Dungeon")
    local tagColor = inst.isRaid and "|cFFFF6600" or "|cFF66CCFF"
    row.tagLabel:SetText(tagColor .. tag .. "|r")

    -- Click to route
    row:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        DungeonPicker:SelectInstance(inst)
    end)

    -- Tooltip
    row:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(inst.name or "?", 1, 0.82, 0)
        GameTooltip:AddLine(tag, 1, 1, 1)
        if inst.zoneMapID and C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(inst.zoneMapID)
            if mapInfo and mapInfo.name then
                GameTooltip:AddLine(mapInfo.name, 0.7, 0.7, 0.7)
            end
        end
        if inst.zoneMapID and inst.x and inst.y then
            GameTooltip:AddLine(L and L["DUNGEON_ROUTE_TO_TT"] or "Calculate the fastest route to this dungeon entrance", 0.5, 0.5, 0.5, true)
        else
            GameTooltip:AddLine("No entrance coordinates available", 0.8, 0.2, 0.2, true)
        end
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    table_insert(self.rows, row)
    return row, yOffset + ROW_HEIGHT
end

-------------------------------------------------------------------------------
-- Select Instance
-------------------------------------------------------------------------------

--- Route to the selected instance entrance
-- @param inst table Instance data with zoneMapID, x, y
function DungeonPicker:SelectInstance(inst)
    if not inst then return end

    if inst.zoneMapID and inst.x and inst.y and QR.POIRouting then
        QR.POIRouting:RouteToMapPosition(inst.zoneMapID, inst.x, inst.y)
    else
        QR:Print(L and L["DUNGEON_PICKER_NO_RESULTS"] or "No entrance coordinates available")
    end

    self:Hide()
end

-------------------------------------------------------------------------------
-- Refresh List
-------------------------------------------------------------------------------

--- Refresh the picker list, applying search filter
function DungeonPicker:RefreshList()
    if not self.frame then return end

    L = QR.L

    self:ReleaseAllRows()

    local DD = QR.DungeonData
    if not DD or not DD.scanned then
        -- No data available
        self.frame.title:SetText(L and L["DUNGEON_PICKER_TITLE"] or "Dungeons & Raids")
        local row = self:GetRow()
        row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
        row.nameLabel:SetText(L and L["DUNGEON_PICKER_NO_RESULTS"] or "No matching instances")
        row.nameLabel:SetTextColor(0.5, 0.5, 0.5)
        row.tagLabel:SetText("")
        table_insert(self.rows, row)

        local totalHeight = TITLE_HEIGHT + SEARCH_HEIGHT + ROW_HEIGHT + PADDING * 4
        self.frame:SetHeight(totalHeight)
        self.frame.scrollChild:SetHeight(ROW_HEIGHT)
        return
    end

    self.frame.title:SetText(L and L["DUNGEON_PICKER_TITLE"] or "Dungeons & Raids")

    -- Get search query
    local query = ""
    if self.frame.searchBox and self.frame.searchBox.GetText then
        query = self.frame.searchBox:GetText() or ""
    end
    local queryLower = string_lower(query)
    local isSearching = query ~= ""

    -- Build display: group by tier (newest first)
    local yOffset = 0
    local totalRows = 0

    -- Iterate tiers from newest to oldest
    for tier = DD.numTiers, 1, -1 do
        local tierName = DD:GetTierName(tier) or string_format("Tier %d", tier)
        local tierInstances = DD.byTier[tier] or {}

        -- Collect instances for this tier that match search
        local matchingInstances = {}
        for _, instanceID in ipairs(tierInstances) do
            local inst = DD.instances[instanceID]
            if inst and inst.name then
                local matches = true
                if isSearching then
                    matches = string_find(string_lower(inst.name), queryLower, 1, true) ~= nil
                end
                if matches then
                    table_insert(matchingInstances, {
                        instanceID = instanceID,
                        name = inst.name,
                        isRaid = inst.isRaid,
                        zoneMapID = inst.zoneMapID,
                        x = inst.x,
                        y = inst.y,
                        tier = inst.tier,
                        tierName = inst.tierName,
                    })
                end
            end
        end

        -- Sort: raids first, then alphabetical
        table_sort(matchingInstances, function(a, b)
            if a.isRaid ~= b.isRaid then
                return a.isRaid -- raids before dungeons (true > false)
            end
            return (a.name or "") < (b.name or "")
        end)

        -- Only show this tier if it has matching instances
        if #matchingInstances > 0 then
            -- Tier header (always visible when there are matches)
            local _, newY = self:CreateTierHeader(tier, tierName, yOffset)
            yOffset = newY
            totalRows = totalRows + 1

            -- Instance rows (hidden if collapsed, unless searching)
            if not self.collapsedTiers[tier] or isSearching then
                for _, inst in ipairs(matchingInstances) do
                    local _, newY2 = self:CreateInstanceRow(inst, yOffset)
                    yOffset = newY2
                    totalRows = totalRows + 1
                end
            end
        end
    end

    -- "No results" message
    if totalRows == 0 then
        local row = self:GetRow()
        row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
        row.nameLabel:SetText(L and L["DUNGEON_PICKER_NO_RESULTS"] or "No matching instances")
        row.nameLabel:SetTextColor(0.5, 0.5, 0.5)
        row.tagLabel:SetText("")
        table_insert(self.rows, row)
        yOffset = ROW_HEIGHT
        totalRows = 1
    end

    -- Set frame height based on rows (capped)
    local visibleRows = totalRows <= MAX_VISIBLE_ROWS and totalRows or MAX_VISIBLE_ROWS
    local contentHeight = yOffset
    local frameHeight = TITLE_HEIGHT + SEARCH_HEIGHT + visibleRows * ROW_HEIGHT + PADDING * 4
    self.frame:SetHeight(frameHeight)
    self.frame.scrollChild:SetHeight(contentHeight)
end

-------------------------------------------------------------------------------
-- Show / Hide / Toggle
-------------------------------------------------------------------------------

--- Show the picker, anchored to a trigger button
-- @param anchorButton Frame|nil The button to anchor to
function DungeonPicker:Show(anchorButton)
    if InCombatLockdown() then
        QR:Print(L and L["CANNOT_USE_IN_COMBAT"] or "Cannot use during combat")
        return
    end

    if not self.frame then
        self:CreatePickerFrame()
    end

    -- Anchor below the trigger button
    self.frame:ClearAllPoints()
    if anchorButton then
        self.frame:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -4)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    -- Set search placeholder text
    if self.frame.searchBox then
        self.frame.searchBox:SetText("")
        if self.frame.searchBox.SetTextInsets then
            self.frame.searchBox:SetTextInsets(2, 2, 0, 0)
        end
    end

    self:RefreshList()
    self.frame:Show()
    self.isShowing = true
end

--- Hide the picker
function DungeonPicker:Hide()
    if self.frame then
        self:ReleaseAllRows()
        self.frame:Hide()
    end
    self.isShowing = false
end

--- Toggle the picker
-- @param anchorButton Frame|nil The button to anchor to
function DungeonPicker:Toggle(anchorButton)
    if self.isShowing then
        self:Hide()
    else
        self:Show(anchorButton)
    end
end

-------------------------------------------------------------------------------
-- Combat Integration
-------------------------------------------------------------------------------

--- Initialize combat callbacks for auto-hide
function DungeonPicker:RegisterCombat()
    QR:RegisterCombatCallback(
        -- Enter combat: hide picker
        function()
            if DungeonPicker.isShowing and DungeonPicker.frame then
                DungeonPicker.frame:Hide()
                DungeonPicker.isShowing = false
            end
        end,
        -- Leave combat: no action needed
        nil
    )
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function DungeonPicker:Initialize()
    L = QR.L
    self:RegisterCombat()
    QR:Debug("DungeonPicker initialized")
end
