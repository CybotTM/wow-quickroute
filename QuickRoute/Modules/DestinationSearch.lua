-- DestinationSearch.lua
-- Unified search box + dropdown for routing to waypoints, cities, and dungeons.
local ADDON_NAME, QR = ...

local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local string_lower = string.lower
local string_find = string.find
local table_insert, table_sort = table.insert, table.sort
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

QR.DestinationSearch = {
    frame = nil,
    searchBox = nil,
    isShowing = false,
    rows = {},
    rowPool = {},
    collapsedSections = {},
}

local DS = QR.DestinationSearch
local L

-- Constants
local DROPDOWN_WIDTH = 340
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 24
local PADDING = 6
local MAX_VISIBLE_ROWS = 16

-- Hidden container for recycled frames
local recycleContainer = CreateFrame("Frame")
recycleContainer:Hide()

--- Collect all destination results, optionally filtered by search query
-- @param query string Search text (empty = all results)
-- @return table { waypoints = {}, cities = {}, dungeons = {}, services = {} }
function DS:CollectResults(query)
    L = QR.L
    local queryLower = string_lower(query or "")
    local isSearching = queryLower ~= ""

    local results = {
        waypoints = {},
        cities = {},
        dungeons = {},
        services = {},
    }

    -- 1. Active Waypoints
    if QR.WaypointIntegration then
        local ok, available = pcall(function()
            return QR.WaypointIntegration:GetAllAvailableWaypoints()
        end)
        if ok and available then
            for _, entry in ipairs(available) do
                if entry.waypoint then
                    local title = entry.waypoint.title or entry.label or "?"
                    if not isSearching or string_find(string_lower(title), queryLower, 1, true) then
                        table_insert(results.waypoints, {
                            name = title,
                            label = entry.label,
                            key = entry.key,
                            mapID = entry.waypoint.mapID,
                            x = entry.waypoint.x,
                            y = entry.waypoint.y,
                            source = entry.key,
                        })
                    end
                end
            end
        end
    end

    -- 2. Cities (filtered by player faction)
    local playerFaction = QR.PlayerInfo and QR.PlayerInfo:GetFaction() or "Alliance"
    local cities = QR.CAPITAL_CITIES
    if cities then
        local cityList = {}
        for name, data in pairs(cities) do
            if data.faction == "both" or data.faction == playerFaction then
                if not isSearching or string_find(string_lower(name), queryLower, 1, true) then
                    table_insert(cityList, {
                        name = name,
                        mapID = data.mapID,
                        x = data.x,
                        y = data.y,
                        faction = data.faction,
                    })
                end
            end
        end
        table_sort(cityList, function(a, b) return a.name < b.name end)
        results.cities = cityList
    end

    -- 3. Dungeons & Raids (from DungeonData, grouped by tier)
    local DD = QR.DungeonData
    if DD and DD.scanned then
        for tier = DD.numTiers, 1, -1 do
            local tierName = DD:GetTierName(tier) or string_format("Tier %d", tier)
            local tierInstances = DD.byTier[tier] or {}

            local matchingInstances = {}
            for _, instanceID in ipairs(tierInstances) do
                local inst = DD.instances[instanceID]
                if inst and inst.name then
                    if not isSearching or string_find(string_lower(inst.name), queryLower, 1, true) then
                        table_insert(matchingInstances, {
                            name = inst.name,
                            isRaid = inst.isRaid,
                            zoneMapID = inst.zoneMapID,
                            x = inst.x,
                            y = inst.y,
                        })
                    end
                end
            end

            table_sort(matchingInstances, function(a, b)
                if a.isRaid ~= b.isRaid then return not a.isRaid end
                return a.name < b.name
            end)

            if #matchingInstances > 0 or not isSearching then
                table_insert(results.dungeons, {
                    tierName = tierName,
                    tierIndex = tier,
                    instances = matchingInstances,
                })
            end
        end
    end

    -- 4. Services (AH, Bank, Void Storage, Crafting Table)
    local SR = QR.ServiceRouter
    if SR then
        local serviceTypes = SR:GetServiceTypes()
        for _, serviceType in ipairs(serviceTypes) do
            local serviceName = SR:GetServiceName(serviceType)
            -- Match by localized name or slash alias (e.g. "ah" matches "Auction House")
            local aliasMatch = false
            if isSearching and QR.ServiceTypes and QR.ServiceTypes[serviceType] then
                local alias = QR.ServiceTypes[serviceType].slashAlias
                if alias and string_find(alias, queryLower, 1, true) then
                    aliasMatch = true
                end
            end
            if not isSearching or aliasMatch or string_find(string_lower(serviceName), queryLower, 1, true) then
                local locations = SR:GetLocations(serviceType)
                if #locations > 0 then
                    local locs = {}
                    for _, loc in ipairs(locations) do
                        table_insert(locs, {
                            name = SR:GetCityName(loc),
                            mapID = loc.mapID,
                            x = loc.x,
                            y = loc.y,
                            serviceType = serviceType,
                        })
                    end
                    table_sort(locs, function(a, b) return a.name < b.name end)
                    table_insert(results.services, {
                        serviceType = serviceType,
                        serviceName = serviceName,
                        locations = locs,
                    })
                end
            end
        end
    end

    return results
