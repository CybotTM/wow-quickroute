-- DungeonTeleports.lua
-- Spells that teleport the player to a dungeon or raid entrance.
--
-- Derived from the client's own tables, not hand-listed: every SpellName row
-- named "Teleport: <X>" where X is a JournalInstance name. That is a generous
-- match on purpose -- it catches the Mythic+ rewards this file was added for
-- and the older attunement teleports alike, and it cannot be narrowed from
-- outside the game because no client table marks which are which.
--
-- The generosity is safe because nothing here is used until IsSpellKnown says
-- the player has it: a spell nobody can learn is inert, and a boss ability of
-- the same name is never known. What a wrong entry would cost is a teleport
-- offered to a dungeon it does not lead to, which /qrscan lists and
-- /qrverifymap can be pointed at.
--
-- Regenerate: match SpellName.Name_lang against JournalInstance.Name_lang.
-- Several instances have more than one spell; both are kept, since they share
-- the journalInstanceID and the unlearned one never becomes an edge.
local ADDON_NAME, QR = ...

QR.DungeonTeleportSpells = {
    -- Algeth'ar Academy
    [396126] = { journalInstanceID = 1201, destination = "Algeth'ar Academy" },
    -- Altar of Fangs
    [1289772] = { journalInstanceID = 1322, destination = "Altar of Fangs" },
    -- Antorus, the Burning Throne
    [253524] = { journalInstanceID = 946, destination = "Antorus, the Burning Throne" },
    -- Ara-Kara, City of Echoes
    [442929] = { journalInstanceID = 1271, destination = "Ara-Kara, City of Echoes" },
    -- Atal'Dazar
    [272256] = { journalInstanceID = 968, destination = "Atal'Dazar" },
    -- Auchindoun
    [169764] = { journalInstanceID = 547, destination = "Auchindoun" },
    -- Baradin Hold
    [219338] = { journalInstanceID = 75, destination = "Baradin Hold" },
    -- Black Rook Hold
    [205373] = { journalInstanceID = 740, destination = "Black Rook Hold" },
    [426400] = { journalInstanceID = 740, destination = "Black Rook Hold" },
    -- Black Temple
    [41234] = { journalInstanceID = 751, destination = "Black Temple" },
    [1248491] = { journalInstanceID = 751, destination = "Black Temple" },
    -- Blackrock Foundry
    [169771] = { journalInstanceID = 457, destination = "Blackrock Foundry" },
    -- Bloodmaul Slag Mines
    [151895] = { journalInstanceID = 385, destination = "Bloodmaul Slag Mines" },
    [169762] = { journalInstanceID = 385, destination = "Bloodmaul Slag Mines" },
    -- Brackenhide Hollow
    [396129] = { journalInstanceID = 1196, destination = "Brackenhide Hollow" },
    -- Cathedral of Eternal Night
    [240988] = { journalInstanceID = 900, destination = "Cathedral of Eternal Night" },
    -- Cinderbrew Meadery
    [442932] = { journalInstanceID = 1272, destination = "Cinderbrew Meadery" },
    -- City of Threads
    [442927] = { journalInstanceID = 1274, destination = "City of Threads" },
    -- Court of Stars
    [220052] = { journalInstanceID = 800, destination = "Court of Stars" },
    -- Crucible of Storms
    [286637] = { journalInstanceID = 1177, destination = "Crucible of Storms" },
    -- Darkflame Cleft
    [442930] = { journalInstanceID = 1210, destination = "Darkflame Cleft" },
    -- Darkheart Thicket
    [205374] = { journalInstanceID = 762, destination = "Darkheart Thicket" },
    -- Dawn of the Infinite
    [426121] = { journalInstanceID = 1209, destination = "Dawn of the Infinite" },
    -- De Other Side
    [348537] = { journalInstanceID = 1188, destination = "De Other Side" },
    -- Den of Nalorakk
    [1289773] = { journalInstanceID = 1311, destination = "Den of Nalorakk" },
    -- Eye of Azshara
    [205376] = { journalInstanceID = 716, destination = "Eye of Azshara" },
    -- Freehold
    [272262] = { journalInstanceID = 1001, destination = "Freehold" },
    -- Grim Batol
    [396121] = { journalInstanceID = 71, destination = "Grim Batol" },
    -- Grimrail Depot
    [169766] = { journalInstanceID = 536, destination = "Grimrail Depot" },
    -- Halls of Atonement
    [325777] = { journalInstanceID = 1185, destination = "Halls of Atonement" },
    [348534] = { journalInstanceID = 1185, destination = "Halls of Atonement" },
    -- Halls of Infusion
    [396130] = { journalInstanceID = 1204, destination = "Halls of Infusion" },
    -- Halls of Valor
    [205377] = { journalInstanceID = 721, destination = "Halls of Valor" },
    [213529] = { journalInstanceID = 721, destination = "Halls of Valor" },
    [228931] = { journalInstanceID = 721, destination = "Halls of Valor" },
    [232624] = { journalInstanceID = 721, destination = "Halls of Valor" },
    -- Hellfire Citadel
    [187328] = { journalInstanceID = 669, destination = "Hellfire Citadel" },
    -- Highmaul
    [169770] = { journalInstanceID = 477, destination = "Highmaul" },
    -- Iron Docks
    [169763] = { journalInstanceID = 558, destination = "Iron Docks" },
    -- Karazhan
    [230118] = { journalInstanceID = 745, destination = "Karazhan" },
    [373515] = { journalInstanceID = 745, destination = "Karazhan" },
    -- Kings' Rest
    [272261] = { journalInstanceID = 1041, destination = "Kings' Rest" },
    [1289778] = { journalInstanceID = 1041, destination = "Kings' Rest" },
    -- Magisters' Terrace
    [1255433] = { journalInstanceID = 1300, destination = "Magisters' Terrace" },
    -- Maisara Caverns
    [1255247] = { journalInstanceID = 1315, destination = "Maisara Caverns" },
    -- Maw of Souls
    [205392] = { journalInstanceID = 727, destination = "Maw of Souls" },
    -- Mists of Tirna Scithe
    [348533] = { journalInstanceID = 1184, destination = "Mists of Tirna Scithe" },
    -- Murder Row
    [1248186] = { journalInstanceID = 1304, destination = "Murder Row" },
    [1253942] = { journalInstanceID = 1304, destination = "Murder Row" },
    [1289775] = { journalInstanceID = 1304, destination = "Murder Row" },
    -- Neltharion's Lair
    [205379] = { journalInstanceID = 767, destination = "Neltharion's Lair" },
    -- Neltharus
    [396128] = { journalInstanceID = 1199, destination = "Neltharus" },
    -- Nexus-Point Xenas
    [1255391] = { journalInstanceID = 1316, destination = "Nexus-Point Xenas" },
    -- Operation: Floodgate
    [1218105] = { journalInstanceID = 1298, destination = "Operation: Floodgate" },
    -- Operation: Mechagon
    [300433] = { journalInstanceID = 1178, destination = "Operation: Mechagon" },
    -- Pit of Saron
    [1255366] = { journalInstanceID = 278, destination = "Pit of Saron" },
    -- Plaguefall
    [348531] = { journalInstanceID = 1183, destination = "Plaguefall" },
    -- Priory of the Sacred Flame
    [442923] = { journalInstanceID = 1267, destination = "Priory of the Sacred Flame" },
    -- Return to Karazhan
    [245588] = { journalInstanceID = 860, destination = "Return to Karazhan" },
    -- Ruby Life Pools
    [1289780] = { journalInstanceID = 1202, destination = "Ruby Life Pools" },
    -- Sanguine Depths
    [348538] = { journalInstanceID = 1189, destination = "Sanguine Depths" },
    -- Seat of the Triumvirate
    [252631] = { journalInstanceID = 945, destination = "Seat of the Triumvirate" },
    -- Shadowmoon Burial Grounds
    [169768] = { journalInstanceID = 537, destination = "Shadowmoon Burial Grounds" },
    [396131] = { journalInstanceID = 537, destination = "Shadowmoon Burial Grounds" },
    -- Shrine of the Storm
    [272263] = { journalInstanceID = 1036, destination = "Shrine of the Storm" },
    -- Siege of Boralus
    [272264] = { journalInstanceID = 1023, destination = "Siege of Boralus" },
    [272265] = { journalInstanceID = 1023, destination = "Siege of Boralus" },
    -- Skyreach
    [169765] = { journalInstanceID = 476, destination = "Skyreach" },
    -- Spires of Ascension
    [348535] = { journalInstanceID = 1186, destination = "Spires of Ascension" },
    -- Temple of Sethraliss
    [272267] = { journalInstanceID = 1030, destination = "Temple of Sethraliss" },
    [1289782] = { journalInstanceID = 1030, destination = "Temple of Sethraliss" },
    -- Temple of the Jade Serpent
    [396132] = { journalInstanceID = 313, destination = "Temple of the Jade Serpent" },
    -- The Azure Vault
    [396125] = { journalInstanceID = 1203, destination = "The Azure Vault" },
    -- The Blinding Vale
    [1289776] = { journalInstanceID = 1309, destination = "The Blinding Vale" },
    -- The Dawnbreaker
    [442931] = { journalInstanceID = 1270, destination = "The Dawnbreaker" },
    -- The Eternal Palace
    [302415] = { journalInstanceID = 1179, destination = "The Eternal Palace" },
    -- The Everbloom
    [426410] = { journalInstanceID = 556, destination = "The Everbloom" },
    -- The Necrotic Wake
    [348529] = { journalInstanceID = 1182, destination = "The Necrotic Wake" },
    -- The Nighthold
    [232457] = { journalInstanceID = 786, destination = "The Nighthold" },
    [232539] = { journalInstanceID = 786, destination = "The Nighthold" },
    [262338] = { journalInstanceID = 786, destination = "The Nighthold" },
    [265577] = { journalInstanceID = 786, destination = "The Nighthold" },
    -- The Nokhud Offensive
    [396123] = { journalInstanceID = 1198, destination = "The Nokhud Offensive" },
    -- The Rookery
    [442925] = { journalInstanceID = 1268, destination = "The Rookery" },
    -- The Stonevault
    [442926] = { journalInstanceID = 1269, destination = "The Stonevault" },
    -- The Underrot
    [272269] = { journalInstanceID = 1022, destination = "The Underrot" },
    -- The Vortex Pinnacle
    [408371] = { journalInstanceID = 68, destination = "The Vortex Pinnacle" },
    -- Theater of Pain
    [348536] = { journalInstanceID = 1187, destination = "Theater of Pain" },
    -- Throne of the Tides
    [426132] = { journalInstanceID = 65, destination = "Throne of the Tides" },
    [426464] = { journalInstanceID = 65, destination = "Throne of the Tides" },
    -- Tol Dagor
    [272270] = { journalInstanceID = 1002, destination = "Tol Dagor" },
    -- Tomb of Sargeras
    [240991] = { journalInstanceID = 875, destination = "Tomb of Sargeras" },
    -- Trial of Valor
    [232892] = { journalInstanceID = 861, destination = "Trial of Valor" },
    -- Uldaman: Legacy of Tyr
    [396127] = { journalInstanceID = 1197, destination = "Uldaman: Legacy of Tyr" },
    -- Uldir
    [272280] = { journalInstanceID = 1031, destination = "Uldir" },
    -- Upper Blackrock Spire
    [169769] = { journalInstanceID = 559, destination = "Upper Blackrock Spire" },
    -- Vault of the Wardens
    [205395] = { journalInstanceID = 707, destination = "Vault of the Wardens" },
    -- Voidscar Arena
    [1286119] = { journalInstanceID = 1313, destination = "Voidscar Arena" },
    [1289777] = { journalInstanceID = 1313, destination = "Voidscar Arena" },
    -- Waycrest Manor
    [272271] = { journalInstanceID = 1021, destination = "Waycrest Manor" },
    -- Windrunner Spire
    [1254840] = { journalInstanceID = 1299, destination = "Windrunner Spire" },
    -- Zul'Farrak
    [51958] = { journalInstanceID = 241, destination = "Zul'Farrak" },
}
