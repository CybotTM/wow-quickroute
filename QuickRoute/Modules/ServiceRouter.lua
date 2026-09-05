-- ServiceRouter.lua
-- Routes player to nearest service POI (AH, Bank, Void Storage, Crafting Table) using Dijkstra.
local ADDON_NAME, QR = ...

local pairs, ipairs, pcall = pairs, ipairs, pcall
local type, tonumber, tostring = type, tonumber, tostring
local string_format = string.format
local string_lower = string.lower
local string_match = string.match
local table_insert, table_sort = table.insert, table.sort
local math_huge = math.huge
local math_floor, math_min, math_abs = math.floor, math.min, math.abs

QR.ServiceRouter = {}

local SR = QR.ServiceRouter
local L

local function IsFinite(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value and value > -math_huge and value < math_huge
end

local function IsPosition(loc)
    return type(loc) == "table" and IsFinite(loc.mapID) and loc.mapID > 0
        and loc.mapID == math_floor(loc.mapID) and IsFinite(loc.x) and IsFinite(loc.y)
        and loc.x >= 0 and loc.x <= 1 and loc.y >= 0 and loc.y <= 1
end

--- Compare complete travel estimates, including available teleports and portals.
function SR:FindNearestLocation(locations)
    local bestLoc, bestCost, bestResult
    for _, loc in ipairs(locations) do
        if QR.PathCalculator and IsPosition(loc) then
            local ok, result = pcall(QR.PathCalculator.CalculatePath, QR.PathCalculator, loc.mapID, loc.x, loc.y)
            if ok and type(result) == "table" and IsFinite(result.totalTime) and result.totalTime >= 0
                and (not bestCost or result.totalTime < bestCost) then
                bestLoc, bestCost, bestResult = loc, result.totalTime, result
            end
        end
    end
    return bestLoc, bestCost, bestResult
end

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

--- Get city name for a service location via C_Map, with parent zone for context
-- Returns "City (Zone)" format, e.g. "Dalaran (Northrend)" to disambiguate
-- @param loc table Location with mapID
-- @return string City name with zone
function SR:GetCityName(loc)
    if loc.mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(loc.mapID)
        if info and info.name then
            -- Add parent zone/continent for context
            if info.parentMapID then
                local parentInfo = C_Map.GetMapInfo(info.parentMapID)
                if parentInfo and parentInfo.name then
                    return info.name .. " (" .. parentInfo.name .. ")"
                end
            end
            return info.name
        end
    end
    return string_format("Map %d", loc.mapID or 0)
end

--- Find the nearest service location using PathCalculator
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return table|nil bestLocation, number|nil bestCost, table|nil bestResult
function SR:FindNearest(serviceType)
    return self:FindNearestLocation(self:GetLocations(serviceType))
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

-------------------------------------------------------------------------------
-- Currency vendors learned from actual merchant interactions
-------------------------------------------------------------------------------

local MAX_VENDOR_LOCATIONS = 500
local MAX_VENDOR_CURRENCIES = 32

local function GetCharacter()
    local guid = _G.UnitGUID and _G.UnitGUID("player")
    if issecretvalue and issecretvalue(guid) then return nil end
    return type(guid) == "string" and guid or nil
end

local function GetCurrencyName(currencyID)
    local api = _G.C_CurrencyInfo
    if api and api.GetCurrencyInfo then
        local ok, info = pcall(api.GetCurrencyInfo, currencyID)
        if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info.name))
            and type(info.name) == "string" then return info.name end
    end
    return tostring(currencyID)
end

function SR:GetCurrencyName(currencyID)
    return GetCurrencyName(currencyID)
end

