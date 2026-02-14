# Dungeon & Raid Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Route players to any dungeon or raid entrance via three entry points: Route tab picker, Encounter Journal button, world map pin click.

**Architecture:** Hybrid data layer (runtime WoW API + static fallback) feeds dungeon entrance nodes into the existing Dijkstra graph. Three UI integration points share a single `QR.DungeonData` module for entrance lookups. The routing engine needs no changes — dungeon entrances are just new graph nodes.

**Tech Stack:** WoW Lua 5.1, WoW 12.0.1 API (C_EncounterJournal, EJ_*), existing QuickRoute graph/routing engine.

---

### Task 1: WoW API Mocks for Encounter Journal

**Files:**
- Modify: `tests/mock_wow_api.lua` (inside the `Install()` function, after existing C_MountJournal mock ~line 1137)

**Step 1: Add EJ and C_EncounterJournal mocks**

Add these mocks inside `MockWoW:Install()`. The mock data represents a minimal set of dungeons/raids for testing (2 tiers, 2 dungeons, 1 raid):

```lua
-- Encounter Journal mocks
local ejTierData = {
    { name = "Classic" },
    { name = "The War Within" },
}
local ejInstanceData = {
    -- tier 1 (Classic)
    [1] = {
        dungeons = {
            { id = 226, name = "Ragefire Chasm", mapID = 389, dungeonAreaMapID = 213 },
        },
        raids = {
            { id = 741, name = "Molten Core", mapID = 409, dungeonAreaMapID = 232 },
        },
    },
    -- tier 2 (TWW)
    [2] = {
        dungeons = {
            { id = 1267, name = "The Stonevault", mapID = 2341, dungeonAreaMapID = 2341 },
            { id = 1268, name = "City of Threads", mapID = 2343, dungeonAreaMapID = 2343 },
        },
        raids = {
            { id = 1273, name = "Nerub-ar Palace", mapID = 2345, dungeonAreaMapID = 2345 },
        },
    },
}
local ejSelectedTier = 1

_G.EJ_GetNumTiers = function() return #ejTierData end
_G.EJ_SelectTier = function(tier) ejSelectedTier = tier end
_G.EJ_GetTierInfo = function(tier)
    local t = ejTierData[tier]
    return t and t.name or nil
end
_G.EJ_GetInstanceByIndex = function(index, isRaid)
    local tierData = ejInstanceData[ejSelectedTier]
    if not tierData then return nil end
    local list = isRaid and tierData.raids or tierData.dungeons
    if not list then return nil end
    local entry = list[index]
    if not entry then return nil end
    return entry.id, entry.name
end
_G.EJ_GetInstanceInfo = function(instanceID)
    for _, tierData in pairs(ejInstanceData) do
        for _, list in pairs(tierData) do
            for _, entry in ipairs(list) do
                if entry.id == instanceID then
                    local isRaid = false
                    for _, td in pairs(ejInstanceData) do
                        if td.raids then
                            for _, r in ipairs(td.raids) do
                                if r.id == instanceID then isRaid = true end
                            end
                        end
                    end
                    return entry.name, "desc", nil, nil, nil, nil,
                        entry.dungeonAreaMapID, "|cffffffff|Hjournal:2:"..instanceID.."|h["..entry.name.."]|h|r",
                        true, entry.mapID, 0, isRaid
                end
            end
        end
    end
    return nil
end

-- Dungeon entrance data per zone map
local dungeonEntranceData = {
    -- Ragefire Chasm entrance in Orgrimmar (mapID 85)
    [85] = {
        { areaPoiID = 5001, position = { x = 0.3900, y = 0.5000, GetXY = function(self) return self.x, self.y end }, name = "Ragefire Chasm", description = "Level 15-21 dungeon", atlasName = "Dungeon", journalInstanceID = 226 },
    },
    -- The Stonevault entrance in Khaz Algar zone (mapID 2339 = Dornogal area)
    [2248] = {
        { areaPoiID = 5002, position = { x = 0.6200, y = 0.3100, GetXY = function(self) return self.x, self.y end }, name = "The Stonevault", description = "Level 80 dungeon", atlasName = "Dungeon", journalInstanceID = 1267 },
        { areaPoiID = 5003, position = { x = 0.3500, y = 0.5500, GetXY = function(self) return self.x, self.y end }, name = "City of Threads", description = "Level 80 dungeon", atlasName = "Dungeon", journalInstanceID = 1268 },
    },
}

if not _G.C_EncounterJournal then _G.C_EncounterJournal = {} end
_G.C_EncounterJournal.GetDungeonEntrancesForMap = function(mapID)
    return dungeonEntranceData[mapID] or {}
end
_G.C_EncounterJournal.GetInstanceForGameMap = function(mapID)
    for _, tierData in pairs(ejInstanceData) do
        for _, list in pairs(tierData) do
            for _, entry in ipairs(list) do
                if entry.mapID == mapID or entry.dungeonAreaMapID == mapID then
                    return entry.id
                end
            end
        end
    end
    return nil
end

-- Enum for UIMapType (if not already defined)
if not _G.Enum then _G.Enum = {} end
if not _G.Enum.UIMapType then
    _G.Enum.UIMapType = {
        Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6,
    }
end
```

**Step 2: Run tests to verify mocks don't break anything**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All existing tests still pass (mocks are additive)

**Step 3: Commit**

```bash
git add tests/mock_wow_api.lua
git commit -S -m "test: add Encounter Journal API mocks for dungeon routing"
```

---

### Task 2: Static Dungeon Entrance Data

**Files:**
- Create: `QuickRoute/Data/DungeonEntrances.lua`

**Step 1: Write the static data file**

This file provides fallback entrance coordinates for all expansions. The data is keyed by `zoneMapID` and contains arrays of entrance info. Each entry has `journalInstanceID`, `x`, `y`, `name` (English fallback), and `isRaid`.

The `name` field is only used when the runtime API isn't available — the runtime API provides localized names.

