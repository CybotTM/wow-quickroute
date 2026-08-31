-- FlightPoints.lua
-- Zones that have a flight master, with the position of one of their flight
-- points in both zone and world coordinates.
--
-- Derived from the client's own tables, not surveyed: TaxiNodes gives every
-- flight point with a world position and the world map it sits on, and
-- UiMapAssignment converts that position into a zone and normalized
-- coordinates. 1352 of 1464 flight points resolved to a zone; the 112 that
-- did not are on maps with no zone-level assignment and are left out.
--
-- Collapsed to one entry per zone on purpose. The graph is zone-level, and
-- from any flight master the game auto-routes multi-hop to any other point
-- you have discovered on that world map, so the per-path topology buys
-- nothing here -- what matters is which zones are reachable and how far.
--
-- worldX/worldY are what edge weights are computed from: the distance is
-- exact, and only the speed it is divided by is an estimate. continentID is
-- the world map from TaxiNodes, NOT a uiMapID -- two flight points are
-- connected exactly when they share it.
--
-- Regenerate: TaxiNodes.Pos_0/Pos_1 + ContinentID against UiMapAssignment's
-- Region box, keeping the smallest zone-type (UiMap Type 3) match.
local ADDON_NAME, QR = ...

QR.FlightPoints = {
    -- world map 0
    [14] = { x = 0.4739, y = 0.3992, worldX = -1240.5, worldY = -2515.1, continentID = 0, node = "Refuge Pointe, Arathi" },
    [15] = { x = 0.5103, y = 0.5249, worldX = -6898.2, worldY = -3514.0, continentID = 0, node = "Bloodwatcher Point, Badlands" },
    [17] = { x = 0.8922, y = 0.4711, worldX = -12761.9, worldY = -2919.0, continentID = 0, node = "Surwich, Blasted Lands" },
    [21] = { x = 0.4242, y = 0.4556, worldX = 478.9, worldY = 1536.6, continentID = 0, node = "The Sepulcher, Silverpine Forest" },
    [22] = { x = 0.8495, y = 0.4295, worldX = 931.3, worldY = -1430.1, continentID = 0, node = "Chillwind Camp, Western Plaguelands" },
    [23] = { x = 0.5398, y = 0.7584, worldX = 2253.4, worldY = -5344.9, continentID = 0, node = "Eastern Plaguelands" },
    [25] = { x = 0.4624, y = 0.5602, worldX = -17.7, worldY = -874.2, continentID = 0, node = "Tarren Mill, Hillsbrad" },
    [26] = { x = 0.4609, y = 0.1111, worldX = 283.7, worldY = -2002.8, continentID = 0, node = "Aerie Peak, The Hinterlands" },
    [27] = { x = 0.4616, y = 0.5722, worldX = -5448.5, worldY = -665.1, continentID = 0, node = "CC Prologue - GT - Quest - Vent Horizon - Start" },
    [32] = { x = 0.3878, y = 0.9459, worldX = -6676.9, worldY = -2433.4, continentID = 0, node = "New Kargath, Badlands" },
    [36] = { x = 0.6568, y = 0.7214, worldX = -8364.6, worldY = -2738.4, continentID = 0, node = "Morgan's Vigil, Burning Steppes" },
    [37] = { x = 0.6487, y = 0.4236, worldX = -9441.2, worldY = 65.1, continentID = 0, node = "Filming" },
    [42] = { x = 0.3893, y = 0.1713, worldX = -10515.5, worldY = -1261.7, continentID = 0, node = "Darkshire, Duskwood" },
    [47] = { x = 0.9041, y = 0.3889, worldX = -11344.0, worldY = -216.8, continentID = 0, node = "Rebel Camp, Stranglethorn Vale" },
    [48] = { x = 0.5079, y = 0.3394, worldX = -5421.9, worldY = -2930.0, continentID = 0, node = "Thelsamar, Loch Modan" },
    [49] = { x = 0.5340, y = 0.2928, worldX = -9429.1, worldY = -2231.4, continentID = 0, node = "Lakeshire, Redridge" },
    [50] = { x = 0.5113, y = 0.3896, worldX = -12414.2, worldY = 146.3, continentID = 0, node = "Grom'gol, Stranglethorn" },
    [51] = { x = 0.9426, y = 0.5400, worldX = -11112.3, worldY = -3435.7, continentID = 0, node = "Nethergarde Keep, Blasted Lands" },
    [52] = { x = 0.4937, y = 0.5664, worldX = -10551.9, worldY = 1034.4, continentID = 0, node = "Sentinel Hill, Westfall" },
    [56] = { x = 0.5950, y = 0.0939, worldX = -3787.8, worldY = -777.7, continentID = 0, node = "Menethil Harbor, Wetlands" },
    [84] = { x = 0.7297, y = 0.7098, worldX = -8841.1, worldY = 489.7, continentID = 0, node = "Stormwind, Elwynn" },
    [87] = { x = 0.4787, y = 0.5589, worldX = -4821.8, worldY = -1155.4, continentID = 0, node = "Ironforge, Dun Morogh" },
    [90] = { x = 0.4832, y = 0.6309, worldX = 1568.6, worldY = 268.0, continentID = 0, node = "Undercity, Tirisfal" },
    [201] = { x = 0.3046, y = 0.5673, worldX = -4588.0, worldY = 3481.1, continentID = 0, node = "Smuggler's Scar, Vashj'ir" },
    [204] = { x = 0.4415, y = 0.9689, worldX = -6105.6, worldY = 4285.1, continentID = 0, node = "Silver Tide Hollow, Vashj'ir" },
    [205] = { x = 0.7588, y = 0.5681, worldX = -7209.7, worldY = 3925.9, continentID = 0, node = "Voldrin's Hold, Vashj'ir" },
    [210] = { x = 0.6670, y = 0.4583, worldX = -14271.8, worldY = 299.9, continentID = 0, node = "Booty Bay, Stranglethorn" },
    [217] = { x = 0.1796, y = 0.5725, worldX = -910.2, worldY = 1638.6, continentID = 0, node = "Forsaken Forward Command, Gilneas" },
    [241] = { x = 0.7613, y = 0.4575, worldX = -4831.8, worldY = -4848.9, continentID = 0, node = "Crushblow, Twilight Highlands" },
    [425] = { x = 0.4926, y = 0.1941, worldX = -8889.0, worldY = -0.5, continentID = 0, node = "Northshire Abbey" },
    [469] = { x = 0.5738, y = 0.3693, worldX = -5434.7, worldY = 523.1, continentID = 0, node = "CC Prologue - GT - Battle Flight - End" },
    [2393] = { x = 0.6270, y = 0.4176, worldX = 8599.9, worldY = -4507.4, continentID = 0, node = "Thalassian University Teleport Base" },
    [2395] = { x = 0.9005, y = 0.3106, worldX = 4512.1, worldY = -2780.1, continentID = 0, node = "Silverglade Refuge, Eversong Woods" },
    [2424] = { x = 0.3381, y = 0.5775, worldX = 11245.3, worldY = -4781.4, continentID = 0, node = "Terrace of the Sun, Isle of Quel'Danas" },
    [2437] = { x = 0.7843, y = 0.3384, worldX = 3620.6, worldY = -6670.7, continentID = 0, node = "Torntusk Overlook, Zul'Aman" },
    [2512] = { x = 0.3327, y = 0.0701, worldX = 6781.0, worldY = -7875.0, continentID = 0, node = "Camp Stonewash, Zul'Aman" },
    [2536] = { x = 0.4116, y = 0.4008, worldX = 5114.3, worldY = -6473.8, continentID = 0, node = "Atal'Aman, Zul'Aman" },
    [2668] = { x = 0.1792, y = 0.3505, worldX = 7400.6, worldY = 4358.7, continentID = 0, node = "Quest Path 4599: Shadowmoon 6.x - The Search for Owynn Graddock: Garrison, Shadowmoon Valley -> Bloodmaul Slag Mines, Frostfire Ridge (HMC)" },
    -- world map 1
    [1] = { x = 0.6383, y = 0.1198, worldX = -441.8, worldY = -2596.1, continentID = 1, node = "The Crossroads, Northern Barrens" },
    [7] = { x = 0.5958, y = 0.4757, worldX = -2333.4, worldY = -388.5, continentID = 1, node = "Mulgore - Red Cloud Mesa: To Bloodhoof (End)" },
    [10] = { x = 0.2292, y = 0.0389, worldX = 932.1, worldY = -21.2, continentID = 1, node = "Krom'gar Fortress, Stonetalon Mountains" },
    [57] = { x = 0.8845, y = 0.5539, worldX = 8383.8, worldY = 981.0, continentID = 1, node = "Rut'theran Village, Teldrassil" },
    [62] = { x = 0.1770, y = 0.5172, worldX = 7459.9, worldY = -326.6, continentID = 1, node = "Lor'danel, Darkshore" },
    [63] = { x = 0.4802, y = 0.3450, worldX = 2827.3, worldY = -289.2, continentID = 1, node = "Astranaar, Ashenvale" },
    [64] = { x = 0.1173, y = 0.1122, worldX = -4310.6, worldY = -927.1, continentID = 1, node = "Westreach Summit, Thousand Needles" },
    [65] = { x = 0.6179, y = 0.3202, worldX = 973.9, worldY = 2013.1, continentID = 1, node = "Farwatcher's Glen, Stonetalon Mountains" },
    [66] = { x = 0.1044, y = 0.6467, worldX = 139.2, worldY = 1325.8, continentID = 1, node = "Nijel's Point, Desolace" },
    [69] = { x = 0.5677, y = 0.7723, worldX = -4996.9, worldY = 73.9, continentID = 1, node = "Shadebough, Feralas" },
    [70] = { x = 0.5120, y = 0.6746, worldX = -3825.4, worldY = -4516.6, continentID = 1, node = "Theramore, Dustwallow Marsh" },
    [71] = { x = 0.2943, y = 0.5138, worldX = -7186.0, worldY = -3768.2, continentID = 1, node = "Gadgetzan, Tanaris" },
    [76] = { x = 0.4988, y = 0.5298, worldX = 3547.2, worldY = -6294.7, continentID = 1, node = "Bilgewater Harbor, Azshara" },
    [77] = { x = 0.5230, y = 0.3495, worldX = 5123.5, worldY = -321.2, continentID = 1, node = "Bloodvenom Post, Felwood [DISABLED in 4.x]" },
    [78] = { x = 0.6411, y = 0.5607, worldX = -7548.0, worldY = -1541.1, continentID = 1, node = "Marshal's Stand, Un'Goro Crater" },
    [80] = { x = 0.6711, y = 0.4791, worldX = 7458.5, worldY = -2487.2, continentID = 1, node = "Moonglade" },
    [81] = { x = 0.3468, y = 0.5289, worldX = -6811.4, worldY = 836.7, continentID = 1, node = "Cenarion Hold, Silithus" },
    [83] = { x = 0.4871, y = 0.6099, worldX = 6796.8, worldY = -4742.4, continentID = 1, node = "Everlook, Winterspring" },
    [85] = { x = 0.5937, y = 0.4927, worldX = 1798.3, worldY = -4363.3, continentID = 1, node = "Orgrimmar, Durotar" },
    [88] = { x = 0.4990, y = 0.4665, worldX = -1197.2, worldY = 29.7, continentID = 1, node = "Thunder Bluff, Mulgore" },
    [89] = { x = 0.4827, y = 0.3672, worldX = 9968.8, worldY = 2622.1, continentID = 1, node = "Darnassus, Teldrassil" },
    [198] = { x = 0.7852, y = 0.0931, worldX = 3972.8, worldY = -1324.5, continentID = 1, node = "Emerald Sanctuary, Felwood" },
    [199] = { x = 0.4390, y = 0.9687, worldX = -1965.2, worldY = -5824.3, continentID = 1, node = "Transport, Booty Bay" },
    [249] = { x = 0.3533, y = 0.7925, worldX = -9487.9, worldY = -2467.1, continentID = 1, node = "Dawnrise Expedition, Tanaris" },
    [461] = { x = 0.9940, y = 0.0973, worldX = -894.6, worldY = -3773.0, continentID = 1, node = "Ratchet, Northern Barrens" },
    [462] = { x = 0.3050, y = 0.1329, worldX = -2936.1, worldY = -1.5, continentID = 1, node = "Mulgore - Red Cloud Mesa: To Bloodhoof" },
    [463] = { x = 0.2684, y = 0.4694, worldX = -848.2, worldY = -5339.5, continentID = 1, node = "Durotar - ET - CC Prologue - Troll Battle End" },
    -- world map 530
    [94] = { x = 0.5195, y = 0.6895, worldX = 9335.8, worldY = -7883.1, continentID = 530, node = "Eversong - Duskwither Teleport" },
    [95] = { x = 0.3055, y = 0.4548, worldX = 7594.5, worldY = -6784.3, continentID = 530, node = "Tranquillien, Ghostlands" },
    [97] = { x = 0.4923, y = 0.4963, worldX = -4130.1, worldY = -12520.5, continentID = 530, node = "Azure Watch, Azuremyst Isle" },
    [100] = { x = 0.3638, y = 0.5627, worldX = 228.5, worldY = 2633.6, continentID = 530, node = "Thrallmar, Hellfire Peninsula" },
    [102] = { x = 0.6210, y = 0.7842, worldX = -146.3, worldY = 5532.6, continentID = 530, node = "Zangarmarsh - Quest - As the Crow Flies" },
    [103] = { x = 0.9569, y = 0.1215, worldX = -4284.0, worldY = -11194.7, continentID = 530, node = "Transport, Exodar" },
    [104] = { x = 0.3048, y = 0.6319, worldX = -3065.6, worldY = 749.4, continentID = 530, node = "Altar of Sha'tar, Shadowmoon Valley" },
    [105] = { x = 0.3666, y = 0.9677, worldX = 3082.3, worldY = 3596.1, continentID = 530, node = "Area 52, Netherstorm" },
    [106] = { x = 0.5402, y = 0.5761, worldX = -1933.3, worldY = -11954.6, continentID = 530, node = "Blood Watch, Bloodmyst Isle" },
    [107] = { x = 0.5028, y = 0.4097, worldX = -1810.2, worldY = 8032.1, continentID = 530, node = "Nagrand - PvP - Attack Run Start 1 " },
    [108] = { x = 0.5520, y = 0.5945, worldX = -2987.2, worldY = 3872.8, continentID = 530, node = "Allerian Stronghold, Terokkar Forest" },
    [109] = { x = 0.3494, y = 0.4527, worldX = 4157.6, worldY = 2959.7, continentID = 530, node = "The Stormspire, Netherstorm" },
    [110] = { x = 0.9649, y = 0.6316, worldX = 9375.2, worldY = -7165.9, continentID = 530, node = "Silvermoon City" },
    [111] = { x = 0.4172, y = 0.6380, worldX = -1837.2, worldY = 5301.9, continentID = 530, node = "Shattrath, Terokkar Forest" },
    [122] = { x = 0.2526, y = 0.4838, worldX = 13008.4, worldY = -6911.8, continentID = 530, node = "Quest - Sunwell Daily - Dead Scar Bombing - Start" },
    -- world map 571
    [114] = { x = 0.3726, y = 0.4630, worldX = 3465.7, worldY = 5901.8, continentID = 571, node = "Amber Ledge, Borean (To Beryl)" },
    [115] = { x = 0.5535, y = 0.2918, worldX = 3505.3, worldY = 1990.8, continentID = 571, node = "Quest - Stars' Rest -> Wintergarde" },
    [116] = { x = 0.8708, y = 0.7466, worldX = 2468.8, worldY = -5029.8, continentID = 571, node = "Fort Wildervar, Howling Fjord" },
    [117] = { x = 0.5784, y = 0.6067, worldX = 784.9, worldY = -5066.2, continentID = 571, node = "Transport, Howling Fjord" },
    [118] = { x = 0.6601, y = 0.9094, worldX = 6667.0, worldY = -258.7, continentID = 571, node = "Frosthold, The Storm Peaks" },
    [119] = { x = 0.9685, y = 0.2794, worldX = 4474.8, worldY = 5712.1, continentID = 571, node = "Bor'gorok Outpost, Borean Tundra" },
    [120] = { x = 0.5070, y = 0.6540, worldX = 7793.9, worldY = -2810.1, continentID = 571, node = "Camp Tunka'lo, The Storm Peaks" },
    [121] = { x = 0.9263, y = 0.7319, worldX = 4585.0, worldY = -4254.7, continentID = 571, node = "Westfall Brigade, Grizzly Hills" },
    [123] = { x = 0.5569, y = 0.9824, worldX = 4612.2, worldY = 1406.6, continentID = 571, node = "Fordragon Hold, Dragonblight" },
    [127] = { x = 0.8572, y = 0.1020, worldX = 4946.7, worldY = 1165.9, continentID = 571, node = "Kor'kron Vanguard, Dragonblight" },
    [170] = { x = 0.9416, y = 0.8523, worldX = 8472.5, worldY = -336.0, continentID = 571, node = "Bouldercrag's Refuge, The Storm Peaks" },
    -- world map 646
    [207] = { x = 0.4627, y = 0.6531, worldX = 1222.7, worldY = -279.0, continentID = 646, node = "Quest Path 2374: Deeopholm Test Copy" },
    -- world map 870
    [371] = { x = 0.2682, y = 0.5082, worldX = 2403.9, worldY = -2097.2, continentID = 870, node = "Quest Path 2837: Quest - Jade Forest: (DLA) - Dawnblossom to Jade Mines" },
    [376] = { x = 0.4359, y = 0.6883, worldX = -44.7, worldY = -22.2, continentID = 870, node = "Quest Path 2955: Quest - Valley of the Four Winds (Flyback: Chen B) PRK" },
    [379] = { x = 0.6450, y = 0.8547, worldX = 2927.2, worldY = -509.2, continentID = 870, node = "Honeydew Village, Jade Forest" },
    [388] = { x = 0.6411, y = 0.9776, worldX = 2103.4, worldY = 1463.8, continentID = 870, node = "Westwind Rest, Kun-Lai Summit" },
    [418] = { x = 0.5023, y = 0.2889, worldX = -1680.0, worldY = 1593.7, continentID = 870, node = "Quest Path 2962: Quest - Valley of the Four Winds (Flyback: Horde B) PRK" },
    [422] = { x = 0.3486, y = 0.5582, worldX = 172.7, worldY = 3152.2, continentID = 870, node = "Klaxxi'vess, Dread Wastes" },
    [433] = { x = 0.2266, y = 0.7249, worldX = 1418.6, worldY = -487.7, continentID = 870, node = "Grookin Hill, Jade Forest" },
    [507] = { x = 0.7923, y = 0.4188, worldX = 5753.8, worldY = 1255.6, continentID = 870, node = "Beeble's Wreck, Isle Of Giants" },
    [554] = { x = 0.5193, y = 0.4817, worldX = -597.6, worldY = -5239.5, continentID = 870, node = "Quest Path 3886: Timeless Isle 5.4 - Vignette - Source of Water - Bubble Down (RKS) [REUSEME]" },
    [1530] = { x = 0.1259, y = 0.8651, worldX = 1690.1, worldY = 304.0, continentID = 870, node = "Binan Village, Kun-Lai Summit" },
    -- world map 1116
    [525] = { x = 0.5608, y = 0.2168, worldX = 5988.7, worldY = 6180.9, continentID = 1116, node = "Wor'gol, Frostfire Ridge" },
    [534] = { x = 0.7184, y = 0.1273, worldX = 3418.8, worldY = 1040.2, continentID = 1116, node = "Zangarra, Talador" },
    [535] = { x = 0.1057, y = 0.6149, worldX = 4008.9, worldY = 2166.9, continentID = 1116, node = "Frostwolf Overlook, Talador" },
    [539] = { x = 0.4607, y = 0.5939, worldX = 602.7, worldY = -1710.4, continentID = 1116, node = "Path of the Light, Shadowmoon Valley" },
    [542] = { x = 0.1031, y = 0.9423, worldX = 966.9, worldY = -1029.7, continentID = 1116, node = "Shadowmoon Valley 6.0 - Observatory (JP3)" },
    [543] = { x = 0.5750, y = 0.6410, worldX = 6456.1, worldY = -174.8, continentID = 1116, node = "Wildwood Wash, Gorgrond" },
    [550] = { x = 0.7206, y = 0.9104, worldX = 2196.8, worldY = 4141.9, continentID = 1116, node = "Quest Path 4269: Draenor Zone Breadcrumb - Shadowmoon Garrison > Nagrand Start Loc (ELM)" },
    [588] = { x = 0.1061, y = 0.4065, worldX = 5356.2, worldY = -3942.2, continentID = 1116, node = "Warspear, Ashran" },
    -- world map 1220
    [634] = { x = 0.5982, y = 0.7208, worldX = 2862.9, worldY = 851.0, continentID = 1220, node = "Quest Path 5263: Stormheim: (DLA) - Valdisdall -> Greywatch (Spell Taxi)" },
    [641] = { x = 0.9688, y = 0.4474, worldX = 1406.1, worldY = 7140.7, continentID = 1220, node = "Challiane's Terrace, Azsuna" },
    [646] = { x = 0.3338, y = 0.1612, worldX = -860.8, worldY = 4296.0, continentID = 1220, node = "Dalaran" },
    [650] = { x = 0.3935, y = 0.2997, worldX = 5108.3, worldY = 5570.6, continentID = 1220, node = "Felbane Camp, Highmountain" },
    [680] = { x = 0.7751, y = 0.0026, worldX = 576.4, worldY = 6644.0, continentID = 1220, node = "Azurewing Repose, Azsuna" },
    [739] = { x = 0.2782, y = 0.3646, worldX = 4634.3, worldY = 5339.4, continentID = 1220, node = "Trueshot Lodge, Highmountain" },
    [790] = { x = 0.4592, y = 0.3825, worldX = -3362.3, worldY = 4823.0, continentID = 1220, node = "Eye of Azshara, Azsuna" },
    [1187] = { x = 0.4379, y = 0.4462, worldX = -117.8, worldY = 6891.2, continentID = 1220, node = "Illidari Stand, Azsuna" },
    -- world map 1642
    [862] = { x = 0.7218, y = 0.4484, worldX = -2692.8, worldY = 1915.1, continentID = 1642, node = "Xibala, Zuldazar" },
    [863] = { x = 0.7806, y = 0.3894, worldX = 793.2, worldY = 1400.7, continentID = 1642, node = "Zul'jan, Nazmir" },
    [864] = { x = 0.9780, y = 0.7614, worldX = -104.0, worldY = 1502.5, continentID = 1642, node = "Garden of the Loa, Zuldazar" },
    [1165] = { x = 0.4121, y = 0.5165, worldX = -1036.0, worldY = 756.6, continentID = 1642, node = "The Great Seal" },
    -- world map 1643
    [895] = { x = 0.8291, y = 0.7708, worldX = -1786.5, worldY = -729.4, continentID = 1643, node = "Freehold, Tiragarde Sound" },
    [896] = { x = 0.3479, y = 0.5513, worldX = -66.3, worldY = 2141.2, continentID = 1643, node = "Fallhaven, Drustvar" },
    [942] = { x = 0.9307, y = 0.5210, worldX = 1641.3, worldY = 385.9, continentID = 1643, node = "Wolf's Den, Tiragarde Sound" },
    [1161] = { x = 0.4450, y = 0.2682, worldX = 801.1, worldY = 252.2, continentID = 1643, node = "Firebreaker Expedition, Tiragarde Sound" },
    [1169] = { x = 0.9199, y = 0.3799, worldX = -80.0, worldY = -2648.4, continentID = 1643, node = "Tol Dagor, Tiragarde Sound" },
    [1462] = { x = 0.2562, y = 0.7360, worldX = 3282.0, worldY = 4900.5, continentID = 1643, node = "Prospectus Bay, Mechagon" },
    -- world map 1669
    [830] = { x = 0.6735, y = 0.5548, worldX = 985.8, worldY = 1711.9, continentID = 1669, node = "Krokul Hovel, Krokuun" },
    [882] = { x = 0.7491, y = 0.5286, worldX = 4995.3, worldY = 9823.6, continentID = 1669, node = "Quest Path 6175: 7.3 Argus - Isle 2 - Alleria Arc - Alleria Shadow Ball Taxi (JAK)" },
    [885] = { x = 0.5052, y = 0.7296, worldX = -2934.8, worldY = 8798.4, continentID = 1669, node = "Hope's Landing, Antoran Wastes" },
    -- world map 1718
    [1355] = { x = 0.2495, y = 0.7420, worldX = 2077.9, worldY = -1566.3, continentID = 1718, node = "Kelya's Grave, Nazjatar" },
    -- world map 2222
    [1525] = { x = 0.8409, y = 0.7075, worldX = -3499.1, worldY = 5435.5, continentID = 2222, node = "TEMP, 9.0, Zone, Revendreth" },
    [1536] = { x = 0.6766, y = 0.5268, worldX = 1974.7, worldY = -2691.8, continentID = 2222, node = "Bleak Redoubt, Maldraxxus" },
    [1543] = { x = 0.4596, y = 0.4433, worldX = 4464.5, worldY = 6831.6, continentID = 2222, node = "Progenitor Console" },
    [1565] = { x = 0.1761, y = 0.6852, worldX = -5196.7, worldY = -573.4, continentID = 2222, node = "TEMP, 9.0, Zone, Ardenweald" },
    [1569] = { x = 0.7623, y = 0.3697, worldX = -4251.7, worldY = -3886.2, continentID = 2222, node = "9.0, Zone, Bastion" },
    [1961] = { x = 0.2390, y = 0.6507, worldX = 3270.7, worldY = 5739.2, continentID = 2222, node = "Keeper's Respite" },
    -- world map 2374
    [1970] = { x = 0.6504, y = 0.3561, worldX = -4213.0, worldY = 684.6, continentID = 2374, node = "Haven, Zereth Mortis" },
    -- world map 2444
    [2022] = { x = 0.5683, y = 0.7582, worldX = 2348.9, worldY = -1394.9, continentID = 2444, node = "Rebuff Lookout, The Waking Shores" },
    [2023] = { x = 0.5837, y = 0.2888, worldX = -1525.8, worldY = 4634.5, continentID = 2444, node = "Quest Path 8635: 10.0 Pre-Prod - Grasslands - Dragonsmeet to Emerald Gardens (JLW)" },
    [2024] = { x = 0.6082, y = 0.3710, worldX = -5341.6, worldY = 1454.6, continentID = 2444, node = "Azure Archives, Azure Span" },
    [2025] = { x = 0.9364, y = 0.4681, worldX = -2114.7, worldY = -1620.6, continentID = 2444, node = "Theron's Watch, Azure Span" },
    [2112] = { x = 0.6791, y = 0.4447, worldX = -10.0, worldY = -844.2, continentID = 2444, node = "Valdrakken, Thaldraszus" },
    [2151] = { x = 0.5918, y = 0.3574, worldX = 6407.7, worldY = -2560.3, continentID = 2444, node = "Morqut Village, The Forbidden Reach" },
    [2239] = { x = 0.3421, y = 0.9639, worldX = -1116.7, worldY = 5148.2, continentID = 2444, node = "Quest Path 8851: 10.0 Plains - Emerald Hub - Taxi Down to Portal Grove (RMV)" },
    -- world map 2454
    [2133] = { x = 0.5479, y = 0.5557, worldX = -324.6, worldY = 2032.0, continentID = 2454, node = "Loamm, Zaralek Cavern" },
    -- world map 2548
    [2200] = { x = 0.6241, y = 0.5106, worldX = -1716.3, worldY = 7074.1, continentID = 2548, node = "Central Encampment, The Emerald Dream" },
    -- world map 2552
    [2271] = { x = 0.7853, y = 0.3822, worldX = 985.5, worldY = -1847.6, continentID = 2552, node = "Freywold Village, Isle of Dorn" },
    [2339] = { x = 0.5104, y = 0.4476, worldX = 2585.4, worldY = -2473.3, continentID = 2552, node = "Dornogal, Isle of Dorn" },
    -- world map 2601
    [2213] = { x = 0.4476, y = 0.5383, worldX = -2149.6, worldY = -975.3, continentID = 2601, node = "The Burrows, Azj-Kahet" },
    [2255] = { x = 0.5114, y = 0.2320, worldX = -796.0, worldY = 876.1, continentID = 2601, node = "Wildcamp Or'lay, Azj-Kahet" },
    [2272] = { x = 0.9975, y = 0.1848, worldX = -593.3, worldY = -1446.6, continentID = 2601, node = "Weaver's Lair, Azj-Kahet" },
    [2273] = { x = 0.8010, y = 0.5439, worldX = 1552.8, worldY = 10.9, continentID = 2601, node = "Lightspark, Hallowfall" },
    -- world map 2657
    [2298] = { x = 0.2365, y = 0.5073, worldX = -2843.1, worldY = -396.6, continentID = 2657, node = "Grand Rampart" },
    -- world map 2694
    [2480] = { x = 0.5840, y = 0.7376, worldX = -420.8, worldY = -2006.5, continentID = 2694, node = "Quest Path 10497: 12.0 Z3 - Legends - Shrine 01 - Exit Path - (LWB)" },
    -- world map 2706
    [2346] = { x = 0.4620, y = 0.4293, worldX = 65.6, worldY = 535.8, continentID = 2706, node = "The Incontinental Hotel" },
    -- world map 2735
    [2352] = { x = 0.2759, y = 0.5668, worldX = 3770.8, worldY = -119.5, continentID = 2735, node = "Entrance Portal, Founder's Point" },
    -- world map 2736
    [2351] = { x = 0.5114, y = 0.5481, worldX = 2011.7, worldY = 128.8, continentID = 2736, node = "Entrance Gate, Razorwind Shores" },
    -- world map 2738
    [2371] = { x = 0.6084, y = 0.7020, worldX = -140.3, worldY = -570.5, continentID = 2738, node = "Eco-Dome: Rhovan, K'aresh" },
    [2472] = { x = 0.1035, y = 0.3470, worldX = -636.4, worldY = 6.3, continentID = 2738, node = "Tazavesh, K'aresh" },
    -- world map 2771
    [2405] = { x = 0.5890, y = 0.3690, worldX = 1661.9, worldY = 1050.3, continentID = 2771, node = "The Ingress, Voidstorm" },
    [2444] = { x = 0.7985, y = 0.3822, worldX = 2975.9, worldY = 250.4, continentID = 2771, node = "Masters' Perch, Voidstorm" },
    -- world map 2916
    [2509] = { x = 0.6217, y = 0.4432, worldX = 5028.2, worldY = -10316.6, continentID = 2916, node = "Amani Foothold, Vaults of Atal'Utek" },
    -- world map 3047
    [2599] = { x = 0.1602, y = 0.6080, worldX = -3848.8, worldY = 445.9, continentID = 3047, node = "Umbral Base Camp" },
    -- world map 3075
    [2600] = { x = 0.8290, y = 0.4667, worldX = -2180.0, worldY = -1709.0, continentID = 3075, node = "Umbral Base Camp" },
}
