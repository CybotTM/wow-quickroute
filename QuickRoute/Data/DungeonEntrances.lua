-- DungeonEntrances.lua
-- Static fallback data for dungeon/raid entrance coordinates.
-- Used when the runtime API C_EncounterJournal.GetDungeonEntrancesForMap()
-- returns nothing (character hasn't discovered the instance yet).
--
-- Format: [zoneMapID] = { { journalInstanceID, x, y, "English Name", isRaid }, ... }
-- Coordinates are 0-1 normalized.  Names are English fallbacks only —
-- at runtime the DungeonData module resolves localized names via the API.
local ADDON_NAME, QR = ...

QR.StaticDungeonEntrances = {

    ---------------------------------------------------------------------------
    -- CLASSIC
    ---------------------------------------------------------------------------

    -- Durotar / Orgrimmar
    [1] = {
        { 226, 0.4577, 0.0834, "Ragefire Chasm", false },
    },
    [85] = {
        { 226, 0.5500, 0.5780, "Ragefire Chasm", false },
    },

    -- Northern Barrens
    [10] = {
        { 240, 0.4028, 0.6808, "Wailing Caverns", false },
    },

    -- Ashenvale  (mapID 11 is primary; 63 is alternate)
    [11] = {
        { 227, 0.1386, 0.1370, "Blackfathom Deeps", false },
    },
    [63] = {
        { 227, 0.1386, 0.1370, "Blackfathom Deeps", false },
    },

    -- Desolace
    [66] = {
        { 232, 0.3010, 0.6190, "Maraudon", false },
    },

    -- Southern Barrens
    [199] = {
        { 234, 0.3913, 0.9431, "Razorfen Kraul", false },
    },

    -- Thousand Needles
    [64] = {
        { 233, 0.4930, 0.2640, "Razorfen Downs", false },
    },

    -- Feralas  (mapID 67)
    [67] = {
        { 230, 0.6147, 0.3093, "Dire Maul", false },
    },

    -- Tanaris  (mapID 69 = main zone; 71 = Caverns of Time sub-area)
    [69] = {
        { 241, 0.3939, 0.2098, "Zul'Farrak", false },
    },

    -- Silithus (AQ gates)
    [81] = {
        { 743, 0.5900, 0.1430, "Ruins of Ahn'Qiraj", true },
        { 744, 0.4680, 0.0750, "Temple of Ahn'Qiraj", true },
    },

    -- Silverpine Forest
    [21] = {
        { 64, 0.4487, 0.6731, "Shadowfang Keep", false },
    },

    -- Tirisfal Glades
    [18] = {
        { 311, 0.8300, 0.3000, "Scarlet Halls", false },
        { 316, 0.8300, 0.3000, "Scarlet Monastery", false },
    },

    -- Western Plaguelands
    [22] = {
        { 246, 0.7079, 0.7095, "Scholomance", false },
    },

    -- Eastern Plaguelands  (Stratholme, mapID 49)
    [49] = {
        { 236, 0.2720, 0.1160, "Stratholme", false },
    },

    -- Dun Morogh
    [27] = {
        { 231, 0.3020, 0.3572, "Gnomeregan", false },
    },

    -- Stormwind City
    [84] = {
        { 238, 0.5100, 0.6810, "The Stockade", false },
    },

    -- Westfall
    [52] = {
        { 63, 0.4436, 0.7344, "The Deadmines", false },
    },

    -- Badlands  (UiMapID 15 is the sub-zone; 17 is the zone-level map)
    [15] = {
        { 239, 0.4140, 0.1080, "Uldaman", false },
    },
    [17] = {
        { 239, 0.4180, 0.1130, "Uldaman", false },
    },

    -- Swamp of Sorrows
    [51] = {
        { 237, 0.6964, 0.5391, "Temple of Atal'Hakkar", false },
    },

    -- Northern Stranglethorn  (mapID 50)
    [50] = {
        { 76, 0.6415, 0.1830, "Zul'Gurub", false },
    },

    -- Burning Steppes  (Blackrock Mountain complex, mapID 25)
    [25] = {
        { 228, 0.2049, 0.3534, "Blackrock Depths", false },
        { 229, 0.2049, 0.3534, "Lower Blackrock Spire", false },
        { 559, 0.2049, 0.3534, "Upper Blackrock Spire", false },
        { 66,  0.2049, 0.3534, "Blackrock Caverns", false },
        { 741, 0.2049, 0.3534, "Molten Core", true },
        { 742, 0.2049, 0.3534, "Blackwing Lair", true },
        { 73,  0.2049, 0.3534, "Blackwing Descent", true },
    },

    -- Dustwallow Marsh (Onyxia's Lair)  — mapID 68 in this project
    [68] = {
        { 760, 0.5290, 0.7770, "Onyxia's Lair", true },
    },

    -- Deadwind Pass  (Karazhan / Return to Karazhan)
    [42] = {
        { 745, 0.4700, 0.7100, "Karazhan", true },
        { 860, 0.4670, 0.7020, "Return to Karazhan", false },
    },

    -- Ghostlands  (Zul'Aman)
    [95] = {
        { 77, 0.7793, 0.6272, "Zul'Aman", false },
    },

    ---------------------------------------------------------------------------
    -- THE BURNING CRUSADE
    ---------------------------------------------------------------------------

    -- Hellfire Peninsula  (Hellfire Citadel complex)
    [100] = {
        { 248, 0.4679, 0.5180, "Hellfire Ramparts", false },
        { 256, 0.4679, 0.5180, "The Blood Furnace", false },
        { 259, 0.4679, 0.5180, "The Shattered Halls", false },
        { 747, 0.4679, 0.5180, "Magtheridon's Lair", true },
    },

    -- Zangarmarsh  (Coilfang Reservoir complex, mapID 101)
    [101] = {
        { 260, 0.4998, 0.4070, "The Slave Pens", false },
        { 261, 0.4998, 0.4070, "The Steamvault", false },
        { 262, 0.4998, 0.4070, "The Underbog", false },
        { 748, 0.4998, 0.4070, "Serpentshrine Cavern", true },
    },

    -- Terokkar Forest  (Auchindoun complex, mapID 102)
    [102] = {
        { 247, 0.3430, 0.6560, "Auchenai Crypts", false },
        { 250, 0.3970, 0.5770, "Mana-Tombs", false },
        { 252, 0.4490, 0.6560, "Sethekk Halls", false },
        { 253, 0.3960, 0.7360, "Shadow Labyrinth", false },
    },

    -- Netherstorm  (Tempest Keep complex; mapID 107 is primary, 109 is alternate)
    [107] = {
        { 257, 0.7260, 0.6000, "The Botanica", false },
        { 258, 0.6960, 0.7060, "The Mechanar", false },
        { 254, 0.8230, 0.5960, "The Arcatraz", false },
        { 749, 0.7380, 0.6380, "The Eye", true },
    },
    [109] = {
        { 257, 0.7260, 0.6000, "The Botanica", false },
        { 258, 0.6960, 0.7060, "The Mechanar", false },
        { 254, 0.8230, 0.5960, "The Arcatraz", false },
        { 749, 0.7380, 0.6380, "The Eye", true },
    },

    -- Blade's Edge Mountains  (Gruul's Lair)
    [105] = {
        { 746, 0.4385, 0.1945, "Gruul's Lair", true },
    },

    -- Shadowmoon Valley (Outland, mapID 108)
    [108] = {
        { 751, 0.7100, 0.4660, "Black Temple", true },
    },

    -- Isle of Quel'Danas
    [122] = {
        { 249, 0.6070, 0.3055, "Magisters' Terrace", false },
        { 752, 0.4430, 0.4570, "Sunwell Plateau", true },
    },

    ---------------------------------------------------------------------------
    -- WRATH OF THE LICH KING
    ---------------------------------------------------------------------------

    -- Borean Tundra  (Nexus complex)
    [114] = {
        { 282, 0.2700, 0.2596, "The Nexus", false },
        { 281, 0.2700, 0.2596, "The Oculus", false },
        { 756, 0.2700, 0.2596, "Eye of Eternity", true },
    },

    -- Dragonblight
    [115] = {
        { 272, 0.2680, 0.4850, "Azjol-Nerub", false },
        { 271, 0.2850, 0.5170, "Ahn'kahet: The Old Kingdom", false },
        { 754, 0.8730, 0.5100, "Naxxramas", true },
        { 755, 0.6000, 0.5690, "The Obsidian Sanctum", true },
        { 761, 0.6130, 0.5260, "The Ruby Sanctum", true },
    },

    -- Howling Fjord
    [117] = {
        { 285, 0.5820, 0.4890, "Utgarde Keep", false },
        { 286, 0.5840, 0.4500, "Utgarde Pinnacle", false },
    },

    -- Grizzly Hills
    [116] = {
        { 273, 0.1770, 0.2330, "Drak'Tharon Keep", false },
    },

    -- Zul'Drak
    [121] = {
        { 274, 0.8215, 0.1945, "Gundrak", false },
    },

    -- Icecrown
    [118] = {
        { 276, 0.5140, 0.8830, "The Forge of Souls", false },
        { 278, 0.5140, 0.8830, "Halls of Reflection", false },
        { 280, 0.5140, 0.8830, "Pit of Saron", false },
        { 284, 0.7400, 0.2090, "Trial of the Champion", false },
        { 757, 0.7520, 0.2180, "Trial of the Crusader", true },
        { 758, 0.5380, 0.8720, "Icecrown Citadel", true },
    },

    -- Storm Peaks
    [120] = {
        { 275, 0.4513, 0.1978, "Halls of Lightning", false },
        { 277, 0.3773, 0.2634, "Halls of Stone", false },
        { 759, 0.4160, 0.1770, "Ulduar", true },
    },

    -- Wintergrasp
    [123] = {
        { 753, 0.4980, 0.1820, "Vault of Archavon", true },
    },

    -- Dalaran (Northrend)
    [125] = {
        { 283, 0.6721, 0.6865, "The Violet Hold", false },
    },

    ---------------------------------------------------------------------------
    -- CATACLYSM
    ---------------------------------------------------------------------------

    -- Deepholm
    [207] = {
        { 67, 0.4680, 0.4970, "The Stonecore", false },
    },

    -- Mount Hyjal
    [198] = {
        { 78, 0.4730, 0.7810, "Firelands", true },
    },

    -- Tol Barad Peninsula
    [244] = {
        { 75, 0.4610, 0.4790, "Baradin Hold", true },
    },

    -- Twilight Highlands  (mapID 35 is primary; 241 is alternate)
    [35] = {
        { 71, 0.1986, 0.5372, "Grim Batol", false },
        { 72, 0.3400, 0.7800, "The Bastion of Twilight", true },
    },
    [241] = {
        { 71, 0.1986, 0.5372, "Grim Batol", false },
        { 72, 0.3400, 0.7800, "The Bastion of Twilight", true },
    },

    -- Uldum  (UiMapID 249 is Cataclysm-era map; 261 is the parent zone map)
    [249] = {
        { 68, 0.7640, 0.8416, "The Vortex Pinnacle", false },
        { 69, 0.6160, 0.6920, "Lost City of the Tol'vir", false },
        { 70, 0.7000, 0.5260, "Halls of Origination", false },
        { 74, 0.3830, 0.8060, "Throne of the Four Winds", true },
    },
    [261] = {
        { 68, 0.7640, 0.8416, "The Vortex Pinnacle", false },
        { 69, 0.6160, 0.6920, "Lost City of the Tol'vir", false },
        { 70, 0.7000, 0.5260, "Halls of Origination", false },
        { 74, 0.3830, 0.8060, "Throne of the Four Winds", true },
    },

    -- Vashj'ir  (Throne of the Tides; Vashj'ir is mapID 203 in HandyNotes
    -- but 203 = Un'Goro Crater in this project.  The actual Vashj'ir zone ID
    -- in the modern API varies.  Abyssal Depths = 204.)
    [204] = {
        { 65, 0.7040, 0.2959, "Throne of the Tides", false },
    },

    -- Caverns of Time (Tanaris sub-zone)
    [75] = {
        { 251, 0.2649, 0.3304, "The Black Morass", false },
        { 255, 0.3454, 0.8531, "Old Hillsbrad Foothills", false },
        { 279, 0.6070, 0.8300, "The Culling of Stratholme", false },
        { 185, 0.2215, 0.6387, "End Time", false },
        { 186, 0.6849, 0.2959, "Well of Eternity", false },
        { 184, 0.5726, 0.2615, "Hour of Twilight", false },
        { 750, 0.5572, 0.5333, "Hyjal Summit", true },
        { 187, 0.5572, 0.5333, "Dragon Soul", true },
    },

    ---------------------------------------------------------------------------
    -- MISTS OF PANDARIA
    ---------------------------------------------------------------------------

    -- Jade Forest
    [371] = {
        { 313, 0.5603, 0.5749, "Temple of the Jade Serpent", false },
    },

    -- Valley of the Four Winds
    [376] = {
        { 302, 0.3601, 0.6964, "Stormstout Brewery", false },
    },

    -- Kun-Lai Summit
    [379] = {
        { 312, 0.3692, 0.4745, "Shado-Pan Monastery", false },
        { 317, 0.5950, 0.3920, "Mogu'shan Vaults", true },
    },

    -- Townlong Steppes
    [388] = {
        { 324, 0.3414, 0.8125, "Siege of Niuzao Temple", false },
    },

    -- Vale of Eternal Blossoms  (390 = standard; 1530 = N'Zoth assault version)
    [390] = {
        { 321, 0.7900, 0.3500, "Mogu'shan Palace", false },
        { 303, 0.1585, 0.7423, "Gate of the Setting Sun", false },
        { 369, 0.7410, 0.4200, "Siege of Orgrimmar", true },
        { 1180, 0.3900, 0.4300, "Ny'alotha, the Waking City", true },
    },
    [1530] = {
        { 321, 0.7900, 0.3500, "Mogu'shan Palace", false },
        { 303, 0.1585, 0.7423, "Gate of the Setting Sun", false },
        { 369, 0.7410, 0.4200, "Siege of Orgrimmar", true },
        { 1180, 0.3900, 0.4300, "Ny'alotha, the Waking City", true },
    },

    -- Dread Wastes
    [422] = {
        { 330, 0.3880, 0.3500, "Heart of Fear", true },
    },

    -- Terrace of Endless Spring  (Veiled Stair / Kun-Lai sub-zone)
    [433] = {
        { 320, 0.4830, 0.6130, "Terrace of Endless Spring", true },
    },

    -- Isle of Thunder
    [504] = {
        { 362, 0.6976, 0.2232, "Throne of Thunder", true },
    },

    ---------------------------------------------------------------------------
    -- WARLORDS OF DRAENOR
    ---------------------------------------------------------------------------

    -- Frostfire Ridge
    [525] = {
        { 385, 0.5036, 0.2462, "Bloodmaul Slag Mines", false },
    },

    -- Shadowmoon Valley (Draenor)
    [539] = {
        { 537, 0.3130, 0.4310, "Shadowmoon Burial Grounds", false },
    },

    -- Gorgrond
    [543] = {
        { 536, 0.5510, 0.3040, "Grimrail Depot", false },
        { 556, 0.5980, 0.4520, "The Everbloom", false },
        { 558, 0.4490, 0.1350, "Iron Docks", false },
        { 457, 0.4990, 0.2400, "Blackrock Foundry", true },
    },

    -- Talador
    [535] = {
        { 547, 0.4480, 0.7450, "Auchindoun", false },
    },

    -- Spires of Arak
    [542] = {
        { 476, 0.3925, 0.3440, "Skyreach", false },
    },

    -- Nagrand (Draenor)
    [550] = {
        { 477, 0.3290, 0.3840, "Highmaul", true },
    },

    -- Tanaan Jungle
    [534] = {
        { 669, 0.4560, 0.5360, "Hellfire Citadel", true },
    },

    ---------------------------------------------------------------------------
    -- LEGION
    ---------------------------------------------------------------------------

    -- Azsuna
    [630] = {
        { 716, 0.6120, 0.4110, "Eye of Azshara", false },
        { 707, 0.4830, 0.8030, "Vault of the Wardens", false },
    },

    -- Stormheim
    [634] = {
        { 721, 0.7270, 0.7050, "Halls of Valor", false },
        { 727, 0.5250, 0.4530, "Maw of Souls", false },
        { 861, 0.7110, 0.7280, "Trial of Valor", true },
    },

    -- Val'sharah
    [641] = {
        { 740, 0.3720, 0.5020, "Black Rook Hold", false },
        { 762, 0.5900, 0.3120, "Darkheart Thicket", false },
        { 768, 0.5630, 0.3680, "The Emerald Nightmare", true },
    },

    -- Broken Shore
    [646] = {
        { 900, 0.6470, 0.1660, "Cathedral of Eternal Night", false },
        { 875, 0.6460, 0.2070, "Tomb of Sargeras", true },
    },

    -- Highmountain
    [650] = {
        { 767, 0.4960, 0.6860, "Neltharion's Lair", false },
    },

    -- Suramar
    [680] = {
        { 726, 0.4110, 0.6170, "The Arcway", false },
        { 800, 0.5080, 0.6550, "Court of Stars", false },
        { 786, 0.4410, 0.5980, "The Nighthold", true },
    },

    -- Dalaran (Broken Isles)
    [627] = {
        { 777, 0.6640, 0.6850, "Assault on Violet Hold", false },
    },

    -- Mac'Aree (Argus)
    [882] = {
        { 945, 0.2220, 0.5584, "Seat of the Triumvirate", false },
    },

    -- Antoran Wastes (Argus)
    [885] = {
        { 946, 0.5478, 0.6241, "Antorus, the Burning Throne", true },
    },

    ---------------------------------------------------------------------------
    -- BATTLE FOR AZEROTH
    ---------------------------------------------------------------------------

    -- Tiragarde Sound  (Kul Tiras)
    [895] = {
        { 1001, 0.8445, 0.7887, "Freehold", false },
        { 1023, 0.7475, 0.2350, "Siege of Boralus", false },
    },

    -- Drustvar  (Kul Tiras)
    [896] = {
        { 1021, 0.3368, 0.1233, "Waycrest Manor", false },
    },

    -- Stormsong Valley  (Kul Tiras)
    [942] = {
        { 1036, 0.7893, 0.2647, "Shrine of the Storm", false },
    },

    -- Boralus  (Kul Tiras city)
    [1161] = {
        { 1023, 0.7250, 0.1550, "Siege of Boralus", false },
    },

    -- Tol Dagor  (off Kul Tiras)
    [1169] = {
        { 1002, 0.3957, 0.6833, "Tol Dagor", false },
    },

    -- Zuldazar  (Zandalar)
    [862] = {
        { 1041, 0.3746, 0.3948, "Atal'Dazar", false },
        { 968,  0.5000, 0.6500, "King's Rest", false },
        { 1012, 0.3922, 0.7137, "The MOTHERLODE!!", false },
    },

    -- Nazmir  (Zandalar)
    [863] = {
        { 1022, 0.5138, 0.6483, "The Underrot", false },
        { 1031, 0.5388, 0.6268, "Uldir", true },
    },

    -- Vol'dun  (Zandalar)
    [864] = {
        { 1030, 0.5193, 0.2484, "Temple of Sethraliss", false },
    },

    -- Nazjatar  (BFA neutral)
    [1355] = {
        { 1179, 0.5043, 0.1199, "The Eternal Palace", true },
    },

    -- Mechagon  (BFA neutral)
    [1462] = {
        { 1178, 0.1987, 0.2697, "Operation: Mechagon", false },
    },

    -- Dazar'alor  (Zandalar city)
    [1165] = {
        { 1176, 0.5500, 0.5350, "Battle of Dazar'alor", true },
    },

    -- Crucible of Storms  (near Stormsong)
    [876] = {
        { 1177, 0.6716, 0.2482, "Crucible of Storms", true },
    },

    -- Uldum (N'Zoth assault version, UiMapID 1527 — same dungeons + Ny'alotha)
    [1527] = {
        { 68, 0.7640, 0.8416, "The Vortex Pinnacle", false },
        { 69, 0.6160, 0.6920, "Lost City of the Tol'vir", false },
        { 70, 0.7000, 0.5260, "Halls of Origination", false },
        { 74, 0.3830, 0.8060, "Throne of the Four Winds", true },
        { 1180, 0.5400, 0.4300, "Ny'alotha, the Waking City", true },
    },

    ---------------------------------------------------------------------------
    -- SHADOWLANDS
    ---------------------------------------------------------------------------

    -- Bastion
    [1533] = {
        { 1182, 0.6000, 0.7577, "The Necrotic Wake", false },
        { 1186, 0.5847, 0.2870, "Spires of Ascension", false },
    },

    -- Maldraxxus
    [1536] = {
        { 1183, 0.5930, 0.6484, "Plaguefall", false },
        { 1187, 0.5321, 0.5314, "Theater of Pain", false },
    },

    -- Ardenweald
    [1565] = {
        { 1184, 0.3571, 0.5421, "Mists of Tirna Scithe", false },
        { 1188, 0.6860, 0.6598, "De Other Side", false },
    },

    -- Revendreth
    [1525] = {
        { 1185, 0.7796, 0.4852, "Halls of Atonement", false },
        { 1189, 0.5109, 0.3007, "Sanguine Depths", false },
        { 1190, 0.4576, 0.4149, "Castle Nathria", true },
    },

    -- The Maw
    [1543] = {
        { 1193, 0.6868, 0.8540, "Sanctum of Domination", true },
    },

    -- Zereth Mortis
    [1970] = {
        { 1195, 0.6480, 0.3730, "Sepulcher of the First Ones", true },
    },

    -- Oribos  (Tazavesh portal entrance)
    [1670] = {
        { 1194, 0.4800, 0.5300, "Tazavesh, the Veiled Market", false },
    },

    ---------------------------------------------------------------------------
    -- DRAGONFLIGHT
    ---------------------------------------------------------------------------

    -- The Waking Shores
    [2022] = {
        { 1202, 0.6000, 0.7577, "Ruby Life Pools", false },
        { 1199, 0.2557, 0.5695, "Neltharus", false },
    },

    -- Ohn'ahran Plains
    [2023] = {
        { 1198, 0.6201, 0.4244, "The Nokhud Offensive", false },
    },

    -- The Azure Span
    [2024] = {
        { 1196, 0.1157, 0.4878, "Brackenhide Hollow", false },
        { 1203, 0.3889, 0.6476, "The Azure Vault", false },
    },

    -- Thaldraszus
    [2025] = {
        { 1201, 0.5828, 0.4235, "Algeth'ar Academy", false },
        { 1204, 0.5924, 0.6064, "Halls of Infusion", false },
        { 1200, 0.7314, 0.5560, "Vault of the Incarnates", true },
        { 1209, 0.6120, 0.8440, "Dawn of the Infinite", false },
    },

    -- Zaralek Cavern
    [2133] = {
        { 1208, 0.4847, 0.1036, "Aberrus, the Shadowed Crucible", true },
    },

    -- The Emerald Dream
    [2200] = {
        { 1207, 0.2700, 0.3100, "Amirdrassil, the Dream's Hope", true },
    },

    -- Badlands  (Uldaman: Legacy of Tyr — shares entrance with classic Uldaman)
    -- Note: journalInstanceID 1197 is the Dragonflight version
    -- Already in Badlands [15] above as classic Uldaman (239); this adds the new one.

    ---------------------------------------------------------------------------
    -- THE WAR WITHIN
    ---------------------------------------------------------------------------

    -- Isle of Dorn
    [2248] = {
        { 1272, 0.7660, 0.4380, "Cinderbrew Meadery", false },
    },

    -- Dornogal  (city on Isle of Dorn)
    [2339] = {
        { 1268, 0.3200, 0.3570, "The Rookery", false },
    },

    -- The Ringing Deeps
    [2214] = {
        { 1269, 0.4680, 0.0860, "The Stonevault", false },
        { 1210, 0.5960, 0.2180, "Darkflame Cleft", false },
        -- Operation: Floodgate (Patch 11.1) — journalInstanceID TBD; runtime API resolves it
    },

    -- Hallowfall
    [2215] = {
        { 1267, 0.4120, 0.4960, "Priory of the Sacred Flame", false },
        { 1270, 0.5470, 0.6290, "The Dawnbreaker", false },
    },

    -- Azj-Kahet
    [2255] = {
        { 1273, 0.4370, 0.9040, "Nerub-ar Palace", true },
    },

    -- City of Threads  (sub-zone of Azj-Kahet)
    [2213] = {
        { 1274, 0.4408, 0.1169, "City of Threads", false },
        { 1271, 0.5220, 0.4570, "Ara-Kara, City of Echoes", false },
    },

    -- Undermine  (Patch 11.1)
    [2346] = {
        { 1296, 0.4203, 0.5028, "Liberation of Undermine", true },
    },

    -- K'aresh  (Patch 11.2)
    -- Manaforge Omega raid entrance: ~0.4180, 0.2100

    ---------------------------------------------------------------------------
    -- MIDNIGHT  (Patch 12.0)
    ---------------------------------------------------------------------------

    -- Eversong Woods (Midnight)
    [2395] = {
        { 1299, 0.6440, 0.6180, "Windrunner Spire", false },
    },

    -- Silvermoon City (Midnight)
    [2393] = {
        { 1304, 0.5620, 0.6110, "Murder Row", false },
    },

    -- Isle of Quel'Danas (Midnight)
    [2424] = {
        { 1300, 0.6340, 0.1530, "Magisters' Terrace", false },
        { 1308, 0.5270, 0.8490, "March on Quel'Danas", true },
    },

    -- Zul'Aman (Midnight)
    [2437] = {
        { 1315, 0.4440, 0.4030, "Maisara Caverns", false },
    },

    -- Harandar
    [2576] = {
        { 1309, 0.2780, 0.7790, "The Blinding Vale", false },
        { 1314, 0.6100, 0.6420, "The Dreamrift", true },
    },

    -- Voidstorm
    [2405] = {
        { 1307, 0.4540, 0.6400, "The Voidspire", true },
        { 1313, 0.5370, 0.3480, "Voidscar Arena", false },
        { 1316, 0.6440, 0.6180, "Nexus Point Xenas", false },
    },
}

-------------------------------------------------------------------------------
-- Badlands addendum — add Dragonflight Uldaman: Legacy of Tyr alongside classic
-------------------------------------------------------------------------------
-- Inserting directly avoids overwriting the entries above.
-- (Classic Uldaman is jid 239, DF version is jid 1197, same coordinates)
for _, mapID in ipairs({15, 17}) do
    local zone = QR.StaticDungeonEntrances[mapID]
    if zone then
        zone[#zone + 1] = { 1197, 0.4140, 0.1080, "Uldaman: Legacy of Tyr", false }
    end
end

-------------------------------------------------------------------------------
-- Classic wing-split addendum (EJ lists wings as separate instances)
-------------------------------------------------------------------------------

-- Dire Maul wings (same entrance as classic Dire Maul, Feralas mapID 69)
local direMaulZone = QR.StaticDungeonEntrances[69]
if direMaulZone then
    direMaulZone[#direMaulZone + 1] = { 1276, 0.6147, 0.3093, "Dire Maul - Warpwood Quarter", false }
    direMaulZone[#direMaulZone + 1] = { 1277, 0.6147, 0.3093, "Dire Maul - Gordok Commons", false }
end

-- Stratholme - Service Entrance (Eastern Plaguelands, same area as main entrance)
local stratZone = QR.StaticDungeonEntrances[23]
if stratZone then
    stratZone[#stratZone + 1] = { 1292, 0.2720, 0.1160, "Stratholme - Service Entrance", false }
end

-- Blackrock Depths (revamp, same entrance in Searing Gorge)
local brdZone = QR.StaticDungeonEntrances[36]
if brdZone then
    brdZone[#brdZone + 1] = { 1301, 0.2049, 0.3534, "Blackrock Depths", false }
end