```lua
-- DungeonEntrances.lua
-- Static fallback data for dungeon/raid entrance locations
-- Used when C_EncounterJournal.GetDungeonEntrancesForMap returns nothing
-- (character hasn't discovered the instance yet)
local ADDON_NAME, QR = ...

QR.StaticDungeonEntrances = {
    -- Format: [zoneMapID] = { { journalInstanceID, x, y, name, isRaid }, ... }

    -----------------------------------------------------------------------
    -- Classic (Tier 1)
    -----------------------------------------------------------------------
    -- Orgrimmar
    [85] = {
        { 226, 0.3896, 0.4984, "Ragefire Chasm", false },
    },
    -- Westfall
    [52] = {
        { 63, 0.4246, 0.7185, "The Deadmines", false },
    },
    -- Silverpine Forest
    [21] = {
        { 64, 0.4467, 0.6790, "Shadowfang Keep", false },
    },
    -- Ashenvale
    [63] = {
        { 227, 0.1435, 0.1399, "Blackfathom Deeps", false },
    },
    -- Stonetalon Mountains
    [65] = {
        { 234, 0.5260, 0.4610, "Razorfen Kraul", false },
    },
    -- Desolace
    [66] = {
        { 232, 0.2900, 0.6220, "Maraudon", false },
    },
    -- Dustwallow Marsh
    [70] = {
        { 230, 0.5264, 0.7668, "Onyxia's Lair", true },
    },
    -- Thousand Needles
    [64] = {
        { 235, 0.4700, 0.2300, "Razorfen Downs", false },
    },
    -- Badlands
    [15] = {
        { 228, 0.4115, 0.1171, "Uldaman", false },
    },
    -- Swamp of Sorrows
    [51] = {
        { 237, 0.6920, 0.5380, "Temple of Atal'Hakkar", false },
    },
    -- Searing Gorge
    [32] = {
        { 229, 0.3522, 0.8390, "Blackrock Depths", false },
        { 559, 0.3522, 0.8390, "Blackrock Caverns", false },
    },
    -- Burning Steppes
    [36] = {
        { 233, 0.2911, 0.3853, "Lower Blackrock Spire", false },
        { 559, 0.2911, 0.3853, "Upper Blackrock Spire", false },
        { 741, 0.2911, 0.3853, "Molten Core", true },
        { 742, 0.2911, 0.3853, "Blackwing Lair", true },
    },
    -- Eastern Plaguelands
    [23] = {
        { 236, 0.2730, 0.1165, "Stratholme", false },
    },
    -- Western Plaguelands
    [22] = {
        { 246, 0.6932, 0.7340, "Scholomance", false },
    },
    -- Tirisfal Glades
    [18] = {
        { 231, 0.8220, 0.2960, "Scarlet Monastery", false },
    },
    -- Tanaris
    [71] = {
        { 239, 0.3858, 0.2093, "Zul'Farrak", false },
    },
    -- Felwood
    [77] = {
        { 234, 0.3500, 0.5920, "Dire Maul", false },
    },
    -- Feralas
    [69] = {
        { 234, 0.5966, 0.3119, "Dire Maul", false },
    },
    -- Winterspring
    [83] = {
        { 743, 0.5960, 0.5140, "Ruins of Ahn'Qiraj", true },
    },
    -- Silithus
    [81] = {
        { 743, 0.2650, 0.9285, "Ruins of Ahn'Qiraj", true },
        { 744, 0.2225, 0.8700, "Temple of Ahn'Qiraj", true },
    },
    -- Stormwind City
    [84] = {
        { 238, 0.5432, 0.6840, "The Stockade", false },
    },
    -- Dun Morogh
    [27] = {
        { 231, 0.3027, 0.3726, "Gnomeregan", false },
    },
    -- Loch Modan (Gnomeregan entrance via Dun Morogh)
    -- Wailing Caverns via Northern Barrens
    [10] = {
        { 240, 0.4240, 0.6660, "Wailing Caverns", false },
    },

    -----------------------------------------------------------------------
    -- The Burning Crusade (Tier 2)
    -----------------------------------------------------------------------
    -- Hellfire Peninsula
    [100] = {
        { 248, 0.4762, 0.5262, "Hellfire Ramparts", false },
        { 249, 0.4762, 0.5262, "The Blood Furnace", false },
        { 250, 0.4762, 0.5262, "The Shattered Halls", false },
        { 745, 0.4762, 0.5262, "Magtheridon's Lair", true },
    },
    -- Zangarmarsh
    [102] = {
        { 252, 0.5040, 0.3600, "The Slave Pens", false },
        { 253, 0.5040, 0.3600, "The Underbog", false },
        { 254, 0.5040, 0.3600, "The Steamvault", false },
        { 748, 0.5040, 0.3600, "Serpentshrine Cavern", true },
    },
    -- Terokkar Forest
    [104] = {
        { 255, 0.3666, 0.6558, "Mana-Tombs", false },
        { 256, 0.3666, 0.6558, "Auchenai Crypts", false },
        { 257, 0.3666, 0.6558, "Sethekk Halls", false },
        { 258, 0.3666, 0.6558, "Shadow Labyrinth", false },
    },
    -- Netherstorm
    [109] = {
        { 259, 0.7140, 0.6935, "The Mechanar", false },
        { 260, 0.7140, 0.6935, "The Botanica", false },
        { 261, 0.7140, 0.6935, "The Arcatraz", false },
        { 749, 0.7140, 0.6935, "The Eye", true },
    },
    -- Blade's Edge Mountains
    [105] = {
        { 746, 0.6850, 0.2430, "Gruul's Lair", true },
    },
    -- Shadowmoon Valley (Outland)
    [104] = {
        { 751, 0.7130, 0.4660, "Black Temple", true },
    },
    -- Quel'Danas / Sunwell
    [122] = {
        { 262, 0.6120, 0.3050, "Magisters' Terrace", false },
        { 752, 0.5540, 0.2530, "Sunwell Plateau", true },
    },

    -----------------------------------------------------------------------
    -- Wrath of the Lich King (Tier 3)
    -----------------------------------------------------------------------
    -- Borean Tundra
    [114] = {
        { 272, 0.2702, 0.2630, "The Nexus", false },
        { 273, 0.2702, 0.2630, "The Oculus", false },
        { 754, 0.2702, 0.2630, "The Eye of Eternity", true },
    },
    -- Dragonblight
    [115] = {
        { 271, 0.2629, 0.5095, "Azjol-Nerub", false },
        { 277, 0.2629, 0.5095, "Ahn'kahet: The Old Kingdom", false },
        { 755, 0.8720, 0.5100, "Naxxramas", true },
        { 756, 0.6005, 0.5680, "The Obsidian Sanctum", true },
    },
    -- Grizzly Hills
    [116] = {
        { 274, 0.6774, 0.7319, "Drak'Tharon Keep", false },
    },
    -- Zul'Drak
    [121] = {
        { 275, 0.2873, 0.8583, "Gundrak", false },
    },
    -- Howling Fjord
    [117] = {
        { 285, 0.5726, 0.4637, "Utgarde Keep", false },
        { 286, 0.5726, 0.4637, "Utgarde Pinnacle", false },
    },
    -- Storm Peaks
    [120] = {
        { 276, 0.3957, 0.2669, "Halls of Stone", false },
        { 277, 0.3957, 0.2669, "Halls of Lightning", false },
        { 759, 0.4142, 0.1748, "Ulduar", true },
    },
    -- Icecrown
    [118] = {
        { 278, 0.5249, 0.8948, "The Forge of Souls", false },
        { 280, 0.5249, 0.8948, "Pit of Saron", false },
        { 283, 0.5249, 0.8948, "Halls of Reflection", false },
        { 758, 0.5361, 0.8629, "Icecrown Citadel", true },
        { 757, 0.7539, 0.2182, "Trial of the Crusader", true },
    },
    -- Dalaran (Northrend)
    [125] = {
        { 271, 0.6667, 0.6889, "The Violet Hold", false },
        { 761, 0.6400, 0.4300, "Ruby Sanctum", true },
    },

    -----------------------------------------------------------------------
    -- Cataclysm (Tier 4)
    -----------------------------------------------------------------------
    -- Uldum
    [249] = {
        { 69, 0.7162, 0.5269, "Halls of Origination", false },
        { 70, 0.7672, 0.8411, "Lost City of the Tol'vir", false },
        { 74, 0.3816, 0.8063, "Throne of the Four Winds", true },
    },
    -- Mount Hyjal
    [198] = {
        { 800, 0.2312, 0.7344, "Firelands", true },
    },
    -- Twilight Highlands
    [241] = {
        { 71, 0.1944, 0.5340, "Grim Batol", false },
        { 75, 0.3379, 0.7790, "The Bastion of Twilight", true },
    },
    -- Deepholm
    [207] = {
        { 67, 0.4728, 0.5217, "The Stonecore", false },
    },
    -- Vashj'ir (Abyssal Depths)
    [204] = {
        { 65, 0.6913, 0.3431, "Throne of the Tides", false },
    },
    -- Tol Barad Peninsula
    [244] = {
        { 66, 0.4680, 0.4900, "Baradin Hold", true },
    },

    -----------------------------------------------------------------------
    -- Mists of Pandaria (Tier 5)
    -----------------------------------------------------------------------
    -- Jade Forest
    [371] = {
        { 313, 0.5594, 0.5710, "Temple of the Jade Serpent", false },
    },
    -- Valley of the Four Winds
    [376] = {
        { 321, 0.3602, 0.6909, "Stormstout Brewery", false },
    },
    -- Kun-Lai Summit
    [379] = {
        { 312, 0.3661, 0.4693, "Shado-Pan Monastery", false },
        { 317, 0.5929, 0.3953, "Mogu'shan Vaults", true },
    },
    -- Townlong Steppes
    [388] = {
        { 324, 0.3428, 0.8153, "Siege of Niuzao Temple", false },
    },
    -- Vale of Eternal Blossoms
    [390] = {
        { 320, 0.1578, 0.7433, "Mogu'shan Palace", false },
        { 322, 0.7370, 0.3670, "Heart of Fear", true },
    },
    -- Dread Wastes
    [422] = {
        { 322, 0.3861, 0.3512, "Heart of Fear", true },
        { 325, 0.4716, 0.2571, "Terrace of Endless Spring", true },
    },
    -- Throne of Thunder (Isle of Thunder)
    [504] = {
        { 362, 0.6360, 0.3260, "Throne of Thunder", true },
    },

    -----------------------------------------------------------------------
    -- Warlords of Draenor (Tier 6)
    -----------------------------------------------------------------------
    -- Shadowmoon Valley (WoD)
    [539] = {
        { 476, 0.7720, 0.4190, "Shadowmoon Burial Grounds", false },
    },
    -- Gorgrond
    [543] = {
        { 385, 0.5135, 0.2744, "Bloodmaul Slag Mines", false },
        { 984, 0.5570, 0.3540, "Iron Docks", false },
        { 988, 0.4565, 0.1346, "Blackrock Foundry", true },
    },
    -- Talador
    [535] = {
        { 547, 0.4639, 0.7405, "Auchindoun", false },
    },
    -- Spires of Arak
    [542] = {
        { 476, 0.3554, 0.3336, "Skyreach", false },
    },
    -- Nagrand (WoD)
    [550] = {
        { 457, 0.3303, 0.3805, "Highmaul", true },
    },
    -- Tanaan Jungle
    [534] = {
        { 669, 0.4580, 0.1530, "Hellfire Citadel", true },
    },

    -----------------------------------------------------------------------
    -- Legion (Tier 7)
    -----------------------------------------------------------------------
    -- Azsuna
    [630] = {
        { 716, 0.6102, 0.4113, "Eye of Azshara", false },
        { 777, 0.4890, 0.8230, "Vault of the Wardens", false },
    },
    -- Val'sharah
    [641] = {
        { 762, 0.5629, 0.3675, "Darkheart Thicket", false },
        { 800, 0.3893, 0.5271, "The Emerald Nightmare", true },
    },
    -- Highmountain
    [650] = {
        { 767, 0.4966, 0.6134, "Neltharion's Lair", false },
    },
    -- Stormheim
    [634] = {
        { 721, 0.6989, 0.6930, "Halls of Valor", false },
        { 727, 0.5203, 0.4541, "Maw of Souls", false },
        { 875, 0.6720, 0.6920, "Trial of Valor", true },
    },
    -- Suramar
    [680] = {
        { 800, 0.4400, 0.5100, "Court of Stars", false },
        { 800, 0.4300, 0.5950, "The Arcway", false },
        { 946, 0.4400, 0.5900, "The Nighthold", true },
    },
    -- Broken Shore
    [646] = {
        { 900, 0.6430, 0.2230, "Cathedral of Eternal Night", false },
        { 945, 0.6390, 0.2200, "Tomb of Sargeras", true },
    },
    -- Dalaran (Broken Isles)
    [627] = {
        { 900, 0.6550, 0.6820, "The Violet Hold", false },
    },
    -- Argus / Antoran Wastes
    [885] = {
        { 946, 0.5530, 0.6260, "Seat of the Triumvirate", false },
    },
    -- Argus / Antorus
    [830] = {
        { 946, 0.5460, 0.6250, "Antorus, the Burning Throne", true },
    },

    -----------------------------------------------------------------------
    -- Battle for Azeroth (Tier 8)
    -----------------------------------------------------------------------
    -- Tiragarde Sound
    [895] = {
        { 968, 0.7450, 0.3230, "Freehold", false },
        { 1001, 0.7560, 0.3370, "Tol Dagor", false },
        { 1023, 0.8490, 0.7850, "Siege of Boralus", false },
    },
    -- Drustvar
    [896] = {
        { 1002, 0.3360, 0.1210, "Waycrest Manor", false },
    },
    -- Stormsong Valley
    [942] = {
        { 1001, 0.7400, 0.8280, "Shrine of the Storm", false },
    },
    -- Zuldazar
    [862] = {
        { 1012, 0.4020, 0.3940, "Atal'Dazar", false },
        { 1031, 0.5500, 0.6800, "King's Rest", false },
        { 1176, 0.5160, 0.3200, "Battle of Dazar'alor", true },
    },
    -- Nazmir
    [863] = {
        { 1012, 0.3950, 0.5680, "The Underrot", false },
        { 1148, 0.5350, 0.6240, "Uldir", true },
    },
    -- Vol'dun
    [864] = {
        { 1012, 0.5130, 0.3440, "Temple of Sethraliss", false },
    },
    -- Nazjatar
    [1355] = {
        { 1179, 0.5000, 0.1200, "The Eternal Palace", true },
    },
    -- Vale of Eternal Blossoms (N'Zoth)
    -- (reuse mapID 390 from MoP, but new raid)

    -----------------------------------------------------------------------
    -- Shadowlands (Tier 9)
    -----------------------------------------------------------------------
    -- Bastion
    [1533] = {
        { 1184, 0.5823, 0.4124, "The Necrotic Wake", false },
        { 1185, 0.2540, 0.5710, "Spires of Ascension", false },
    },
    -- Maldraxxus
    [1536] = {
        { 1182, 0.5970, 0.3867, "Plaguefall", false },
        { 1183, 0.5455, 0.5345, "Theater of Pain", false },
    },
    -- Ardenweald
    [1565] = {
        { 1188, 0.6519, 0.3683, "Mists of Tirna Scithe", false },
        { 1186, 0.3530, 0.5560, "De Other Side", false },
    },
    -- Revendreth
    [1525] = {
        { 1189, 0.2790, 0.5540, "Halls of Atonement", false },
        { 1190, 0.7340, 0.3280, "Sanguine Depths", false },
        { 1193, 0.4500, 0.4200, "Castle Nathria", true },
    },
    -- The Maw / Torghast area
    [1543] = {
        { 1193, 0.7140, 0.3200, "Sanctum of Domination", true },
    },
    -- Zereth Mortis
    [1970] = {
        { 1195, 0.6600, 0.4400, "Sepulcher of the First Ones", true },
    },

    -----------------------------------------------------------------------
    -- Dragonflight (Tier 10)
    -----------------------------------------------------------------------
    -- The Waking Shores
    [2022] = {
        { 1197, 0.6079, 0.3747, "Ruby Life Pools", false },
        { 1198, 0.2560, 0.4060, "Neltharus", false },
        { 1200, 0.4730, 0.8280, "Vault of the Incarnates", true },
    },
    -- Ohn'ahran Plains
    [2023] = {
        { 1199, 0.6195, 0.4106, "The Nokhud Offensive", false },
    },
    -- The Azure Span
    [2024] = {
        { 1203, 0.3820, 0.5340, "The Azure Vault", false },
        { 1201, 0.5760, 0.4800, "Brackenhide Hollow", false },
    },
    -- Thaldraszus
    [2025] = {
        { 1202, 0.5987, 0.4160, "Algeth'ar Academy", false },
        { 1204, 0.5915, 0.5557, "Halls of Infusion", false },
        { 1208, 0.5370, 0.5710, "Aberrus, the Shadowed Crucible", true },
    },
    -- Zaralek Cavern
    [2133] = {
        { 1209, 0.4870, 0.1540, "Aberrus, the Shadowed Crucible", true },
    },
    -- Emerald Dream
    [2200] = {
        { 1207, 0.5370, 0.3360, "Amirdrassil, the Dream's Hope", true },
    },

    -----------------------------------------------------------------------
    -- The War Within (Tier 11)
    -----------------------------------------------------------------------
    -- Isle of Dorn
    [2248] = {
        { 1267, 0.6181, 0.3131, "The Stonevault", false },
    },
    -- The Ringing Deeps
    [2214] = {
        { 1268, 0.4590, 0.5750, "Darkflame Cleft", false },
    },
    -- Hallowfall
    [2215] = {
        { 1269, 0.4270, 0.5240, "Priory of the Sacred Flame", false },
    },
    -- Azj-Kahet
    [2255] = {
        { 1270, 0.5570, 0.4340, "City of Threads", false },
        { 1271, 0.5360, 0.4120, "The Dawnbreaker", false },
        { 1273, 0.4520, 0.5130, "Nerub-ar Palace", true },
    },
    -- Azj-Kahet lower / Ara-Kara
    [2256] = {
        { 1272, 0.3460, 0.5720, "Ara-Kara, City of Echoes", false },
    },
    -- Cinderbrew Meadery (Dornogal area)
    [2339] = {
        { 1274, 0.5150, 0.4380, "Cinderbrew Meadery", false },
    },
}
```

