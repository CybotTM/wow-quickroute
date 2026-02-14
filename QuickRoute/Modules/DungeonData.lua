-- DungeonData.lua
-- Runtime scanner, static fallback merger, and lookup API for dungeon/raid data.
-- Builds a unified catalog from the Encounter Journal API and static fallback data.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local table_insert = table.insert
local table_sort = table.sort
local string_lower = string.lower
local string_find = string.find
local string_format = string.format

-------------------------------------------------------------------------------
-- DungeonData Module
-------------------------------------------------------------------------------
QR.DungeonData = {
    instances = {},         -- journalInstanceID -> { name, zoneMapID, x, y, isRaid, tier, tierName, atlasName }
    byZone = {},            -- zoneMapID -> { journalInstanceID, ... }
    byTier = {},            -- tierIndex -> { journalInstanceID, ... }
    tierNames = {},         -- tierIndex -> string
    numTiers = 0,
    scanned = false,
    entrancesScanned = false,
}

local DungeonData = QR.DungeonData

-------------------------------------------------------------------------------
-- ScanInstances
-- Iterate EJ_GetNumTiers() -> EJ_SelectTier(tier) -> EJ_GetInstanceByIndex()
-- to build the full instance catalog.
-------------------------------------------------------------------------------
function DungeonData:ScanInstances()
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex then
        QR:Debug("DungeonData: Encounter Journal API not available, skipping scan")
        return
    end

    local numTiers = EJ_GetNumTiers()
    if not numTiers or numTiers == 0 then
        QR:Debug("DungeonData: No tiers found")
        return
    end

    self.numTiers = numTiers

    for tier = 1, numTiers do
        EJ_SelectTier(tier)

        -- Get tier name
        local tierName
        if EJ_GetTierInfo then
            tierName = EJ_GetTierInfo(tier)
        end
        tierName = tierName or string_format("Tier %d", tier)
        self.tierNames[tier] = tierName
        self.byTier[tier] = self.byTier[tier] or {}

        -- Scan dungeons (isRaid = false)
        local index = 1
        while true do
            local instanceID, name = EJ_GetInstanceByIndex(index, false)
            if not instanceID then break end

            if not self.instances[instanceID] then
                self.instances[instanceID] = {
                    name = name,
                    isRaid = false,
                    tier = tier,
                    tierName = tierName,
                }
            else
                -- Update tier info if missing
                self.instances[instanceID].tier = self.instances[instanceID].tier or tier
                self.instances[instanceID].tierName = self.instances[instanceID].tierName or tierName
                if not self.instances[instanceID].name or self.instances[instanceID].name == "" then
                    self.instances[instanceID].name = name
                end
            end

            table_insert(self.byTier[tier], instanceID)
            index = index + 1
        end

        -- Scan raids (isRaid = true)
        index = 1
        while true do
            local instanceID, name = EJ_GetInstanceByIndex(index, true)
            if not instanceID then break end

            if not self.instances[instanceID] then
                self.instances[instanceID] = {
                    name = name,
                    isRaid = true,
                    tier = tier,
                    tierName = tierName,
                }
            else
                self.instances[instanceID].tier = self.instances[instanceID].tier or tier
                self.instances[instanceID].tierName = self.instances[instanceID].tierName or tierName
                self.instances[instanceID].isRaid = true
                if not self.instances[instanceID].name or self.instances[instanceID].name == "" then
                    self.instances[instanceID].name = name
                end
            end

            table_insert(self.byTier[tier], instanceID)
            index = index + 1
        end
    end

    -- Filter out continent-level EJ overview entries (not actual instances)
    -- These are expansion overview pages that EJ_GetInstanceByIndex returns
    -- but have no dungeon entrance (e.g., "Pandaria", "Draenor", "Broken Isles")
    local CONTINENT_OVERVIEWS = {
        [322] = true,   -- Pandaria
        [557] = true,   -- Draenor
        [822] = true,   -- Broken Isles
        [959] = true,   -- Invasion Points (Legion)
        [1028] = true,  -- Azeroth (BfA)
        [1192] = true,  -- Shadowlands
        [1205] = true,  -- Dragon Isles
        [1278] = true,  -- Khaz Algar
        [1312] = true,  -- Midnight world bosses (no entrance)
    }
    local removedCount = 0
    for id in pairs(CONTINENT_OVERVIEWS) do
        if self.instances[id] then
            self.instances[id] = nil
            removedCount = removedCount + 1
        end
    end
    -- Also remove from byTier lists
    if removedCount > 0 then
        for tier, ids in pairs(self.byTier) do
            local filtered = {}
            for _, id in ipairs(ids) do
                if not CONTINENT_OVERVIEWS[id] then
                    table_insert(filtered, id)
                end
            end
            self.byTier[tier] = filtered
        end
    end

    self.scanned = true

    local instanceCount = 0
    for _ in pairs(self.instances) do instanceCount = instanceCount + 1 end
    QR:Debug(string_format("DungeonData: Scanned %d tiers, %d instances (%d continent entries filtered)",
        numTiers, instanceCount, removedCount))
