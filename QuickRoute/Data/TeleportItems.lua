-- TeleportItems.lua
-- Comprehensive database of teleport items, toys, and spells
local ADDON_NAME, QR = ...

-------------------------------------------------------------------------------
-- Teleport Types Enum
-------------------------------------------------------------------------------
QR.TeleportTypes = {
    HEARTHSTONE = "hearthstone",
    TOY = "toy",
    ITEM = "item",
    SPELL = "spell",
    ENGINEER = "engineer",
}

-------------------------------------------------------------------------------
-- Teleport Items Data
-- Each entry: itemID/spellID -> { name, destination, mapID, x, y, cooldown, type, faction, etc. }
-------------------------------------------------------------------------------
QR.TeleportItemsData = {
    -- =========================================================================
    -- HEARTHSTONES
    -- =========================================================================
    [6948] = {
        name = "Hearthstone",
        destination = "Bound Location",
        mapID = nil,  -- Dynamic, based on binding
        cooldown = 1800,  -- 30 minutes (reduced by talents/items)
        type = QR.TeleportTypes.ITEM,  -- Regular item in bags
        faction = "both",
        isDynamic = true,
    },
    [64488] = {
        name = "The Innkeeper's Daughter",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [140192] = {
        name = "Dalaran Hearthstone",
        destination = "Dalaran (Legion)",
        mapID = 627,  -- Dalaran (Broken Isles)
        x = 0.5044,
        y = 0.5313,
        cooldown = 1200,  -- 20 minutes
        type = QR.TeleportTypes.TOY,
        faction = "both",
        acquisition = "Quest reward from initial Legion intro questline",
    },
    [110560] = {
        name = "Garrison Hearthstone",
        destination = "Garrison",
        mapID = nil,  -- Dynamic, depends on garrison level/faction
        cooldown = 1200,  -- 20 minutes
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
        acquisition = "Quest reward from Warlords of Draenor intro questline",
    },

    -- =========================================================================
    -- HEARTHSTONE TOY VARIANTS (cosmetic, all teleport to bound location)
    -- =========================================================================
    -- Covenant Hearthstones (Shadowlands) - cosmetic variants, NOT sanctum teleports
    [184353] = {
        name = "Kyrian Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [183716] = {
        name = "Venthyr Sinstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [180290] = {
        name = "Night Fae Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [182773] = {
        name = "Necrolord Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [188952] = {
        name = "Dominated Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    -- Seasonal / Event Hearthstones
    [54452] = {
        name = "Ethereal Portal",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [93672] = {
        name = "Dark Portal",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [162973] = {
        name = "Greatfather Winter's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [163045] = {
        name = "Headless Horseman's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [165669] = {
        name = "Lunar Elder's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [165670] = {
        name = "Peddlefeet's Lovely Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [165802] = {
        name = "Noble Gardener's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [166746] = {
        name = "Fire Eater's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [166747] = {
        name = "Brewfest Reveler's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    -- Promotion / Shop / Achievement Hearthstones
    [168907] = {
        name = "Holographic Digitalization Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [172179] = {
        name = "Eternal Traveler's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [190196] = {
        name = "Enlightened Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [190237] = {
        name = "Broker Translocation Matrix",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [193588] = {
        name = "Timewalker's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [200630] = {
        name = "Ohn'ir Windsage's Hearthstone",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [206195] = {
        name = "Path of the Naaru",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [212337] = {
        name = "Stone of the Hearth",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },

    -- =========================================================================
    -- KIRIN TOR RINGS
    -- =========================================================================
    -- Base Tier
    [40585] = {
        name = "Signet of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [40586] = {
        name = "Band of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,  -- Dalaran (Northrend)
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [44934] = {
        name = "Loop of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [44935] = {
        name = "Ring of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    -- Inscribed Tier
    [45688] = {
        name = "Inscribed Band of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [45689] = {
        name = "Inscribed Loop of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [45690] = {
        name = "Inscribed Ring of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [45691] = {
        name = "Inscribed Signet of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    -- Etched Tier
    [48954] = {
        name = "Etched Band of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [48955] = {
        name = "Etched Loop of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [48956] = {
        name = "Etched Ring of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [48957] = {
        name = "Etched Signet of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    -- Runed Tier
    [51557] = {
        name = "Runed Signet of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [51558] = {
        name = "Runed Band of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [51559] = {
        name = "Runed Ring of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    [51560] = {
        name = "Runed Loop of the Kirin Tor",
        destination = "Dalaran (Northrend)",
        mapID = 125,
        x = 0.4947,
        y = 0.4709,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },
    -- Empowered Ring (Legion Dalaran)
    [139599] = {
        name = "Empowered Ring of the Kirin Tor",
        destination = "Dalaran (Legion)",
        mapID = 627,
        x = 0.5044,
        y = 0.5313,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
    },

    -- =========================================================================
    -- TABARDS
    -- =========================================================================
    [46874] = {
        name = "Argent Crusader's Tabard",
        destination = "Argent Tournament Grounds",
        mapID = 118,  -- Icecrown
        x = 0.7435,
        y = 0.1959,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 19,
        faction = "both",
        requiredRep = { faction = "Argent Crusade", level = "Exalted" },
        acquisition = "Exalted with Argent Crusade + Champion of faction at Argent Tournament",
        vendor = {
            name = "Dame Evniki Kapsalis",
            mapID = 118,  -- Icecrown
            x = 0.6938,
            y = 0.2310,
            location = "Argent Tournament Grounds",
        },
    },
    [63378] = {
        name = "Hellscream's Reach Tabard",
        destination = "Tol Barad Peninsula",
        mapID = 773,  -- Tol Barad Peninsula
        x = 0.5553,
        y = 0.7869,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 19,
        faction = "Horde",
        requiredRep = { faction = "Hellscream's Reach", level = "Exalted" },
        acquisition = "Exalted with Hellscream's Reach (Tol Barad dailies)",
    },
    [63379] = {
        name = "Baradin's Wardens Tabard",
        destination = "Tol Barad Peninsula",
        mapID = 773,
        x = 0.7272,
        y = 0.5793,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 19,
        faction = "Alliance",
        requiredRep = { faction = "Baradin's Wardens", level = "Exalted" },
        acquisition = "Exalted with Baradin's Wardens (Tol Barad dailies)",
    },

    -- =========================================================================
    -- GUILD CLOAKS (Guild vendor, Honored rep)
    -- =========================================================================
    [63206] = {
        name = "Wrap of Unity",
        destination = "Stormwind City", mapID = 84,
        x = 0.4965, y = 0.8725,
        cooldown = 14400, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Alliance",
    },
    [63207] = {
        name = "Wrap of Unity",
        destination = "Orgrimmar", mapID = 85,
        x = 0.4690, y = 0.3870,
        cooldown = 14400, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Horde",
    },
    [65360] = {
        name = "Cloak of Coordination",
        destination = "Stormwind City", mapID = 84,
        x = 0.4965, y = 0.8725,
        cooldown = 14400, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Alliance",
    },
    [65274] = {
        name = "Cloak of Coordination",
        destination = "Orgrimmar", mapID = 85,
        x = 0.4690, y = 0.3870,
        cooldown = 14400, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Horde",
    },
    [63352] = {
        name = "Shroud of Cooperation",
        destination = "Stormwind City", mapID = 84,
        x = 0.4965, y = 0.8725,
        cooldown = 28800, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Alliance",
    },
    [63353] = {
        name = "Shroud of Cooperation",
        destination = "Orgrimmar", mapID = 85,
        x = 0.4690, y = 0.3870,
        cooldown = 28800, type = QR.TeleportTypes.ITEM, equipSlot = 15, faction = "Horde",
    },

    -- =========================================================================
    -- BRAWLER'S GUILD RINGS
    -- =========================================================================
    [95050] = {
        name = "The Brassiest Knuckle",
        destination = "Brawl'gar Arena",
        mapID = 85,  -- Orgrimmar (instanced arena)
        x = 0.4690, y = 0.3870,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Horde",
        acquisition = "Brawler's Guild Rank 4 (Horde)",
    },
    [95051] = {
        name = "The Brassiest Knuckle",
        destination = "Bizmo's Brawlpub",
        mapID = 84,  -- Stormwind City (instanced arena)
        x = 0.4965, y = 0.8725,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Alliance",
        acquisition = "Brawler's Guild Rank 4 (Alliance)",
    },
    [118908] = {
        name = "Pit Fighter's Punching Ring",
        destination = "Brawl'gar Arena",
        mapID = 85,
        x = 0.4690, y = 0.3870,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Horde",
        acquisition = "Brawler's Guild Rank 2 (Horde)",
    },
    [118907] = {
        name = "Pit Fighter's Punching Ring",
        destination = "Bizmo's Brawlpub",
        mapID = 84,
        x = 0.4965, y = 0.8725,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Alliance",
        acquisition = "Brawler's Guild Rank 2 (Alliance)",
    },
    [144392] = {
        name = "Pugilist's Powerful Punching Ring",
        destination = "Brawl'gar Arena",
        mapID = 85,
        x = 0.4690, y = 0.3870,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Horde",
        acquisition = "Brawler's Guild Rank 4, Legion (Horde)",
    },
    [144391] = {
        name = "Pugilist's Powerful Punching Ring",
        destination = "Bizmo's Brawlpub",
        mapID = 84,
        x = 0.4965, y = 0.8725,
        cooldown = 3600,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Alliance",
        acquisition = "Brawler's Guild Rank 4, Legion (Alliance)",
    },

    -- =========================================================================
    -- SPECIAL ITEMS
    -- =========================================================================
    [28585] = {
        name = "Ruby Slippers",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 3600,  -- 1 hour
        type = QR.TeleportTypes.ITEM,
        equipSlot = 8,
        faction = "both",
        isDynamic = true,
        acquisition = "Drop from The Big Bad Wolf (Opera event) in Karazhan",
    },
    [142298] = {
        name = "Astonishingly Scarlet Slippers",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 8,
        faction = "both",
        isDynamic = true,
        acquisition = "Drop from Opera: Wikket in Return to Karazhan",
    },
    [169064] = {
        name = "Mountebank's Colorful Cloak",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 86400,  -- 24 hours
        type = QR.TeleportTypes.ITEM,
        equipSlot = 15,
        faction = "both",
        isDynamic = true,
        acquisition = "Drop from Trixie Tazer in Operation: Mechagon",
    },
    [52251] = {
        name = "Jaina's Locket",
        destination = "Dalaran (Northrend)",
        mapID = 125,  -- Dalaran (Northrend)
        x = 0.4947,
        y = 0.4709,
        cooldown = 3600,  -- 1 hour
        type = QR.TeleportTypes.ITEM,
        faction = "both",
        acquisition = "Drop from heroic Lich King 25 in Icecrown Citadel",
    },
    [32757] = {
        name = "Blessed Medallion of Karabor",
        destination = "Black Temple",
        mapID = 104,  -- Shadowmoon Valley (Outland)
        x = 0.7107,
        y = 0.4613,
        cooldown = 900,  -- 15 minutes
        type = QR.TeleportTypes.ITEM,
        equipSlot = 2,
        faction = "both",
    },
    [50287] = {
        name = "Boots of the Bay",
        destination = "Booty Bay",
        mapID = 210,  -- Cape of Stranglethorn
        x = 0.4100,
        y = 0.7300,
        cooldown = 86400,  -- 24 hours
        type = QR.TeleportTypes.ITEM,
        equipSlot = 8,
        faction = "both",
        acquisition = "Kalu'ak Fishing Derby reward",
    },
    [142469] = {
        name = "Violet Seal of the Grand Magus",
        destination = "Karazhan",
        mapID = 42,  -- Deadwind Pass
        x = 0.4700,
        y = 0.7500,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "both",
        acquisition = "Vendor in Return to Karazhan",
    },
    [166560] = {
        name = "Captain's Signet of Command",
        destination = "Boralus Harbor",
        mapID = 1161,
        x = 0.7025,
        y = 0.1725,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Alliance",
        acquisition = "300 7th Legion Service Medals",
    },
    [166559] = {
        name = "Commander's Signet of Battle",
        destination = "Dazar'alor",
        mapID = 1165,
        x = 0.5020,
        y = 0.4080,
        cooldown = 1800,
        type = QR.TeleportTypes.ITEM,
        equipSlot = 11,
        faction = "Horde",
        acquisition = "Provisioner Mukra vendor",
    },
    [118663] = {
        name = "Relic of Karabor",
        destination = "Karabor, Shadowmoon Valley",
        mapID = 539,  -- Shadowmoon Valley (WoD)
        x = 0.3200,
        y = 0.3100,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.ITEM,
        faction = "Alliance",
        acquisition = "Vindicator Nuurem vendor, Shadowmoon Valley (WoD)",
    },
    [118662] = {
        name = "Bladespire Relic",
        destination = "Bladespire Citadel, Frostfire Ridge",
        mapID = 525,  -- Frostfire Ridge
        x = 0.2300,
        y = 0.3000,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.ITEM,
        faction = "Horde",
        acquisition = "Vendor in Frostfire Ridge (WoD)",
    },
    [243056] = {
        name = "Delver's Mana-Bound Ethergate",
        destination = "Dornogal",
        mapID = 2339,
        x = 0.4850,
        y = 0.5520,
        cooldown = 7200,  -- 2 hours
        type = QR.TeleportTypes.TOY,
        faction = "both",
        acquisition = "Delver's Bounty Tier 7 (War Within Season 3)",
    },

    -- =========================================================================
    -- ENGINEERING ITEMS
    -- =========================================================================
    [18984] = {
        name = "Dimensional Ripper - Everlook",
        destination = "Everlook, Winterspring",
        mapID = 83,  -- Winterspring
        x = 0.6006,
        y = 0.4955,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,  -- Can malfunction
    },
    [18986] = {
        name = "Ultrasafe Transporter: Gadgetzan",
        destination = "Gadgetzan, Tanaris",
        mapID = 71,  -- Tanaris
        x = 0.5187,
        y = 0.2887,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [30542] = {
        name = "Dimensional Ripper - Area 52",
        destination = "Area 52, Netherstorm",
        mapID = 109,  -- Netherstorm
        x = 0.3272,
        y = 0.6482,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [30544] = {
        name = "Ultrasafe Transporter: Toshley's Station",
        destination = "Toshley's Station, Blade's Edge Mountains",
        mapID = 105,  -- Blade's Edge Mountains
        x = 0.5318,
        y = 0.3494,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [48933] = {
        name = "Wormhole Generator: Northrend",
        destination = "Random Northrend Location",
        mapID = nil,  -- Random
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [87215] = {
        name = "Wormhole Generator: Pandaria",
        destination = "Random Pandaria Location",
        mapID = nil,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [112059] = {
        name = "Wormhole Centrifuge",
        destination = "Random Draenor Location",
        mapID = nil,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [151652] = {
        name = "Wormhole Generator: Argus",
        destination = "Random Argus Location",
        mapID = nil,
        cooldown = 14400,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [168807] = {
        name = "Wormhole Generator: Kul Tiras",
        destination = "Random Kul Tiras Location",
        mapID = nil,
        cooldown = 900,  -- 15 minutes
        type = QR.TeleportTypes.ENGINEER,
        faction = "Alliance",
        profession = "Engineering",
        isRandom = true,
    },
    [168808] = {
        name = "Wormhole Generator: Zandalar",
        destination = "Random Zandalar Location",
        mapID = nil,
        cooldown = 900,
        type = QR.TeleportTypes.ENGINEER,
        faction = "Horde",
        profession = "Engineering",
        isRandom = true,
    },
    [172924] = {
        name = "Wormhole Generator: Shadowlands",
        destination = "Random Shadowlands Location",
        mapID = nil,
        cooldown = 900,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [198156] = {
        name = "Wyrmhole Generator: Dragon Isles",
        destination = "Random Dragon Isles Location",
        mapID = nil,
        cooldown = 900,
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },
    [221966] = {
        name = "Wormhole Generator: Khaz Algar",
        destination = "Random Khaz Algar Location",
        mapID = nil,
        cooldown = 1800,  -- 30 minutes
        type = QR.TeleportTypes.ENGINEER,
        faction = "both",
        profession = "Engineering",
        isRandom = true,
    },

    -- =========================================================================
    -- TOYS (specific destinations)
    -- =========================================================================
    [95567] = {
        name = "Kirin Tor Beacon",
        destination = "Isle of Thunder (Kirin Tor)",
        mapID = 504,  -- Isle of Thunder
        x = 0.6300,
        y = 0.7300,
        cooldown = 600,  -- 10 minutes
        type = QR.TeleportTypes.TOY,
        faction = "Alliance",
        restriction = "Only works on Isle of Thunder or in Throne of Thunder",
    },
    [95568] = {
        name = "Sunreaver Beacon",
        destination = "Isle of Thunder (Sunreavers)",
        mapID = 504,  -- Isle of Thunder
        x = 0.3200,
        y = 0.3500,
        cooldown = 600,  -- 10 minutes
        type = QR.TeleportTypes.TOY,
        faction = "Horde",
        restriction = "Only works on Isle of Thunder or in Throne of Thunder",
    },
    [128353] = {
        name = "Admiral's Compass",
        destination = "Garrison Shipyard",
        mapID = nil,  -- Dynamic, garrison
        cooldown = 1200,  -- 20 minutes
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isDynamic = true,
    },
    [103678] = {
        name = "Time-Lost Artifact",
        destination = "Random location",
        mapID = nil,
        cooldown = 900,
        type = QR.TeleportTypes.TOY,
        equipSlot = 13,
        faction = "both",
        isRandom = true,
    },
    [37863] = {
        name = "Direbrew's Remote",
        destination = "Grim Guzzler, Blackrock Depths",
        mapID = 35,  -- Blackrock Depths (dungeon mapID approximation)
        x = 0.5000,
        y = 0.5000,
        cooldown = 3600,  -- 1 hour
        type = QR.TeleportTypes.TOY,
        faction = "both",
    },
    [142542] = {
        name = "Tome of Town Portal",
        destination = "Dalaran (Legion)",
        mapID = 627,
        x = 0.5044,
        y = 0.5313,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
    },
    [180817] = {
        name = "Cypher of Relocation",
        destination = "Haven, Zereth Mortis",
        mapID = 1970,  -- Zereth Mortis
        x = 0.3480,
        y = 0.5550,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
    },
    [140324] = {
        name = "Mobile Telemancy Beacon",
        destination = "Shal'Aran, Suramar",
        mapID = 680,  -- Suramar
        x = 0.3700,
        y = 0.4600,
        cooldown = 72000,  -- 20 hours
        type = QR.TeleportTypes.TOY,
        faction = "both",
        acquisition = "Honored with The Nightfallen",
    },
    [129276] = {
        name = "Beginner's Guide to Dimensional Rifting",
        destination = "Ley Line in Azsuna",
        mapID = 630,  -- Azsuna
        x = 0.3300,
        y = 0.4600,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.TOY,
        faction = "both",
        acquisition = "Veridis Fallon vendor in Azsuna",
    },
    [202046] = {
        name = "Lucky Tortollan Charm",
        destination = "Seekers' Vista, Stormsong Valley",
        mapID = 942,  -- Stormsong Valley
        x = 0.4100,
        y = 0.3600,
        cooldown = 3600,  -- 1 hour
        type = QR.TeleportTypes.TOY,
        faction = "both",
        acquisition = "Vendor for 50g",
    },
    -- Random destination toys
    [64457] = {
        name = "The Last Relic of Argus",
        destination = "Random location worldwide",
        mapID = nil,
        cooldown = 43200,  -- 12 hours
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isRandom = true,
        acquisition = "Archaeology (Draenei artifact)",
    },
    [136849] = {
        name = "Nature's Beacon",
        destination = "Random natural location",
        mapID = nil,
        cooldown = 60,  -- 1 minute
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isRandom = true,
        acquisition = "Originally Druid-only, now Warband",
    },
    [140493] = {
        name = "Adept's Guide to Dimensional Rifting",
        destination = "Random Broken Isles Ley Line",
        mapID = nil,
        cooldown = 14400,  -- 4 hours
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isRandom = true,
        acquisition = "Higher Dimensional Learning achievement",
    },
    [153004] = {
        name = "Unstable Portal Emitter",
        destination = "Random location",
        mapID = nil,
        cooldown = 1800,
        type = QR.TeleportTypes.TOY,
        faction = "both",
        isRandom = true,
        acquisition = "Drop from Vixx the Collector (Argus)",
    },
}

-------------------------------------------------------------------------------
-- Class Teleport Spells
-------------------------------------------------------------------------------
QR.ClassTeleportSpells = {
    -- Death Knight
    [50977] = {
        name = "Death Gate",
        destination = "Ebon Hold",
        mapID = 23,  -- Eastern Plaguelands (Ebon Hold entrance)
        x = 0.8390,
        y = 0.4990,
        cooldown = 60,
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "DEATHKNIGHT",
    },

    -- Monk
    [126892] = {
        name = "Zen Pilgrimage",
        destination = "Peak of Serenity / Temple of Five Dawns",
        mapID = 809,  -- Peak of Serenity
        x = 0.5000,
        y = 0.5000,
        cooldown = 60,
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "MONK",
    },

    -- Druid
    [18960] = {
        name = "Teleport: Moonglade",
        destination = "Moonglade",
        mapID = 80,  -- Moonglade
        x = 0.4396,
        y = 0.4544,
        cooldown = 0,  -- No cooldown
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "DRUID",
    },
    [193753] = {
        name = "Dreamwalk",
        destination = "Emerald Dreamway",
        mapID = 715,  -- Emerald Dreamway
        x = 0.5000,
        y = 0.5000,
        cooldown = 60,
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "DRUID",
    },

    -- Demon Hunter
    [204587] = {
        name = "Fel Retreat",
        destination = "Illidari Camp",
        mapID = nil,  -- Variable based on progression
        cooldown = 60,
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "DEMONHUNTER",
        isDynamic = true,
    },

    -- Shaman
    [556] = {
        name = "Astral Recall",
        destination = "Bound Location",
        mapID = nil,
        cooldown = 600,  -- 10 minutes
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "SHAMAN",
        isDynamic = true,
    },

    -- Evoker
    [368229] = {
        name = "Path of the Bronze",
        destination = "Valdrakken",
        mapID = 2112,  -- Valdrakken
        x = 0.5810,
        y = 0.3550,
        cooldown = 300,  -- 5 minutes
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        class = "EVOKER",
    },
}

-------------------------------------------------------------------------------
-- Racial Teleport Spells
-------------------------------------------------------------------------------
QR.RacialTeleportSpells = {
    -- Dark Iron Dwarf - Mole Machine (multiple destinations, use primary)
    [265225] = {
        name = "Mole Machine",
        destination = "Shadowforge City",
        mapID = 1584,  -- Blackrock Depths
        x = 0.3800,
        y = 0.3300,
        cooldown = 1800,  -- 30 minutes
        type = QR.TeleportTypes.SPELL,
        faction = "Alliance",
        race = "DarkIronDwarf",
    },

    -- Vulpera - Return to Camp
    [312372] = {
        name = "Return to Camp",
        destination = "Camp Location",
        mapID = nil,  -- Dynamic, wherever camp was placed
        cooldown = 3600,  -- 1 hour
        type = QR.TeleportTypes.SPELL,
        faction = "Horde",
        race = "Vulpera",
        isDynamic = true,
    },

    -- Nightborne - Teleport to Suramar
    [255661] = {
        name = "Cantrips",
        destination = "Suramar",
        mapID = 680,  -- Suramar
        x = 0.4386,
        y = 0.7350,
        cooldown = 0,
        type = QR.TeleportTypes.SPELL,
        faction = "Horde",
        race = "Nightborne",
    },
}

-------------------------------------------------------------------------------
-- General Teleport Spells (available to all players)
-------------------------------------------------------------------------------
QR.GeneralTeleportSpells = {
    -- Player Housing (Patch 11.2.7+)
    [1233637] = {
        name = "Teleport Home",
        destination = "Homestead",
        mapID = nil,  -- Dynamic, player's housing plot
        cooldown = 900,  -- 15 minutes
        type = QR.TeleportTypes.SPELL,
        faction = "both",
        isDynamic = true,
    },
}

-------------------------------------------------------------------------------
-- Mage Teleport Spells
-- Separated by faction for easier filtering
-------------------------------------------------------------------------------
QR.MageTeleports = {
    Alliance = {
        -- Vanilla
        [3561] = {
            name = "Teleport: Stormwind",
            destination = "Stormwind City",
            mapID = 84,
            x = 0.4965,
            y = 0.8725,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [3562] = {
            name = "Teleport: Ironforge",
            destination = "Ironforge",
            mapID = 87,
            x = 0.2730,
            y = 0.7330,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [3565] = {
            name = "Teleport: Darnassus",
            destination = "Darnassus",
            mapID = 89,
            x = 0.4100,
            y = 0.4710,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Burning Crusade
        [32271] = {
            name = "Teleport: Exodar",
            destination = "The Exodar",
            mapID = 103,
            x = 0.3970,
            y = 0.6247,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [49359] = {
            name = "Teleport: Theramore",
            destination = "Theramore Isle",
            mapID = 70,  -- Dustwallow Marsh
            x = 0.6675,
            y = 0.4869,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Cataclysm
        [88342] = {
            name = "Teleport: Tol Barad",
            destination = "Tol Barad Peninsula",
            mapID = 773,
            x = 0.7272,
            y = 0.5793,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Mists of Pandaria
        [132621] = {
            name = "Teleport: Vale of Eternal Blossoms",
            destination = "Shrine of Seven Stars",
            mapID = 390,  -- Vale of Eternal Blossoms
            x = 0.8470,
            y = 0.6260,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Warlords of Draenor
        [176242] = {
            name = "Teleport: Stormshield",
            destination = "Stormshield, Ashran",
            mapID = 622,  -- Stormshield
            x = 0.4406,
            y = 0.3453,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Battle for Azeroth
        [281403] = {
            name = "Teleport: Boralus",
            destination = "Boralus Harbor",
            mapID = 1161,
            x = 0.7025,
            y = 0.1725,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
    },

    Horde = {
        -- Vanilla
        [3563] = {
            name = "Teleport: Undercity",
            destination = "Undercity",
            mapID = 90,
            x = 0.6549,
            y = 0.4161,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [3566] = {
            name = "Teleport: Thunder Bluff",
            destination = "Thunder Bluff",
            mapID = 88,
            x = 0.2920,
            y = 0.2740,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [3567] = {
            name = "Teleport: Orgrimmar",
            destination = "Orgrimmar",
            mapID = 85,
            x = 0.4690,
            y = 0.3870,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Burning Crusade
        [32272] = {
            name = "Teleport: Silvermoon",
            destination = "Silvermoon City",
            mapID = 110,
            x = 0.5850,
            y = 0.1920,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [49358] = {
            name = "Teleport: Stonard",
            destination = "Stonard, Swamp of Sorrows",
            mapID = 51,
            x = 0.4671,
            y = 0.5480,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Cataclysm
        [88344] = {
            name = "Teleport: Tol Barad",
            destination = "Tol Barad Peninsula",
            mapID = 773,
            x = 0.5553,
            y = 0.7869,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Mists of Pandaria
        [132627] = {
            name = "Teleport: Vale of Eternal Blossoms",
            destination = "Shrine of Two Moons",
            mapID = 390,
            x = 0.1610,
            y = 0.5800,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Warlords of Draenor
        [176244] = {
            name = "Teleport: Warspear",
            destination = "Warspear, Ashran",
            mapID = 624,  -- Warspear
            x = 0.5308,
            y = 0.4142,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Battle for Azeroth
        [281404] = {
            name = "Teleport: Dazar'alor",
            destination = "Dazar'alor",
            mapID = 1165,
            x = 0.5020,
            y = 0.4080,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
    },

    -- Neutral teleports available to both factions
    Shared = {
        -- Burning Crusade
        [33690] = {
            name = "Teleport: Shattrath",
            destination = "Shattrath City",
            mapID = 111,
            x = 0.5410,
            y = 0.4120,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Wrath of the Lich King
        [53140] = {
            name = "Teleport: Dalaran - Northrend",
            destination = "Dalaran (Northrend)",
            mapID = 125,
            x = 0.4947,
            y = 0.4709,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [120145] = {
            name = "Ancient Teleport: Dalaran",
            destination = "Dalaran Crater",
            mapID = 25,  -- Hillsbrad Foothills
            x = 0.5700,
            y = 0.2000,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Legion
        [224869] = {
            name = "Teleport: Dalaran - Broken Isles",
            destination = "Dalaran (Legion)",
            mapID = 627,
            x = 0.5044,
            y = 0.5313,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        [193759] = {
            name = "Teleport: Hall of the Guardian",
            destination = "Hall of the Guardian",
            mapID = 734,  -- Hall of the Guardian
            x = 0.5000,
            y = 0.5000,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Shadowlands
        [344587] = {
            name = "Teleport: Oribos",
            destination = "Oribos",
            mapID = 1670,
            x = 0.4483,
            y = 0.6466,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- Dragonflight
        [395277] = {
            name = "Teleport: Valdrakken",
            destination = "Valdrakken",
            mapID = 2112,
            x = 0.5835,
            y = 0.3535,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
        -- The War Within
        [446540] = {
            name = "Teleport: Dornogal",
            destination = "Dornogal",
            mapID = 2339,
            x = 0.4850,
            y = 0.5520,
            cooldown = 0,
            type = QR.TeleportTypes.SPELL,
            class = "MAGE",
        },
    },
}

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