**Note:** These coordinates are approximate — they'll be overridden by accurate runtime API data when the player has discovered the instance. The static data covers undiscovered instances as a fallback. Instance IDs (journalInstanceID) should be verified against the live game. Some coordinates are approximate and can be refined later.

**Step 2: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass (file is loaded but no tests exercise it yet)

**Step 3: Commit**

```bash
git add QuickRoute/Data/DungeonEntrances.lua
git commit -S -m "data: add static dungeon/raid entrance coordinates for all expansions"
```

---

### Task 3: DungeonData Module — Runtime Scanner + Merger

**Files:**
- Create: `QuickRoute/Modules/DungeonData.lua`
- Create: `tests/test_dungeondata.lua`

**Step 1: Write the test file**

```lua
-- test_dungeondata.lua
-- Tests for the DungeonData module (runtime scanner + merger + lookup API)
local testHelper = require("tests.test_helper")

local function runTests()
    local passed, failed = 0, 0
    local function assert_eq(a, b, msg)
        if a == b then passed = passed + 1
        else failed = failed + 1; print("  FAIL: " .. msg .. " expected=" .. tostring(b) .. " got=" .. tostring(a)) end
    end
    local function assert_true(v, msg)
        if v then passed = passed + 1
        else failed = failed + 1; print("  FAIL: " .. msg) end
    end
    local function assert_nil(v, msg)
        if v == nil then passed = passed + 1
        else failed = failed + 1; print("  FAIL: " .. msg .. " expected nil, got=" .. tostring(v)) end
    end

    local QR = testHelper.getQR()

    -- Test: DungeonData module exists
    assert_true(QR.DungeonData ~= nil, "DungeonData module exists")

    -- Test: ScanInstances populates catalog from EJ API
    QR.DungeonData:ScanInstances()
    assert_true(QR.DungeonData.scanned, "ScanInstances sets scanned flag")

    -- Test: byTier populated (tier 1 = Classic, tier 2 = TWW in mock)
    local tier1 = QR.DungeonData.byTier[1]
    assert_true(tier1 ~= nil, "Tier 1 data exists")
    assert_true(#tier1 > 0, "Tier 1 has instances")

    local tier2 = QR.DungeonData.byTier[2]
    assert_true(tier2 ~= nil, "Tier 2 data exists")

    -- Test: instances table populated
    -- Mock has instanceID 226 = Ragefire Chasm (dungeon) and 741 = Molten Core (raid)
    local rfc = QR.DungeonData.instances[226]
    assert_true(rfc ~= nil, "Ragefire Chasm (226) in instances")
    assert_eq(rfc.name, "Ragefire Chasm", "RFC name")
    assert_eq(rfc.isRaid, false, "RFC is not a raid")
    assert_eq(rfc.tier, 1, "RFC tier = 1")

    local mc = QR.DungeonData.instances[741]
    assert_true(mc ~= nil, "Molten Core (741) in instances")
    assert_eq(mc.isRaid, true, "MC is a raid")

    -- Test: ScanEntrances finds entrance coordinates
    QR.DungeonData:ScanEntrances()
    -- Mock has entrance for RFC in zone 85 (Orgrimmar)
    local rfcAfter = QR.DungeonData.instances[226]
    assert_true(rfcAfter.zoneMapID ~= nil, "RFC has zoneMapID after ScanEntrances")
    assert_eq(rfcAfter.zoneMapID, 85, "RFC zoneMapID = 85 (Orgrimmar)")
    assert_true(rfcAfter.x ~= nil, "RFC has x coordinate")
    assert_true(rfcAfter.y ~= nil, "RFC has y coordinate")

    -- Test: byZone populated
    local zone85 = QR.DungeonData.byZone[85]
    assert_true(zone85 ~= nil, "Zone 85 has dungeon entrances")

    -- Test: Static fallback for instances not in API
    -- The Deadmines (63) is in static data (zone 52) but not in mock API entrances
    QR.DungeonData:MergeStaticFallback()
    local dm = QR.DungeonData.instances[63]
    if QR.StaticDungeonEntrances and QR.StaticDungeonEntrances[52] then
        assert_true(dm ~= nil, "Deadmines (63) loaded from static fallback")
        if dm then
            assert_eq(dm.zoneMapID, 52, "Deadmines zoneMapID = 52")
        end
    end

    -- Test: GetInstance returns data
    local inst = QR.DungeonData:GetInstance(226)
    assert_true(inst ~= nil, "GetInstance(226) returns data")
    assert_eq(inst.name, "Ragefire Chasm", "GetInstance returns correct name")

    -- Test: GetInstance returns nil for unknown
    assert_nil(QR.DungeonData:GetInstance(99999), "GetInstance(99999) returns nil")

    -- Test: GetInstancesForZone returns entries
    local zoneInstances = QR.DungeonData:GetInstancesForZone(85)
    assert_true(zoneInstances ~= nil, "GetInstancesForZone(85) returns data")
    assert_true(#zoneInstances > 0, "Zone 85 has at least 1 instance")

    -- Test: GetTierName returns expansion name
    local tierName = QR.DungeonData:GetTierName(1)
    assert_eq(tierName, "Classic", "Tier 1 name = Classic")

    -- Test: GetAllTiers returns list
    local tiers = QR.DungeonData:GetAllTiers()
    assert_true(#tiers >= 2, "At least 2 tiers")

    -- Test: Search by name
    local results = QR.DungeonData:Search("rage")
    assert_true(#results > 0, "Search 'rage' finds Ragefire Chasm")
    assert_eq(results[1].name, "Ragefire Chasm", "Search result name matches")

    -- Test: Search no results
    local noResults = QR.DungeonData:Search("zzzznonexistent")
    assert_eq(#noResults, 0, "Search nonexistent returns empty")

    print(string.format("  DungeonData: %d passed, %d failed", passed, failed))
    return passed, failed
end

return { run = runTests }
```

