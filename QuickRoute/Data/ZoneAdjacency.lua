-- ZoneAdjacency.lua
-- Defines continent groupings and zone adjacencies for proper pathfinding
local ADDON_NAME, QR = ...

-------------------------------------------------------------------------------
-- Continent Definitions
-- Maps each continent to its zones and a representative "hub" zone
-------------------------------------------------------------------------------
QR.Continents = {
    EASTERN_KINGDOMS = {
        name = "Eastern Kingdoms",
        hub = 84,  -- Stormwind City
        hubHorde = 85,  -- Orgrimmar (cross-continent portal room hub)
        zones = {
            -- Major Cities
            84,   -- Stormwind City
            87,   -- Ironforge
            89,   -- Darnassus (portal from here)
            90,   -- Undercity
            110,  -- Silvermoon City
            -- Zones (uiMapIDs verified via warcraft.wiki.gg)
            14,   -- Arathi Highlands
            15,   -- Badlands
            17,   -- Blasted Lands
            18,   -- Tirisfal Glades
            21,   -- Silverpine Forest
            22,   -- Western Plaguelands
            23,   -- Eastern Plaguelands
            25,   -- Hillsbrad Foothills
            26,   -- Hinterlands
            27,   -- Dun Morogh
            32,   -- Searing Gorge
            35,   -- Blackrock Mountain
            36,   -- Burning Steppes
            37,   -- Elwynn Forest
            42,   -- Deadwind Pass
            47,   -- Duskwood
            48,   -- Loch Modan
            49,   -- Redridge Mountains
            50,   -- Northern Stranglethorn
            51,   -- Swamp of Sorrows
            52,   -- Westfall
            56,   -- Wetlands
            210,  -- Cape of Stranglethorn
            224,  -- Stranglethorn Vale
            241,  -- Twilight Highlands
            700,  -- Twilight Highlands (Cataclysm)
            -- Midnight Expansion (12.0)
            2393, -- Silvermoon City (revamped)
            2395, -- Eversong Woods (includes old Ghostlands)
            2424, -- Isle of Quel'Danas
            2437, -- Zul'Aman
            2576, -- Harandar
            2405, -- Voidstorm
            -- Pre-Midnight legacy zones (classic/TBC dungeon entrances)
            15,   -- Badlands (sub-zone for Uldaman entrance)
            95,   -- Ghostlands (Zul'Aman entrance, pre-Midnight)
            122,  -- Isle of Quel'Danas (TBC, Magisters' Terrace/Sunwell)
            244,  -- Tol Barad Peninsula (Baradin Hold)
            207,  -- Deepholm (portal from SW/Org, The Stonecore)
        },
    },
    KALIMDOR = {
        name = "Kalimdor",
        hub = 85,   -- Orgrimmar
        hubAlliance = 103, -- Exodar (Darnassus destroyed in BFA)
        zones = {
            -- Major Cities
            85,   -- Orgrimmar
            88,   -- Thunder Bluff
            89,   -- Darnassus
            103,  -- Exodar
            -- Zones (uiMapIDs verified via warcraft.wiki.gg)
            1,    -- Durotar
            7,    -- Mulgore
            10,   -- Northern Barrens
            57,   -- Teldrassil
            62,   -- Darkshore
            63,   -- Ashenvale
            64,   -- Thousand Needles
            65,   -- Stonetalon Mountains
            66,   -- Desolace
            67,   -- Feralas
            69,   -- Tanaris
            70,   -- Dustwallow Marsh
            71,   -- Tanaris (Caverns of Time area)
            76,   -- Azshara
            77,   -- Felwood
            80,   -- Moonglade
            81,   -- Silithus
            83,   -- Winterspring
            106,  -- Bloodmyst Isle
            199,  -- Southern Barrens
            198,  -- Mount Hyjal
            203,  -- Un'Goro Crater
            204,  -- Vashj'ir / Abyssal Depths
            261,  -- Uldum
            -- Dungeon entrance zones
            75,   -- Caverns of Time (Tanaris sub-zone)
            249,  -- Uldum (Cataclysm-era map)
            1527, -- Uldum (N'Zoth Assault version, BFA)
        },
    },
    OUTLAND = {
        name = "Outland",
        hub = 111,  -- Shattrath City
        zones = {
            100,  -- Hellfire Peninsula
            101,  -- Outland (continent overview)
            102,  -- Zangarmarsh
            104,  -- Shadowmoon Valley (Outland)
            105,  -- Blade's Edge Mountains
            107,  -- Nagrand
            108,  -- Terokkar Forest
            109,  -- Netherstorm
            111,  -- Shattrath City
        },
    },
    NORTHREND = {
        name = "Northrend",
        hub = 125,  -- Dalaran (Northrend)
        zones = {
            114,  -- Borean Tundra
            115,  -- Dragonblight
            116,  -- Grizzly Hills
            117,  -- Howling Fjord
            118,  -- Icecrown
            119,  -- Sholazar Basin
            120,  -- Storm Peaks
            121,  -- Zul'Drak
            123,  -- Wintergrasp
            125,  -- Dalaran (Northrend)
            127,  -- Crystalsong Forest
        },
    },
    PANDARIA = {
        name = "Pandaria",
        hub = 390,  -- Vale of Eternal Blossoms (Shrine)
        zones = {
            371,  -- Jade Forest
            376,  -- Valley of the Four Winds
            378,  -- Kun-Lai Summit
            379,  -- Kun-Lai Summit (alternate ID)
            388,  -- Townlong Steppes
            390,  -- Vale of Eternal Blossoms
            418,  -- Krasarang Wilds
            422,  -- Dread Wastes
            433,  -- Isle of Thunder
            504,  -- Isle of Giants
            507,  -- Isle of Thunder (alternate)
            554,  -- Timeless Isle
            1530, -- Vale of Eternal Blossoms (N'Zoth Assault version)
        },
    },
    DRAENOR = {
        name = "Draenor",
        hub = 622,  -- Warspear/Stormshield (Ashran)
        zones = {
            525,  -- Frostfire Ridge
            534,  -- Tanaan Jungle (intro)
            535,  -- Talador
            539,  -- Shadowmoon Valley (Draenor)
            542,  -- Spires of Arak
            543,  -- Gorgrond
            550,  -- Nagrand (Draenor)
            582,  -- Lunarfall (Alliance Garrison)
            590,  -- Frostwall (Horde Garrison)
            622,  -- Stormshield
            624,  -- Warspear
            588,  -- Ashran
        },
    },
    BROKEN_ISLES = {
        name = "Broken Isles",
        hub = 627,  -- Dalaran (Broken Isles)
        zones = {
            627,  -- Dalaran (Broken Isles)
            630,  -- Azsuna
            634,  -- Stormheim
            641,  -- Val'sharah
            646,  -- Broken Shore
            650,  -- Highmountain
            680,  -- Suramar
            790,  -- Eye of Azshara
            830,  -- Krokuun
            882,  -- Mac'Aree
            885,  -- Antoran Wastes
        },
    },
    KUL_TIRAS = {
        name = "Kul Tiras",
        hub = 1161,  -- Boralus
        faction = "Alliance",
        zones = {
            895,  -- Tiragarde Sound
            896,  -- Drustvar
            942,  -- Stormsong Valley
            1161, -- Boralus
        },
    },
    ZANDALAR = {
        name = "Zandalar",
        hub = 1165,  -- Dazar'alor
        faction = "Horde",
        zones = {
            862,  -- Zuldazar
            863,  -- Nazmir
            864,  -- Vol'dun
            1165, -- Dazar'alor
            876,  -- Zandalar (continent-level map, Crucible of Storms)
        },
    },
    BFA_NEUTRAL = {
        name = "Battle for Azeroth Neutral",
        hub = 1355,  -- Nazjatar
        zones = {
            1355, -- Nazjatar
            1462, -- Mechagon
            1169, -- Tol Dagor (off Kul Tiras)
        },
    },
    SHADOWLANDS = {
        name = "Shadowlands",
        hub = 1670,  -- Oribos
        zones = {
            1525, -- Revendreth
            1533, -- Bastion
            1536, -- Maldraxxus
            1565, -- Ardenweald
            1670, -- Oribos
            1543, -- The Maw
            1961, -- Korthia
            1970, -- Zereth Mortis
        },
    },
    DRAGON_ISLES = {
        name = "Dragon Isles",
        hub = 2112,  -- Valdrakken
        zones = {
            2022, -- Waking Shores
            2023, -- Ohn'ahran Plains
            2024, -- Azure Span
            2025, -- Thaldraszus
            2112, -- Valdrakken
            2107, -- Forbidden Reach (alternate ID)
            2151, -- Forbidden Reach (10.0.7 open-world)
            2133, -- Zaralek Cavern
            2200, -- Emerald Dream
            2239, -- Bel'ameth (10.2.5, Night Elf capital on Amirdrassil)
        },
    },
    KHAZ_ALGAR = {
        name = "Khaz Algar",
        hub = 2339,  -- Dornogal
        zones = {
            2248, -- Isle of Dorn
            2214, -- The Ringing Deeps
            2215, -- Hallowfall
            2255, -- Azj-Kahet
            2339, -- Dornogal
            2213, -- City of Threads
            2371, -- K'aresh (Patch 11.2)
            2369, -- Siren Isle (11.0.7, zeppelin from Isle of Dorn)
            2346, -- Undermine (11.1, teleporter from Dornogal)
            2472, -- Tazavesh (11.2, hub within K'aresh)
        },
    },
}

-------------------------------------------------------------------------------
-- Zone to Continent Mapping
-- Quick lookup: mapID -> continent key
-------------------------------------------------------------------------------
QR.ZoneToContinent = {}

-- Build the reverse lookup table
for continentKey, continentData in pairs(QR.Continents) do
    for _, zoneID in ipairs(continentData.zones) do
        QR.ZoneToContinent[zoneID] = continentKey
    end
end

-- Fallback: continent-level map IDs (for when user pins on continent map)
-- These are the parent uiMapIDs that C_Map.GetUserWaypoint may return
QR.ZoneToContinent[12]   = "EASTERN_KINGDOMS"  -- Eastern Kingdoms (continent)
QR.ZoneToContinent[13]   = "KALIMDOR"          -- Kalimdor (continent)
QR.ZoneToContinent[101]  = "OUTLAND"           -- Outland (continent)
QR.ZoneToContinent[113]  = "NORTHREND"         -- Northrend (continent)
QR.ZoneToContinent[424]  = "PANDARIA"          -- Pandaria (continent)
QR.ZoneToContinent[572]  = "DRAENOR"           -- Draenor (continent)
QR.ZoneToContinent[619]  = "BROKEN_ISLES"      -- Broken Isles (continent)
QR.ZoneToContinent[875]  = "KUL_TIRAS"         -- Kul Tiras (continent)
QR.ZoneToContinent[876]  = "ZANDALAR"          -- Zandalar (continent)
QR.ZoneToContinent[1550] = "SHADOWLANDS"       -- Shadowlands (continent)
QR.ZoneToContinent[1978] = "DRAGON_ISLES"      -- Dragon Isles (continent)
QR.ZoneToContinent[2274] = "KHAZ_ALGAR"        -- Khaz Algar (continent)

-------------------------------------------------------------------------------
-- Continent Key → Map ID (for C_Map.GetMapInfo localization)
-------------------------------------------------------------------------------
local ContinentKeyToMapID = {
    EASTERN_KINGDOMS = 12, KALIMDOR = 13, OUTLAND = 101,
    NORTHREND = 113, PANDARIA = 424, DRAENOR = 572,
    BROKEN_ISLES = 619, KUL_TIRAS = 875, ZANDALAR = 876,
    SHADOWLANDS = 1550, DRAGON_ISLES = 1978, KHAZ_ALGAR = 2274,
}

--- Get a localized continent display name from a continent key.
-- Tries C_Map.GetMapInfo first, then falls back to QR.Continents[key].name.
-- @param continentKey string The continent key (e.g., "EASTERN_KINGDOMS")
-- @return string The localized continent name, or the raw key as last resort
function QR.GetLocalizedContinentName(continentKey)
    if not continentKey then return nil end
    local mapID = ContinentKeyToMapID[continentKey]
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    local data = QR.Continents[continentKey]
    return data and data.name or continentKey
end

-------------------------------------------------------------------------------
-- Zone Adjacencies
-- Defines which zones are directly walkable/flyable to each other
-- Format: [mapID] = { {zone = targetMapID, travelTime = seconds}, ... }
-- travelTime is approximate ground mount travel time
-------------------------------------------------------------------------------
QR.ZoneAdjacencies = {
    -- Eastern Kingdoms connections
    [84] = {  -- Stormwind City
        {zone = 37, travelTime = 30},   -- Elwynn Forest
    },
    [37] = {  -- Elwynn Forest
        {zone = 84, travelTime = 30},   -- Stormwind City
        {zone = 52, travelTime = 60},   -- Westfall
        {zone = 49, travelTime = 60},   -- Redridge Mountains
        {zone = 47, travelTime = 90},   -- Duskwood
    },
    [87] = {  -- Ironforge
        {zone = 27, travelTime = 30},   -- Dun Morogh
    },
    [27] = {  -- Dun Morogh
        {zone = 87, travelTime = 30},   -- Ironforge
        {zone = 48, travelTime = 60},   -- Loch Modan
    },
    [90] = {  -- Undercity
        {zone = 18, travelTime = 30},   -- Tirisfal Glades
    },
    [18] = {  -- Tirisfal Glades
        {zone = 90, travelTime = 30},   -- Undercity
        {zone = 21, travelTime = 60},   -- Silverpine Forest
        {zone = 22, travelTime = 90},   -- Western Plaguelands
    },

    -- Kalimdor connections
    [85] = {  -- Orgrimmar
        {zone = 1, travelTime = 30},    -- Durotar
        {zone = 76, travelTime = 60},   -- Azshara
    },
    [1] = {  -- Durotar
        {zone = 85, travelTime = 30},   -- Orgrimmar
        {zone = 10, travelTime = 60},   -- Northern Barrens
    },
    [88] = {  -- Thunder Bluff
        {zone = 7, travelTime = 30},    -- Mulgore
    },
    [7] = {  -- Mulgore
        {zone = 88, travelTime = 30},   -- Thunder Bluff
        {zone = 199, travelTime = 90},  -- Southern Barrens
    },
    [10] = {  -- Northern Barrens
        {zone = 1, travelTime = 60},    -- Durotar
        {zone = 63, travelTime = 60},   -- Ashenvale
        {zone = 199, travelTime = 60},  -- Southern Barrens
        {zone = 70, travelTime = 90},   -- Dustwallow Marsh
    },
    [80] = {  -- Moonglade
        {zone = 77, travelTime = 60},   -- Felwood
        {zone = 83, travelTime = 60},   -- Winterspring
        {zone = 198, travelTime = 60},  -- Mount Hyjal (via world tree portal)
    },

    -- Northrend connections
    [125] = {  -- Dalaran Northrend
        {zone = 127, travelTime = 30},  -- Crystalsong Forest
    },
    [127] = {  -- Crystalsong Forest
        {zone = 125, travelTime = 30},  -- Dalaran
        {zone = 115, travelTime = 60},  -- Dragonblight
        {zone = 121, travelTime = 60},  -- Zul'Drak
        {zone = 120, travelTime = 60},  -- Storm Peaks
    },
    [114] = {  -- Borean Tundra
        {zone = 115, travelTime = 90},  -- Dragonblight
        {zone = 119, travelTime = 90},  -- Sholazar Basin
    },
    [117] = {  -- Howling Fjord
        {zone = 116, travelTime = 90},  -- Grizzly Hills
    },
    [116] = {  -- Grizzly Hills
        {zone = 117, travelTime = 90},  -- Howling Fjord
        {zone = 115, travelTime = 90},  -- Dragonblight
        {zone = 121, travelTime = 90},  -- Zul'Drak
    },

    -- Pandaria connections
    [378] = {  -- Kun-Lai Summit
        {zone = 371, travelTime = 90},  -- Jade Forest
        {zone = 376, travelTime = 90},  -- Valley of Four Winds
        {zone = 388, travelTime = 90},  -- Townlong Steppes
        {zone = 390, travelTime = 60},  -- Vale of Eternal Blossoms
        {zone = 504, travelTime = 120}, -- Isle of Giants (boat)
        {zone = 1530, travelTime = 60}, -- Vale N'Zoth Assault (same as Vale)
    },
    [379] = {  -- Kun-Lai Summit (alternate ID)
        {zone = 371, travelTime = 90},
        {zone = 376, travelTime = 90},
        {zone = 388, travelTime = 90},
        {zone = 390, travelTime = 60},
    },
    [390] = {  -- Vale of Eternal Blossoms
        {zone = 378, travelTime = 60},  -- Kun-Lai Summit
        {zone = 379, travelTime = 60},  -- Kun-Lai Summit (alt)
        {zone = 388, travelTime = 60},  -- Townlong Steppes
        {zone = 422, travelTime = 60},  -- Dread Wastes
    },
    [371] = {  -- Jade Forest
        {zone = 378, travelTime = 90},  -- Kun-Lai Summit
        {zone = 379, travelTime = 90},  -- Kun-Lai Summit (alt)
        {zone = 376, travelTime = 60},  -- Valley of Four Winds
        {zone = 418, travelTime = 60},  -- Krasarang Wilds
    },
    [376] = {  -- Valley of the Four Winds
        {zone = 371, travelTime = 60},  -- Jade Forest
        {zone = 378, travelTime = 90},  -- Kun-Lai Summit
        {zone = 379, travelTime = 90},  -- Kun-Lai Summit (alternate ID)
        {zone = 418, travelTime = 60},  -- Krasarang Wilds
    },

    -- Outland connections
    [111] = {  -- Shattrath City
        {zone = 108, travelTime = 30},  -- Terokkar Forest
    },
    [100] = {  -- Hellfire Peninsula
        {zone = 102, travelTime = 90},  -- Zangarmarsh
        {zone = 108, travelTime = 90},  -- Terokkar Forest
    },
    [108] = {  -- Terokkar Forest
        {zone = 111, travelTime = 30},  -- Shattrath City
        {zone = 100, travelTime = 90},  -- Hellfire Peninsula
        {zone = 102, travelTime = 90},  -- Zangarmarsh
        {zone = 107, travelTime = 90},  -- Nagrand
        {zone = 104, travelTime = 90},  -- Shadowmoon Valley
    },

    -- Shadowlands connections
    [1670] = {  -- Oribos
        {zone = 1533, travelTime = 120}, -- Bastion
        {zone = 1536, travelTime = 120}, -- Maldraxxus
        {zone = 1565, travelTime = 120}, -- Ardenweald
        {zone = 1525, travelTime = 120}, -- Revendreth
        {zone = 1543, travelTime = 120}, -- The Maw
    },

    -- Dragon Isles connections
    [2112] = {  -- Valdrakken
        {zone = 2025, travelTime = 30},  -- Thaldraszus
    },
    [2025] = {  -- Thaldraszus
        {zone = 2112, travelTime = 30},  -- Valdrakken
        {zone = 2024, travelTime = 60},  -- Azure Span
        {zone = 2023, travelTime = 60},  -- Ohn'ahran Plains
        {zone = 2133, travelTime = 60},  -- Zaralek Cavern (entrance nearby)
    },
    [2022] = {  -- Waking Shores
        {zone = 2023, travelTime = 60},  -- Ohn'ahran Plains
    },
    [2023] = {  -- Ohn'ahran Plains
        {zone = 2022, travelTime = 60},  -- Waking Shores
        {zone = 2024, travelTime = 60},  -- Azure Span
        {zone = 2025, travelTime = 60},  -- Thaldraszus
        {zone = 2239, travelTime = 60},  -- Bel'ameth (Amirdrassil, west coast)
        {zone = 2200, travelTime = 60},  -- Emerald Dream (Ancient Bough portal)
    },
    [2239] = {  -- Bel'ameth (Night Elf capital, Patch 10.2.5)
        {zone = 2023, travelTime = 60},  -- Ohn'ahran Plains (dragonriding)
    },
    [2024] = {  -- Azure Span
        {zone = 2023, travelTime = 60},  -- Ohn'ahran Plains
        {zone = 2025, travelTime = 60},  -- Thaldraszus
    },

    -- Khaz Algar connections (The War Within)
    [2339] = {  -- Dornogal
        {zone = 2248, travelTime = 30},  -- Isle of Dorn
        -- K'aresh and Undermine accessed via portals (see StandalonePortals in Portals.lua)
    },
    [2248] = {  -- Isle of Dorn
        {zone = 2339, travelTime = 30},  -- Dornogal
        {zone = 2214, travelTime = 60},  -- The Ringing Deeps
        -- Siren Isle accessed via zeppelin (see StandalonePortals in Portals.lua)
    },
    [2214] = {  -- The Ringing Deeps
        {zone = 2248, travelTime = 60},  -- Isle of Dorn
        {zone = 2215, travelTime = 60},  -- Hallowfall
        {zone = 2255, travelTime = 90},  -- Azj-Kahet
        -- Siren Isle accessed via Mole Machine (see StandalonePortals in Portals.lua)
    },
    [2215] = {  -- Hallowfall
        {zone = 2214, travelTime = 60},  -- The Ringing Deeps
        {zone = 2255, travelTime = 60},  -- Azj-Kahet
    },
    [2255] = {  -- Azj-Kahet
        {zone = 2214, travelTime = 90},  -- The Ringing Deeps
        {zone = 2215, travelTime = 60},  -- Hallowfall
        {zone = 2213, travelTime = 30},  -- City of Threads
    },
    [2213] = {  -- City of Threads
        {zone = 2255, travelTime = 30},  -- Azj-Kahet
    },
    [2371] = {  -- K'aresh (Patch 11.2)
        -- Dornogal accessed via return portal (see StandalonePortals in Portals.lua)
        {zone = 2472, travelTime = 15},  -- Tazavesh (hub within K'aresh)
    },
    [2472] = {  -- Tazavesh (open-world hub within K'aresh, Patch 11.2)
        {zone = 2371, travelTime = 15},  -- K'aresh
    },
    [2369] = {  -- Siren Isle (Patch 11.0.7)
        -- Isle of Dorn via zeppelin and Ringing Deeps via Mole Machine
        -- (see StandalonePortals in Portals.lua)
    },
    [2346] = {  -- Undermine (Patch 11.1)
        -- Dornogal via teleporter (see StandalonePortals in Portals.lua)
    },

    -- Kul Tiras connections (BFA Alliance)
    [1161] = {  -- Boralus
        {zone = 895, travelTime = 30},   -- Tiragarde Sound
    },
    [895] = {  -- Tiragarde Sound
        {zone = 1161, travelTime = 30},  -- Boralus
        {zone = 896, travelTime = 60},   -- Drustvar
        {zone = 942, travelTime = 60},   -- Stormsong Valley
        {zone = 1169, travelTime = 60},  -- Tol Dagor
    },
    [896] = {  -- Drustvar
        {zone = 895, travelTime = 60},   -- Tiragarde Sound
        {zone = 942, travelTime = 90},   -- Stormsong Valley
    },
    [942] = {  -- Stormsong Valley
        {zone = 895, travelTime = 60},   -- Tiragarde Sound
        {zone = 896, travelTime = 90},   -- Drustvar
        {zone = 876, travelTime = 60},   -- Zandalar continent (Crucible of Storms)
    },

    -- Zandalar connections (BFA Horde)
    [1165] = {  -- Dazar'alor
        {zone = 862, travelTime = 30},   -- Zuldazar
    },
    [862] = {  -- Zuldazar
        {zone = 1165, travelTime = 30},  -- Dazar'alor
        {zone = 863, travelTime = 60},   -- Nazmir
        {zone = 864, travelTime = 60},   -- Vol'dun
    },
    [863] = {  -- Nazmir
        {zone = 862, travelTime = 60},   -- Zuldazar
        {zone = 864, travelTime = 90},   -- Vol'dun
    },
    [864] = {  -- Vol'dun
        {zone = 862, travelTime = 60},   -- Zuldazar
        {zone = 863, travelTime = 90},   -- Nazmir
    },

    -- BFA Neutral zones
    [1355] = {  -- Nazjatar
        -- Accessed via portal from Boralus/Dazar'alor, not walkable to other zones
    },
    [1462] = {  -- Mechagon
        -- Accessed via portal from Boralus/Dazar'alor, not walkable to other zones
    },

    -- Broken Isles additional connections
    [627] = {  -- Dalaran (Broken Isles)
        {zone = 630, travelTime = 60},   -- Azsuna
        {zone = 634, travelTime = 60},   -- Stormheim
        {zone = 641, travelTime = 60},   -- Val'sharah
        {zone = 646, travelTime = 60},   -- Broken Shore
        {zone = 650, travelTime = 60},   -- Highmountain
        {zone = 680, travelTime = 60},   -- Suramar
    },
    [630] = {  -- Azsuna
        {zone = 627, travelTime = 60},   -- Dalaran
        {zone = 641, travelTime = 60},   -- Val'sharah
        {zone = 646, travelTime = 90},   -- Broken Shore
    },
    [641] = {  -- Val'sharah
        {zone = 630, travelTime = 60},   -- Azsuna
        {zone = 627, travelTime = 60},   -- Dalaran
        {zone = 650, travelTime = 60},   -- Highmountain
    },
    [650] = {  -- Highmountain
        {zone = 641, travelTime = 60},   -- Val'sharah
        {zone = 627, travelTime = 60},   -- Dalaran
        {zone = 634, travelTime = 60},   -- Stormheim
    },
    [634] = {  -- Stormheim
        {zone = 650, travelTime = 60},   -- Highmountain
        {zone = 627, travelTime = 60},   -- Dalaran
    },
    [680] = {  -- Suramar
        {zone = 627, travelTime = 60},   -- Dalaran
    },
    [646] = {  -- Broken Shore
        {zone = 630, travelTime = 90},   -- Azsuna
        {zone = 627, travelTime = 60},   -- Dalaran
    },

    -- Kalimdor - Azshara (corrected mapID 76)
    [76] = {  -- Azshara
        {zone = 85, travelTime = 60},    -- Orgrimmar
    },

    -- Draenor connections
    [622] = {  -- Stormshield (Alliance Ashran)
        {zone = 588, travelTime = 15},   -- Ashran
    },
    [624] = {  -- Warspear (Horde Ashran)
        {zone = 588, travelTime = 15},   -- Ashran
    },
    [588] = {  -- Ashran
        {zone = 622, travelTime = 15},   -- Stormshield
        {zone = 624, travelTime = 15},   -- Warspear
    },

    ---------------------------------------------------------------------------
    -- Eastern Kingdoms - additional inter-zone connections
    -- NOTE: uiMapIDs verified against warcraft.wiki.gg/wiki/UiMapID
    ---------------------------------------------------------------------------
    [47] = {  -- Duskwood
        {zone = 37, travelTime = 90},    -- Elwynn Forest
        {zone = 52, travelTime = 60},    -- Westfall
        {zone = 42, travelTime = 60},    -- Deadwind Pass
        {zone = 50, travelTime = 60},    -- Northern Stranglethorn
    },
    [52] = {  -- Westfall
        {zone = 37, travelTime = 60},    -- Elwynn Forest
        {zone = 47, travelTime = 60},    -- Duskwood
    },
    [49] = {  -- Redridge Mountains (uiMapID 49)
        {zone = 37, travelTime = 60},    -- Elwynn Forest
        {zone = 36, travelTime = 90},    -- Burning Steppes
        {zone = 51, travelTime = 90},    -- Swamp of Sorrows
    },
    [42] = {  -- Deadwind Pass
        {zone = 47, travelTime = 60},    -- Duskwood
        {zone = 51, travelTime = 60},    -- Swamp of Sorrows
    },
    [51] = {  -- Swamp of Sorrows
        {zone = 49, travelTime = 90},    -- Redridge Mountains
        {zone = 42, travelTime = 60},    -- Deadwind Pass
        {zone = 17, travelTime = 60},    -- Blasted Lands
    },
    [17] = {  -- Blasted Lands (uiMapID 17)
        {zone = 51, travelTime = 60},    -- Swamp of Sorrows
    },
    [36] = {  -- Burning Steppes (uiMapID 36)
        {zone = 32, travelTime = 60},    -- Searing Gorge
        {zone = 49, travelTime = 90},    -- Redridge Mountains
        {zone = 35, travelTime = 30},    -- Blackrock Mountain
    },
    [32] = {  -- Searing Gorge
        {zone = 36, travelTime = 60},    -- Burning Steppes
        {zone = 15, travelTime = 60},    -- Badlands
        {zone = 48, travelTime = 90},    -- Loch Modan
        {zone = 35, travelTime = 30},    -- Blackrock Mountain
    },
    [35] = {  -- Blackrock Mountain (uiMapID 35)
        {zone = 36, travelTime = 30},    -- Burning Steppes
        {zone = 32, travelTime = 30},    -- Searing Gorge
    },
    [15] = {  -- Badlands (uiMapID 15)
        {zone = 32, travelTime = 60},    -- Searing Gorge
        {zone = 48, travelTime = 60},    -- Loch Modan
    },
    [48] = {  -- Loch Modan (uiMapID 48)
        {zone = 27, travelTime = 60},    -- Dun Morogh
        {zone = 56, travelTime = 60},    -- Wetlands
        {zone = 15, travelTime = 60},    -- Badlands
        {zone = 32, travelTime = 90},    -- Searing Gorge
    },
    [56] = {  -- Wetlands
        {zone = 48, travelTime = 60},    -- Loch Modan
        {zone = 14, travelTime = 60},    -- Arathi Highlands
        {zone = 241, travelTime = 90},   -- Twilight Highlands (via Dragonmaw Pass)
    },
    [14] = {  -- Arathi Highlands
        {zone = 56, travelTime = 60},    -- Wetlands
        {zone = 25, travelTime = 60},    -- Hillsbrad Foothills
        {zone = 26, travelTime = 60},    -- Hinterlands
    },
    [25] = {  -- Hillsbrad Foothills (uiMapID 25)
        {zone = 21, travelTime = 60},    -- Silverpine Forest
        {zone = 14, travelTime = 60},    -- Arathi Highlands
        {zone = 22, travelTime = 90},    -- Western Plaguelands (via Alterac)
    },
    [21] = {  -- Silverpine Forest
        {zone = 18, travelTime = 60},    -- Tirisfal Glades
        {zone = 25, travelTime = 60},    -- Hillsbrad Foothills
    },
    [22] = {  -- Western Plaguelands
        {zone = 18, travelTime = 90},    -- Tirisfal Glades
        {zone = 23, travelTime = 60},    -- Eastern Plaguelands
        {zone = 25, travelTime = 90},    -- Hillsbrad Foothills (via Alterac)
    },
    [23] = {  -- Eastern Plaguelands (uiMapID 23)
        {zone = 22, travelTime = 60},    -- Western Plaguelands
        {zone = 2395, travelTime = 60},  -- Eversong Woods (Thalassian Pass, seamless)
        {zone = 95, travelTime = 60},    -- Ghostlands (pre-Midnight Zul'Aman)
        {zone = 122, travelTime = 120},  -- Isle of Quel'Danas (TBC, via flight)
    },

    ---------------------------------------------------------------------------
    -- Midnight Expansion (12.0) - revamped Quel'Thalas
    ---------------------------------------------------------------------------
    [2393] = {  -- Silvermoon City (revamped)
        {zone = 2395, travelTime = 30},  -- Eversong Woods
    },
    [2395] = {  -- Eversong Woods (includes old Ghostlands)
        {zone = 2393, travelTime = 30},  -- Silvermoon City
        {zone = 23, travelTime = 60},    -- Eastern Plaguelands (Thalassian Pass)
        {zone = 2424, travelTime = 60},  -- Isle of Quel'Danas
        {zone = 2437, travelTime = 60},  -- Zul'Aman
        {zone = 122, travelTime = 60},   -- Isle of Quel'Danas (TBC era)
    },
    [2424] = {  -- Isle of Quel'Danas
        {zone = 2395, travelTime = 60},  -- Eversong Woods
    },
    [2437] = {  -- Zul'Aman
        {zone = 2395, travelTime = 60},  -- Eversong Woods
        -- Harandar accessed via portal (see StandalonePortals in Portals.lua)
    },
    [2576] = {  -- Harandar
        -- Portal-accessed from Eversong/Zul'Aman (see StandalonePortals in Portals.lua)
    },
    [2405] = {  -- Voidstorm
        -- Portal-accessed, final campaign zone (see StandalonePortals in Portals.lua)
    },

    [50] = {  -- Northern Stranglethorn
        {zone = 47, travelTime = 60},    -- Duskwood
        {zone = 210, travelTime = 60},   -- Cape of Stranglethorn
        {zone = 224, travelTime = 0.001},-- Stranglethorn Vale (parent zone map)
    },
    [210] = {  -- Cape of Stranglethorn
        {zone = 50, travelTime = 60},    -- Northern Stranglethorn
        {zone = 224, travelTime = 0.001},-- Stranglethorn Vale (parent zone map)
    },
    [224] = {  -- Stranglethorn Vale (parent zone map, covers 50 + 210)
        {zone = 50, travelTime = 0.001}, -- Northern Stranglethorn
        {zone = 210, travelTime = 0.001},-- Cape of Stranglethorn
    },
    [26] = {  -- Hinterlands
        {zone = 14, travelTime = 60},    -- Arathi Highlands
    },
    -- NOTE: [35] Blackrock Mountain defined in main EK section above
    [241] = {  -- Twilight Highlands (uiMapID 241)
        {zone = 56, travelTime = 90},    -- Wetlands (via Dragonmaw Pass)
    },
    -- NOTE: [15] Badlands is defined in main EK section with correct adjacencies
    [95] = {  -- Ghostlands (pre-Midnight Zul'Aman entrance)
        {zone = 23, travelTime = 60},    -- Eastern Plaguelands
    },
    [122] = {  -- Isle of Quel'Danas (TBC era)
        {zone = 2395, travelTime = 60},  -- Eversong Woods (Midnight)
        {zone = 23, travelTime = 120},   -- Eastern Plaguelands (via flight)
    },
    [244] = {  -- Tol Barad Peninsula (portal-accessed)
        -- Accessed via portal from Stormwind/Orgrimmar (see StandalonePortals)
    },
    [207] = {  -- Deepholm (portal-accessed)
        -- Accessed via portal from Stormwind/Orgrimmar (see StandalonePortals)
    },

    ---------------------------------------------------------------------------
    -- Kalimdor - additional inter-zone connections (Tier 4.2)
    -- NOTE: uiMapIDs verified via warcraft.wiki.gg (Feb 2026)
    -- 63=Ashenvale, 77=Felwood, 106=Bloodmyst Isle, 70=Dustwallow Marsh
    -- Old IDs used in DungeonEntrances: 11(Ashenvale), 68(Dustwallow)
    ---------------------------------------------------------------------------
    [63] = {  -- Ashenvale (uiMapID 63)
        {zone = 10, travelTime = 60},    -- Northern Barrens
        {zone = 65, travelTime = 60},    -- Stonetalon Mountains
        {zone = 62, travelTime = 60},    -- Darkshore
        {zone = 77, travelTime = 90},    -- Felwood
        {zone = 11, travelTime = 0.001}, -- Ashenvale (old mapID, used in DungeonEntrances)
    },
    [11] = {  -- Ashenvale (old mapID, used in DungeonEntrances for Blackfathom Deeps)
        {zone = 63, travelTime = 0.001}, -- Ashenvale (correct mapID)
    },
    [77] = {  -- Felwood (uiMapID 77)
        {zone = 63, travelTime = 90},    -- Ashenvale
        {zone = 80, travelTime = 60},    -- Moonglade
        {zone = 83, travelTime = 60},    -- Winterspring
    },
    [103] = { -- Exodar (Azuremyst Isle)
        {zone = 62, travelTime = 120},   -- Darkshore (boat/flight)
    },
    [57] = {  -- Teldrassil (Rut'theran Village)
        {zone = 89, travelTime = 15},    -- Darnassus (portal from Rut'theran)
        {zone = 62, travelTime = 120},   -- Darkshore (ferry to Auberdine)
    },
    [89] = {  -- Darnassus
        {zone = 57, travelTime = 15},    -- Teldrassil (portal to Rut'theran)
    },
    [62] = {  -- Darkshore
        {zone = 63, travelTime = 60},    -- Ashenvale
        {zone = 57, travelTime = 120},   -- Teldrassil (ferry from Auberdine)
        {zone = 103, travelTime = 120},  -- Exodar (boat/flight)
    },
    [65] = {  -- Stonetalon Mountains
        {zone = 63, travelTime = 60},    -- Ashenvale
        {zone = 199, travelTime = 60},   -- Southern Barrens
        {zone = 66, travelTime = 90},    -- Desolace
    },
    [199] = {  -- Southern Barrens
        {zone = 10, travelTime = 60},    -- Northern Barrens
        {zone = 7, travelTime = 90},     -- Mulgore
        {zone = 70, travelTime = 60},    -- Dustwallow Marsh
        {zone = 65, travelTime = 60},    -- Stonetalon Mountains
        {zone = 64, travelTime = 60},    -- Thousand Needles
    },
    [66] = {  -- Desolace
        {zone = 65, travelTime = 90},    -- Stonetalon Mountains
        {zone = 67, travelTime = 90},    -- Feralas
    },
    [67] = {  -- Feralas
        {zone = 66, travelTime = 90},    -- Desolace
        {zone = 64, travelTime = 60},    -- Thousand Needles
    },
    [64] = {  -- Thousand Needles
        {zone = 199, travelTime = 60},   -- Southern Barrens
        {zone = 67, travelTime = 60},    -- Feralas
        {zone = 69, travelTime = 60},    -- Tanaris
    },
    [70] = {  -- Dustwallow Marsh (uiMapID 70)
        {zone = 10, travelTime = 90},    -- Northern Barrens
        {zone = 199, travelTime = 60},   -- Southern Barrens
        {zone = 68, travelTime = 0.001}, -- Dustwallow (old mapID, used in DungeonEntrances)
    },
    [68] = {  -- Dustwallow Marsh (old mapID, used in DungeonEntrances for Onyxia's Lair)
        {zone = 70, travelTime = 0.001}, -- Dustwallow Marsh (correct mapID)
    },
    [69] = {  -- Tanaris
        {zone = 64, travelTime = 60},    -- Thousand Needles
        {zone = 203, travelTime = 60},   -- Un'Goro Crater
        {zone = 261, travelTime = 90},   -- Uldum
        {zone = 71, travelTime = 0.001}, -- Tanaris (Caverns of Time area, alternate)
        {zone = 75, travelTime = 30},    -- Caverns of Time (sub-zone)
        {zone = 249, travelTime = 90},   -- Uldum (Cataclysm-era map)
        {zone = 1527, travelTime = 90},  -- Uldum (N'Zoth Assault version)
    },
    [203] = {  -- Un'Goro Crater
        {zone = 69, travelTime = 60},    -- Tanaris
        {zone = 81, travelTime = 60},    -- Silithus
    },
    [81] = {  -- Silithus
        {zone = 203, travelTime = 60},   -- Un'Goro Crater
    },
    [106] = {  -- Bloodmyst Isle (uiMapID 106, NOT Felwood)
        -- Accessed via Exodar/continent routing; no direct zone adjacency needed
    },
    [83] = {  -- Winterspring
        {zone = 80, travelTime = 60},    -- Moonglade
        {zone = 77, travelTime = 60},    -- Felwood
    },
    [261] = {  -- Uldum
        {zone = 69, travelTime = 90},    -- Tanaris
        {zone = 249, travelTime = 0.001},-- Uldum (Cataclysm-era, same zone)
        {zone = 1527, travelTime = 0.001},-- Uldum (N'Zoth version, same zone)
    },
    [198] = {  -- Mount Hyjal
        {zone = 80, travelTime = 60},    -- Moonglade (via world tree portal)
    },
    [71] = {  -- Tanaris (Caverns of Time area, alternate mapID for 69)
        {zone = 69, travelTime = 0.001}, -- Tanaris (primary mapID)
    },
    [75] = {  -- Caverns of Time (Tanaris sub-zone)
        {zone = 69, travelTime = 30},    -- Tanaris (entrance portal in Tanaris)
    },
    [249] = {  -- Uldum (Cataclysm-era map, same physical zone as 261)
        {zone = 69, travelTime = 90},    -- Tanaris
        {zone = 261, travelTime = 0.001},-- Uldum (parent zone map)
    },
    [1527] = {  -- Uldum (N'Zoth Assault version, same physical zone)
        {zone = 69, travelTime = 90},    -- Tanaris
        {zone = 261, travelTime = 0.001},-- Uldum (parent zone map)
    },
    [204] = {  -- Vashj'ir / Abyssal Depths (boat from Stormwind/Orgrimmar)
        -- Accessed via boat from Eastern Kingdoms (see StandalonePortals)
    },

    ---------------------------------------------------------------------------
    -- Outland - additional inter-zone connections (Tier 4.6)
    -- NOTE: uiMapIDs verified: 100=Hellfire, 102=Zangarmarsh, 104=Shadowmoon Valley,
    -- 105=Blade's Edge, 107=Nagrand, 108=Terokkar, 109=Netherstorm, 111=Shattrath
    -- Old ID: 101=Outland continent overview (used in DungeonEntrances for Coilfang)
    ---------------------------------------------------------------------------
    [102] = {  -- Zangarmarsh (uiMapID 102)
        {zone = 100, travelTime = 90},   -- Hellfire Peninsula
        {zone = 108, travelTime = 90},   -- Terokkar Forest
        {zone = 107, travelTime = 90},   -- Nagrand
        {zone = 105, travelTime = 90},   -- Blade's Edge Mountains
        {zone = 101, travelTime = 0.001},-- Zangarmarsh (old mapID, used in DungeonEntrances)
    },
    [101] = {  -- Zangarmarsh (old mapID 101, used in DungeonEntrances for Coilfang)
        {zone = 102, travelTime = 0.001},-- Zangarmarsh (correct mapID)
    },
    [107] = {  -- Nagrand (uiMapID 107)
        {zone = 102, travelTime = 90},   -- Zangarmarsh
        {zone = 108, travelTime = 90},   -- Terokkar Forest
    },
    [105] = {  -- Blade's Edge Mountains
        {zone = 102, travelTime = 90},   -- Zangarmarsh
        {zone = 109, travelTime = 90},   -- Netherstorm
    },
    [104] = {  -- Shadowmoon Valley (uiMapID 104)
        {zone = 108, travelTime = 90},   -- Terokkar Forest
    },
    [109] = {  -- Netherstorm (uiMapID 109)
        {zone = 105, travelTime = 90},   -- Blade's Edge Mountains
    },

    ---------------------------------------------------------------------------
    -- Northrend - additional inter-zone connections (Tier 4.6)
    ---------------------------------------------------------------------------
    [115] = {  -- Dragonblight
        {zone = 114, travelTime = 90},   -- Borean Tundra
        {zone = 118, travelTime = 90},   -- Icecrown (via Icecrown border)
        {zone = 127, travelTime = 60},   -- Crystalsong Forest
        {zone = 116, travelTime = 90},   -- Grizzly Hills
        {zone = 121, travelTime = 90},   -- Zul'Drak
        {zone = 123, travelTime = 90},   -- Wintergrasp
    },
    [119] = {  -- Sholazar Basin
        {zone = 114, travelTime = 90},   -- Borean Tundra
    },
    [121] = {  -- Zul'Drak
        {zone = 127, travelTime = 60},   -- Crystalsong Forest
        {zone = 116, travelTime = 90},   -- Grizzly Hills
        {zone = 115, travelTime = 90},   -- Dragonblight
    },
    [120] = {  -- Storm Peaks
        {zone = 127, travelTime = 60},   -- Crystalsong Forest
        {zone = 118, travelTime = 90},   -- Icecrown
        {zone = 123, travelTime = 90},   -- Wintergrasp
    },
    [118] = {  -- Icecrown
        {zone = 120, travelTime = 90},   -- Storm Peaks
        {zone = 115, travelTime = 90},   -- Dragonblight (via Icecrown border)
    },
    [123] = {  -- Wintergrasp
        {zone = 115, travelTime = 90},   -- Dragonblight
        {zone = 120, travelTime = 90},   -- Storm Peaks
    },

    ---------------------------------------------------------------------------
    -- Draenor - additional inter-zone connections (Tier 4.6)
    ---------------------------------------------------------------------------
    [525] = {  -- Frostfire Ridge
        {zone = 543, travelTime = 90},   -- Gorgrond
    },
    [543] = {  -- Gorgrond
        {zone = 525, travelTime = 90},   -- Frostfire Ridge
        {zone = 535, travelTime = 90},   -- Talador
        {zone = 542, travelTime = 90},   -- Spires of Arak
        {zone = 534, travelTime = 90},   -- Tanaan Jungle
    },
    [535] = {  -- Talador
        {zone = 543, travelTime = 90},   -- Gorgrond
        {zone = 539, travelTime = 60},   -- Shadowmoon Valley (Draenor)
        {zone = 542, travelTime = 60},   -- Spires of Arak
        {zone = 550, travelTime = 90},   -- Nagrand (Draenor)
        {zone = 534, travelTime = 90},   -- Tanaan Jungle
    },
    [539] = {  -- Shadowmoon Valley (Draenor)
        {zone = 535, travelTime = 60},   -- Talador
    },
    [542] = {  -- Spires of Arak
        {zone = 535, travelTime = 60},   -- Talador
        {zone = 543, travelTime = 90},   -- Gorgrond
    },
    [550] = {  -- Nagrand (Draenor)
        {zone = 535, travelTime = 90},   -- Talador
    },
    [534] = {  -- Tanaan Jungle
        {zone = 543, travelTime = 90},   -- Gorgrond
        {zone = 535, travelTime = 90},   -- Talador
    },

    ---------------------------------------------------------------------------
    -- Pandaria - additional inter-zone connections (Tier 4.6)
    ---------------------------------------------------------------------------
    [388] = {  -- Townlong Steppes
        {zone = 378, travelTime = 90},   -- Kun-Lai Summit
        {zone = 379, travelTime = 90},   -- Kun-Lai Summit (alternate ID)
        {zone = 390, travelTime = 60},   -- Vale of Eternal Blossoms
        {zone = 422, travelTime = 60},   -- Dread Wastes
        {zone = 433, travelTime = 120},  -- Isle of Thunder (portal/boat)
        {zone = 1530, travelTime = 60},  -- Vale N'Zoth Assault (same as Vale)
    },
    [422] = {  -- Dread Wastes
        {zone = 390, travelTime = 60},   -- Vale of Eternal Blossoms
        {zone = 388, travelTime = 60},   -- Townlong Steppes
    },
    [418] = {  -- Krasarang Wilds
        {zone = 371, travelTime = 60},   -- Jade Forest
        {zone = 376, travelTime = 60},   -- Valley of the Four Winds
    },
    [433] = {  -- Isle of Thunder
        {zone = 388, travelTime = 120},  -- Townlong Steppes (portal/boat)
    },
    [504] = {  -- Isle of Giants
        {zone = 378, travelTime = 120},  -- Kun-Lai Summit (boat)
    },
    [1530] = {  -- Vale of Eternal Blossoms (N'Zoth Assault version)
        {zone = 378, travelTime = 60},   -- Kun-Lai Summit
        {zone = 388, travelTime = 60},   -- Townlong Steppes
    },

    ---------------------------------------------------------------------------
    -- Broken Isles - Argus zones (portal-accessed via Vindicaar)
    ---------------------------------------------------------------------------
    [882] = {  -- Mac'Aree (Argus)
        {zone = 885, travelTime = 30},   -- Antoran Wastes (Vindicaar network)
    },
    [885] = {  -- Antoran Wastes (Argus)
        {zone = 882, travelTime = 30},   -- Mac'Aree (Vindicaar network)
        -- Return portal to Dalaran (see StandalonePortals)
    },

    ---------------------------------------------------------------------------
    -- BFA - additional zones
    ---------------------------------------------------------------------------
    [876] = {  -- Zandalar (continent-level map, Crucible of Storms)
        {zone = 942, travelTime = 60},   -- Stormsong Valley (nearest zone)
    },
    [1169] = {  -- Tol Dagor (off Kul Tiras)
        {zone = 895, travelTime = 60},   -- Tiragarde Sound (nearest Kul Tiras zone)
    },

    ---------------------------------------------------------------------------
    -- Shadowlands - patch zones
    ---------------------------------------------------------------------------
    [1970] = {  -- Zereth Mortis
        -- Portal-accessed from Oribos (see StandalonePortals)
    },

    ---------------------------------------------------------------------------
    -- Dragon Isles - patch zones
    ---------------------------------------------------------------------------
    [2133] = {  -- Zaralek Cavern
        {zone = 2025, travelTime = 60},  -- Thaldraszus (entrance near Valdrakken)
    },
    [2200] = {  -- Emerald Dream
        {zone = 2023, travelTime = 60},  -- Ohn'ahran Plains (Ancient Bough portal)
    },
}

-------------------------------------------------------------------------------
-- Cross-Continent Travel Times
-- Base travel time between continents (via portals/boats when no direct teleport)
-------------------------------------------------------------------------------
QR.CrossContinentTravel = {
    ---------------------------------------------------------------------------
    -- Classic continents (EK <-> Kalimdor: boats/portals between capital cities)
    ---------------------------------------------------------------------------
    EASTERN_KINGDOMS = {
        KALIMDOR = 180,         -- Boat/portal between capital cities
        OUTLAND = 240,          -- Dark Portal in Blasted Lands or Stormwind/Orgrimmar portal
        NORTHREND = 240,        -- Boat from Stormwind/Menethil or portal
        PANDARIA = 300,         -- Portal from Stormwind/Orgrimmar
        DRAENOR = 300,          -- Portal from Stormwind/Orgrimmar (Ashran)
        BROKEN_ISLES = 300,     -- Portal from Stormwind/Orgrimmar to Dalaran
        KUL_TIRAS = 180,        -- Boat from Stormwind (Alliance direct)
        ZANDALAR = 300,         -- Horde needs portal; Alliance indirect
        BFA_NEUTRAL = 360,      -- Portal from Boralus/Dazar'alor, then another hop
        SHADOWLANDS = 300,      -- Oribos portal from Stormwind/Orgrimmar
        DRAGON_ISLES = 240,     -- Portal from Stormwind/Orgrimmar to Valdrakken
        KHAZ_ALGAR = 240,       -- Portal from Stormwind/Orgrimmar to Dornogal
    },
    KALIMDOR = {
        EASTERN_KINGDOMS = 180, -- Boat/portal between capital cities
        OUTLAND = 300,          -- Portal from Orgrimmar/Stormwind
        NORTHREND = 240,        -- Boat from Auberdine or portal from Orgrimmar
        PANDARIA = 300,         -- Portal from Orgrimmar/Stormwind
        DRAENOR = 300,          -- Portal from Orgrimmar/Stormwind (Ashran)
        BROKEN_ISLES = 300,     -- Portal from Orgrimmar/Stormwind to Dalaran
        KUL_TIRAS = 300,        -- Alliance needs portal; Horde indirect
        ZANDALAR = 180,         -- Boat from Orgrimmar (Horde direct)
        BFA_NEUTRAL = 360,      -- Portal from Boralus/Dazar'alor, then another hop
        SHADOWLANDS = 300,      -- Oribos portal from Orgrimmar/Stormwind
        DRAGON_ISLES = 240,     -- Portal from Orgrimmar/Stormwind to Valdrakken
        KHAZ_ALGAR = 240,       -- Portal from Orgrimmar/Stormwind to Dornogal
    },

    ---------------------------------------------------------------------------
    -- Outland (TBC) - accessible via Dark Portal or capital city portals
    ---------------------------------------------------------------------------
    OUTLAND = {
        EASTERN_KINGDOMS = 240, -- Dark Portal to Blasted Lands or Shattrath portal
        KALIMDOR = 300,         -- Shattrath portal to Orgrimmar/Stormwind then boat
        NORTHREND = 360,        -- Shattrath -> capital city -> boat/portal
        PANDARIA = 360,         -- Shattrath -> capital city -> portal
        DRAENOR = 360,          -- Shattrath -> capital city -> portal (no direct link)
        BROKEN_ISLES = 360,     -- Shattrath -> capital city -> portal
        KUL_TIRAS = 360,        -- Shattrath -> Stormwind -> boat
        ZANDALAR = 360,         -- Shattrath -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Shattrath -> capital city -> Oribos portal
        DRAGON_ISLES = 360,     -- Shattrath -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Shattrath -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Northrend (WotLK) - accessible via boats or capital city portals
    ---------------------------------------------------------------------------
    NORTHREND = {
        EASTERN_KINGDOMS = 240, -- Boat to Stormwind/Menethil or Dalaran portal
        KALIMDOR = 240,         -- Dalaran portal or boat
        OUTLAND = 360,          -- Dalaran -> capital city -> Dark Portal
        PANDARIA = 360,         -- Dalaran -> capital city -> portal
        DRAENOR = 360,          -- Dalaran -> capital city -> portal
        BROKEN_ISLES = 300,     -- Dalaran (Northrend) to Dalaran (Broken Isles) via portal
        KUL_TIRAS = 360,        -- Dalaran -> Stormwind -> boat
        ZANDALAR = 360,         -- Dalaran -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Dalaran -> capital city -> Oribos portal
        DRAGON_ISLES = 360,     -- Dalaran -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Dalaran -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Pandaria (MoP) - accessible via portal from capital cities
    ---------------------------------------------------------------------------
    PANDARIA = {
        EASTERN_KINGDOMS = 300, -- Shrine portal to Stormwind/Orgrimmar
        KALIMDOR = 300,         -- Shrine portal to Stormwind/Orgrimmar
        OUTLAND = 360,          -- Shrine -> capital city -> Dark Portal
        NORTHREND = 360,        -- Shrine -> capital city -> boat/portal
        DRAENOR = 360,          -- Shrine -> capital city -> portal
        BROKEN_ISLES = 360,     -- Shrine -> capital city -> portal
        KUL_TIRAS = 360,        -- Shrine -> Stormwind -> boat
        ZANDALAR = 360,         -- Shrine -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Shrine -> capital city -> Oribos portal
        DRAGON_ISLES = 360,     -- Shrine -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Shrine -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Draenor (WoD) - accessible via portal from capital cities
    ---------------------------------------------------------------------------
    DRAENOR = {
        EASTERN_KINGDOMS = 300, -- Ashran/Garrison portal to Stormwind/Orgrimmar
        KALIMDOR = 300,         -- Ashran/Garrison portal to Stormwind/Orgrimmar
        OUTLAND = 360,          -- Garrison -> capital city -> Dark Portal
        NORTHREND = 360,        -- Garrison -> capital city -> boat/portal
        PANDARIA = 360,         -- Garrison -> capital city -> portal
        BROKEN_ISLES = 360,     -- Garrison -> capital city -> portal
        KUL_TIRAS = 360,        -- Garrison -> Stormwind -> boat
        ZANDALAR = 360,         -- Garrison -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Garrison -> capital city -> Oribos portal
        DRAGON_ISLES = 360,     -- Garrison -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Garrison -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Broken Isles (Legion) - accessible via Dalaran hearthstone or portal
    ---------------------------------------------------------------------------
    BROKEN_ISLES = {
        EASTERN_KINGDOMS = 300, -- Dalaran portal to Stormwind/Orgrimmar
        KALIMDOR = 300,         -- Dalaran portal to Stormwind/Orgrimmar
        OUTLAND = 360,          -- Dalaran -> capital city -> Dark Portal
        NORTHREND = 300,        -- Dalaran (Broken Isles) to Dalaran (Northrend) via portal
        PANDARIA = 360,         -- Dalaran -> capital city -> portal
        DRAENOR = 360,          -- Dalaran -> capital city -> portal
        KUL_TIRAS = 360,        -- Dalaran -> Stormwind -> boat
        ZANDALAR = 360,         -- Dalaran -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Dalaran -> capital city -> Oribos portal
        DRAGON_ISLES = 360,     -- Dalaran -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Dalaran -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Kul Tiras (BFA Alliance) - accessible via boat from Stormwind
    ---------------------------------------------------------------------------
    KUL_TIRAS = {
        EASTERN_KINGDOMS = 180, -- Boat to Stormwind (Alliance direct)
        KALIMDOR = 300,         -- Boralus -> Stormwind -> boat/portal
        OUTLAND = 360,          -- Boralus -> Stormwind -> Dark Portal
        NORTHREND = 360,        -- Boralus -> Stormwind -> boat/portal
        PANDARIA = 360,         -- Boralus -> Stormwind -> portal
        DRAENOR = 360,          -- Boralus -> Stormwind -> portal
        BROKEN_ISLES = 360,     -- Boralus -> Stormwind -> portal
        ZANDALAR = 240,         -- BFA cross-faction portal or boat
        BFA_NEUTRAL = 180,      -- Direct portal from Boralus to Nazjatar/Mechagon
        SHADOWLANDS = 300,      -- Boralus -> Stormwind -> Oribos portal
        DRAGON_ISLES = 300,     -- Boralus -> Stormwind -> portal
        KHAZ_ALGAR = 300,       -- Boralus -> Stormwind -> portal
    },

    ---------------------------------------------------------------------------
    -- Zandalar (BFA Horde) - accessible via boat from Orgrimmar
    ---------------------------------------------------------------------------
    ZANDALAR = {
        EASTERN_KINGDOMS = 300, -- Dazar'alor -> Orgrimmar -> portal/boat
        KALIMDOR = 180,         -- Boat to Orgrimmar (Horde direct)
        OUTLAND = 360,          -- Dazar'alor -> Orgrimmar -> Dark Portal
        NORTHREND = 360,        -- Dazar'alor -> Orgrimmar -> boat/portal
        PANDARIA = 360,         -- Dazar'alor -> Orgrimmar -> portal
        DRAENOR = 360,          -- Dazar'alor -> Orgrimmar -> portal
        BROKEN_ISLES = 360,     -- Dazar'alor -> Orgrimmar -> portal
        KUL_TIRAS = 240,        -- BFA cross-faction portal or boat
        BFA_NEUTRAL = 180,      -- Direct portal from Dazar'alor to Nazjatar/Mechagon
        SHADOWLANDS = 300,      -- Dazar'alor -> Orgrimmar -> Oribos portal
        DRAGON_ISLES = 300,     -- Dazar'alor -> Orgrimmar -> portal
        KHAZ_ALGAR = 300,       -- Dazar'alor -> Orgrimmar -> portal
    },

    ---------------------------------------------------------------------------
    -- BFA Neutral zones (Nazjatar/Mechagon) - portal from Boralus or Dazar'alor
    ---------------------------------------------------------------------------
    BFA_NEUTRAL = {
        EASTERN_KINGDOMS = 360, -- Nazjatar -> Boralus/Dazar'alor -> capital city
        KALIMDOR = 360,         -- Nazjatar -> Boralus/Dazar'alor -> capital city
        OUTLAND = 420,          -- Multiple hops required
        NORTHREND = 420,        -- Multiple hops required
        PANDARIA = 420,         -- Multiple hops required
        DRAENOR = 420,          -- Multiple hops required
        BROKEN_ISLES = 420,     -- Multiple hops required
        KUL_TIRAS = 180,        -- Direct portal to Boralus
        ZANDALAR = 180,         -- Direct portal to Dazar'alor
        SHADOWLANDS = 420,      -- Multiple hops required
        DRAGON_ISLES = 420,     -- Multiple hops required
        KHAZ_ALGAR = 420,       -- Multiple hops required
    },

    ---------------------------------------------------------------------------
    -- Shadowlands - only accessible via Oribos portal from capital cities
    ---------------------------------------------------------------------------
    SHADOWLANDS = {
        EASTERN_KINGDOMS = 300, -- Oribos portal to Stormwind/Orgrimmar
        KALIMDOR = 300,         -- Oribos portal to Orgrimmar/Stormwind
        OUTLAND = 360,          -- Oribos -> capital city -> Dark Portal
        NORTHREND = 360,        -- Oribos -> capital city -> boat/portal
        PANDARIA = 360,         -- Oribos -> capital city -> portal
        DRAENOR = 360,          -- Oribos -> capital city -> portal
        BROKEN_ISLES = 360,     -- Oribos -> capital city -> portal
        KUL_TIRAS = 300,        -- Oribos -> Stormwind -> boat
        ZANDALAR = 300,         -- Oribos -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        DRAGON_ISLES = 360,     -- Oribos -> capital city -> portal
        KHAZ_ALGAR = 360,       -- Oribos -> capital city -> portal
    },

    ---------------------------------------------------------------------------
    -- Dragon Isles (Dragonflight) - portal from capital cities to Valdrakken
    ---------------------------------------------------------------------------
    DRAGON_ISLES = {
        EASTERN_KINGDOMS = 240, -- Valdrakken portal to Stormwind/Orgrimmar
        KALIMDOR = 240,         -- Valdrakken portal to Stormwind/Orgrimmar
        OUTLAND = 360,          -- Valdrakken -> capital city -> Dark Portal
        NORTHREND = 360,        -- Valdrakken -> capital city -> boat/portal
        PANDARIA = 360,         -- Valdrakken -> capital city -> portal
        DRAENOR = 360,          -- Valdrakken -> capital city -> portal
        BROKEN_ISLES = 360,     -- Valdrakken -> capital city -> portal
        KUL_TIRAS = 300,        -- Valdrakken -> Stormwind -> boat
        ZANDALAR = 300,         -- Valdrakken -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Valdrakken -> capital city -> Oribos portal
        KHAZ_ALGAR = 240,       -- Recent expansions, direct portal likely
    },

    ---------------------------------------------------------------------------
    -- Khaz Algar (The War Within) - portal from capital cities to Dornogal
    ---------------------------------------------------------------------------
    KHAZ_ALGAR = {
        EASTERN_KINGDOMS = 240, -- Dornogal portal to Stormwind/Orgrimmar
        KALIMDOR = 240,         -- Dornogal portal to Stormwind/Orgrimmar
        OUTLAND = 360,          -- Dornogal -> capital city -> Dark Portal
        NORTHREND = 360,        -- Dornogal -> capital city -> boat/portal
        PANDARIA = 360,         -- Dornogal -> capital city -> portal
        DRAENOR = 360,          -- Dornogal -> capital city -> portal
        BROKEN_ISLES = 360,     -- Dornogal -> capital city -> portal
        KUL_TIRAS = 300,        -- Dornogal -> Stormwind -> boat
        ZANDALAR = 300,         -- Dornogal -> Orgrimmar -> boat
        BFA_NEUTRAL = 420,      -- Multiple hops required
        SHADOWLANDS = 360,      -- Dornogal -> capital city -> Oribos portal
        DRAGON_ISLES = 240,     -- Recent expansions, direct portal likely
    },
}

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

--- Estimate travel time between two zones on the same continent
-- Uses BFS through adjacency graph
-- @param fromMapID number Starting map ID
-- @param toMapID number Destination map ID
-- @return number|nil Travel time in seconds, or nil if no path
function QR.EstimateSameContinentTravel(fromMapID, toMapID)
    if fromMapID == toMapID then
        return 0
    end

    -- Check if same continent
    if not QR.AreSameContinent(fromMapID, toMapID) then
        return nil
    end

    -- BFS to find path through zone adjacencies
    -- Uses front-pointer instead of table.remove(queue, 1) for O(1) dequeue
    local visited = {}
    local queue = {{zone = fromMapID, time = 0}}
    local front = 1
    visited[fromMapID] = true

    while front <= #queue do
        local current = queue[front]
        front = front + 1

        local adjacencies = QR.ZoneAdjacencies[current.zone]
        if adjacencies then
            for _, adj in ipairs(adjacencies) do
                if adj.zone == toMapID then
                    return current.time + adj.travelTime
                end

                if not visited[adj.zone] then
                    visited[adj.zone] = true
                    queue[#queue + 1] = {
                        zone = adj.zone,
                        time = current.time + adj.travelTime
                    }
                end
            end
        end
    end

    -- No path found through adjacencies, estimate based on continent
    -- Assume flying at ~300% speed across zone takes ~120 seconds average
    return 180
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
