-- Resolve owned travel choices and character-specific destinations. No protected
-- action is invoked here: a user still activates the configured secure button.
local ADDON_NAME, QR = ...
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local math_huge = math.huge

QR.TeleportDestinations = { houses = {} }
local Destinations = QR.TeleportDestinations

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math_huge and value < math_huge
end

local function Point(value)
    return type(value) == "table" and Number(value.mapID) and value.mapID > 0
        and Number(value.x) and value.x >= 0 and value.x <= 1
        and Number(value.y) and value.y >= 0 and value.y <= 1
end

local function Copy(value)
    local result = {}
    for key, field in pairs(value) do result[key] = field end
    return result
end

local function PlayerGUID()
    if not UnitGUID then return end
    local ok, guid = pcall(UnitGUID, "player")
    if ok and Public(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function Position()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local ok, point = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if not Number(mapID) or mapID <= 0 then return end
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return end
        local x, y = position:GetXY()
        return { mapID = mapID, x = x, y = y }
    end)
    if ok and Point(point) then return point end
end

local function Dirty()
    if QR.PathCalculator then QR.PathCalculator.graphDirty = true end
end

--- Record the actual Make Camp position, scoped to this character. A failed
-- position read clears the former camp instead of routing to an obsolete camp.
function Destinations:RecordCamp()
    local guid = PlayerGUID()
    if not guid or not QR.db then return false end
    if type(QR.db.campLocations) ~= "table" then QR.db.campLocations = {} end
    QR.db.campLocations[guid] = Position()
    Dirty()
    return QR.db.campLocations[guid] ~= nil
end

--- Read plot coordinates only for the neighborhood the client has loaded.
-- Plot layouts are keyed by map and plot ID; we never substitute a zone centre
-- or assume an asynchronous finder response belongs to our request.
function Destinations:RecordHousingPlots()
    local neighborhood = _G.C_HousingNeighborhood
    if not (C_Housing and C_Housing.GetCurrentNeighborhoodGUID
        and C_Housing.GetUIMapIDForNeighborhood and neighborhood
        and neighborhood.GetNeighborhoodMapData and QR.db) then return end
    local ok, mapID, plots = pcall(function()
        local guid = C_Housing.GetCurrentNeighborhoodGUID()
        if not Public(guid) or type(guid) ~= "string" then return end
        return C_Housing.GetUIMapIDForNeighborhood(guid), neighborhood.GetNeighborhoodMapData()
    end)
    if not ok or not Number(mapID) or mapID <= 0 or type(plots) ~= "table" then return end
    if type(QR.db.housingPlots) ~= "table" then QR.db.housingPlots = {} end
    local points = {}
    for _, plot in ipairs(plots) do
        if type(plot) == "table" and Number(plot.plotID) and plot.mapPosition then
            local success, x, y = pcall(function() return plot.mapPosition:GetXY() end)
            local point = success and { mapID = mapID, x = x, y = y }
            if Point(point) then points[plot.plotID] = point end
        end
    end
    if next(points) then QR.db.housingPlots[mapID] = points; Dirty() end
end

function Destinations:SetHouses(houses)
    self.houses = {}
    for _, house in ipairs(type(houses) == "table" and houses or {}) do
        if type(house) == "table" and Public(house.neighborhoodGUID) and Public(house.houseGUID)
            and type(house.neighborhoodGUID) == "string" and type(house.houseGUID) == "string"
            and house.neighborhoodGUID ~= "" and house.houseGUID ~= ""
            and Number(house.plotID) and house.plotID >= 0 then
            self.houses[#self.houses + 1] = Copy(house)
        end
    end
    self:RecordHousingPlots()
    Dirty()
end

function Destinations:GetHousingDestinations(data)
    local result = {}
    if not (C_Housing and C_Housing.GetUIMapIDForNeighborhood) then return result end
    local layouts = QR.db and QR.db.housingPlots
    for _, house in ipairs(self.houses) do
        local ok, mapID = pcall(C_Housing.GetUIMapIDForNeighborhood, house.neighborhoodGUID)
        local point = ok and Number(mapID) and type(layouts) == "table"
            and type(layouts[mapID]) == "table" and layouts[mapID][house.plotID]
        if Point(point) then
            local resolved = Copy(data)
            resolved.mapID, resolved.x, resolved.y = point.mapID, point.x, point.y
            resolved.destination = Public(house.houseName) and type(house.houseName) == "string"
                and house.houseName or (QR.L and QR.L["DEST_HOMESTEAD"] or "Homestead")
            resolved.nodeKey = "House:" .. house.houseGUID
            resolved.housing = { neighborhoodGUID = house.neighborhoodGUID,
                houseGUID = house.houseGUID, plotID = house.plotID }
            resolved.choiceText = resolved.destination
            resolved.isDynamic = false
            result[#result + 1] = resolved
        end
    end
    return result
end

--- Return independent landing candidates. Requirements remain on each candidate
-- so the phase-aware graph can evaluate them for the simulated route state.
function Destinations:GetDestinations(id, entry)
    if not Number(id) or id <= 0 or id ~= math.floor(id) or type(entry) ~= "table" then return {} end
    local data = entry.data or entry
    if type(data) ~= "table" then return {} end
    if id == 1233637 then return self:GetHousingDestinations(data) end
    if id == 312372 then
        local guid = PlayerGUID()
        local camps = QR.db and QR.db.campLocations
        local point = guid and type(camps) == "table" and camps[guid]
        if not Point(point) then return {} end
        local resolved = Copy(data)
        resolved.mapID, resolved.x, resolved.y = point.mapID, point.x, point.y
        resolved.nodeKey = "Camp:" .. guid
        resolved.isDynamic = false
        return { resolved }
    end
    if QR.Hearthstone then data = QR.Hearthstone:ResolveTeleport(data) end
    local supplement = data.travelDestinationKey and QR.TeleportDestinationData
        and QR.TeleportDestinationData[data.travelDestinationKey]
    local result = {}
    if supplement and #supplement.destinations > 0 then
        if supplement.isRandom then return result end
        for _, destination in ipairs(supplement.destinations) do
            if Point(destination) and not destination.isApproximate then
                local resolved = Copy(data)
                for key, value in pairs(destination) do resolved[key] = value end
                resolved.isDynamic, resolved.isRandom = false, false
                result[#result + 1] = resolved
            end
        end
    elseif Point(data) and not data.isDynamic and not data.isRandom then
        result[1] = data
    elseif not data.isDynamic and not data.isRandom then
        -- Integrations can refer to an already-known graph destination by name.
        -- Its verified coordinates are safe to reuse only on the same map.
        local graph = QR.PathCalculator and QR.PathCalculator.graph
        local node = graph and graph.nodes and graph.nodes[data.nodeKey or data.destination or data.name]
        local position = node and (node.data or node)
        if Point(position) and position.mapID == data.mapID then
            local resolved = Copy(data)
            resolved.x, resolved.y = position.x, position.y
            result[1] = resolved
        end
    end
    return result
end

function Destinations:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if C_Housing then
        frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
        frame:RegisterEvent("HOUSE_PLOT_ENTERED")
    end
    frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if Public(unit) and unit == "player" and Number(spellID) and spellID == 312370 then
                self:RecordCamp()
            end
        elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
            self:SetHouses(unit)
        else
            self:RecordHousingPlots()
            if C_Housing and C_Housing.GetPlayerOwnedHouses then pcall(C_Housing.GetPlayerOwnedHouses) end
        end
    end)
    self.frame = frame
    if C_Housing and C_Housing.GetPlayerOwnedHouses then pcall(C_Housing.GetPlayerOwnedHouses) end
end