**Step 2: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: Errors about DungeonData module not existing

**Step 3: Write the DungeonData module**

```lua
-- DungeonData.lua
-- Runtime dungeon/raid entrance scanner with static fallback
-- Provides QR.DungeonData API for entrance lookups
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local string_lower = string.lower
local string_find = string.find
local table_insert, table_sort = table.insert, table.sort

-------------------------------------------------------------------------------
-- DungeonData Module
-------------------------------------------------------------------------------
QR.DungeonData = {
    instances = {},      -- journalInstanceID -> { name, zoneMapID, x, y, isRaid, tier, tierName, atlasName }
    byZone = {},         -- zoneMapID -> { journalInstanceID, ... }
    byTier = {},         -- tierIndex -> { journalInstanceID, ... }
    tierNames = {},      -- tierIndex -> string (expansion name)
    numTiers = 0,
    scanned = false,
    entrancesScanned = false,
}

local DungeonData = QR.DungeonData

-------------------------------------------------------------------------------
-- Runtime Scanning
-------------------------------------------------------------------------------

--- Scan all instances from the Encounter Journal API
-- Populates instances, byTier tables
function DungeonData:ScanInstances()
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex then
        QR:Debug("DungeonData: EJ API not available, skipping scan")
        self.scanned = true
        return
    end

    local numTiers = EJ_GetNumTiers()
    self.numTiers = numTiers

    for tier = 1, numTiers do
        EJ_SelectTier(tier)

        -- Get tier name
        local tierName = EJ_GetTierInfo and EJ_GetTierInfo(tier) or string_format("Tier %d", tier)
        self.tierNames[tier] = tierName
        self.byTier[tier] = self.byTier[tier] or {}

        -- Scan dungeons and raids
        for _, isRaid in ipairs({false, true}) do
            local index = 1
            while true do
                local instanceID, name = EJ_GetInstanceByIndex(index, isRaid)
                if not instanceID then break end

                if not self.instances[instanceID] then
                    self.instances[instanceID] = {
                        name = name,
                        isRaid = isRaid,
                        tier = tier,
                        tierName = tierName,
                        -- zoneMapID, x, y filled by ScanEntrances
                    }
                    table_insert(self.byTier[tier], instanceID)
                end

                index = index + 1
            end
        end
    end

    self.scanned = true
    QR:Debug(string_format("DungeonData: scanned %d tiers", numTiers))
end

--- Scan dungeon entrance coordinates from the map API
-- Must be called after ScanInstances
function DungeonData:ScanEntrances()
    if not C_EncounterJournal or not C_EncounterJournal.GetDungeonEntrancesForMap then
        QR:Debug("DungeonData: C_EncounterJournal.GetDungeonEntrancesForMap not available")
        self.entrancesScanned = true
        return
    end

    -- Scan all zone maps from ZoneAdjacency data
    local zoneMaps = {}
    if QR.ZoneAdjacency then
        for _, continent in pairs(QR.ZoneAdjacency) do
            if continent.zones then
                for _, zone in pairs(continent.zones) do
                    if zone.mapID then
                        zoneMaps[zone.mapID] = true
                    end
                end
            end
        end
    end

    -- Also scan capital cities from PathCalculator
    for _, cityData in pairs(QR.PathCalculator and {} or {}) do
        if cityData.mapID then
            zoneMaps[cityData.mapID] = true
        end
    end

    -- Add known zone mapIDs from static data as scan targets
    if QR.StaticDungeonEntrances then
        for zoneMapID, _ in pairs(QR.StaticDungeonEntrances) do
            zoneMaps[zoneMapID] = true
        end
    end

    local foundCount = 0
    for zoneMapID, _ in pairs(zoneMaps) do
        local entrances = C_EncounterJournal.GetDungeonEntrancesForMap(zoneMapID)
        if entrances and #entrances > 0 then
            for _, info in ipairs(entrances) do
                local instanceID = info.journalInstanceID
                if instanceID then
                    local x, y
                    if info.position then
                        if info.position.GetXY then
                            x, y = info.position:GetXY()
                        else
                            x, y = info.position.x, info.position.y
                        end
                    end

                    -- Create or update instance entry
                    if not self.instances[instanceID] then
                        -- Instance found via map but not in EJ scan (edge case)
                        local isRaid = false
                        if EJ_GetInstanceInfo then
                            local _, _, _, _, _, _, _, _, _, _, _, ejIsRaid = EJ_GetInstanceInfo(instanceID)
                            isRaid = ejIsRaid or false
                        end
                        self.instances[instanceID] = {
                            name = info.name or ("Instance " .. instanceID),
                            isRaid = isRaid,
                        }
                    end

                    local inst = self.instances[instanceID]
                    inst.zoneMapID = zoneMapID
                    inst.x = x
                    inst.y = y
                    inst.atlasName = info.atlasName
                    if info.name then inst.name = info.name end

                    -- Update byZone index
                    if not self.byZone[zoneMapID] then
                        self.byZone[zoneMapID] = {}
                    end
                    -- Avoid duplicates
                    local found = false
                    for _, id in ipairs(self.byZone[zoneMapID]) do
                        if id == instanceID then found = true; break end
                    end
                    if not found then
                        table_insert(self.byZone[zoneMapID], instanceID)
                    end

                    foundCount = foundCount + 1
                end
            end
        end
    end

    self.entrancesScanned = true
    QR:Debug(string_format("DungeonData: found %d entrance locations from API", foundCount))
end

--- Merge static fallback data for instances without coordinates
function DungeonData:MergeStaticFallback()
    if not QR.StaticDungeonEntrances then return end

    local mergedCount = 0
    for zoneMapID, entrances in pairs(QR.StaticDungeonEntrances) do
        for _, entry in ipairs(entrances) do
            local instanceID = entry[1]
            local x, y, name, isRaid = entry[2], entry[3], entry[4], entry[5]

            local inst = self.instances[instanceID]
            if not inst then
                -- Instance not in EJ scan at all — add from static
                inst = {
                    name = name,
                    isRaid = isRaid,
                    zoneMapID = zoneMapID,
                    x = x,
                    y = y,
                }
                self.instances[instanceID] = inst
                mergedCount = mergedCount + 1
            elseif not inst.zoneMapID then
                -- Instance in EJ scan but no entrance coordinates — fill from static
                inst.zoneMapID = zoneMapID
                inst.x = x
                inst.y = y
                mergedCount = mergedCount + 1
            end

            -- Update byZone index
            if inst.zoneMapID then
                if not self.byZone[zoneMapID] then
                    self.byZone[zoneMapID] = {}
                end
                local found = false
                for _, id in ipairs(self.byZone[zoneMapID]) do
                    if id == instanceID then found = true; break end
                end
                if not found then
                    table_insert(self.byZone[zoneMapID], instanceID)
                end
            end

            -- Update byTier if tier known
            if inst.tier and self.byTier[inst.tier] then
                local found = false
                for _, id in ipairs(self.byTier[inst.tier]) do
                    if id == instanceID then found = true; break end
                end
                if not found then
                    table_insert(self.byTier[inst.tier], instanceID)
                end
            end
        end
    end

    QR:Debug(string_format("DungeonData: merged %d entries from static fallback", mergedCount))
end

-------------------------------------------------------------------------------
-- Lookup API
-------------------------------------------------------------------------------

--- Get instance data by journalInstanceID
-- @param instanceID number
-- @return table|nil Instance data
function DungeonData:GetInstance(instanceID)
    return self.instances[instanceID]
end

--- Get all instances for a zone map
-- @param zoneMapID number
-- @return table Array of instance data tables
function DungeonData:GetInstancesForZone(zoneMapID)
    local ids = self.byZone[zoneMapID]
    if not ids then return {} end
    local results = {}
    for _, id in ipairs(ids) do
        local inst = self.instances[id]
        if inst then
            table_insert(results, {
                journalInstanceID = id,
                name = inst.name,
                isRaid = inst.isRaid,
                zoneMapID = inst.zoneMapID,
                x = inst.x,
                y = inst.y,
                tier = inst.tier,
                tierName = inst.tierName,
                atlasName = inst.atlasName,
            })
        end
    end
    return results
end

--- Get expansion tier name
-- @param tier number Tier index
-- @return string Tier name
function DungeonData:GetTierName(tier)
    return self.tierNames[tier] or string_format("Tier %d", tier)
end

--- Get all tiers with their instance counts
-- @return table Array of { tier, name, dungeonCount, raidCount }
function DungeonData:GetAllTiers()
    local tiers = {}
    for tier = 1, self.numTiers do
        local ids = self.byTier[tier] or {}
        local dungeons, raids = 0, 0
        for _, id in ipairs(ids) do
            local inst = self.instances[id]
            if inst then
                if inst.isRaid then raids = raids + 1 else dungeons = dungeons + 1 end
            end
        end
        table_insert(tiers, {
            tier = tier,
            name = self.tierNames[tier] or string_format("Tier %d", tier),
            dungeonCount = dungeons,
            raidCount = raids,
        })
    end
    return tiers
end

--- Search instances by name (case-insensitive substring match)
-- @param query string Search text
-- @return table Array of matching instance data
function DungeonData:Search(query)
    if not query or query == "" then return {} end
    local q = string_lower(query)
    local results = {}
    for id, inst in pairs(self.instances) do
        if inst.name and string_find(string_lower(inst.name), q, 1, true) then
            table_insert(results, {
                journalInstanceID = id,
                name = inst.name,
                isRaid = inst.isRaid,
                zoneMapID = inst.zoneMapID,
                x = inst.x,
                y = inst.y,
                tier = inst.tier,
                tierName = inst.tierName,
                atlasName = inst.atlasName,
            })
        end
    end
    table_sort(results, function(a, b)
        -- Sort: current expansion first, then by name
        if (a.tier or 0) ~= (b.tier or 0) then
            return (a.tier or 0) > (b.tier or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    return results
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Full initialization: scan + merge + log summary
function DungeonData:Initialize()
    self:ScanInstances()
    self:ScanEntrances()
    self:MergeStaticFallback()

    -- Log summary
    local total, withCoords, dungeons, raids = 0, 0, 0, 0
    for _, inst in pairs(self.instances) do
        total = total + 1
        if inst.zoneMapID then withCoords = withCoords + 1 end
        if inst.isRaid then raids = raids + 1 else dungeons = dungeons + 1 end
    end
    QR:Debug(string_format(
        "DungeonData: %d instances (%d dungeons, %d raids), %d with coordinates",
        total, dungeons, raids, withCoords
    ))
end
```