end

function DS:Initialize()
    L = QR.L
    self:RegisterCombat()
    QR:Debug("DestinationSearch initialized")
end

function DS:RegisterCombat()
    QR:RegisterCombatCallback(
        function() DS:HideDropdown() end,
        nil
    )
end

function DS:HideDropdown()
    if self.frame then
        self.frame:Hide()
    end
    self.isShowing = false
end

-------------------------------------------------------------------------------
-- Frame Creation
-------------------------------------------------------------------------------

--- Create the dropdown popup frame
-- @return Frame The dropdown frame
function DS:CreateDropdown()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "QRDestSearchDropdown", UIParent, "BackdropTemplate")
    frame:SetSize(DROPDOWN_WIDTH, PADDING * 2)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    -- Backdrop (tooltip-style, same as DungeonPicker)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Scroll frame for rows
    local scrollFrame = CreateFrame("ScrollFrame", "QRDestSearchScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 10, PADDING)
    QR.SkinScrollBar(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(DROPDOWN_WIDTH - PADDING * 2 - 18)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- ESC to close
    table_insert(UISpecialFrames, "QRDestSearchDropdown")

    -- Sync isShowing on hide
    frame:SetScript("OnHide", function()
        DS.isShowing = false
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
function DS:GetRow()
    -- Recycle from pool
    for _, row in ipairs(self.rowPool) do
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

    -- Tag label (category info)
    local tagLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    tagLabel:SetJustifyH("RIGHT")
    tagLabel:SetWidth(80)
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
function DS:ReleaseAllRows()
    for _, row in ipairs(self.rowPool) do
        if row.inUse then
            row.inUse = false
            row:Hide()
            row:SetParent(recycleContainer)
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row._isHeader = nil
            row._entryData = nil
        end
    end
    self.rows = {}
end

-------------------------------------------------------------------------------
-- Section Header Creation
-------------------------------------------------------------------------------

--- Create a collapsible section header row
-- @param sectionKey string Key for collapsedSections tracking
-- @param title string The section title text
-- @param yOffset number The vertical offset
-- @return Frame headerRow, number newYOffset
function DS:CreateSectionHeader(sectionKey, title, yOffset)
    local row = self:GetRow()
    row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
    row:SetHeight(HEADER_HEIGHT)

    -- Style as header: gold text with collapse arrow
    local collapsed = self.collapsedSections[sectionKey]
    local arrow = collapsed and "|cFFAAAAAA+ |r" or "|cFFAAAAAA- |r"
    row.nameLabel:SetText(arrow .. title)
    row.nameLabel:SetTextColor(1, 0.82, 0) -- Gold header color
    row.nameLabel:SetWidth(260)
    row.tagLabel:SetText("")

    -- Click to toggle collapse
    row:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        DS.collapsedSections[sectionKey] = not DS.collapsedSections[sectionKey]
        DS:RefreshDropdown(DS._lastQuery)
    end)

    -- Tooltip for header
    row:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        local tipText = L and L["SIDEBAR_COLLAPSE_TT"] or "Click to collapse/expand"
        GameTooltip:AddLine(tipText, 1, 1, 1)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    row._isHeader = true
    table_insert(self.rows, row)
    return row, yOffset + HEADER_HEIGHT
end

-------------------------------------------------------------------------------
-- Result Row Creation
-------------------------------------------------------------------------------

--- Create a result row for an individual entry
-- @param entry table Entry data with name, mapID, x, y, and optional category info
-- @param yOffset number The vertical offset
-- @return Frame row, number newYOffset
function DS:CreateResultRow(entry, yOffset)
    local row = self:GetRow()
    row:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)

    -- Name (indented under header)
    row.nameLabel:SetText("  " .. (entry.name or "?"))
    row.nameLabel:SetTextColor(1, 1, 1)
    row.nameLabel:SetWidth(220)

    -- Tag label with category info
    local tag = entry.tag or ""
    if entry.isRaid ~= nil then
        local tagText = entry.isRaid and (L and L["DUNGEON_RAID_TAG"] or "Raid") or (L and L["DUNGEON_TAG"] or "Dungeon")
        local tagColor = entry.isRaid and "|cFFFF6600" or "|cFF66CCFF"
        tag = tagColor .. tagText .. "|r"
    end
    row.tagLabel:SetText(tag)

    -- Click to select and route
    row:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        DS:SelectResult(entry)
    end)

    -- Tooltip
    row:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.name or "?", 1, 0.82, 0)
        -- Zone info
        local mapID = entry.mapID or entry.zoneMapID
        if mapID and C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.name then
                GameTooltip:AddLine(mapInfo.name, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine(L and L["DEST_SEARCH_ROUTE_TO_TT"] or "Click to calculate route", 0.5, 0.5, 0.5, true)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    row._entryData = entry
    table_insert(self.rows, row)
    return row, yOffset + ROW_HEIGHT
end

-------------------------------------------------------------------------------
-- Refresh Dropdown
-------------------------------------------------------------------------------

--- Refresh the dropdown content, applying search filter
-- @param query string|nil The search query text
function DS:RefreshDropdown(query)
    if not self.frame then return end

    L = QR.L

    self:ReleaseAllRows()

    query = query or ""
    self._lastQuery = query

    local results = self:CollectResults(query)

    local yOffset = 0
    local totalRows = 0

    -- 1. Active Waypoints section
    if #results.waypoints > 0 then
        local title = L and L["DEST_SEARCH_ACTIVE_WAYPOINT"] or "Active Waypoint"
        local _, newY = self:CreateSectionHeader("waypoints", title, yOffset)
        yOffset = newY
        totalRows = totalRows + 1

        if not self.collapsedSections["waypoints"] then
            for _, wp in ipairs(results.waypoints) do
                wp.tag = wp.source or ""
                local _, newY2 = self:CreateResultRow(wp, yOffset)
                yOffset = newY2
                totalRows = totalRows + 1
            end
        end
    end

    -- 2. Cities section
    if #results.cities > 0 then
        local title = L and L["DEST_SEARCH_CITIES"] or "Cities"
        local _, newY = self:CreateSectionHeader("cities", title, yOffset)
        yOffset = newY
        totalRows = totalRows + 1

        if not self.collapsedSections["cities"] then
            for _, city in ipairs(results.cities) do
                city.tag = ""  -- Section header provides category context
                local _, newY2 = self:CreateResultRow(city, yOffset)
                yOffset = newY2
                totalRows = totalRows + 1
            end
        end
    end

    -- 3. Dungeons & Raids section (one sub-header per tier)
    if #results.dungeons > 0 then
        local hasAnyInstances = false
        for _, tier in ipairs(results.dungeons) do
            if #tier.instances > 0 then hasAnyInstances = true end
        end

        if hasAnyInstances then
            local sectionTitle = L and L["DEST_SEARCH_DUNGEONS"] or "Dungeons & Raids"
            local _, newY = self:CreateSectionHeader("dungeons", sectionTitle, yOffset)
            yOffset = newY
            totalRows = totalRows + 1

            if not self.collapsedSections["dungeons"] then
                for _, tier in ipairs(results.dungeons) do
                    if #tier.instances > 0 then
                        -- Tier sub-header
                        local tierKey = "tier_" .. (tier.tierIndex or 0)
                        local _, newYTier = self:CreateSectionHeader(tierKey, tier.tierName, yOffset)
                        yOffset = newYTier
                        totalRows = totalRows + 1

                        if not self.collapsedSections[tierKey] then
                            for _, inst in ipairs(tier.instances) do
                                inst.mapID = inst.zoneMapID
                                local _, newY2 = self:CreateResultRow(inst, yOffset)
                                yOffset = newY2
                                totalRows = totalRows + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- 4. Services section
    if #results.services > 0 then
        local sectionTitle = L and L["DEST_SEARCH_SERVICES"] or "Services"
        local _, newY = self:CreateSectionHeader("services", sectionTitle, yOffset)
        yOffset = newY
        totalRows = totalRows + 1

        if not self.collapsedSections["services"] then
            for _, svc in ipairs(results.services) do
                -- "Nearest X" auto-pick row
                local nearestKey = "SERVICE_NEAREST_" .. svc.serviceType
                local nearestLabel = L and L[nearestKey] or ("Nearest " .. svc.serviceName)
                local nearestRow = self:GetRow()
                nearestRow:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
                nearestRow:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
                nearestRow.nameLabel:SetText("  " .. nearestLabel)
                nearestRow.nameLabel:SetTextColor(0.4, 0.8, 1)  -- Blue highlight for auto-pick
                nearestRow.tagLabel:SetText("")

                nearestRow:SetScript("OnClick", function()
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    if QR.ServiceRouter then
                        QR.ServiceRouter:RouteToNearest(svc.serviceType)
                    end
                    DS:HideDropdown()
                end)
                nearestRow:SetScript("OnEnter", function(btn)
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(nearestLabel, 1, 0.82, 0)
                    GameTooltip:AddLine(L and L["DEST_SEARCH_ROUTE_TO_TT"] or "Click to calculate route", 0.5, 0.5, 0.5, true)
                    QR.AddTooltipBranding(GameTooltip)
                    GameTooltip:Show()
                end)
                nearestRow:SetScript("OnLeave", function() GameTooltip_Hide() end)
                table_insert(self.rows, nearestRow)
                yOffset = yOffset + ROW_HEIGHT
                totalRows = totalRows + 1

                -- Individual city locations
                for _, loc in ipairs(svc.locations) do
                    loc.tag = ""
                    local _, newY2 = self:CreateResultRow(loc, yOffset)
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
        row.nameLabel:SetText(L and L["DEST_SEARCH_NO_RESULTS"] or "No matching destinations")
        row.nameLabel:SetTextColor(0.5, 0.5, 0.5)
        row.tagLabel:SetText("")
        table_insert(self.rows, row)
        yOffset = ROW_HEIGHT
    end

    -- Resize frame based on content
    local maxHeight = MAX_VISIBLE_ROWS * ROW_HEIGHT
    local contentHeight = yOffset
    local visibleHeight = contentHeight < maxHeight and contentHeight or maxHeight
    self.frame:SetHeight(visibleHeight + PADDING * 2)
    self.frame.scrollChild:SetHeight(contentHeight)
end

-------------------------------------------------------------------------------
-- Show / Select / Search
-------------------------------------------------------------------------------

--- Show the dropdown, optionally anchored to a frame
-- @param anchorFrame Frame|nil The frame to anchor below
function DS:ShowDropdown(anchorFrame)
    if InCombatLockdown() then return end

    if not self.frame then
        self:CreateDropdown()
    end

    -- Anchor below the provided frame, or center on screen
    self.frame:ClearAllPoints()
    if anchorFrame then
        self.frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    self:RefreshDropdown("")
    self.frame:Show()
    self.isShowing = true
end

--- Select a result entry and route to it
-- @param entry table Entry data with name, mapID, x, y
function DS:SelectResult(entry)
    if not entry then return end

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

    local mapID = entry.mapID or entry.zoneMapID
    if mapID and entry.x and entry.y and QR.POIRouting then
        QR.POIRouting:RouteToMapPosition(mapID, entry.x, entry.y)
    end

    -- Update search box text (suppress OnTextChanged to avoid re-entrancy)
    if self.searchBox and entry.name then
        self._suppressTextChanged = true
        self.searchBox:SetText(entry.name)
        self._suppressTextChanged = false
    end

    self:HideDropdown()
end

--- Called when search text changes while dropdown is visible
-- @param text string The current search text
function DS:OnSearchTextChanged(text)
    if self._suppressTextChanged then return end
    if self.isShowing then
        self:RefreshDropdown(text)
    end
end

--- Set search box text programmatically (suppresses OnTextChanged re-entrancy)
-- @param text string The text to set
function DS:SetSearchText(text)
    if self.searchBox then
        self._suppressTextChanged = true
        self.searchBox:SetText(text or "")
        self._suppressTextChanged = false
    end
end