end

-------------------------------------------------------------------------------
-- ScanEntrances
-- For each zone in ZoneAdjacency and StaticDungeonEntrances, call
-- C_EncounterJournal.GetDungeonEntrancesForMap(zoneMapID).
-- Update instances with zoneMapID, x, y, atlasName. Populate byZone.
-------------------------------------------------------------------------------
function DungeonData:ScanEntrances()
    if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then
        QR:Debug("DungeonData: C_EncounterJournal.GetDungeonEntrancesForMap not available")
        return
    end

    -- Collect all zone mapIDs to scan
    local zonesToScan = {}

    -- From ZoneAdjacency data
    if QR.ZoneAdjacencies then
        for zoneMapID in pairs(QR.ZoneAdjacencies) do
            zonesToScan[zoneMapID] = true
        end
    end

    -- From Continents data (zone lists)
    if QR.Continents then
        for _, contData in pairs(QR.Continents) do
            if contData.zones then
                for _, zoneID in ipairs(contData.zones) do
                    zonesToScan[zoneID] = true
                end
            end
        end
    end

    -- From StaticDungeonEntrances
    if QR.StaticDungeonEntrances then
        for zoneMapID in pairs(QR.StaticDungeonEntrances) do
            zonesToScan[zoneMapID] = true
        end
    end

    local entranceCount = 0

    for zoneMapID in pairs(zonesToScan) do
        local entrances = C_EncounterJournal.GetDungeonEntrancesForMap(zoneMapID)
        if entrances and #entrances > 0 then
            for _, entrance in ipairs(entrances) do
                local instanceID = entrance.journalInstanceID
                if instanceID then
                    -- Extract position - handle both .x/.y and GetXY() patterns
                    local x, y
                    if entrance.position then
                        if entrance.position.GetXY then
                            x, y = entrance.position:GetXY()
                        end
                        -- Also try direct .x/.y fields as fallback
                        if not x and entrance.position.x then
                            x = entrance.position.x
                        end
                        if not y and entrance.position.y then
                            y = entrance.position.y
                        end
                    end

                    -- Create or update instance entry
                    if not self.instances[instanceID] then
                        self.instances[instanceID] = {
                            name = entrance.name,
                            isRaid = false,
                        }
                    end

                    local inst = self.instances[instanceID]
                    inst.zoneMapID = zoneMapID
                    if x then inst.x = x end
                    if y then inst.y = y end
                    if entrance.atlasName then
                        inst.atlasName = entrance.atlasName
                    end
                    if entrance.name and (not inst.name or inst.name == "") then
                        inst.name = entrance.name
                    end

                    -- Populate byZone index
                    if not self.byZone[zoneMapID] then
                        self.byZone[zoneMapID] = {}
                    end

                    -- Avoid duplicates in byZone
                    local found = false
                    for _, existingID in ipairs(self.byZone[zoneMapID]) do
                        if existingID == instanceID then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table_insert(self.byZone[zoneMapID], instanceID)
                    end

                    entranceCount = entranceCount + 1
                end
            end
        end
    end

    self.entrancesScanned = true
    QR:Debug(string_format("DungeonData: Found %d entrances from API", entranceCount))
end

-------------------------------------------------------------------------------
-- MergeStaticFallback
-- Iterate QR.StaticDungeonEntrances, fill any instances missing coordinates
-- or missing entirely.
-- Static data format: { journalInstanceID, x, y, name, isRaid } per entry.
-------------------------------------------------------------------------------
function DungeonData:MergeStaticFallback()
    if not QR.StaticDungeonEntrances then
        QR:Debug("DungeonData: No static dungeon entrances data")
        return
    end

    local mergedCount = 0

    for zoneMapID, entries in pairs(QR.StaticDungeonEntrances) do
        for _, entry in ipairs(entries) do
            local instanceID = entry[1]
            local x = entry[2]
            local y = entry[3]
            local name = entry[4]
            local isRaid = entry[5]

            if instanceID then
                -- Create instance if missing entirely
                if not self.instances[instanceID] then
                    self.instances[instanceID] = {
                        name = name,
                        isRaid = isRaid or false,
                    }
                    mergedCount = mergedCount + 1
                end

                local inst = self.instances[instanceID]

                -- Fill missing coordinates
                if not inst.zoneMapID then
                    inst.zoneMapID = zoneMapID
                end
                if not inst.x and x then
                    inst.x = x
                end
                if not inst.y and y then
                    inst.y = y
                end
                -- Fill missing name
                if (not inst.name or inst.name == "") and name then
                    inst.name = name
                end
                -- Fill missing isRaid
                if inst.isRaid == nil then
                    inst.isRaid = isRaid or false
                end

                -- Populate byZone index
                if not self.byZone[zoneMapID] then
                    self.byZone[zoneMapID] = {}
                end

                local found = false
                for _, existingID in ipairs(self.byZone[zoneMapID]) do
                    if existingID == instanceID then
                        found = true
                        break
                    end
                end
                if not found then
                    table_insert(self.byZone[zoneMapID], instanceID)
                end
            end
        end
    end

    QR:Debug(string_format("DungeonData: Merged %d static fallback instances", mergedCount))