**Step 4: Register in addon_loader.lua and TOC**

Add `"Data/DungeonEntrances.lua"` after `"Data/ZoneAdjacency.lua"` in both:
- `tests/addon_loader.lua` line 42: after `"Data/ZoneAdjacency.lua"`
- `QuickRoute/QuickRoute.toc` line 32: after `Data\ZoneAdjacency.lua`

Add `"Modules/DungeonData.lua"` after `"Modules/POIRouting.lua"` in both:
- `tests/addon_loader.lua` line 57: after `"Modules/POIRouting.lua"`
- `QuickRoute/QuickRoute.toc` line 52: after `Modules\POIRouting.lua`

Register the test file in `tests/run_tests.lua` test list.

**Step 5: Add initialization call in QuickRoute.lua**

In the `OnPlayerLogin` function, add after existing module initialization calls:
```lua
-- Initialize dungeon data (deferred to avoid loading screen lag)
if QR.DungeonData then
    C_Timer.After(2, function()
        QR.DungeonData:Initialize()
    end)
end
```

**Step 6: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass including new DungeonData tests

**Step 7: Commit**

```bash
git add QuickRoute/Modules/DungeonData.lua tests/test_dungeondata.lua \
    tests/addon_loader.lua QuickRoute/QuickRoute.toc QuickRoute/QuickRoute.lua
git commit -S -m "feat: add DungeonData module with runtime scanning and static fallback"
```

