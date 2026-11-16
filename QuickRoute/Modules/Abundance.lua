-- Abundance.lua
-- Finds the active "place of abundance" in Midnight: the cave where a Shard of
-- Dundun (currency 3376) starts a rewarded harvest. The cave moves to another
-- zone every 8 hours.
--
-- The client's AreaPOI table holds one "Abundant Harvest" event per cave
-- (8525 to 8528, wago.tools export of build 12.1.5.70783). The world map draws
-- events from C_AreaPoiInfo.GetEventsForMap (Blizzard_SharedMapDataProviders/
-- AreaPOIEventDataProvider.lua). The assumption that only the active cave's
-- event is returned is unmeasured, so a result counts only when exactly one of
-- the four events is returned; any other result is discarded and filed.
local ADDON_NAME, QR = ...

local pcall, type, ipairs, pairs = pcall, type, ipairs, pairs
local table_concat, table_sort = table.concat, table.sort

QR.Abundance = {
    SHARD_CURRENCY_ID = 3376,
    -- areaPoiID -> UI map of the cave (AreaPOI position projected through
    -- UiMapAssignment; each matched method.gg's cave coordinates).
    HARVEST_EVENTS = {
        [8525] = 2437, -- Skinning Den, Zul'Aman
        [8526] = 2405, -- Mining Voidburrow, Voidstorm
        [8527] = 2413, -- Herbalism Grotto, Harandar
        [8528] = 2395, -- Enchanting Crypt, Eversong Woods
    },
}

local Abundance = QR.Abundance

local function IsUsable(value)
    return not (issecretvalue and issecretvalue(value))
end

--- The active harvest cave, or nil and the sorted list of returned event IDs.
-- @return table|nil { areaPoiID, mapID, x, y, name }
-- @return string the returned Abundant Harvest event IDs, comma-separated
function Abundance:GetActive()
    local api = _G.C_AreaPoiInfo
    if not (api and api.GetEventsForMap and api.GetAreaPOIInfo) then return nil, "no-api" end
    local found, ids = {}, {}
    for _, mapID in pairs(self.HARVEST_EVENTS) do
        local ok, events = pcall(api.GetEventsForMap, mapID)
        if ok and type(events) == "table" then
            for _, eventID in ipairs(events) do
                if IsUsable(eventID) and self.HARVEST_EVENTS[eventID] == mapID and not found[eventID] then
                    found[eventID] = mapID
                    ids[#ids + 1] = eventID
                end
            end
        end
    end
    table_sort(ids)
    local returned = table_concat(ids, ",")
    if #ids ~= 1 then return nil, returned end
    local poiID = ids[1]
    local mapID = found[poiID]
    local ok, info = pcall(api.GetAreaPOIInfo, mapID, poiID)
    if not ok or type(info) ~= "table" or type(info.position) ~= "table" then return nil, returned end
    local x, y = info.position.x, info.position.y
    if info.position.GetXY then x, y = info.position:GetXY() end
    if not (IsUsable(x) and IsUsable(y)) or type(x) ~= "number" or type(y) ~= "number"
        or x <= 0 or x >= 1 or y <= 0 or y >= 1 then
        return nil, returned
    end
    local name = IsUsable(info.name) and type(info.name) == "string" and info.name or nil
    return { areaPoiID = poiID, mapID = mapID, x = x, y = y, name = name }, returned
end

--- Route to the active cave. Returns false and prints when none is known.
function Abundance:Route()
    local active = self:GetActive()
    if not active then
        QR:Print(QR.L["ABUNDANCE_NONE"])
        return false
    end
    if QR.POIRouting then
        QR.POIRouting:RouteToMapPosition(active.mapID, active.x, active.y)
        if QR.DestinationSearch then
            QR.DestinationSearch:SetSearchText(active.name or QR.L["ABUNDANCE_PLACE"])
        end
    end
    return true
end