end

-------------------------------------------------------------------------------
-- Lookup API
-------------------------------------------------------------------------------

--- Get instance data by journalInstanceID
-- @param instanceID number The journal instance ID
-- @return table|nil Instance data table or nil
function DungeonData:GetInstance(instanceID)
    if not instanceID then return nil end
    return self.instances[instanceID]
end

--- Get all instances for a given zone map ID
-- @param zoneMapID number The zone map ID
-- @return table Array of instance info tables (with instanceID field added)
function DungeonData:GetInstancesForZone(zoneMapID)
    if not zoneMapID then return {} end

    local instanceIDs = self.byZone[zoneMapID]
    if not instanceIDs then return {} end

    local results = {}
    for _, instanceID in ipairs(instanceIDs) do
        local inst = self.instances[instanceID]
        if inst then
            local info = {}
            for k, v in pairs(inst) do
                info[k] = v
            end
            info.instanceID = instanceID
            table_insert(results, info)
        end
    end

    return results
end

--- Get expansion name for a tier index
-- @param tier number The tier index
-- @return string|nil Expansion name or nil
function DungeonData:GetTierName(tier)
    if not tier then return nil end
    return self.tierNames[tier]
end

--- Get summary of all tiers
-- @return table Array of { tier, name, dungeonCount, raidCount }
function DungeonData:GetAllTiers()
    local result = {}

    for tier = 1, self.numTiers do
        local name = self.tierNames[tier] or string_format("Tier %d", tier)
        local dungeonCount = 0
        local raidCount = 0

        local tierInstances = self.byTier[tier]
        if tierInstances then
            for _, instanceID in ipairs(tierInstances) do
                local inst = self.instances[instanceID]
                if inst then
                    if inst.isRaid then
                        raidCount = raidCount + 1
                    else
                        dungeonCount = dungeonCount + 1
                    end
                end
            end
        end

        table_insert(result, {
            tier = tier,
            name = name,
            dungeonCount = dungeonCount,
            raidCount = raidCount,
        })
    end

    return result
end

--- Search instances by name (case-insensitive substring match)
-- Results sorted by newest expansion first, then alphabetical
-- @param query string The search query
-- @return table Array of instance info tables (with instanceID field)
function DungeonData:Search(query)
    if not query or query == "" then return {} end

    local queryLower = string_lower(query)
    local results = {}

    for instanceID, inst in pairs(self.instances) do
        if inst.name then
            local nameLower = string_lower(inst.name)
            if string_find(nameLower, queryLower, 1, true) then
                local info = {}
                for k, v in pairs(inst) do
                    info[k] = v
                end
                info.instanceID = instanceID
                table_insert(results, info)
            end
        end
    end

    -- Sort: newest expansion first (highest tier first), then alphabetical
    table_sort(results, function(a, b)
        local tierA = a.tier or 0
        local tierB = b.tier or 0
        if tierA ~= tierB then
            return tierA > tierB
        end
        return (a.name or "") < (b.name or "")
    end)

    return results
end

-------------------------------------------------------------------------------
-- Initialize
-- Runs all three scan stages and logs a summary.
-------------------------------------------------------------------------------
function DungeonData:Initialize()
    self:ScanInstances()
    self:ScanEntrances()
    self:MergeStaticFallback()

    local instanceCount = 0
    local withCoords = 0
    for _, inst in pairs(self.instances) do
        instanceCount = instanceCount + 1
        if inst.x and inst.y then
            withCoords = withCoords + 1
        end
    end

    QR:Debug(string_format(
        "DungeonData: Initialized — %d instances total, %d with coordinates, %d tiers",
        instanceCount, withCoords, self.numTiers
    ))

    -- Log instances missing coordinates so gaps can be identified
    if withCoords < instanceCount then
        local missing = {}
        for id, inst in pairs(self.instances) do
            if not inst.x or not inst.y then
                table_insert(missing, string_format("  [%d] %s (tier %s)",
                    id, inst.name or "?", tostring(inst.tier or "?")))
            end
        end
        table_sort(missing)
        QR:Debug("DungeonData: Instances missing coordinates:")
        for _, line in ipairs(missing) do
            QR:Debug(line)
        end
    end
end