---

### Task 4: Graph Integration — Dungeon Entrance Nodes

**Files:**
- Modify: `QuickRoute/Core/PathCalculator.lua` (BuildGraph method, ~line 141-208)
- Modify: `tests/test_dungeondata.lua` (add graph integration tests)

**Step 1: Add graph integration tests**

Append to `tests/test_dungeondata.lua`:

```lua
-- Test: Graph integration - dungeon nodes added
-- Rebuild graph after DungeonData is initialized
if QR.PathCalculator then
    QR.PathCalculator.graphDirty = true
    QR.PathCalculator:BuildGraph()
    local graph = QR.PathCalculator.graph
    assert_true(graph ~= nil, "Graph exists after rebuild")

    -- Check that dungeon nodes were added (RFC has coords in mock)
    local rfcNode = graph.nodes["Dungeon: Ragefire Chasm"]
    assert_true(rfcNode ~= nil, "Dungeon node 'Dungeon: Ragefire Chasm' exists in graph")
    if rfcNode then
        assert_eq(rfcNode.mapID, 85, "RFC node mapID = 85")
        assert_true(rfcNode.isDungeon, "RFC node has isDungeon flag")
    end
end
```

**Step 2: Add AddDungeonNodes method to PathCalculator**

In `PathCalculator.lua`, add a new method after `AddPlayerTeleportEdges` (~line 442):

