-- Portals.lua
-- Database of portal hub locations and standalone travel connections
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert

-------------------------------------------------------------------------------
-- Portal Hubs
-- Major cities containing multiple portals to various destinations
-------------------------------------------------------------------------------
QR.PortalHubs = {
    -- =========================================================================
    -- ALLIANCE PORTAL HUBS
    -- =========================================================================
    ["Stormwind Portal Room"] = {
        mapID = 84,  -- Stormwind City
        x = 0.4934,
        y = 0.8711,
        faction = "Alliance",
        portals = {
            {destination = "Boralus", mapID = 1161, x = 0.7025, y = 0.1725},
            {destination = "Oribos", mapID = 1670, x = 0.4483, y = 0.6466},
            {destination = "Valdrakken", mapID = 2112, x = 0.5835, y = 0.3535},
            {destination = "Dornogal", mapID = 2339, x = 0.4850, y = 0.5520},
            {destination = "Jade Forest", mapID = 371, x = 0.4610, y = 0.9490},
            {destination = "Azsuna", mapID = 630, x = 0.4510, y = 0.4660},
            {destination = "Ashran (Stormshield)", mapID = 622, x = 0.4406, y = 0.3453},
            {destination = "Shattrath City", mapID = 111, x = 0.5410, y = 0.4120},
            {destination = "Dalaran (Northrend)", mapID = 125, x = 0.4947, y = 0.4709},
            {destination = "Caverns of Time", mapID = 71, x = 0.6390, y = 0.5060},
            {destination = "Exodar", mapID = 103, x = 0.3970, y = 0.6247},
            {destination = "Ironforge", mapID = 87, x = 0.2730, y = 0.7330},
        },
    },

    ["Boralus"] = {
        mapID = 1161,  -- Boralus
        x = 0.7025,
        y = 0.1725,
        faction = "Alliance",
        portals = {
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711},
            {destination = "Silithus", mapID = 81, x = 0.4180, y = 0.4470},
            {destination = "Nazjatar", mapID = 1355, x = 0.3950, y = 0.5310},
            {destination = "Mechagon", mapID = 1462, x = 0.7200, y = 0.3900},
        },
    },

    -- =========================================================================
    -- HORDE PORTAL HUBS
    -- =========================================================================
    ["Orgrimmar Portal Room"] = {
        mapID = 85,  -- Orgrimmar
        x = 0.5540,
        y = 0.3840,
        faction = "Horde",
        portals = {
            {destination = "Dazar'alor", mapID = 1165, x = 0.5020, y = 0.4080},
            {destination = "Oribos", mapID = 1670, x = 0.4483, y = 0.6466},
            {destination = "Valdrakken", mapID = 2112, x = 0.5835, y = 0.3535},
            {destination = "Dornogal", mapID = 2339, x = 0.4850, y = 0.5520},
            {destination = "Jade Forest (Honeydew)", mapID = 371, x = 0.2830, y = 0.5110},
            {destination = "Azsuna", mapID = 630, x = 0.4510, y = 0.4660},
            {destination = "Ashran (Warspear)", mapID = 624, x = 0.5308, y = 0.4142},
            {destination = "Shattrath City", mapID = 111, x = 0.5410, y = 0.4120},
            {destination = "Dalaran (Northrend)", mapID = 125, x = 0.4947, y = 0.4709},
            {destination = "Caverns of Time", mapID = 71, x = 0.6390, y = 0.5060},
            {destination = "Silvermoon City", mapID = 110, x = 0.5850, y = 0.1920},
            {destination = "Thunder Bluff", mapID = 88, x = 0.2920, y = 0.2740},
        },
    },

    ["Dazar'alor"] = {
        mapID = 1165,  -- Dazar'alor
        x = 0.5020,
        y = 0.4080,
        faction = "Horde",
        portals = {
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840},
            {destination = "Silithus", mapID = 81, x = 0.4180, y = 0.4470},
            {destination = "Nazjatar", mapID = 1355, x = 0.3830, y = 0.4150},
            {destination = "Mechagon", mapID = 1462, x = 0.7200, y = 0.3900},
            {destination = "Thunder Bluff", mapID = 88, x = 0.2920, y = 0.2740},
            {destination = "Silvermoon City", mapID = 110, x = 0.5850, y = 0.1920},
        },
    },

    -- =========================================================================
    -- NEUTRAL PORTAL HUBS
    -- =========================================================================
    ["Dalaran (Broken Isles)"] = {
        mapID = 627,  -- Dalaran (Legion)
        x = 0.5044,
        y = 0.5313,
        faction = "both",
        portals = {
            -- Faction portals (Silver Enclave / Sunreaver's Sanctuary)
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Chamber of the Guardian (neutral, survived 8.1.5 / re-added 11.0.5)
            {destination = "Karazhan", mapID = 42, x = 0.4650, y = 0.7510},
            {destination = "Wyrmrest Temple", mapID = 115, x = 0.5980, y = 0.5410},
            {destination = "Dalaran Crater", mapID = 25, x = 0.1740, y = 0.2740},
        },
    },

    ["Oribos"] = {
        mapID = 1670,  -- Oribos
        x = 0.4483,
        y = 0.6466,
        faction = "both",
        portals = {
            -- Faction capitals
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Shadowlands zones
            {destination = "Bastion", mapID = 1533, x = 0.5290, y = 0.4690},
            {destination = "Maldraxxus", mapID = 1536, x = 0.5060, y = 0.5370},
            {destination = "Ardenweald", mapID = 1565, x = 0.4930, y = 0.5200},
            {destination = "Revendreth", mapID = 1525, x = 0.6140, y = 0.7630},
            {destination = "Korthia", mapID = 1961, x = 0.6080, y = 0.2170},
            {destination = "Zereth Mortis", mapID = 1970, x = 0.3480, y = 0.5550},
        },
    },

    ["Valdrakken"] = {
        mapID = 2112,  -- Valdrakken
        x = 0.5835,
        y = 0.3535,
        faction = "both",
        portals = {
            -- Faction capitals
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Dragon Isles zones
            {destination = "Waking Shores", mapID = 2022, x = 0.2410, y = 0.3310},
            {destination = "Ohn'ahran Plains", mapID = 2023, x = 0.8580, y = 0.2530},
            {destination = "Azure Span", mapID = 2024, x = 0.1290, y = 0.4880},
            {destination = "Forbidden Reach", mapID = 2107, x = 0.3380, y = 0.5340},
            {destination = "Zaralek Cavern", mapID = 2133, x = 0.5640, y = 0.5580},
            -- Special destinations
            {destination = "Badlands (Dragon's Mouth)", mapID = 15, x = 0.2120, y = 0.5640},
            {destination = "Emerald Dream", mapID = 2200, x = 0.5170, y = 0.2920},
        },
    },

    ["Dornogal"] = {
        mapID = 2339,  -- Dornogal
        x = 0.4850,
        y = 0.5520,
        faction = "both",
        portals = {
            -- Faction capitals
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Previous expansion hubs
            {destination = "Valdrakken", mapID = 2112, x = 0.5835, y = 0.3535},
            {destination = "Oribos", mapID = 1670, x = 0.4483, y = 0.6466},
        },
    },

    ["Shattrath City"] = {
        mapID = 111,  -- Shattrath City
        x = 0.5410,
        y = 0.4120,
        faction = "both",
        portals = {
            -- Faction capitals
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Special destinations
            {destination = "Isle of Quel'Danas", mapID = 122, x = 0.4860, y = 0.3100},
        },
    },

    ["Dalaran (Northrend)"] = {
        mapID = 125,  -- Dalaran (Northrend)
        x = 0.4947,
        y = 0.4709,
        faction = "both",
        portals = {
            -- Faction portals (Silver Enclave / Sunreaver's Sanctuary)
            {destination = "Stormwind City", mapID = 84, x = 0.4934, y = 0.8711, faction = "Alliance"},
            {destination = "Orgrimmar", mapID = 85, x = 0.5540, y = 0.3840, faction = "Horde"},
            -- Violet Citadel (neutral)
            {destination = "Caverns of Time", mapID = 71, x = 0.6390, y = 0.5060},
        },
    },
}

-------------------------------------------------------------------------------
-- Standalone Portals
-- One-off travel connections: boats, zeppelins, trams, and other transports
-------------------------------------------------------------------------------
QR.StandalonePortals = {
    -- =========================================================================
    -- TRAMS
    -- =========================================================================
    {
        name = "Deeprun Tram (Stormwind to Ironforge)",
        from = {mapID = 84, x = 0.6400, y = 0.0820},  -- Stormwind entrance
        to = {mapID = 87, x = 0.7680, y = 0.5130},    -- Ironforge entrance
        travelTime = 60,
        faction = "Alliance",
        type = "tram",
        bidirectional = true,
    },

    -- =========================================================================
    -- ALLIANCE BOATS
    -- =========================================================================
    {
        name = "Stormwind to Borean Tundra",
        from = {mapID = 84, x = 0.2360, y = 0.5640},  -- Stormwind Harbor
        to = {mapID = 114, x = 0.5980, y = 0.6970},   -- Valiance Keep
        travelTime = 120,
        faction = "Alliance",
        type = "boat",
        bidirectional = true,
    },
    {
        name = "Menethil Harbor to Theramore",
        from = {mapID = 56, x = 0.0500, y = 0.5630},  -- Menethil Harbor
        to = {mapID = 70, x = 0.7180, y = 0.5680},    -- Theramore Isle
        travelTime = 180,
        faction = "Alliance",
        type = "boat",
        bidirectional = true,
    },
    {
        name = "Stormwind to Teldrassil",
        from = {mapID = 84, x = 0.2260, y = 0.5740},  -- Stormwind Harbor
        to = {mapID = 57, x = 0.5490, y = 0.9310},    -- Rut'theran Village
        travelTime = 180,
        faction = "Alliance",
        type = "boat",
        bidirectional = true,
    },
    {
        name = "Menethil Harbor to Howling Fjord",
        from = {mapID = 56, x = 0.0480, y = 0.5560},  -- Menethil Harbor
        to = {mapID = 117, x = 0.6080, y = 0.6260},   -- Valgarde
        travelTime = 180,
        faction = "Alliance",
        type = "boat",
        bidirectional = true,
    },

    -- =========================================================================
    -- HORDE ZEPPELINS
    -- =========================================================================
    {
        name = "Orgrimmar to Undercity",
        from = {mapID = 85, x = 0.5090, y = 0.5580},  -- Orgrimmar Zeppelin Tower
        to = {mapID = 18, x = 0.6210, y = 0.5890},    -- Brill/Tirisfal Glades
        travelTime = 90,
        faction = "Horde",
        type = "zeppelin",
        bidirectional = true,
    },
    {
        name = "Orgrimmar to Borean Tundra",
        from = {mapID = 85, x = 0.5090, y = 0.5580},  -- Orgrimmar Zeppelin Tower
        to = {mapID = 114, x = 0.4110, y = 0.5540},   -- Warsong Hold
        travelTime = 120,
        faction = "Horde",
        type = "zeppelin",
        bidirectional = true,
    },
    {
        name = "Undercity to Howling Fjord",
        from = {mapID = 18, x = 0.5940, y = 0.5880},  -- Tirisfal Glades Zeppelin Tower
        to = {mapID = 117, x = 0.7810, y = 0.2820},   -- Vengeance Landing
        travelTime = 120,
        faction = "Horde",
        type = "zeppelin",
        bidirectional = true,
    },
    {
        name = "Orgrimmar to Thunder Bluff",
        from = {mapID = 85, x = 0.5090, y = 0.5580},  -- Orgrimmar Zeppelin Tower
        to = {mapID = 88, x = 0.4720, y = 0.4980},    -- Thunder Bluff Platform
        travelTime = 90,
        faction = "Horde",
        type = "zeppelin",
        bidirectional = true,
    },
    {
        name = "Orgrimmar to Stranglethorn Vale",
        from = {mapID = 85, x = 0.5030, y = 0.5670},  -- Orgrimmar Zeppelin Tower
        to = {mapID = 50, x = 0.3720, y = 0.5230},    -- Grom'gol
        travelTime = 150,
        faction = "Horde",
        type = "zeppelin",
        bidirectional = true,
    },

    -- =========================================================================
    -- DRUID DREAMWAY PORTALS
    -- =========================================================================
    {
        name = "Dreamway to Moonglade",
        from = {mapID = 715, x = 0.5600, y = 0.3100},  -- Emerald Dreamway
        to = {mapID = 80, x = 0.4396, y = 0.4544},     -- Moonglade
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },
    {
        name = "Dreamway to Hyjal",
        from = {mapID = 715, x = 0.4200, y = 0.2100},  -- Emerald Dreamway
        to = {mapID = 198, x = 0.6210, y = 0.2280},    -- Mount Hyjal
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },
    {
        name = "Dreamway to Feralas",
        from = {mapID = 715, x = 0.3100, y = 0.3700},  -- Emerald Dreamway
        to = {mapID = 69, x = 0.5150, y = 0.0940},     -- Feralas (Dream Bough)
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },
    {
        name = "Dreamway to Grizzly Hills",
        from = {mapID = 715, x = 0.6200, y = 0.5200},  -- Emerald Dreamway
        to = {mapID = 116, x = 0.4850, y = 0.3230},    -- Grizzly Hills (Grizzlemaw)
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },
    {
        name = "Dreamway to Duskwood",
        from = {mapID = 715, x = 0.4800, y = 0.6300},  -- Emerald Dreamway
        to = {mapID = 47, x = 0.4600, y = 0.3490},     -- Duskwood (Twilight Grove)
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },
    {
        name = "Dreamway to The Dreamgrove",
        from = {mapID = 715, x = 0.5000, y = 0.4500},  -- Emerald Dreamway
        to = {mapID = 747, x = 0.5200, y = 0.5100},    -- The Dreamgrove (Val'sharah)
        travelTime = 5,
        faction = "both",
        type = "portal",
        class = "DRUID",
        bidirectional = true,
    },

    -- =========================================================================
    -- NEUTRAL BOATS
    -- =========================================================================
    {
        name = "Ratchet to Booty Bay",
        from = {mapID = 10, x = 0.6330, y = 0.3810},   -- Ratchet, The Barrens
        to = {mapID = 50, x = 0.2680, y = 0.7260},     -- Booty Bay, Stranglethorn Vale
        travelTime = 240,
        faction = "both",
        type = "boat",
        bidirectional = true,
    },

    -- =========================================================================
    -- MIDNIGHT: TWILIGHT HIGHLANDS FACTION HUB PORTALS (mapID 241)
    -- =========================================================================
    {
        name = "Twilight Highlands to Stormwind",
        from = {mapID = 241, x = 0.496, y = 0.812},
        to = {mapID = 84, x = 0.4934, y = 0.8711},
        travelTime = 10,
        faction = "Alliance",
        type = "portal",
        bidirectional = true,
    },
    {
        name = "Twilight Highlands to Orgrimmar",
        from = {mapID = 241, x = 0.496, y = 0.812},
        to = {mapID = 85, x = 0.5540, y = 0.3840},
        travelTime = 10,
        faction = "Horde",
        type = "portal",
        bidirectional = true,
    },
    {
        name = "Twilight Highlands to Dornogal",
        from = {mapID = 241, x = 0.496, y = 0.812},
        to = {mapID = 2339, x = 0.4850, y = 0.5520},
        travelTime = 10,
        faction = "both",
        type = "portal",
        bidirectional = true,
    },

    -- =========================================================================
    -- THE WAR WITHIN: HALLOWFALL PORTAL (mapID 2215)
    -- =========================================================================
    {
        name = "Hallowfall to Dornogal",
        from = {mapID = 2215, x = 0.42, y = 0.52},  -- Dunelle's Kindness (approx)
        to = {mapID = 2339, x = 0.4850, y = 0.5520},
        travelTime = 10,
        faction = "both",
        type = "portal",
        bidirectional = true,
    },

    -- =========================================================================
    -- THE WAR WITHIN: DORNOGAL PORTALS (K'aresh, Undermine)
    -- =========================================================================
    {
        name = "Dornogal to K'aresh",
        from = {mapID = 2339, x = 0.47, y = 0.51},  -- Foundation Hall portal
        to = {mapID = 2371, x = 0.50, y = 0.50},    -- K'aresh arrival
        travelTime = 30,
        faction = "both",
        type = "portal",
        bidirectional = true,
    },
    {
        name = "Dornogal to Undermine",
        from = {mapID = 2339, x = 0.52, y = 0.51},  -- Teleporter in Founder's Hall
        to = {mapID = 2346, x = 0.27, y = 0.53},    -- Undermine arrival
        travelTime = 30,
        faction = "both",
        type = "portal",
        bidirectional = true,
    },

    -- =========================================================================
    -- THE WAR WITHIN: SIREN ISLE TRANSPORTS
    -- =========================================================================
    {
        name = "Isle of Dorn to Siren Isle",
        from = {mapID = 2248, x = 0.554, y = 0.339},  -- Zeppelin platform
        to = {mapID = 2369, x = 0.50, y = 0.50},      -- Siren Isle arrival
        travelTime = 60,
        faction = "both",
        type = "zeppelin",
        bidirectional = true,
    },
    {
        name = "Ringing Deeps to Siren Isle",
        from = {mapID = 2214, x = 0.46, y = 0.302},   -- Gundargaz Mole Machine
        to = {mapID = 2369, x = 0.68, y = 0.386},     -- Flotsam Shoal
        travelTime = 30,
        faction = "both",
        type = "portal",
        bidirectional = true,
    },
}

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
