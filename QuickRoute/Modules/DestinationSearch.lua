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

--- Collect all destination results, optionally filtered by search query
-- @param query string Search text (empty = all results)
-- @return table { waypoints = {}, cities = {}, dungeons = {} }
function DS:CollectResults(query)
    L = QR.L
    local queryLower = string_lower(query or "")
    local isSearching = queryLower ~= ""

    local results = {
        waypoints = {},
        cities = {},
        dungeons = {},
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