```lua
--- Add dungeon/raid entrance nodes to the graph
-- Each entrance becomes a node connected to its parent zone via walking edge
function PathCalculator:AddDungeonNodes()
    if not QR.DungeonData or not QR.DungeonData.scanned then
        QR:Debug("PathCalculator: DungeonData not available, skipping dungeon nodes")
        return
    end

    local addedCount = 0
    for instanceID, inst in pairs(QR.DungeonData.instances) do
        if inst.zoneMapID and inst.x and inst.y and inst.name then
            local nodeName = "Dungeon: " .. inst.name
            self.graph:AddNode(nodeName, {
                mapID = inst.zoneMapID,
                x = inst.x,
                y = inst.y,
                journalInstanceID = instanceID,
                isRaid = inst.isRaid,
                isDungeon = true,
            })
            addedCount = addedCount + 1
        end
    end

    QR:Debug(string_format("PathCalculator: added %d dungeon/raid entrance nodes", addedCount))
end
```

**Step 3: Call AddDungeonNodes from BuildGraph**

In `PathCalculator:BuildGraph()` (~line 174), add after AddPlayerTeleportEdges:

```lua
-- Add dungeon/raid entrance nodes
success, err = pcall(function()
    self:AddDungeonNodes()
end)
if not success then
    QR:Error("AddDungeonNodes failed: " .. tostring(err))
    buildSuccess = false
    buildError = buildError or err
end
```

**Step 4: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass including graph integration tests

**Step 5: Commit**

```bash
git add QuickRoute/Core/PathCalculator.lua tests/test_dungeondata.lua
git commit -S -m "feat: integrate dungeon entrance nodes into pathfinding graph"
```

---

### Task 5: Localization Keys

**Files:**
- Modify: `QuickRoute/Localization.lua` (add dungeon routing strings in all 10 languages)

**Step 1: Add English keys**

After the existing `MINI_PANEL_RANDOM_FAVORITE` key (~line 189), add:

```lua
-- Dungeon/Raid routing
L["DUNGEON_PICKER_TITLE"] = "Dungeons & Raids"
L["DUNGEON_PICKER_SEARCH"] = "Search..."
L["DUNGEON_PICKER_NO_RESULTS"] = "No matching instances"
L["DUNGEON_ROUTE_TO"] = "Route to entrance"
L["DUNGEON_ROUTE_TO_TT"] = "Calculate the fastest route to this dungeon entrance"
L["DUNGEON_TAG"] = "Dungeon"
L["DUNGEON_RAID_TAG"] = "Raid"
L["DUNGEON_ENTRANCE"] = "%s Entrance"
L["EJ_ROUTE_BUTTON_TT"] = "Route to this instance entrance"
```

**Step 2: Add translations for all 9 other languages**

Add the same keys in each language section (deDE, frFR, esES, ptBR, ruRU, koKR, zhCN, zhTW, itIT). Example for deDE:

```lua
L["DUNGEON_PICKER_TITLE"] = "Dungeons & Schlachtzüge"
L["DUNGEON_PICKER_SEARCH"] = "Suchen..."
L["DUNGEON_PICKER_NO_RESULTS"] = "Keine passenden Instanzen"
L["DUNGEON_ROUTE_TO"] = "Route zum Eingang"
L["DUNGEON_ROUTE_TO_TT"] = "Berechne die schnellste Route zum Eingang dieser Instanz"
L["DUNGEON_TAG"] = "Dungeon"
L["DUNGEON_RAID_TAG"] = "Schlachtzug"
L["DUNGEON_ENTRANCE"] = "%s Eingang"
L["EJ_ROUTE_BUTTON_TT"] = "Route zum Eingang dieser Instanz"
```

**Step 3: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass

**Step 4: Commit**

```bash
git add QuickRoute/Localization.lua
git commit -S -m "i18n: add dungeon/raid routing localization keys (10 languages)"
```

---

### Task 6: DungeonPicker UI — Route Tab Dropdown

**Files:**
- Create: `QuickRoute/Modules/DungeonPicker.lua`
- Create: `tests/test_dungeonpicker.lua`
- Modify: `QuickRoute/Modules/UI.lua` (mount picker button in route tab)

**Step 1: Write tests**

Test that DungeonPicker creates a frame, populates tiers, filters by search, and triggers routing on selection.

**Step 2: Write the DungeonPicker module**

Key elements:
- Popup frame (BackdropTemplate) anchored below a trigger button in the Route tab
- EditBox at top for search filtering
- ScrollFrame with row pool, grouped by expansion tier (collapsible headers)
- Each row: atlas icon + instance name + Dungeon/Raid tag
- Clicking a row calls `POIRouting:RouteToMapPosition(zoneMapID, x, y)` and closes the picker
- ESC closes via UISpecialFrames
- Combat hide via `QR:RegisterCombatCallback()`

**Step 3: Mount the trigger button in UI.lua**

In `UI:CreateContent()`, after the toolbar buttons (~line 334), add a "Dungeons & Raids" button:

```lua
local dungeonButton = QR.CreateModernButton(frame, dungeonWidth, BUTTON_HEIGHT)
dungeonButton:SetPoint("LEFT", zoneDebugButton, "RIGHT", BUTTON_PADDING, 0)
ApplyButtonStyle(dungeonButton, L["DUNGEON_PICKER_TITLE"], "dungeon")
dungeonButton:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if QR.DungeonPicker then
        QR.DungeonPicker:Toggle(dungeonButton)
    end
end)
```

**Step 4: Register in addon_loader and TOC**

Add `"Modules/DungeonPicker.lua"` after `"Modules/DungeonData.lua"` in both files.

**Step 5: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass

**Step 6: Commit**

```bash
git add QuickRoute/Modules/DungeonPicker.lua tests/test_dungeonpicker.lua \
    QuickRoute/Modules/UI.lua tests/addon_loader.lua QuickRoute/QuickRoute.toc
git commit -S -m "feat: add dungeon/raid picker dropdown in Route tab"
```

---

### Task 7: EncounterJournalButton — QR Button on Dungeon Journal

**Files:**
- Create: `QuickRoute/Modules/EncounterJournalButton.lua`
- Modify: `tests/test_dungeondata.lua` (add EJ button tests)

**Step 1: Write the module**

Hook the Encounter Journal frame. When viewing a specific instance, show a small QR route button:

