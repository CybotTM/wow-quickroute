-- DataAccess.lua
-- Lookups over the data tables. They read QR.PortalHubs, QR.TeleportItemsData,
-- QR.Continents and their siblings at call time, so the same functions serve
-- whichever data set the TOC loaded: the retail files or Data/Forever/.
-- Loaded after the data files; nothing here runs at file scope.
local ADDON_NAME, QR = ...

local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert

-------------------------------------------------------------------------------
-- Portals
-------------------------------------------------------------------------------

--- Get all available portals for the current player
-- Filters by player faction and class
-- @return table {hubs = {}, standalone = {}} filtered portal data
function QR:GetAvailablePortals()
    local playerFaction = QR.PlayerInfo:GetFaction()
    local result = {
        hubs = {},
        standalone = {},
    }

    -- Filter portal hubs
    for hubName, hubData in pairs(QR.PortalHubs) do
        -- Check if hub is accessible by player faction
        if hubData.faction == "both" or hubData.faction == playerFaction then
            local filteredHub = {
                mapID = hubData.mapID,
                x = hubData.x,
                y = hubData.y,
                faction = hubData.faction,
                portals = {},
            }

            -- Filter portals within the hub by faction
            for _, portal in ipairs(hubData.portals) do
                local portalFaction = portal.faction or "both"
                if portalFaction == "both" or portalFaction == playerFaction then
                    table_insert(filteredHub.portals, portal)
                end
            end

            -- Only add hub if it has accessible portals
            if #filteredHub.portals > 0 then
                result.hubs[hubName] = filteredHub
            end
        end
    end

    -- Filter standalone portals
    for _, portal in ipairs(QR.StandalonePortals) do
        local factionMatch = portal.faction == "both" or portal.faction == playerFaction
        local classMatch = true

        -- Check class restriction if present
        if portal.class then
            classMatch = QR.PlayerInfo:IsClass(portal.class)
        end

        if factionMatch and classMatch then
            table_insert(result.standalone, portal)
        end
    end

    return result
end

--- Get a specific portal hub by name
-- @param hubName string The name of the portal hub
-- @return table|nil The hub data or nil if not found
function QR:GetPortalHub(hubName)
    return QR.PortalHubs[hubName]
end

--- Get all portals leading to a specific mapID
-- Useful for pathfinding to find which portals can reach a destination
-- @param mapID number The destination map ID
-- @return table List of portals that go to the specified map
function QR:GetPortalsToMap(mapID)
    local portals = {}

    -- Check hub portals
    for hubName, hubData in pairs(QR.PortalHubs) do
        for _, portal in ipairs(hubData.portals) do
            if portal.mapID == mapID then
                table_insert(portals, {
                    hubName = hubName,
                    hubMapID = hubData.mapID,
                    hubX = hubData.x,
                    hubY = hubData.y,
                    destination = portal.destination,
                    destMapID = portal.mapID,
                    destX = portal.x,
                    destY = portal.y,
                    faction = portal.faction or hubData.faction,
                    type = "hub_portal",
                })
            end
        end
    end

    -- Check standalone portals (both from and to)
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.to.mapID == mapID then
            table_insert(portals, {
                name = portal.name,
                fromMapID = portal.from.mapID,
                fromX = portal.from.x,
                fromY = portal.from.y,
                toMapID = portal.to.mapID,
                toX = portal.to.x,
                toY = portal.to.y,
                travelTime = portal.travelTime,
                faction = portal.faction,
                type = portal.type,
                class = portal.class,
            })
        end
        -- Check if bidirectional and destination is the "from" side
        if portal.bidirectional and portal.from.mapID == mapID then
            table_insert(portals, {
                name = portal.name .. " (Return)",
                fromMapID = portal.to.mapID,
                fromX = portal.to.x,
                fromY = portal.to.y,
                toMapID = portal.from.mapID,
                toX = portal.from.x,
                toY = portal.from.y,
                travelTime = portal.travelTime,
                faction = portal.faction,
                type = portal.type,
                class = portal.class,
            })
        end
    end

    return portals
end

-------------------------------------------------------------------------------
-- Teleports
-------------------------------------------------------------------------------

--- Get teleport data by item/spell ID
-- @param id number The item or spell ID
-- @return table|nil Teleport data or nil if not found
function QR:GetTeleportDataByID(id)
    -- Check main data table first
    if QR.TeleportItemsData[id] then
        return QR.TeleportItemsData[id]
    end

    -- Check class spells
    if QR.ClassTeleportSpells[id] then
        return QR.ClassTeleportSpells[id]
    end

    -- Check racial spells
    if QR.RacialTeleportSpells and QR.RacialTeleportSpells[id] then
        return QR.RacialTeleportSpells[id]
    end

    -- Check general spells (housing, etc.)
    if QR.GeneralTeleportSpells and QR.GeneralTeleportSpells[id] then
        return QR.GeneralTeleportSpells[id]
    end

    -- Check mage teleports
    for _, factionTable in pairs(QR.MageTeleports) do
        if factionTable[id] then
            return factionTable[id]
        end
    end

    return nil
end

