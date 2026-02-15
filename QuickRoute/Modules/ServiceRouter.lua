-- ServiceRouter.lua
-- Routes player to nearest service POI (AH, Bank, Void Storage, Crafting Table) using Dijkstra.
local ADDON_NAME, QR = ...

local pairs, ipairs = pairs, ipairs
local string_format = string.format
local string_lower = string.lower
local table_insert, table_sort = table.insert, table.sort
local math_huge = math.huge

QR.ServiceRouter = {}

local SR = QR.ServiceRouter
local L

--- Get all service type keys (sorted for stable order)
-- @return table Array of service type strings
function SR:GetServiceTypes()
    local types = {}
    if QR.ServicePOIs then
        for serviceType in pairs(QR.ServicePOIs) do
            table_insert(types, serviceType)
        end
        table_sort(types)
    end
    return types
end

--- Get faction-filtered locations for a service type
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return table Array of location entries
function SR:GetLocations(serviceType)
    local pois = QR.ServicePOIs and QR.ServicePOIs[serviceType]
    if not pois then return {} end

    local playerFaction = QR.PlayerInfo and QR.PlayerInfo:GetFaction() or "Alliance"
    local filtered = {}
    for _, loc in ipairs(pois) do
        if loc.faction == "both" or loc.faction == playerFaction then
            table_insert(filtered, loc)
        end
    end
    return filtered
end

--- Get localized service name
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return string Localized name
function SR:GetServiceName(serviceType)
    L = QR.L
    -- Key format: SERVICE_AUCTION_HOUSE etc.
    local key = "SERVICE_" .. serviceType
    return L and L[key] or serviceType
end

--- Get city name for a service location via C_Map
-- @param loc table Location with mapID
-- @return string City name
function SR:GetCityName(loc)
    if loc.mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(loc.mapID)
        if info and info.name then return info.name end
    end
    return string_format("Map %d", loc.mapID or 0)
end

--- Find the nearest service location using PathCalculator
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return table|nil bestLocation, number|nil bestCost, table|nil bestResult
function SR:FindNearest(serviceType)
    local locations = self:GetLocations(serviceType)
    if #locations == 0 then return nil, nil, nil end

    local bestLoc, bestCost, bestResult = nil, math_huge, nil

    for _, loc in ipairs(locations) do
        if QR.PathCalculator and loc.mapID and loc.x and loc.y then
            local result = QR.PathCalculator:CalculatePath(loc.mapID, loc.x, loc.y)
            if result and result.totalTime and result.totalTime < bestCost then
                bestCost = result.totalTime
                bestLoc = loc
                bestResult = result
            end
        end
    end

    return bestLoc, bestCost, bestResult
end

--- Route to the nearest service of the given type
-- @param serviceType string e.g. "AUCTION_HOUSE"
function SR:RouteToNearest(serviceType)
    L = QR.L
    local bestLoc = self:FindNearest(serviceType)
    if not bestLoc then
        QR:Print(string_format("|cFFFF6600QuickRoute:|r %s",
            L and L["DEST_SEARCH_NO_RESULTS"] or "No matching destinations"))
        return
    end

    if QR.POIRouting then
        local serviceName = self:GetServiceName(serviceType)
        local cityName = self:GetCityName(bestLoc)
        local title = string_format("%s (%s)", serviceName, cityName)
        QR.POIRouting:RouteToMapPosition(bestLoc.mapID, bestLoc.x, bestLoc.y)
        if QR.DestinationSearch then
            QR.DestinationSearch:SetSearchText(title)
        end
    end
end

--- Find service type by slash alias
-- @param alias string e.g. "ah"
-- @return string|nil serviceType
function SR:FindByAlias(alias)
    if not alias or not QR.ServiceTypes then return nil end
    local aliasLower = string_lower(alias)
    for serviceType, meta in pairs(QR.ServiceTypes) do
        if meta.slashAlias == aliasLower then
            return serviceType
        end
    end
    return nil
end

function SR:Initialize()
    L = QR.L
    QR:Debug("ServiceRouter initialized")
end