```lua
-- EncounterJournalButton.lua
-- Adds a QuickRoute "Route to entrance" button on the Encounter Journal
local ADDON_NAME, QR = ...

local InCombatLockdown = InCombatLockdown

QR.EncounterJournalButton = {
    button = nil,
    initialized = false,
    hookedEJ = false,
}

local EJB = QR.EncounterJournalButton
local L

function EJB:CreateButton()
    if self.button then return self.button end

    local btn = CreateFrame("Button", "QREncounterJournalButton", UIParent, "UIPanelButtonTemplate")
    btn:SetSize(120, 22)
    btn:SetText(QR.L["DUNGEON_ROUTE_TO"])
    btn:Hide()

    btn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        EJB:RouteToCurrentInstance()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(QR.L["EJ_ROUTE_BUTTON_TT"], 1, 1, 1, true)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    QR.AddMicroIcon(btn, 16)
    self.button = btn
    return btn
end

function EJB:RouteToCurrentInstance()
    if not EncounterJournal or not EncounterJournal.instanceID then return end
    local instanceID = EncounterJournal.instanceID
    if not QR.DungeonData then return end

    local inst = QR.DungeonData:GetInstance(instanceID)
    if inst and inst.zoneMapID and inst.x and inst.y then
        QR.POIRouting:RouteToMapPosition(inst.zoneMapID, inst.x, inst.y)
    else
        QR:Print(QR.L["DUNGEON_PICKER_NO_RESULTS"])
    end
end

function EJB:UpdateButton()
    if InCombatLockdown() then return end
    if not self.button then return end

    if not EncounterJournal or not EncounterJournal:IsShown() then
        self.button:Hide()
        return
    end

    local instanceID = EncounterJournal.instanceID
    if not instanceID or not QR.DungeonData then
        self.button:Hide()
        return
    end

    local inst = QR.DungeonData:GetInstance(instanceID)
    if inst and inst.zoneMapID then
        -- Anchor to EJ frame header area
        self.button:ClearAllPoints()
        self.button:SetParent(EncounterJournal)
        self.button:SetPoint("TOPRIGHT", EncounterJournal, "TOPRIGHT", -30, -30)
        self.button:Show()
    else
        self.button:Hide()
    end
end

function EJB:HookEncounterJournal()
    if self.hookedEJ then return end
    if not EncounterJournal then return end

    hooksecurefunc(EncounterJournal, "Show", function()
        EJB:UpdateButton()
    end)
    hooksecurefunc(EncounterJournal, "Hide", function()
        if EJB.button then EJB.button:Hide() end
    end)

    -- Hook instance selection changes
    if EncounterJournal_DisplayInstance then
        hooksecurefunc("EncounterJournal_DisplayInstance", function()
            EJB:UpdateButton()
        end)
    end

    self.hookedEJ = true
end

function EJB:Initialize()
    if self.initialized then return end
    L = QR.L
    self:CreateButton()

    -- Defer EJ hook (Encounter Journal is load-on-demand)
    if EncounterJournal then
        self:HookEncounterJournal()
    else
        -- Hook when EJ addon loads
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(_, _, addon)
            if addon == "Blizzard_EncounterJournal" then
                EJB:HookEncounterJournal()
                hookFrame:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end

    self.initialized = true
    QR:Debug("EncounterJournalButton initialized")
end
```

**Step 2: Register in addon_loader and TOC**

Add `"Modules/EncounterJournalButton.lua"` after `"Modules/DungeonPicker.lua"`.

**Step 3: Add initialization call in QuickRoute.lua**

After DungeonData init: `if QR.EncounterJournalButton then QR.EncounterJournalButton:Initialize() end`

**Step 4: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass

**Step 5: Commit**

```bash
git add QuickRoute/Modules/EncounterJournalButton.lua tests/addon_loader.lua \
    QuickRoute/QuickRoute.toc QuickRoute/QuickRoute.lua
git commit -S -m "feat: add Route button on Encounter Journal"
```

---

### Task 8: Map Pin Routing — Dungeon Pins

**Files:**
- Modify: `QuickRoute/Modules/POIRouting.lua` (hook dungeon entrance pins)

**Step 1: Add dungeon pin hook**

In `POIRouting:Initialize()`, after the existing `RegisterMapHook()` call, add:

```lua
self:RegisterDungeonPinHook()
```

Add the new method:

```lua
--- Hook dungeon entrance map pins for Ctrl+Right-click routing
function POIRouting:RegisterDungeonPinHook()
    if not WorldMapFrame then return end

    -- Hook pin creation to add our click handler
    local ok, err = pcall(function()
        -- DungeonEntrancePinMixin is Blizzard's pin template for dungeon entrances
        if DungeonEntrancePinMixin and DungeonEntrancePinMixin.OnMouseClickAction then
            hooksecurefunc(DungeonEntrancePinMixin, "OnMouseClickAction", function(pin, button)
                if button ~= "RightButton" then return end
                if not (IsControlKeyDown and IsControlKeyDown()) then return end
                if not pin.journalInstanceID then return end

                -- Look up entrance coordinates from DungeonData
                if QR.DungeonData then
                    local inst = QR.DungeonData:GetInstance(pin.journalInstanceID)
                    if inst and inst.zoneMapID and inst.x and inst.y then
                        POIRouting:RouteToMapPosition(inst.zoneMapID, inst.x, inst.y)
                    end
                end
            end)
            QR:Debug("POIRouting: Dungeon pin hook registered")
        else
            -- Fallback: try hooking via the data provider
            QR:Debug("POIRouting: DungeonEntrancePinMixin not available, pin hook skipped")
        end
    end)

    if not ok then
        QR:Debug("POIRouting: Failed to hook dungeon pins: " .. tostring(err))
    end
end
```

**Step 2: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass

**Step 3: Commit**

```bash
git add QuickRoute/Modules/POIRouting.lua
git commit -S -m "feat: add Ctrl+Right-click routing on dungeon map pins"
```

---

### Task 9: Final Integration & Cleanup

**Step 1: Run full test suite**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass

**Step 2: Verify TOC and addon_loader have correct load order**

Expected file order additions:
```
Data\DungeonEntrances.lua       (after ZoneAdjacency.lua)
Modules\DungeonData.lua         (after POIRouting.lua)
Modules\DungeonPicker.lua       (after DungeonData.lua)
Modules\EncounterJournalButton.lua (after DungeonPicker.lua)
```

**Step 3: Update /qrhelp command**

In QuickRoute.lua, add dungeon-related commands to help output.

**Step 4: Deploy to game client**

```bash
cp -r QuickRoute/* "/mnt/f/World of Warcraft/_retail_/Interface/AddOns/QuickRoute/"
```

**Step 5: In-game verification checklist**
- [ ] Open Route tab → click "Dungeons & Raids" button → picker appears
- [ ] Search for "stonevault" → filters correctly
- [ ] Click an instance → route calculated and shown
- [ ] Open Encounter Journal → QR button appears on instance page
- [ ] Click QR button → routes to entrance
- [ ] Open world map → Ctrl+right-click dungeon pin → routes to entrance
- [ ] All three entry points work in deDE locale

**Step 6: Commit final cleanup**

```bash
git add -A
git commit -S -m "feat: complete dungeon/raid routing with three entry points"
```