--- Save a bounded observation for this character. Coordinates are the player's
-- interaction location, not a claim that a moving/phased NPC is always there.
-- GetMerchantCurrencies is the list spent at the merchant. GetItemInfo.currencyID
-- is the currency being SOLD and must never be interpreted as an accepted cost.
function SR:ObserveMerchant()
    local api = _G.C_MerchantFrame
    if not (QR.db and api and api.GetMerchantCurrencies and _G.UnitGUID
        and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local character = GetCharacter()
    local guid = _G.UnitGUID("npc")
    if not character or (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return end
    local npcID = tonumber(string_match(guid, "^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return end -- no player/pet/vehicle vendors with unstable identity
    local mapID = C_Map.GetBestMapForUnit("player")
    if not IsFinite(mapID) or mapID <= 0 then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then return end
    local x, y = position.x, position.y
    if position.GetXY then x, y = position:GetXY() end
    local loc = { mapID = mapID, x = x, y = y }
    if not IsPosition(loc) then return end
    local ok, accepted = pcall(api.GetMerchantCurrencies)
    if not ok or type(accepted) ~= "table" then return end
    if #accepted == 0 then
        -- Empty results also occur while merchant data loads. Keep a negative
        -- observation only once a populated inventory confirms this visit, so
        -- an obsolete reference-catalogue offering cannot reappear on merge.
        local itemCount = _G.GetMerchantNumItems and _G.GetMerchantNumItems()
        if not IsFinite(itemCount) or itemCount <= 0 then return end
    end
    if #accepted > MAX_VENDOR_CURRENCIES then
        QR:Debug("Currency vendor observation exceeds currency limit; keeping previous verified data")
        return
    end
    local currencies = {}
    for index = 1, math_min(#accepted, MAX_VENDOR_CURRENCIES) do
        local currencyID = accepted[index]
        if IsFinite(currencyID) and currencyID > 0 and currencyID == math_floor(currencyID) then
            currencies[currencyID] = true
        end
    end
    if #accepted > 0 and not next(currencies) then return end
    local name = UnitName and UnitName("npc")
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return end
    loc.name = name:sub(1, 128)
    loc.npcID, loc.character = npcID, character
    loc.faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    loc.currencies = currencies
    loc.lastSeen = _G.time and _G.time() or 0
    loc.source = "merchant"
    if type(QR.db.currencyVendors) ~= "table" then QR.db.currencyVendors = {} end
    local vendors = QR.db.currencyVendors
    vendors[character .. ":" .. npcID .. ":" .. mapID] = loc

    local entries = {}
    for key, entry in pairs(vendors) do
        if type(entry) ~= "table" or not IsFinite(entry.lastSeen) or not IsPosition(entry) then
            vendors[key] = nil
        else
            table_insert(entries, { key = key, time = entry.lastSeen })
        end
    end
    if #entries > MAX_VENDOR_LOCATIONS then
        table_sort(entries, function(a, b) return a.time < b.time end)
        for index = 1, #entries - MAX_VENDOR_LOCATIONS do vendors[entries[index].key] = nil end
    end
end

function SR:GetCurrencyLocations(currencyID)
    local results, observed = {}, {}
    local vendors = QR.db and QR.db.currencyVendors
    local character = GetCharacter()
    if type(vendors) ~= "table" then vendors = {} end
    local faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    for _, loc in pairs(vendors) do
        if character and IsPosition(loc) and loc.source == "merchant" and loc.character == character
            and loc.faction == faction and type(loc.name) == "string" and IsFinite(loc.npcID) and loc.npcID > 0
            and type(loc.currencies) == "table" then
            observed[loc.npcID .. ":" .. loc.mapID] = true
            if not currencyID or loc.currencies[currencyID] == true then table_insert(results, loc) end
        end
    end
    if currencyID and QR.Catalog then
        for _, loc in ipairs(QR.Catalog:GetCurrencyLocations(currencyID)) do
            -- The character's direct observation supersedes a reference point
            -- for the same vendor on this map (including changed positions).
            if not observed[loc.npcID .. ":" .. loc.mapID] then table_insert(results, loc) end
        end
    end
    table_sort(results, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.mapID < b.mapID
    end)
    return results
end

function SR:GetKnownCurrencies(includeAll)
    local currencies, seen = {}, {}
    for _, loc in ipairs(self:GetCurrencyLocations()) do
        for currencyID in pairs(loc.currencies) do
            if IsFinite(currencyID) and currencyID > 0 and not seen[currencyID] then
                seen[currencyID] = true
                table_insert(currencies, { currencyID = currencyID, name = GetCurrencyName(currencyID) })
            end
        end
    end
    if QR.Catalog then
        local api = _G.C_CurrencyInfo
        for _, currencyID in ipairs(QR.Catalog:GetCurrencies()) do
            local ok, info = false, nil
            if api and api.GetCurrencyInfo then ok, info = pcall(api.GetCurrencyInfo, currencyID) end
            local quantity = ok and type(info) == "table" and info.quantity
            if not seen[currencyID] and (includeAll or (IsFinite(quantity) and quantity > 0)) then
                seen[currencyID] = true
                table_insert(currencies, { currencyID = currencyID, name = GetCurrencyName(currencyID),
                    quantity = IsFinite(quantity) and quantity or nil })
            end
        end
    end
    table_sort(currencies, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.currencyID < b.currencyID
    end)
    return currencies
end

function SR:FindNearestCurrencyVendor(currencyID)
    return self:FindNearestLocation(self:GetCurrencyLocations(currencyID))
end

function SR:CancelCurrencyRouting()
    self._currencyGeneration = (self._currencyGeneration or 0) + 1
end

--- Yield between candidates so a large personal catalogue cannot freeze a
-- frame. A newer route selection invalidates callbacks already in flight.
function SR:FindNearestCurrencyVendorAsync(currencyID, callback)
    self:CancelCurrencyRouting()
    local generation = self._currencyGeneration
    local locations = self:GetCurrencyLocations(currencyID)
    local index, bestLoc, bestCost, bestResult = 1
    local function ReadOrigin()
        if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
        local mapID = C_Map.GetBestMapForUnit("player")
        if not IsFinite(mapID) or mapID <= 0 then return nil end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return nil end
        local point = { mapID = mapID, x = pos.x, y = pos.y }
        if pos.GetXY then point.x, point.y = pos:GetXY() end
        if IsPosition(point) then return point end
    end
    local function SafeOrigin()
        local ok, point = pcall(ReadOrigin)
        return ok and point or nil
    end
    local origin, restarts = SafeOrigin(), 0
    local function CalculateOne()
        if generation ~= SR._currencyGeneration then return end
        local current = SafeOrigin()
        if not origin or not current then
            callback(nil, nil, nil, "position_unavailable")
            return
        end
        local moved = origin.mapID ~= current.mapID
            or math_abs(origin.x - current.x) > 0.001 or math_abs(origin.y - current.y) > 0.001
        if moved then
            restarts = restarts + 1
            if restarts > 2 then
                callback(nil, nil, nil, "position_changed")
                return
            end
            -- Never compare estimates measured from different origins. Two
            -- bounded restarts tolerate a short reposition without an endless
            -- background scan while a player continues traveling.
            origin, index, bestLoc, bestCost, bestResult = current, 1, nil, nil, nil
        end
        if index > #locations then
            callback(bestLoc, bestCost, bestResult)
            return
        end
        local loc, cost, result = SR:FindNearestLocation({ locations[index] })
        if loc and (not bestCost or cost < bestCost) then
            bestLoc, bestCost, bestResult = loc, cost, result
        end
        index = index + 1
        C_Timer.After(0, CalculateOne)
    end
    C_Timer.After(0, CalculateOne)
end

--- Route by currency ID or exact localized name; ambiguous partial names fail.
function SR:RouteToCurrency(query)
    self:CancelCurrencyRouting()
    if QR.MultiRoute and QR.MultiRoute.CancelSelection then QR.MultiRoute:CancelSelection() end
    local currencyID = tonumber(query)
    if not currencyID and type(query) == "string" then
        local name = string_lower(query):match("^%s*(.-)%s*$")
        for _, currency in ipairs(self:GetKnownCurrencies(true)) do
            if string_lower(currency.name) == name then currencyID = currency.currencyID; break end
        end
    end
    if not currencyID or #self:GetCurrencyLocations(currencyID) == 0 then
        QR:Print(QR.L["CURRENCY_VENDOR_NONE"])
        return false
    end
    QR:Print(QR.L["CALCULATING"])
    self:FindNearestCurrencyVendorAsync(currencyID, function(loc, _, _, reason)
        if not loc then
            QR:Print(QR.L[reason == "position_changed" and "CURRENCY_VENDOR_MOVED"
                or reason == "position_unavailable" and "DESTINATION_UNAVAILABLE" or "NO_PATH_FOUND"])
            return
        end
        if QR.POIRouting then
            -- Recalculate the selected vendor from the player's current state.
            QR.POIRouting:RouteToMapPosition(loc.mapID, loc.x, loc.y)
            if QR.DestinationSearch then
                QR.DestinationSearch:SetSearchText(loc.name .. " — " .. GetCurrencyName(currencyID))
            end
            QR:Print(QR.L[loc.source == "merchant" and "CURRENCY_VENDOR_OBSERVED" or "CATALOG_LOCATION"])
        end
    end)
    return true
end

function SR:Initialize()
    L = QR.L
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("MERCHANT_SHOW")
        self.eventFrame:RegisterEvent("MERCHANT_UPDATE")
        self.eventFrame:RegisterEvent("MERCHANT_CLOSED")
        self.eventFrame:SetScript("OnEvent", function(_, event)
            if event == "MERCHANT_SHOW" then SR._merchantOpen = true end
            if event == "MERCHANT_CLOSED" then SR._merchantOpen = false end
            if SR._merchantTimer then SR._merchantTimer:Cancel(); SR._merchantTimer = nil end
            if SR._merchantOpen then
                SR._merchantTimer = C_Timer.NewTimer(0.2, function()
                    SR._merchantTimer = nil
                    local ok, err = pcall(SR.ObserveMerchant, SR)
                    if not ok then QR:Debug("Currency vendor observation unavailable: " .. tostring(err)) end
                end)
            end
        end)
    end
    QR:Debug("ServiceRouter initialized")
end