--- Get all teleports that lead to a specific mapID
-- Useful for pathfinding to find which teleports can reach a destination
-- @param mapID number The destination map ID
-- @return table Teleports that go to the specified map
function QR:GetTeleportsToMap(mapID)
    local teleports = {}

    local function checkAndAdd(id, data)
        if data.mapID and data.mapID == mapID then
            teleports[id] = data
        end
    end

    -- Check all data sources
    for id, data in pairs(QR.TeleportItemsData) do
        checkAndAdd(id, data)
    end

    for id, data in pairs(QR.ClassTeleportSpells) do
        checkAndAdd(id, data)
    end

    if QR.RacialTeleportSpells then
        for id, data in pairs(QR.RacialTeleportSpells) do
            checkAndAdd(id, data)
        end
    end

    if QR.GeneralTeleportSpells then
        for id, data in pairs(QR.GeneralTeleportSpells) do
            checkAndAdd(id, data)
        end
    end

    for _, factionTable in pairs(QR.MageTeleports) do
        for id, data in pairs(factionTable) do
            checkAndAdd(id, data)
        end
    end

    return teleports
end

-------------------------------------------------------------------------------
-- Continents and zones
-------------------------------------------------------------------------------

--- Get a localized continent display name from a continent key.
-- Tries C_Map.GetMapInfo first, then falls back to QR.Continents[key].name.
-- @param continentKey string The continent key (e.g., "EASTERN_KINGDOMS")
-- @return string The localized continent name, or the raw key as last resort
function QR.GetLocalizedContinentName(continentKey)
    if not continentKey then return nil end
    local mapID = QR.ContinentNameMapIDs and QR.ContinentNameMapIDs[continentKey]
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    local data = QR.Continents[continentKey]
    return data and data.name or continentKey
end

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

--- Get the continent key for a given mapID
-- @param mapID number The map ID to look up
-- @return string|nil The continent key, or nil if unknown
function QR.GetContinentForZone(mapID)
    return QR.ZoneToContinent[mapID]
end

--- Get the hub zone for a continent
-- @param continentKey string The continent key
-- @param faction string|nil "Alliance" or "Horde" for faction-specific hub
-- @return number|nil The hub mapID
function QR.GetContinentHub(continentKey, faction)
    local continent = QR.Continents[continentKey]
    if not continent then return nil end

    if faction == "Alliance" and continent.hubAlliance then
        return continent.hubAlliance
    elseif faction == "Horde" and continent.hubHorde then
        return continent.hubHorde
    end

    return continent.hub
end

--- Check if two zones are on the same continent
-- @param mapID1 number First map ID
-- @param mapID2 number Second map ID
-- @return boolean True if same continent
function QR.AreSameContinent(mapID1, mapID2)
    local cont1 = QR.ZoneToContinent[mapID1]
    local cont2 = QR.ZoneToContinent[mapID2]

    if not cont1 or not cont2 then
        return false
    end

    return cont1 == cont2
end

--- Check if two zones are directly adjacent (walkable)
-- @param mapID1 number First map ID
-- @param mapID2 number Second map ID
-- @return boolean, number|nil True if adjacent, and travel time if so
function QR.AreAdjacentZones(mapID1, mapID2)
    local adjacencies = QR.ZoneAdjacencies[mapID1]
    if adjacencies then
        for _, adj in ipairs(adjacencies) do
            if adj.zone == mapID2 then
                return true, adj.travelTime
            end
        end
    end
    return false, nil
end

--- Get all adjacent zones for a given mapID
-- @param mapID number The map ID
-- @return table Array of {zone, travelTime} pairs
function QR.GetAdjacentZones(mapID)
    return QR.ZoneAdjacencies[mapID] or {}
end

--- Build the directed network of documented overland zone connections.
-- Created at routing time, after Core/Graph.lua has loaded.
function QR.BuildZoneTravelGraph()
    local graph = QR.Graph:New()
    for mapID, adjacencies in pairs(QR.ZoneAdjacencies) do
        graph:AddNode(mapID)
        for _, adj in ipairs(adjacencies) do graph:AddNode(adj.zone) end
    end
    for mapID, adjacencies in pairs(QR.ZoneAdjacencies) do
        for _, adj in ipairs(adjacencies) do
            if not QR.TravelRequirements or QR.TravelRequirements:CanTraverseZoneMaps(mapID, adj.zone) then
                graph:AddEdge(mapID, adj.zone, adj.travelTime, "walk")
            end
        end
    end
    return graph
end

--- Fastest documented overland time, or nil when no connection is known.
-- Adjacency times differ, so breadth-first (fewest hops) is not sufficient.
function QR.EstimateSameContinentTravel(fromMapID, toMapID)
    if fromMapID == toMapID then return 0 end
    if not QR.AreSameContinent(fromMapID, toMapID) then return nil end
    local _, cost = QR.BuildZoneTravelGraph():FindShortestPath(fromMapID, toMapID)
    return cost
end

--- Get cross-continent travel estimate
-- @param fromContinent string Source continent key
-- @param toContinent string Destination continent key
-- @return number Travel time in seconds
function QR.GetCrossContinentTravel(fromContinent, toContinent)
    if fromContinent == toContinent then
        return 0
    end

    local fromData = QR.CrossContinentTravel[fromContinent]
    if fromData and fromData[toContinent] then
        return fromData[toContinent]
    end

    -- Default cross-continent time
    return 300
end
