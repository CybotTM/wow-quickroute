-- Hearthstone inn positions, not exact per-character landing coordinates.
-- Sources and conservative exclusions: docs/data/hearthstone-locations.md.
-- AreaTable/UiMap: retail 12.1.0.69587. Names are localized by C_Map.GetAreaInfo.
-- Never infer uniqueness by faction, level, current zone, or quest progress.
-- Explicit defaults use area IDs as localized name aliases for a modern point.
local ADDON_NAME, QR = ...

QR.HearthstoneLocations = {
    { areaID = 42, mapID = 47, x = 0.7387, y = 0.4440 }, -- Darkshire
    { areaID = 69, ambiguous = true }, -- Lakeshire
    { areaID = 108, mapID = 52, x = 0.5286, y = 0.5371 }, -- Sentinel Hill
    { areaID = 147, mapID = 48, x = 0.8191, y = 0.6460 }, -- The Farstrider Lodge
    { areaID = 186, ambiguous = true }, -- Dolanaar
    { areaID = 320, ambiguous = true }, -- Refuge Pointe
    { areaID = 362, mapID = 1, x = 0.5161, y = 0.4165 }, -- Razor Hill
    { areaID = 380, ambiguous = true }, -- The Crossroads
    { areaID = 392, ambiguous = true }, -- Ratchet
    { areaID = 415, mapID = 63, x = 0.3700, y = 0.4917 }, -- Astranaar
    { areaID = 513, ambiguous = true }, -- Theramore Isle
    { areaID = 608, mapID = 66, x = 0.6626, y = 0.0664 }, -- Nijel's Point
    { areaID = 657, mapID = 51, x = 0.2900, y = 0.3260 }, -- The Harborage
    { areaID = 1438, ambiguous = true }, -- Nethergarde Keep
    { areaID = 1598, ambiguous = true }, -- Grol'dom Farm UNUSED
    { areaID = 1704, mapID = 10, x = 0.5627, y = 0.4004 }, -- Grol'dom Farm
    { areaID = 2101, mapID = 48, x = 0.3548, y = 0.4844 }, -- Stoutlager Inn
    { areaID = 2102, mapID = 27, x = 0.5447, y = 0.5081 }, -- Thunderbrew Distillery
    { areaID = 2104, mapID = 56, x = 0.1066, y = 0.6102 }, -- Deepwater Tavern
    { areaID = 2255, mapID = 83, x = 0.5984, y = 0.5117 }, -- Everlook
    { areaID = 2268, ambiguous = true }, -- Light's Hope Chapel
    { areaID = 3462, mapID = 2395, x = 0.4620, y = 0.4600, isDefault = true }, -- Fairbreeze name alias: modern default
    { areaID = 3538, mapID = 100, x = 0.5420, y = 0.6360 }, -- Honor Hold
    { areaID = 3552, mapID = 100, x = 0.2323, y = 0.3650 }, -- Temple of Telhamat
    { areaID = 3584, mapID = 106, x = 0.5584, y = 0.5980 }, -- Blood Watch
    { areaID = 3703, ambiguous = true }, -- Shattrath City
    { areaID = 3745, ambiguous = true }, -- Wildhammer Stronghold
    { areaID = 3766, mapID = 102, x = 0.4185, y = 0.2620 }, -- Orebor Harborage
    { areaID = 3772, mapID = 105, x = 0.3580, y = 0.6390 }, -- Sylvanaar
    { areaID = 3898, mapID = 111, x = 0.5635, y = 0.8155 }, -- Scryer's Tier
    { areaID = 3918, mapID = 105, x = 0.6100, y = 0.6810 }, -- Toshley's Station
    { areaID = 3951, mapID = 105, x = 0.6285, y = 0.3830 }, -- Evergrove
    { areaID = 3981, ambiguous = true }, -- Valgarde
    { areaID = 4108, mapID = 114, x = 0.5712, y = 0.1872 }, -- Fizzcrank Airstrip
    { areaID = 4177, mapID = 115, x = 0.7750, y = 0.5150 }, -- Wintergarde Keep
    { areaID = 4204, mapID = 116, x = 0.3197, y = 0.6022 }, -- Amberpine Lodge
    { areaID = 4361, ambiguous = true }, -- Light's Hope Chapel
    { areaID = 4379, ambiguous = true }, -- Valgarde
    { areaID = 4380, mapID = 117, x = 0.3086, y = 0.4145 }, -- Westguard Inn
    { areaID = 4659, ambiguous = true }, -- Lor'danel
    { areaID = 4805, mapID = 66, x = 0.5668, y = 0.5001 }, -- Karnum's Glade
    { areaID = 4821, mapID = 76, x = 0.5702, y = 0.5029 }, -- Bilgewater Harbor
    { areaID = 4882, mapID = 78, x = 0.5531, y = 0.6226 }, -- Marshal's Stand
    { areaID = 4939, mapID = 65, x = 0.3150, y = 0.6062 }, -- Farwatcher's Glen
    { areaID = 5005, mapID = 205, x = 0.4913, y = 0.4195 }, -- Silver Tide Hollow
    { areaID = 5012, mapID = 201, x = 0.4520, y = 0.2340 }, -- The Briny Cutter
    { areaID = 5024, mapID = 69, x = 0.5102, y = 0.1797 }, -- Dreamer's Rest
    { areaID = 5049, mapID = 64, x = 0.7652, y = 0.7474 }, -- Speedbarge Bar
    { areaID = 5056, mapID = 201, x = 0.3883, y = 0.3162 }, -- The Immortal Coil
    { areaID = 5058, mapID = 201, x = 0.6390, y = 0.5990 }, -- Deepmist Grotto
    { areaID = 5072, mapID = 69, x = 0.4614, y = 0.4524 }, -- Feathermoon Stronghold
    { areaID = 5073, mapID = 65, x = 0.5900, y = 0.5640 }, -- Fallowmere Inn
    { areaID = 5084, ambiguous = true }, -- Surwich
    { areaID = 5117, mapID = 10, x = 0.6252, y = 0.1665 }, -- Nozzlepot's Outpost
    { areaID = 5320, mapID = 50, x = 0.5321, y = 0.6692 }, -- Fort Livingston
    { areaID = 5458, mapID = 51, x = 0.7175, y = 0.1398 }, -- Bogpaddle
    { areaID = 5496, mapID = 15, x = 0.6588, y = 0.3585 }, -- Fuselight
    { areaID = 5564, mapID = 15, x = 0.2069, y = 0.5608 }, -- Dragon's Mouth
    { areaID = 5628, mapID = 32, x = 0.3921, y = 0.6602 }, -- Iron Summit
    { areaID = 5633, ambiguous = true }, -- Terrace of the Augurs
    { areaID = 5637, mapID = 37, x = 0.4377, y = 0.6580 }, -- Lion's Pride Inn
    { areaID = 5645, mapID = 77, x = 0.4475, y = 0.2917 }, -- Whisperwind Grove
    { areaID = 5649, mapID = 77, x = 0.4398, y = 0.6194 }, -- Wildheart Point
    { areaID = 5728, mapID = 94, x = 0.4810, y = 0.4770 }, -- Falconwing Inn
    { areaID = 5776, ambiguous = true }, -- Wildhammer Stronghold
    { areaID = 5836, ambiguous = true }, -- Forest Heart
    { areaID = 6042, ambiguous = true }, -- Theramore Isle
    { areaID = 6502, ambiguous = true }, -- Theramore Isle
    { areaID = 6980, ambiguous = true }, -- Shattrath City
    { areaID = 7420, ambiguous = true }, -- Shattrath City
    { areaID = 7477, ambiguous = true }, -- The Crossroads
    { areaID = 7659, ambiguous = true }, -- Heroes' Rest
    { areaID = 7928, mapID = 680, x = 0.3656, y = 0.4693 }, -- Shal'Aran
    { areaID = 8065, ambiguous = true }, -- The Retreat
    { areaID = 8357, ambiguous = true }, -- Light's Hope Chapel
    { areaID = 8409, ambiguous = true }, -- Heroes' Rest
    { areaID = 8610, mapID = 71, x = 0.5259, y = 0.2700 }, -- The Road Warrior
    { areaID = 8611, ambiguous = true }, -- The Oasis Inn
    { areaID = 8612, mapID = 102, x = 0.7850, y = 0.6300 }, -- Firefly Tavern
    { areaID = 8613, mapID = 109, x = 0.3201, y = 0.6439 }, -- Rusty Rocket Tavern
    { areaID = 8615, mapID = 210, x = 0.4093, y = 0.7379 }, -- The Salty Sailor Tavern
    { areaID = 8756, ambiguous = true }, -- Ratchet
    { areaID = 8762, ambiguous = true }, -- The Crossroads
    { areaID = 8839, ambiguous = true }, -- Theramore Isle
    { areaID = 9598, ambiguous = true }, -- The Great Seal
    { areaID = 9747, ambiguous = true }, -- Refuge Pointe
    { areaID = 10067, ambiguous = true }, -- Lor'danel
    { areaID = 10230, ambiguous = true }, -- Lor'danel
    { areaID = 10237, ambiguous = true }, -- Lor'danel
    { areaID = 10310, ambiguous = true }, -- Lor'danel
    { areaID = 11381, mapID = 1533, x = 0.5315, y = 0.4688 }, -- Hero's Rest
    { areaID = 11473, mapID = 1533, x = 0.4807, y = 0.7300 }, -- Aspirant's Rest
    { areaID = 12858, ambiguous = true }, -- Heart of the Forest
    { areaID = 12876, ambiguous = true }, -- Seat of the Primus
    { areaID = 12923, ambiguous = true }, -- Heart of the Forest
    { areaID = 12953, ambiguous = true }, -- Lakeshire
    { areaID = 13187, ambiguous = true }, -- Seat of the Primus
    { areaID = 13388, ambiguous = true }, -- Heart of the Forest
    { areaID = 13632, ambiguous = true }, -- Haven
    { areaID = 13727, ambiguous = true }, -- Ruby Lifeshrine
    { areaID = 13764, ambiguous = true }, -- Maruukai
    { areaID = 13862, ambiguous = true }, -- Valdrakken
    { areaID = 14434, mapID = 2024, x = 0.3737, y = 0.6243 }, -- The Conjured Biscuit Inn
    { areaID = 14448, ambiguous = true }, -- Ruby Lifeshrine
    { areaID = 14476, ambiguous = true }, -- Maruukai
    { areaID = 14755, mapID = 2255, x = 0.5698, y = 0.3883 }, -- The Weaver's Lair
    { areaID = 14771, mapID = 2339, x = 0.4482, y = 0.4649 }, -- Dornogal
    { areaID = 14796, mapID = 2214, x = 0.4794, y = 0.3216 }, -- Gundargaz
    { areaID = 14917, ambiguous = true }, -- Mereldar
    { areaID = 15073, ambiguous = true }, -- Refuge Pointe
    { areaID = 15149, ambiguous = true }, -- Mereldar
    { areaID = 15545, ambiguous = true }, -- Mereldar
    { areaID = 15733, ambiguous = true }, -- Refuge Pointe
    { areaID = 15995, mapID = 2395, x = 0.4620, y = 0.4600, isDefault = true }, -- Fairbreeze Village: modern default
    { areaID = 16094, ambiguous = true }, -- Augurs' Terrace
    { areaID = 16179, ambiguous = true }, -- Augurs' Terrace
    { areaID = 16326, ambiguous = true }, -- Augurs' Terrace
    { areaID = 16445, ambiguous = true }, -- Refuge Pointe
    { areaID = 16645, mapID = 2393, x = 0.5629, y = 0.7035 }, -- Wayfarer's Rest
}
