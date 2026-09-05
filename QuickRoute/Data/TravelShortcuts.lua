-- Additional owned travel destinations, adapted from Mapzeroth static data.
-- Source revision and MIT notice: ThirdParty/Mapzeroth-NOTICE.md.
local ADDON_NAME, QR = ...

QR.TeleportDestinationData = {
    ["item:103678"] = {
        ["castTime"] = 10,
        ["cooldown"] = 60,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Celestial Court",
                ["mapID"] = 554,
                ["nodeKey"] = "Travel:TIMELESS_ISLE",
                ["x"] = 0.342,
                ["y"] = 0.553,
            },
        },
        ["name"] = "Time-Lost Artifact",
        ["type"] = "item",
    },
    ["item:110560"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Lunarfall",
                ["mapID"] = 582,
                ["nodeKey"] = "Travel:LUNARFALL",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.299,
                ["y"] = 0.339,
            },
            [2] = {
                ["destination"] = "Frostwall",
                ["mapID"] = 525,
                ["nodeKey"] = "Travel:FROSTWALL",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.4792,
                ["y"] = 0.6808,
            },
        },
        ["name"] = "Garrison Hearthstone",
        ["type"] = "toy",
    },
    ["item:112059"] = {
        ["castTime"] = 5,
        ["cooldown"] = 600,
        ["destinations"] = {
            [1] = {
                ["choiceText"] = "Frostfire Ridge (Lava and snow)",
                ["destination"] = "Frostfire Ridge (Lava and snow)",
                ["isApproximate"] = true,
                ["mapID"] = 525,
                ["nodeKey"] = "Travel:FROSTFIRE_RIDGE_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
            [2] = {
                ["choiceText"] = "Shadowmoon Valley (Shadows...)",
                ["destination"] = "Shadowmoon Valley (Shadows...)",
                ["isApproximate"] = true,
                ["mapID"] = 539,
                ["nodeKey"] = "Travel:SHADOWMOON_VALLEY_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
            [3] = {
                ["choiceText"] = "Gorgrond (Primal Forest)",
                ["destination"] = "Gorgrond (Primal Forest)",
                ["isApproximate"] = true,
                ["mapID"] = 543,
                ["nodeKey"] = "Travel:GORGROND_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
            [4] = {
                ["choiceText"] = "Nagrand (Grassy plains)",
                ["destination"] = "Nagrand (Grassy plains)",
                ["isApproximate"] = true,
                ["mapID"] = 550,
                ["nodeKey"] = "Travel:NAGRAND_DRAENOR_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
            [5] = {
                ["choiceText"] = "Talador (A reddish-orange forest)",
                ["destination"] = "Talador (A reddish-orange forest)",
                ["isApproximate"] = true,
                ["mapID"] = 535,
                ["nodeKey"] = "Travel:TALADOR_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
            [6] = {
                ["choiceText"] = "Spires of Arak (A jagged landscape)",
                ["destination"] = "Spires of Arak (A jagged landscape)",
                ["isApproximate"] = true,
                ["mapID"] = 542,
                ["nodeKey"] = "Travel:SPIRES_OF_ARAK_WORMHOLE",
                ["x"] = 0.5,
                ["y"] = 0.5,
            },
        },
        ["name"] = "Wormhole Centrifuge",
        ["type"] = "toy",
    },
    ["item:128353"] = {
        ["castTime"] = 5,
        ["cooldown"] = 1200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Frostwall Shipyard",
                ["mapID"] = 525,
                ["nodeKey"] = "Travel:FROSTWALL_SHIPYARD",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.4298,
                ["y"] = 0.7356,
            },
            [2] = {
                ["destination"] = "Lunarfall Shipyard",
                ["mapID"] = 539,
                ["nodeKey"] = "Travel:LUNARFALL_SHIPYARD",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.279,
                ["y"] = 0.112,
            },
        },
        ["faction"] = "Horde",
        ["name"] = "Admiral's Compass",
        ["type"] = "item",
    },
    ["item:140192"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran (Broken Isles)",
                ["mapID"] = 627,
                ["nodeKey"] = "Travel:DALARAN_BROKEN_ISLES",
                ["x"] = 0.6092,
                ["y"] = 0.4472,
            },
        },
        ["name"] = "Dalaran Hearthstone",
        ["type"] = "toy",
    },
    ["item:142469"] = {
        ["castTime"] = 0,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Karazhan",
                ["mapID"] = 42,
                ["nodeKey"] = "Travel:KARAZHAN",
                ["x"] = 0.473,
                ["y"] = 0.753,
            },
        },
        ["name"] = "Violet Seal of the Grand Magus",
        ["type"] = "item",
    },
    ["item:144391"] = {
        ["castTime"] = 10,
        ["cooldown"] = 3600,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Bizmo's Brawlpub",
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:BIZMOS_BRAWLPUB",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.6943,
                ["y"] = 0.3133,
            },
        },
        ["name"] = "Pugilist's Powerful Punching Ring",
        ["type"] = "item",
    },
    ["item:144392"] = {
        ["castTime"] = 10,
        ["cooldown"] = 3600,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Brawl'gar Arena",
                ["mapID"] = 85,
                ["nodeKey"] = "Travel:BRAWLGAR_ARENA",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.7055,
                ["y"] = 0.3117,
            },
        },
        ["name"] = "Pugilist's Powerful Punching Ring",
        ["type"] = "item",
    },
    ["item:151652"] = {
        ["castTime"] = 3,
        ["cooldown"] = 900,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Vindicaar (Argus)",
                ["mapID"] = 883,
                ["nodeKey"] = "Travel:VINDICAAR_ARGUS",
                ["x"] = 0.5826,
                ["y"] = 0.8101,
            },
        },
        ["isRandom"] = true,
        ["name"] = "Wormhole Generator: Argus",
        ["type"] = "toy",
    },
    ["item:167075"] = {
        ["castTime"] = 10,
        ["cooldown"] = 60,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Rustbolt",
                ["mapID"] = 1462,
                ["nodeKey"] = "Travel:MECHAGON",
                ["x"] = 0.739,
                ["y"] = 0.365,
            },
        },
        ["name"] = "Ultrasafe Transporter: Mechagon",
        ["type"] = "item",
    },
    ["item:172924"] = {
        ["castTime"] = 5,
        ["cooldown"] = 900,
        ["destinations"] = {
            [1] = {
                ["choiceText"] = "Oribos, The Eternal City",
                ["destination"] = "Oribos, The Eternal City",
                ["mapID"] = 1670,
                ["nodeKey"] = "Travel:ORIBOS_WORMHOLE",
                ["x"] = 0.5208,
                ["y"] = 0.2613,
            },
            [2] = {
                ["choiceText"] = "Home of the Kyrian",
                ["destination"] = "Home of the Kyrian",
                ["mapID"] = 1533,
                ["nodeKey"] = "Travel:BASTION_WORMHOLE",
                ["x"] = 0.5186,
                ["y"] = 0.8776,
            },
            [3] = {
                ["choiceText"] = "Citadel of the Necrolords",
                ["destination"] = "Citadel of the Necrolords",
                ["mapID"] = 1536,
                ["nodeKey"] = "Travel:MALDRAXXUS_WORMHOLE",
                ["x"] = 0.4244,
                ["y"] = 0.4399,
            },
            [4] = {
                ["choiceText"] = "Forest of the Night Fae",
                ["destination"] = "Forest of the Night Fae",
                ["mapID"] = 1565,
                ["nodeKey"] = "Travel:ARDENWEALD_WORMHOLE",
                ["x"] = 0.5443,
                ["y"] = 0.6033,
            },
            [5] = {
                ["choiceText"] = "Court of the Venthyr",
                ["destination"] = "Court of the Venthyr",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:REVENDRETH_WORMHOLE",
                ["x"] = 0.375,
                ["y"] = 0.7655,
            },
            [6] = {
                ["choiceText"] = "Wasteland of the Damned",
                ["destination"] = "Wasteland of the Damned",
                ["mapID"] = 1543,
                ["nodeKey"] = "Travel:THE_MAW_WORMHOLE",
                ["x"] = 0.2246,
                ["y"] = 0.2816,
            },
            [7] = {
                ["choiceText"] = "Korthia (Wormhole)",
                ["destination"] = "Korthia (Wormhole)",
                ["mapID"] = 1961,
                ["nodeKey"] = "Travel:KORTHIA_WORMHOLE",
                ["x"] = 0.6241,
                ["y"] = 0.2458,
            },
        },
        ["name"] = "Wormhole Generator: Shadowlands",
        ["type"] = "toy",
    },
    ["item:184500"] = {
        ["castTime"] = 5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Temple of Courage",
                ["mapID"] = 1533,
                ["nodeKey"] = "Travel:BASTION_POCKET_PORTAL",
                ["x"] = 0.42,
                ["y"] = 0.48,
            },
        },
        ["name"] = "Attendant's Pocket Portal: Bastion",
        ["type"] = "item",
    },
    ["item:184501"] = {
        ["castTime"] = 5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Castle Nathria",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:REVENDRETH_POCKET_PORTAL",
                ["x"] = 0.57,
                ["y"] = 0.51,
            },
        },
        ["name"] = "Attendant's Pocket Portal: Revendreth",
        ["type"] = "item",
    },
    ["item:184502"] = {
        ["castTime"] = 5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Theater of Pain",
                ["mapID"] = 1536,
                ["nodeKey"] = "Travel:MALDRAXXUS_POCKET_PORTAL",
                ["x"] = 0.52,
                ["y"] = 0.54,
            },
        },
        ["name"] = "Attendant's Pocket Portal: Maldraxxus",
        ["type"] = "item",
    },
    ["item:184503"] = {
        ["castTime"] = 5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Heart of the Forest",
                ["mapID"] = 1565,
                ["nodeKey"] = "Travel:ARDENWEALD_POCKET_PORTAL",
                ["x"] = 0.48,
                ["y"] = 0.48,
            },
        },
        ["name"] = "Attendant's Pocket Portal: Ardenweald",
        ["type"] = "item",
    },
    ["item:184504"] = {
        ["castTime"] = 5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Entrance, Oribos",
                ["mapID"] = 1670,
                ["nodeKey"] = "Travel:ORIBOS",
                ["x"] = 0.203,
                ["y"] = 0.503,
            },
        },
        ["name"] = "Attendant's Pocket Portal: Oribos",
        ["type"] = "item",
    },
    ["item:18984"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Everlook",
                ["mapID"] = 83,
                ["nodeKey"] = "Travel:EVERLOOK_RIPPER",
                ["x"] = 0.61,
                ["y"] = 0.39,
            },
        },
        ["name"] = "Dimensional Ripper - Everlook",
        ["type"] = "toy",
    },
    ["item:18986"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Gadgetzan",
                ["mapID"] = 71,
                ["nodeKey"] = "Travel:GADGETZAN_TRANSPORTER",
                ["x"] = 0.52,
                ["y"] = 0.27,
            },
        },
        ["name"] = "Ultrasafe Transporter: Gadgetzan",
        ["type"] = "toy",
    },
    ["item:202046"] = {
        ["castTime"] = 10,
        ["cooldown"] = 3600,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Seekers Vista",
                ["mapID"] = 942,
                ["nodeKey"] = "Travel:TORTOLLAN_BASE_CAMP",
                ["x"] = 0.403,
                ["y"] = 0.365,
            },
        },
        ["name"] = "Lucky Tortollan Charm",
        ["type"] = "item",
    },
    ["item:211788"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Gilneas City",
                ["mapID"] = 217,
                ["nodeKey"] = "Travel:GILNEAS",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.589,
                ["y"] = 0.4746,
            },
        },
        ["faction"] = "Alliance",
        ["name"] = "Tess's Peacebloom",
        ["type"] = "toy",
    },
    ["item:243056"] = {
        ["castTime"] = 10,
        ["cooldown"] = 7200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Delver's Office",
                ["mapID"] = 2339,
                ["nodeKey"] = "Travel:DORNOGAL_DELVE_HALL",
                ["x"] = 0.4946,
                ["y"] = 0.4441,
            },
        },
        ["name"] = "Delver's Mana-Bound Ethergate",
        ["type"] = "toy",
    },
    ["item:252607"] = {
        ["castTime"] = 8,
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Loaknit Den",
                ["mapID"] = 2413,
                ["nodeKey"] = "Travel:LOAKNIT_DEN_ZUL_AMAN",
                ["x"] = 0.316,
                ["y"] = 0.212,
            },
        },
        ["name"] = "Abundant Beacon",
        ["type"] = "item",
    },
    ["item:253629"] = {
        ["castTime"] = 5,
        ["cooldown"] = 900,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Arcantina",
                ["mapID"] = 2541,
                ["nodeKey"] = "Travel:ARCANTINA_ENTRANCE",
                ["x"] = 0.5093,
                ["y"] = 0.788,
            },
        },
        ["name"] = "Personal Key to the Arcantina",
        ["type"] = "toy",
    },
    ["item:279550"] = {
        ["castTime"] = 1.5,
        ["cooldown"] = 300,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Amani Foothold",
                ["mapID"] = 2509,
                ["nodeKey"] = "Travel:AMANI_FOOTHOLD_FLIGHT",
                ["x"] = 0.4439,
                ["y"] = 0.6236,
            },
        },
        ["name"] = "Potion of Venomous Return",
        ["type"] = "item",
    },
    ["item:30542"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Area 52",
                ["mapID"] = 109,
                ["nodeKey"] = "Travel:AREA_52_RIPPER",
                ["x"] = 0.32,
                ["y"] = 0.64,
            },
        },
        ["name"] = "Dimensional Ripper - Area 52",
        ["type"] = "toy",
    },
    ["item:30544"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Toshley's Station",
                ["mapID"] = 105,
                ["nodeKey"] = "Travel:TOSHLEYS_STATION_TRANSPORTER",
                ["x"] = 0.6,
                ["y"] = 0.68,
            },
        },
        ["name"] = "Ultrasafe Transporter: Toshley's Station",
        ["type"] = "toy",
    },
    ["item:32757"] = {
        ["castTime"] = 40,
        ["cooldown"] = 900,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Black Temple",
                ["mapID"] = 104,
                ["nodeKey"] = "Travel:BLACK_TEMPLE",
                ["x"] = 0.662,
                ["y"] = 0.44,
            },
        },
        ["name"] = "Blessed Medallion of Karabor",
        ["type"] = "item",
    },
    ["item:40586"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran (Northrend)",
                ["mapID"] = 125,
                ["nodeKey"] = "Travel:DALARAN_NORTHREND",
                ["x"] = 0.5592,
                ["y"] = 0.4678,
            },
        },
        ["name"] = "Signet of the Kirin Tor",
        ["type"] = "item",
    },
    ["item:46874"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Argent Tournament Grounds",
                ["mapID"] = 118,
                ["nodeKey"] = "Travel:ARGENT_TOURNAMENT_GROUNDS",
                ["x"] = 0.694,
                ["y"] = 0.226,
            },
        },
        ["name"] = "Argent Crusader's Tabard",
        ["type"] = "item",
    },
    ["item:48933"] = {
        ["castTime"] = 5,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["choiceText"] = "Borean Tundra (Wormhole)",
                ["destination"] = "Borean Tundra (Wormhole)",
                ["mapID"] = 114,
                ["nodeKey"] = "Travel:BOREAN_TUNDRA_WORMHOLE",
                ["x"] = 0.53,
                ["y"] = 0.15,
            },
            [2] = {
                ["choiceText"] = "Howling Fjord (Wormhole)",
                ["destination"] = "Howling Fjord (Wormhole)",
                ["mapID"] = 117,
                ["nodeKey"] = "Travel:HOWLING_FJORD_WORMHOLE",
                ["x"] = 0.58,
                ["y"] = 0.47,
            },
            [3] = {
                ["choiceText"] = "The Storm Peaks (Wormhole)",
                ["destination"] = "The Storm Peaks (Wormhole)",
                ["mapID"] = 120,
                ["nodeKey"] = "Travel:STORM_PEAKS_WORMHOLE",
                ["x"] = 0.43,
                ["y"] = 0.25,
            },
            [4] = {
                ["choiceText"] = "Sholazar Basin (Wormhole)",
                ["destination"] = "Sholazar Basin (Wormhole)",
                ["mapID"] = 119,
                ["nodeKey"] = "Travel:SHOLAZAR_BASIN_WORMHOLE",
                ["x"] = 0.492,
                ["y"] = 0.396,
            },
        },
        ["name"] = "Wormhole Generator: Northrend",
        ["type"] = "toy",
    },
    ["item:52251"] = {
        ["castTime"] = 10,
        ["cooldown"] = 3600,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran (Northrend)",
                ["mapID"] = 125,
                ["nodeKey"] = "Travel:DALARAN_NORTHREND",
                ["x"] = 0.5592,
                ["y"] = 0.4678,
            },
        },
        ["name"] = "Jaina's Locket",
        ["type"] = "item",
    },
    ["item:63206"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Lower)",
                ["interior"] = true,
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:STORMWIND_PORTAL_ROOM_LOWER",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.4634,
                ["y"] = 0.9024,
            },
        },
        ["name"] = "Wrap of Unity",
        ["type"] = "item",
    },
    ["item:63207"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Upper)",
                ["interior"] = true,
                ["mapID"] = 85,
                ["nodeKey"] = "Travel:ORGRIMMAR_PORTAL_ROOM_UPPER",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.571,
                ["y"] = 0.8981,
            },
        },
        ["name"] = "Wrap of Unity",
        ["type"] = "item",
    },
    ["item:63352"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Lower)",
                ["interior"] = true,
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:STORMWIND_PORTAL_ROOM_LOWER",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.4634,
                ["y"] = 0.9024,
            },
        },
        ["name"] = "Shroud of Cooperation",
        ["type"] = "item",
    },
    ["item:63353"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Upper)",
                ["interior"] = true,
                ["mapID"] = 85,
                ["nodeKey"] = "Travel:ORGRIMMAR_PORTAL_ROOM_UPPER",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.571,
                ["y"] = 0.8981,
            },
        },
        ["name"] = "Shroud of Cooperation",
        ["type"] = "item",
    },
    ["item:63378"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Tol Barad Camp",
                ["mapID"] = 245,
                ["nodeKey"] = "Travel:TOL_BARAD_HORDE",
                ["x"] = 0.531,
                ["y"] = 0.76,
            },
        },
        ["name"] = "Hellscream's Reach Tabard",
        ["type"] = "item",
    },
    ["item:63379"] = {
        ["castTime"] = 10,
        ["cooldown"] = 14400,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Tol Barad Camp",
                ["mapID"] = 245,
                ["nodeKey"] = "Travel:TOL_BARAD_ALLIANCE",
                ["x"] = 0.724,
                ["y"] = 0.562,
            },
        },
        ["name"] = "Baradin's Wardens Tabard",
        ["type"] = "item",
    },
    ["item:65274"] = {
        ["castTime"] = 10,
        ["cooldown"] = 7200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Upper)",
                ["interior"] = true,
                ["mapID"] = 85,
                ["nodeKey"] = "Travel:ORGRIMMAR_PORTAL_ROOM_UPPER",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.571,
                ["y"] = 0.8981,
            },
        },
        ["name"] = "Cloak of Coordination",
        ["type"] = "item",
    },
    ["item:65360"] = {
        ["castTime"] = 10,
        ["cooldown"] = 7200,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Lower)",
                ["interior"] = true,
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:STORMWIND_PORTAL_ROOM_LOWER",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.4634,
                ["y"] = 0.9024,
            },
        },
        ["name"] = "Cloak of Coordination",
        ["type"] = "item",
    },
    ["item:6948"] = {
        ["castTime"] = 10,
        ["cooldown"] = 1200,
        ["destinations"] = {},
        ["name"] = "Hearthstone",
        ["type"] = "item",
    },
    ["item:87215"] = {
        ["castTime"] = 3,
        ["cooldown"] = 900,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Jade Temple Grounds",
                ["mapID"] = 371,
                ["nodeKey"] = "Travel:JADE_TEMPLE_GROUNDS_FLIGHT",
                ["x"] = 0.555,
                ["y"] = 0.627,
            },
        },
        ["isRandom"] = true,
        ["name"] = "Wormhole Generator: Pandaria",
        ["type"] = "toy",
    },
    ["spell:120145"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran Crater",
                ["mapID"] = 25,
                ["nodeKey"] = "Travel:DALARAN_CRATER",
                ["x"] = 0.2,
                ["y"] = 0.586,
            },
        },
        ["name"] = "Ancient Teleport: Dalaran",
        ["spellID"] = 120145,
        ["type"] = "spell",
    },
    ["spell:1216786"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Operation: Floodgate",
                ["mapID"] = 2214,
                ["nodeKey"] = "Travel:OPERATION_FLOODGATE_DUNGEON",
                ["x"] = 0.4209,
                ["y"] = 0.3948,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Circuit Breaker",
        ["spellID"] = 1216786,
        ["type"] = "spell",
    },
    ["spell:1226482"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Liberation of Undermine",
                ["mapID"] = 2346,
                ["nodeKey"] = "Travel:LIBERATION_OF_UNDERMINE_RAID",
                ["x"] = 0.42,
                ["y"] = 0.49,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Full House",
        ["spellID"] = 1226482,
        ["type"] = "spell",
    },
    ["spell:1237215"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Eco-Dome Al'dani",
                ["mapID"] = 2472,
                ["nodeKey"] = "Travel:ECO_DOME_ALDANI_DUNGEON",
                ["x"] = 0.438,
                ["y"] = 0.0447,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Eco-Dome",
        ["spellID"] = 1237215,
        ["type"] = "spell",
    },
    ["spell:1239155"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Manaforge Omega",
                ["mapID"] = 2472,
                ["nodeKey"] = "Travel:MANAFORGE_OMEGA_RAID",
                ["x"] = 0.41,
                ["y"] = 0.21,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the All-Devouring",
        ["spellID"] = 1239155,
        ["type"] = "spell",
    },
    ["spell:1254400"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Windrunner Spire",
                ["mapID"] = 2395,
                ["nodeKey"] = "Travel:WINDRUNNER_SPIRE_DUNGEON",
                ["x"] = 0.3548,
                ["y"] = 0.7883,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Windrunners",
        ["spellID"] = 1254400,
        ["type"] = "spell",
    },
    ["spell:1254551"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Seat of the Triumvirate",
                ["mapID"] = 882,
                ["nodeKey"] = "Travel:SEAT_OF_THE_TRIUMVIRATE_DUNGEON",
                ["x"] = 0.21,
                ["y"] = 0.57,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Dark Dereliction",
        ["spellID"] = 1254551,
        ["type"] = "spell",
    },
    ["spell:1254555"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Pit of Saron",
                ["mapID"] = 118,
                ["nodeKey"] = "Travel:PIT_OF_SARON_DUNGEON",
                ["x"] = 0.52,
                ["y"] = 0.89,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Unyielding Blight",
        ["spellID"] = 1254555,
        ["type"] = "spell",
    },
    ["spell:1254557"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Skyreach",
                ["mapID"] = 542,
                ["nodeKey"] = "Travel:SKYREACH_DUNGEON",
                ["x"] = 0.35,
                ["y"] = 0.33,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Crowning Pinnacle",
        ["spellID"] = 1254557,
        ["type"] = "spell",
    },
    ["spell:1254559"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Maisara Caverns",
                ["mapID"] = 2437,
                ["nodeKey"] = "Travel:MAISARA_CAVERNS_DUNGEON",
                ["x"] = 0.4385,
                ["y"] = 0.3953,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Cavernous Depths",
        ["spellID"] = 1254559,
        ["type"] = "spell",
    },
    ["spell:1254563"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Nexus Point Xenas",
                ["mapID"] = 2405,
                ["nodeKey"] = "Travel:NEXUS_POINT_XENAS_DUNGEON",
                ["x"] = 0.6477,
                ["y"] = 0.6163,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Fracture Core",
        ["spellID"] = 1254563,
        ["type"] = "spell",
    },
    ["spell:1254572"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Magisters' Terrace",
                ["mapID"] = 2424,
                ["nodeKey"] = "Travel:MAGISTERS_TERRACE_DUNGEON",
                ["x"] = 0.6331,
                ["y"] = 0.1527,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Devoted Magistry",
        ["spellID"] = 1254572,
        ["type"] = "spell",
    },
    ["spell:126892"] = {
        ["castTime"] = 10,
        ["class"] = "MONK",
        ["cooldown"] = 60,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Peak of Serenity",
                ["mapID"] = 709,
                ["nodeKey"] = "Travel:PEAK_OF_SERENITY",
                ["x"] = 0.5145,
                ["y"] = 0.4865,
            },
        },
        ["name"] = "Zen Pilgrimage",
        ["spellID"] = 126892,
        ["type"] = "spell",
    },
    ["spell:131204"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Temple of the Jade Serpent",
                ["mapID"] = 371,
                ["nodeKey"] = "Travel:TEMPLE_OF_THE_JADE_SERPENT_DUNGEON",
                ["x"] = 0.56,
                ["y"] = 0.58,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Jade Serpent",
        ["spellID"] = 131204,
        ["type"] = "spell",
    },
    ["spell:131205"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Stormstout Brewery",
                ["mapID"] = 376,
                ["nodeKey"] = "Travel:STORMSTOUT_BREWERY_DUNGEON",
                ["x"] = 0.36,
                ["y"] = 0.69,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Stout Brew",
        ["spellID"] = 131205,
        ["type"] = "spell",
    },
    ["spell:131206"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shado-Pan Monastery",
                ["mapID"] = 379,
                ["nodeKey"] = "Travel:SHADOPAN_MONASTERY_DUNGEON",
                ["x"] = 0.37,
                ["y"] = 0.48,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Shado-Pan",
        ["spellID"] = 131206,
        ["type"] = "spell",
    },
    ["spell:131222"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Mogu'shan Palace",
                ["mapID"] = 390,
                ["nodeKey"] = "Travel:MOGUSHAN_PALACE_DUNGEON",
                ["x"] = 0.79,
                ["y"] = 0.34,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Mogu King",
        ["spellID"] = 131222,
        ["type"] = "spell",
    },
    ["spell:131225"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Gate of the Setting Sun",
                ["mapID"] = 390,
                ["nodeKey"] = "Travel:GATE_OF_THE_SETTING_SUN_DUNGEON",
                ["x"] = 0.16,
                ["y"] = 0.74,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Setting Sun",
        ["spellID"] = 131225,
        ["type"] = "spell",
    },
    ["spell:131228"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Siege of Niuzao Temple",
                ["mapID"] = 388,
                ["nodeKey"] = "Travel:SIEGE_OF_NIUZAO_TEMPLE_DUNGEON",
                ["x"] = 0.35,
                ["y"] = 0.82,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Black Ox",
        ["spellID"] = 131228,
        ["type"] = "spell",
    },
    ["spell:131229"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Scarlet Monastery",
                ["mapID"] = 18,
                ["nodeKey"] = "Travel:SCARLET_MONASTERY_DUNGEON",
                ["x"] = 0.82,
                ["y"] = 0.33,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Scarlet Mitre",
        ["spellID"] = 131229,
        ["type"] = "spell",
    },
    ["spell:131231"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Scarlet Halls",
                ["mapID"] = 18,
                ["nodeKey"] = "Travel:SCARLET_HALLS_DUNGEON",
                ["x"] = 0.82,
                ["y"] = 0.33,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Scarlet Blade",
        ["spellID"] = 131231,
        ["type"] = "spell",
    },
    ["spell:131232"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Scholomance",
                ["mapID"] = 22,
                ["nodeKey"] = "Travel:SCHOLOMANCE_DUNGEON",
                ["x"] = 0.69,
                ["y"] = 0.73,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Necromancer",
        ["spellID"] = 131232,
        ["type"] = "spell",
    },
    ["spell:132621"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shrine of Seven Stars",
                ["mapID"] = 390,
                ["nodeKey"] = "Travel:SHRINE_OF_SEVEN_STARS",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.863,
                ["y"] = 0.611,
            },
        },
        ["name"] = "Teleport: Vale of Eternal Blossoms",
        ["spellID"] = 132621,
        ["type"] = "spell",
    },
    ["spell:132627"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shrine of Two Moons",
                ["mapID"] = 390,
                ["nodeKey"] = "Travel:SHRINE_OF_TWO_MOONS",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.625,
                ["y"] = 0.2182,
            },
        },
        ["name"] = "Teleport: Vale of Eternal Blossoms",
        ["spellID"] = 132627,
        ["type"] = "spell",
    },
    ["spell:159895"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Bloodmaul Slag Mines",
                ["mapID"] = 525,
                ["nodeKey"] = "Travel:BLOODMAUL_SLAG_MINES_DUNGEON",
                ["x"] = 0.49,
                ["y"] = 0.25,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Bloodmaul",
        ["spellID"] = 159895,
        ["type"] = "spell",
    },
    ["spell:159896"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Iron Docks",
                ["mapID"] = 543,
                ["nodeKey"] = "Travel:IRON_DOCKS_DUNGEON",
                ["x"] = 0.45,
                ["y"] = 0.13,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Iron Prow",
        ["spellID"] = 159896,
        ["type"] = "spell",
    },
    ["spell:159897"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Auchindoun",
                ["mapID"] = 535,
                ["nodeKey"] = "Travel:AUCHINDOUN_DUNGEON",
                ["x"] = 0.46,
                ["y"] = 0.74,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Vigilant",
        ["spellID"] = 159897,
        ["type"] = "spell",
    },
    ["spell:159898"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Skyreach",
                ["mapID"] = 542,
                ["nodeKey"] = "Travel:SKYREACH_DUNGEON",
                ["x"] = 0.35,
                ["y"] = 0.33,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Skies",
        ["spellID"] = 159898,
        ["type"] = "spell",
    },
    ["spell:159899"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shadowmoon Burial Grounds",
                ["mapID"] = 539,
                ["nodeKey"] = "Travel:SHADOWMOON_BURIAL_GROUNDS_DUNGEON",
                ["x"] = 0.32,
                ["y"] = 0.42,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Crescent Moon",
        ["spellID"] = 159899,
        ["type"] = "spell",
    },
    ["spell:159900"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Grimrail Depot",
                ["mapID"] = 543,
                ["nodeKey"] = "Travel:GRIMRAIL_DEPOT_DUNGEON",
                ["x"] = 0.55,
                ["y"] = 0.32,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Dark Rail",
        ["spellID"] = 159900,
        ["type"] = "spell",
    },
    ["spell:159901"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Everbloom",
                ["mapID"] = 543,
                ["nodeKey"] = "Travel:THE_EVERBLOOM_DUNGEON",
                ["x"] = 0.59,
                ["y"] = 0.45,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Verdant",
        ["spellID"] = 159901,
        ["type"] = "spell",
    },
    ["spell:159902"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Upper Blackrock Spire",
                ["mapID"] = 33,
                ["nodeKey"] = "Travel:UPPER_BLACKROCK_SPIRE_DUNGEON",
                ["x"] = 0.7897,
                ["y"] = 0.3373,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Burning Mountain",
        ["spellID"] = 159902,
        ["type"] = "spell",
    },
    ["spell:176242"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Warspear",
                ["mapID"] = 624,
                ["nodeKey"] = "Travel:WARSPEAR_ASHRAN",
                ["x"] = 0.5884,
                ["y"] = 0.5135,
            },
        },
        ["name"] = "Teleport: Warspear",
        ["spellID"] = 176242,
        ["type"] = "spell",
    },
    ["spell:176248"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Stormshield",
                ["mapID"] = 622,
                ["nodeKey"] = "Travel:STORMSHIELD_ASHRAN",
                ["x"] = 0.615,
                ["y"] = 0.399,
            },
        },
        ["name"] = "Teleport: Stormshield",
        ["spellID"] = 176248,
        ["type"] = "spell",
    },
    ["spell:18960"] = {
        ["castTime"] = 10,
        ["class"] = "DRUID",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Nighthaven",
                ["mapID"] = 80,
                ["nodeKey"] = "Travel:MOONGLADE",
                ["x"] = 0.567,
                ["y"] = 0.355,
            },
        },
        ["name"] = "Teleport: Moonglade",
        ["spellID"] = 18960,
        ["type"] = "spell",
    },
    ["spell:193753"] = {
        ["castTime"] = 10,
        ["class"] = "DRUID",
        ["cooldown"] = 60,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Emerald Dreamway",
                ["interior"] = true,
                ["mapID"] = 715,
                ["nodeKey"] = "Travel:EMERALD_DREAMWAY",
                ["x"] = 0.3533,
                ["y"] = 0.5315,
            },
        },
        ["name"] = "Dreamwalk",
        ["spellID"] = 193753,
        ["type"] = "spell",
    },
    ["spell:193759"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Hall of the Guardian",
                ["interior"] = true,
                ["mapID"] = 734,
                ["nodeKey"] = "Travel:HALL_OF_THE_GUARDIAN",
                ["x"] = 0.5763,
                ["y"] = 0.8614,
            },
        },
        ["name"] = "Teleport: Hall of the Guardian",
        ["spellID"] = 193759,
        ["type"] = "spell",
    },
    ["spell:224869"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran (Broken Isles)",
                ["mapID"] = 627,
                ["nodeKey"] = "Travel:DALARAN_BROKEN_ISLES",
                ["x"] = 0.6092,
                ["y"] = 0.4472,
            },
        },
        ["name"] = "Teleport: Dalaran - Broken Isles",
        ["spellID"] = 224869,
        ["type"] = "spell",
    },
    ["spell:265225"] = {
        ["castTime"] = 5,
        ["cooldown"] = 1800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Stormwind (Eastern Kingdoms)",
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:STORMWIND_CITY_MOLE",
                ["x"] = 0.633,
                ["y"] = 0.373,
            },
            [10] = {
                ["destination"] = "Hellfire Peninsula (Outland - Honor Hold)",
                ["mapID"] = 100,
                ["nodeKey"] = "Travel:HONOR_HOLD_MOLE",
                ["requirements"] = {
                    ["quest"] = 53592,
                },
                ["x"] = 0.561,
                ["y"] = 0.631,
            },
            [11] = {
                ["destination"] = "Blade's Edge Mountains (Outland - Skald)",
                ["mapID"] = 105,
                ["nodeKey"] = "Travel:BLADES_EDGE_MOUNTAINS_MOLE",
                ["requirements"] = {
                    ["quest"] = 53597,
                },
                ["x"] = 0.725,
                ["y"] = 0.176,
            },
            [12] = {
                ["destination"] = "Shadowmoon Valley (Outland - Fel Pits)",
                ["mapID"] = 104,
                ["nodeKey"] = "Travel:SHADOWMOON_VALLEY_OUTLANDS_MOLE",
                ["requirements"] = {
                    ["quest"] = 53599,
                },
                ["x"] = 0.507,
                ["y"] = 0.353,
            },
            [13] = {
                ["destination"] = "Ruby Dragonshrine (Dragonblight)",
                ["mapID"] = 115,
                ["nodeKey"] = "Travel:RUBY_DRAGONSHRINE_MOLE",
                ["requirements"] = {
                    ["quest"] = 53596,
                },
                ["x"] = 0.453,
                ["y"] = 0.499,
            },
            [14] = {
                ["destination"] = "Argent Tournament Grounds (Icecrown)",
                ["mapID"] = 118,
                ["nodeKey"] = "Travel:ARGENT_TOURNAMENT_GROUNDS_MOLE",
                ["requirements"] = {
                    ["quest"] = 53586,
                },
                ["x"] = 0.77,
                ["y"] = 0.186,
            },
            [15] = {
                ["destination"] = "Valley of the Four Winds (Stormstout Brewery)",
                ["mapID"] = 376,
                ["nodeKey"] = "Travel:VALLEY_OF_THE_FOUR_WINDS_MOLE",
                ["requirements"] = {
                    ["quest"] = 53598,
                },
                ["x"] = 0.315,
                ["y"] = 0.736,
            },
            [16] = {
                ["destination"] = "Kun-Lai Summit (One Keg)",
                ["mapID"] = 379,
                ["nodeKey"] = "Travel:KUN_LAI_SUMMIT_MOLE",
                ["requirements"] = {
                    ["quest"] = 53595,
                },
                ["x"] = 0.577,
                ["y"] = 0.628,
            },
            [17] = {
                ["destination"] = "Gorgrond",
                ["mapID"] = 543,
                ["nodeKey"] = "Travel:GORGROND_MOLE",
                ["requirements"] = {
                    ["quest"] = 53588,
                },
                ["x"] = 0.467,
                ["y"] = 0.387,
            },
            [18] = {
                ["destination"] = "Nagrand (Draenor)",
                ["mapID"] = 550,
                ["nodeKey"] = "Travel:NAGRAND_DRAENOR_MOLE",
                ["requirements"] = {
                    ["quest"] = 53590,
                },
                ["x"] = 0.657,
                ["y"] = 0.083,
            },
            [19] = {
                ["destination"] = "Allgen Point",
                ["mapID"] = 646,
                ["nodeKey"] = "Travel:THE_BROKEN_SHORE_MOLE",
                ["requirements"] = {
                    ["quest"] = 53589,
                },
                ["x"] = 0.717,
                ["y"] = 0.48,
            },
            [2] = {
                ["destination"] = "Ironforge (Eastern Kingdoms)",
                ["mapID"] = 27,
                ["nodeKey"] = "Travel:IRONFORGE_MOLE",
                ["x"] = 0.613,
                ["y"] = 0.372,
            },
            [20] = {
                ["destination"] = "Frosthoof Watch",
                ["mapID"] = 650,
                ["nodeKey"] = "Travel:HIGHMOUNTAIN_MOLE",
                ["requirements"] = {
                    ["quest"] = 53593,
                },
                ["x"] = 0.446,
                ["y"] = 0.729,
            },
            [21] = {
                ["destination"] = "Xibala Incursion",
                ["mapID"] = 862,
                ["nodeKey"] = "Travel:ZULDAZAR_MOLE",
                ["requirements"] = {
                    ["quest"] = 80100,
                },
                ["x"] = 0.382,
                ["y"] = 0.724,
            },
            [22] = {
                ["destination"] = "Zalamar Invasion",
                ["mapID"] = 863,
                ["nodeKey"] = "Travel:NAZMIR_MOLE",
                ["requirements"] = {
                    ["quest"] = 80099,
                },
                ["x"] = 0.344,
                ["y"] = 0.452,
            },
            [23] = {
                ["destination"] = "Wailing Tideways",
                ["mapID"] = 895,
                ["nodeKey"] = "Travel:TIRAGARDE_SOUND_MOLE",
                ["requirements"] = {
                    ["quest"] = 80101,
                },
                ["x"] = 0.882,
                ["y"] = 0.715,
            },
            [24] = {
                ["destination"] = "Tidebreak Summit",
                ["mapID"] = 942,
                ["nodeKey"] = "Travel:STORMSONG_VALLEY_MOLE",
                ["requirements"] = {
                    ["quest"] = 80102,
                },
                ["x"] = 0.642,
                ["y"] = 0.294,
            },
            [25] = {
                ["destination"] = "Valley of a Thousand Legs",
                ["mapID"] = 1536,
                ["nodeKey"] = "Travel:MALDRAXXUS_MOLE",
                ["requirements"] = {
                    ["quest"] = 80103,
                },
                ["x"] = 0.535,
                ["y"] = 0.598,
            },
            [26] = {
                ["destination"] = "Scorched Crypt",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:REVENDRETH_MOLE",
                ["requirements"] = {
                    ["quest"] = 80104,
                },
                ["x"] = 0.199,
                ["y"] = 0.388,
            },
            [27] = {
                ["destination"] = "Soryn's Meadow",
                ["mapID"] = 1565,
                ["nodeKey"] = "Travel:ARDENWEALD_MOLE",
                ["requirements"] = {
                    ["quest"] = 80106,
                },
                ["x"] = 0.665,
                ["y"] = 0.505,
            },
            [28] = {
                ["destination"] = "The Eternal Forge",
                ["mapID"] = 1533,
                ["nodeKey"] = "Travel:BASTION_MOLE",
                ["requirements"] = {
                    ["quest"] = 80105,
                },
                ["x"] = 0.518,
                ["y"] = 0.132,
            },
            [29] = {
                ["destination"] = "The Waking Shores (The Slagmire)",
                ["mapID"] = 2022,
                ["nodeKey"] = "Travel:THE_WAKING_SHORES_MOLE",
                ["requirements"] = {
                    ["quest"] = 80107,
                },
                ["x"] = 0.323,
                ["y"] = 0.549,
            },
            [3] = {
                ["destination"] = "Shadowforge City",
                ["mapID"] = 1186,
                ["nodeKey"] = "Travel:SHADOWFORGE_CITY_MOLE",
                ["x"] = 0.614,
                ["y"] = 0.244,
            },
            [30] = {
                ["destination"] = "The Azure Span (Vakthros Summit)",
                ["mapID"] = 2024,
                ["nodeKey"] = "Travel:AZURE_SPAN_MOLE",
                ["requirements"] = {
                    ["quest"] = 80108,
                },
                ["x"] = 0.801,
                ["y"] = 0.39,
            },
            [31] = {
                ["destination"] = "Zaralek Cavern (Obsidian Rest)",
                ["mapID"] = 2133,
                ["nodeKey"] = "Travel:ZARALEK_CAVERN_MOLE",
                ["requirements"] = {
                    ["quest"] = 80109,
                },
                ["x"] = 0.527,
                ["y"] = 0.277,
            },
            [4] = {
                ["destination"] = "Blackrock Mountain (Eastern Kingdoms - The Masonary)",
                ["interior"] = true,
                ["mapID"] = 35,
                ["nodeKey"] = "Travel:BLACKROCK_MOUNTAIN_MOLE",
                ["requirements"] = {
                    ["quest"] = 53587,
                },
                ["x"] = 0.332,
                ["y"] = 0.251,
            },
            [5] = {
                ["destination"] = "Aerie Peak (Eastern Kingdoms)",
                ["mapID"] = 26,
                ["nodeKey"] = "Travel:AERIE_PEAK_MOLE",
                ["requirements"] = {
                    ["quest"] = 53585,
                },
                ["x"] = 0.134,
                ["y"] = 0.467,
            },
            [6] = {
                ["destination"] = "Nethergarde Keep (Eastern Kingdoms)",
                ["mapID"] = 17,
                ["nodeKey"] = "Travel:NETHERGARDE_KEEP_MOLE",
                ["requirements"] = {
                    ["quest"] = 53594,
                },
                ["x"] = 0.62,
                ["y"] = 0.128,
            },
            [7] = {
                ["destination"] = "Un'Goro Crater (Kalimdor - Fire Plume Ridge)",
                ["mapID"] = 78,
                ["nodeKey"] = "Travel:FIRE_PLUME_RIDGE_MOLE",
                ["requirements"] = {
                    ["quest"] = 53591,
                },
                ["x"] = 0.529,
                ["y"] = 0.559,
            },
            [8] = {
                ["destination"] = "Southern Barrens (Kalimdor - The Great Divide)",
                ["mapID"] = 199,
                ["nodeKey"] = "Travel:THE_GREAT_DIVIDE_MOLE",
                ["requirements"] = {
                    ["quest"] = 53600,
                },
                ["x"] = 0.391,
                ["y"] = 0.093,
            },
            [9] = {
                ["destination"] = "Mount Hyjal (Kalimdor - Throne of Flame)",
                ["mapID"] = 198,
                ["nodeKey"] = "Travel:THRONE_OF_FLAME_MOLE",
                ["requirements"] = {
                    ["quest"] = 53601,
                },
                ["x"] = 0.572,
                ["y"] = 0.771,
            },
        },
        ["name"] = "Mole Machine",
        ["race"] = "DarkIronDwarf",
        ["spellID"] = 265225,
        ["type"] = "spell",
    },
    ["spell:281403"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room",
                ["mapID"] = 1161,
                ["nodeKey"] = "Travel:BORALUS",
                ["x"] = 0.706,
                ["y"] = 0.17,
            },
        },
        ["name"] = "Teleport: Boralus",
        ["spellID"] = 281403,
        ["type"] = "spell",
    },
    ["spell:281404"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room",
                ["mapID"] = 1165,
                ["nodeKey"] = "Travel:DAZARALOR_PORTAL_ROOM",
                ["x"] = 0.6572,
                ["y"] = 0.7433,
            },
        },
        ["name"] = "Teleport: Dazar'alor",
        ["spellID"] = 281404,
        ["type"] = "spell",
    },
    ["spell:32271"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Entrance",
                ["mapID"] = 103,
                ["nodeKey"] = "Travel:EXODAR",
                ["x"] = 0.476,
                ["y"] = 0.598,
            },
        },
        ["name"] = "Teleport: Exodar",
        ["spellID"] = 32271,
        ["type"] = "spell",
    },
    ["spell:32272"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Orgrimmar Portal",
                ["mapID"] = 110,
                ["nodeKey"] = "Travel:SILVERMOON",
                ["x"] = 0.5826,
                ["y"] = 0.1924,
            },
        },
        ["name"] = "Teleport: Silvermoon",
        ["spellID"] = 32272,
        ["type"] = "spell",
    },
    ["spell:33690"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shattrath",
                ["mapID"] = 111,
                ["nodeKey"] = "Travel:SHATTRATH_OUTLANDS",
                ["x"] = 0.5497,
                ["y"] = 0.4023,
            },
        },
        ["name"] = "Teleport: Shattrath",
        ["spellID"] = 33690,
        ["type"] = "spell",
    },
    ["spell:344587"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Entrance, Oribos",
                ["mapID"] = 1670,
                ["nodeKey"] = "Travel:ORIBOS",
                ["x"] = 0.203,
                ["y"] = 0.503,
            },
        },
        ["name"] = "Teleport: Oribos",
        ["spellID"] = 344587,
        ["type"] = "spell",
    },
    ["spell:354462"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Necrotic Wake",
                ["mapID"] = 1533,
                ["nodeKey"] = "Travel:THE_NECROTIC_WAKE_DUNGEON",
                ["x"] = 0.4,
                ["y"] = 0.55,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Courageous",
        ["spellID"] = 354462,
        ["type"] = "spell",
    },
    ["spell:354463"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Plaguefall",
                ["mapID"] = 1536,
                ["nodeKey"] = "Travel:PLAGUEFALL_DUNGEON",
                ["x"] = 0.59,
                ["y"] = 0.65,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Plagued",
        ["spellID"] = 354463,
        ["type"] = "spell",
    },
    ["spell:354464"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Mists of Tirna Scithe",
                ["mapID"] = 1565,
                ["nodeKey"] = "Travel:MISTS_OF_TIRNA_SCITHE_DUNGEON",
                ["x"] = 0.35,
                ["y"] = 0.54,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Misty Forest",
        ["spellID"] = 354464,
        ["type"] = "spell",
    },
    ["spell:354465"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Halls of Atonement",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:HALLS_OF_ATONEMENT_DUNGEON",
                ["x"] = 0.7846,
                ["y"] = 0.4905,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Sinful Soul",
        ["spellID"] = 354465,
        ["type"] = "spell",
    },
    ["spell:354466"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Spires of Ascension",
                ["mapID"] = 1533,
                ["nodeKey"] = "Travel:SPIRES_OF_ASCENSION_DUNGEON",
                ["x"] = 0.58,
                ["y"] = 0.29,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Ascendant",
        ["spellID"] = 354466,
        ["type"] = "spell",
    },
    ["spell:354467"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Theater of Pain",
                ["mapID"] = 1536,
                ["nodeKey"] = "Travel:THEATER_OF_PAIN_DUNGEON",
                ["x"] = 0.53,
                ["y"] = 0.53,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Undefeated",
        ["spellID"] = 354467,
        ["type"] = "spell",
    },
    ["spell:354468"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "De Other Side",
                ["mapID"] = 1565,
                ["nodeKey"] = "Travel:DE_OTHER_SIDE_DUNGEON",
                ["x"] = 0.69,
                ["y"] = 0.66,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Scheming Loa",
        ["spellID"] = 354468,
        ["type"] = "spell",
    },
    ["spell:354469"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Sanguine Depths",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:SANGUINE_DEPTHS_DUNGEON",
                ["x"] = 0.51,
                ["y"] = 0.3,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Stone Warden",
        ["spellID"] = 354469,
        ["type"] = "spell",
    },
    ["spell:3561"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Lower)",
                ["interior"] = true,
                ["mapID"] = 84,
                ["nodeKey"] = "Travel:STORMWIND_PORTAL_ROOM_LOWER",
                ["x"] = 0.4634,
                ["y"] = 0.9024,
            },
        },
        ["name"] = "Teleport: Stormwind",
        ["spellID"] = 3561,
        ["type"] = "spell",
    },
    ["spell:3562"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Hall of Mysteries",
                ["mapID"] = 87,
                ["nodeKey"] = "Travel:IRONFORGE",
                ["x"] = 0.2551,
                ["y"] = 0.0843,
            },
        },
        ["name"] = "Teleport: Ironforge",
        ["spellID"] = 3562,
        ["type"] = "spell",
    },
    ["spell:3563"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Entrance",
                ["mapID"] = 90,
                ["nodeKey"] = "Travel:UNDERCITY",
                ["x"] = 0.663,
                ["y"] = 0.384,
            },
        },
        ["name"] = "Teleport: Undercity",
        ["spellID"] = 3563,
        ["type"] = "spell",
    },
    ["spell:3565"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Darkshore",
                ["mapID"] = 62,
                ["nodeKey"] = "Travel:DARKSHORE_PORTAL_EXIT",
                ["requirements"] = {
                    ["mapArtID"] = {
                        ["artID"] = 1176,
                        ["mapID"] = 62,
                    },
                },
                ["x"] = 0.4595,
                ["y"] = 0.1874,
            },
            [2] = {
                ["destination"] = "Darnassus",
                ["mapID"] = 89,
                ["nodeKey"] = "Travel:DARNASSUS",
                ["requirements"] = {
                    ["mapArtID"] = {
                        ["artID"] = 67,
                        ["mapID"] = 62,
                    },
                },
                ["x"] = 0.435,
                ["y"] = 0.787,
            },
        },
        ["name"] = "Teleport: Darnassus",
        ["spellID"] = 3565,
        ["type"] = "spell",
    },
    ["spell:3566"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Entrance",
                ["mapID"] = 88,
                ["nodeKey"] = "Travel:THUNDER_BLUFF",
                ["x"] = 0.2221,
                ["y"] = 0.1687,
            },
        },
        ["name"] = "Teleport: Thunder Bluff",
        ["spellID"] = 3566,
        ["type"] = "spell",
    },
    ["spell:3567"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room (Upper)",
                ["interior"] = true,
                ["mapID"] = 85,
                ["nodeKey"] = "Travel:ORGRIMMAR_PORTAL_ROOM_UPPER",
                ["x"] = 0.571,
                ["y"] = 0.8981,
            },
        },
        ["name"] = "Teleport: Orgrimmar",
        ["spellID"] = 3567,
        ["type"] = "spell",
    },
    ["spell:35715"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Shattrath",
                ["mapID"] = 111,
                ["nodeKey"] = "Travel:SHATTRATH_OUTLANDS",
                ["x"] = 0.5497,
                ["y"] = 0.4023,
            },
        },
        ["name"] = "Teleport: Shattrath",
        ["spellID"] = 35715,
        ["type"] = "spell",
    },
    ["spell:367416"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Tazavesh, the Veiled Market",
                ["mapID"] = 2472,
                ["nodeKey"] = "Travel:TAZAVESH_THE_VEILED_MARKET_DUNGEON",
                ["x"] = 0.3619,
                ["y"] = 0.1245,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Streetwise Merchant",
        ["spellID"] = 367416,
        ["type"] = "spell",
    },
    ["spell:373190"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Castle Nathria",
                ["mapID"] = 1525,
                ["nodeKey"] = "Travel:CASTLE_NATHRIA_RAID",
                ["x"] = 0.46,
                ["y"] = 0.41,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Sire",
        ["spellID"] = 373190,
        ["type"] = "spell",
    },
    ["spell:373191"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Sanctum of Domination",
                ["mapID"] = 1543,
                ["nodeKey"] = "Travel:SANCTUM_OF_DOMINATION_RAID",
                ["x"] = 0.69,
                ["y"] = 0.31,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Tormented Soul",
        ["spellID"] = 373191,
        ["type"] = "spell",
    },
    ["spell:373192"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Sepulcher of the First Ones",
                ["mapID"] = 1970,
                ["nodeKey"] = "Travel:SEPULCHER_OF_THE_FIRST_ONES_RAID",
                ["x"] = 0.81,
                ["y"] = 0.53,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the First Ones",
        ["spellID"] = 373192,
        ["type"] = "spell",
    },
    ["spell:373262"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Karazhan",
                ["mapID"] = 42,
                ["nodeKey"] = "Travel:KARAZHAN",
                ["x"] = 0.473,
                ["y"] = 0.753,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Fallen Guardian",
        ["spellID"] = 373262,
        ["type"] = "spell",
    },
    ["spell:373274"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Operation: Mechagon",
                ["mapID"] = 1462,
                ["nodeKey"] = "Travel:OPERATION_MECHAGON_DUNGEON",
                ["x"] = 0.73,
                ["y"] = 0.36,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Scrappy Prince",
        ["spellID"] = 373274,
        ["type"] = "spell",
    },
    ["spell:393222"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Uldaman: Legacy of Tyr",
                ["mapID"] = 15,
                ["nodeKey"] = "Travel:ULDAMAN_LEGACY_OF_TYR_DUNGEON",
                ["x"] = 0.41,
                ["y"] = 0.1,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Watcher's Legacy",
        ["spellID"] = 393222,
        ["type"] = "spell",
    },
    ["spell:393256"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Ruby Life Pools",
                ["mapID"] = 2022,
                ["nodeKey"] = "Travel:RUBY_LIFE_POOLS_DUNGEON",
                ["x"] = 0.6,
                ["y"] = 0.75,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Clutch Defender",
        ["spellID"] = 393256,
        ["type"] = "spell",
    },
    ["spell:393262"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Nokhud Offensive",
                ["mapID"] = 2023,
                ["nodeKey"] = "Travel:THE_NOKHUD_OFFENSIVE_DUNGEON",
                ["x"] = 0.61,
                ["y"] = 0.39,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Windswept Plains",
        ["spellID"] = 393262,
        ["type"] = "spell",
    },
    ["spell:393267"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Brackenhide Hollow",
                ["mapID"] = 2024,
                ["nodeKey"] = "Travel:BRACKENHIDE_HOLLOW_DUNGEON",
                ["x"] = 0.11,
                ["y"] = 0.48,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Rotting Woods",
        ["spellID"] = 393267,
        ["type"] = "spell",
    },
    ["spell:393272"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Algeth'ar Academy",
                ["mapID"] = 2025,
                ["nodeKey"] = "Travel:ALGETHAR_ACADEMY_DUNGEON",
                ["x"] = 0.58,
                ["y"] = 0.42,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Draconic Diploma",
        ["spellID"] = 393272,
        ["type"] = "spell",
    },
    ["spell:393276"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Neltharus",
                ["mapID"] = 2022,
                ["nodeKey"] = "Travel:NELTHARUS_DUNGEON",
                ["x"] = 0.25,
                ["y"] = 0.56,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Obsidian Hoard",
        ["spellID"] = 393276,
        ["type"] = "spell",
    },
    ["spell:393279"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Azure Vault",
                ["mapID"] = 2024,
                ["nodeKey"] = "Travel:THE_AZURE_VAULT_DUNGEON",
                ["x"] = 0.38,
                ["y"] = 0.64,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Arcane Secrets",
        ["spellID"] = 393279,
        ["type"] = "spell",
    },
    ["spell:393283"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Halls of Infusion",
                ["mapID"] = 2025,
                ["nodeKey"] = "Travel:HALLS_OF_INFUSION_DUNGEON",
                ["x"] = 0.59,
                ["y"] = 0.6,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Titanic Reservoir",
        ["spellID"] = 393283,
        ["type"] = "spell",
    },
    ["spell:393764"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Halls of Valor",
                ["mapID"] = 634,
                ["nodeKey"] = "Travel:HALLS_OF_VALOR_DUNGEON",
                ["x"] = 0.68,
                ["y"] = 0.66,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Proven Worth",
        ["spellID"] = 393764,
        ["type"] = "spell",
    },
    ["spell:393766"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Court of Stars",
                ["mapID"] = 680,
                ["nodeKey"] = "Travel:COURT_OF_STARS_DUNGEON",
                ["x"] = 0.51,
                ["y"] = 0.65,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Grand Magistrix",
        ["spellID"] = 393766,
        ["type"] = "spell",
    },
    ["spell:395277"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room",
                ["mapID"] = 2112,
                ["nodeKey"] = "Travel:VALDRAKKEN",
                ["x"] = 0.596,
                ["y"] = 0.414,
            },
        },
        ["name"] = "Teleport: Valdrakken",
        ["spellID"] = 395277,
        ["type"] = "spell",
    },
    ["spell:410071"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Freehold",
                ["mapID"] = 895,
                ["nodeKey"] = "Travel:FREEHOLD_DUNGEON",
                ["x"] = 0.85,
                ["y"] = 0.79,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Freebooter",
        ["spellID"] = 410071,
        ["type"] = "spell",
    },
    ["spell:410074"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Underrot",
                ["mapID"] = 863,
                ["nodeKey"] = "Travel:THE_UNDERROT_DUNGEON",
                ["x"] = 0.52,
                ["y"] = 0.66,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Festering Rot",
        ["spellID"] = 410074,
        ["type"] = "spell",
    },
    ["spell:410078"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Neltharion's Lair",
                ["mapID"] = 650,
                ["nodeKey"] = "Travel:NELTHARIONS_LAIR_DUNGEON",
                ["x"] = 0.5,
                ["y"] = 0.68,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Earth-Warder",
        ["spellID"] = 410078,
        ["type"] = "spell",
    },
    ["spell:410080"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Vortex Pinnacle",
                ["mapID"] = 249,
                ["nodeKey"] = "Travel:THE_VORTEX_PINNACLE_DUNGEON",
                ["x"] = 0.76,
                ["y"] = 0.83,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Wind's Domain",
        ["spellID"] = 410080,
        ["type"] = "spell",
    },
    ["spell:424142"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Throne of the Tides",
                ["mapID"] = 204,
                ["nodeKey"] = "Travel:THRONE_OF_THE_TIDES_DUNGEON",
                ["x"] = 0.7,
                ["y"] = 0.3,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Tidehunter",
        ["spellID"] = 424142,
        ["type"] = "spell",
    },
    ["spell:424153"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Black Rook Hold",
                ["mapID"] = 641,
                ["nodeKey"] = "Travel:BLACK_ROOK_HOLD_DUNGEON",
                ["x"] = 0.39,
                ["y"] = 0.53,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Ancient Horrors",
        ["spellID"] = 424153,
        ["type"] = "spell",
    },
    ["spell:424163"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Darkheart Thicket",
                ["mapID"] = 641,
                ["nodeKey"] = "Travel:DARKHEART_THICKET_DUNGEON",
                ["x"] = 0.59,
                ["y"] = 0.31,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Nightmare Lord",
        ["spellID"] = 424163,
        ["type"] = "spell",
    },
    ["spell:424167"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Waycrest Manor",
                ["mapID"] = 896,
                ["nodeKey"] = "Travel:WAYCREST_MANOR_DUNGEON",
                ["x"] = 0.34,
                ["y"] = 0.13,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Heart's Bane",
        ["spellID"] = 424167,
        ["type"] = "spell",
    },
    ["spell:424187"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Atal'Dazar",
                ["mapID"] = 862,
                ["nodeKey"] = "Travel:ATALDAZAR_DUNGEON",
                ["x"] = 0.44,
                ["y"] = 0.39,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Golden Tomb",
        ["spellID"] = 424187,
        ["type"] = "spell",
    },
    ["spell:424197"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dawn of the Infinites",
                ["mapID"] = 2025,
                ["nodeKey"] = "Travel:DAWN_OF_THE_INFINITES_DUNGEON",
                ["x"] = 0.61,
                ["y"] = 0.84,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Twisted Time",
        ["spellID"] = 424197,
        ["type"] = "spell",
    },
    ["spell:432254"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Vault of the Incarnates",
                ["mapID"] = 2025,
                ["nodeKey"] = "Travel:VAULT_OF_THE_INCARNATES_RAID",
                ["x"] = 0.73,
                ["y"] = 0.55,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Primal Prison",
        ["spellID"] = 432254,
        ["type"] = "spell",
    },
    ["spell:432257"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Aberrus, the Shadowed Crucible",
                ["mapID"] = 2133,
                ["nodeKey"] = "Travel:ABERRUS_THE_SHADOWED_CRUCIBLE_RAID",
                ["x"] = 0.48,
                ["y"] = 0.11,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Bitter Legacy",
        ["spellID"] = 432257,
        ["type"] = "spell",
    },
    ["spell:432258"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Amirdrassil, the Dream's Hope",
                ["mapID"] = 2200,
                ["nodeKey"] = "Travel:AMIRDRASSIL_THE_DREAMS_HOPE_RAID",
                ["x"] = 0.28,
                ["y"] = 0.31,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Scorching Dream",
        ["spellID"] = 432258,
        ["type"] = "spell",
    },
    ["spell:445269"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Stonevault",
                ["mapID"] = 2248,
                ["nodeKey"] = "Travel:THE_STONEVAULT_DUNGEON",
                ["x"] = 0.42,
                ["y"] = 0.09,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Corrupted Foundry",
        ["spellID"] = 445269,
        ["type"] = "spell",
    },
    ["spell:445414"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Dawnbreaker",
                ["mapID"] = 2215,
                ["nodeKey"] = "Travel:THE_DAWNBREAKER_DUNGEON",
                ["x"] = 0.547,
                ["y"] = 0.629,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Arathi Flagship",
        ["spellID"] = 445414,
        ["type"] = "spell",
    },
    ["spell:445416"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "City of Threads",
                ["mapID"] = 2255,
                ["nodeKey"] = "Travel:CITY_OF_THREADS_DUNGEON",
                ["x"] = 0.47,
                ["y"] = 0.69,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of Nerubian Ascension",
        ["spellID"] = 445416,
        ["type"] = "spell",
    },
    ["spell:445417"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Ara-Kara, City of Echoes",
                ["mapID"] = 2255,
                ["nodeKey"] = "Travel:ARA_KARA_CITY_OF_ECHOES_DUNGEON",
                ["x"] = 0.49,
                ["y"] = 0.81,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Ruined City",
        ["spellID"] = 445417,
        ["type"] = "spell",
    },
    ["spell:445418"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Siege of Boralus",
                ["mapID"] = 895,
                ["nodeKey"] = "Travel:SIEGE_OF_BORALUS_DUNGEON_ALLIANCE",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.72,
                ["y"] = 0.23,
            },
        },
        ["faction"] = "Alliance",
        ["isDungeon"] = true,
        ["name"] = "Path of the Besieged Harbor",
        ["spellID"] = 445418,
        ["type"] = "spell",
    },
    ["spell:445424"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Grim Batol",
                ["mapID"] = 241,
                ["nodeKey"] = "Travel:GRIM_BATOL_DUNGEON",
                ["x"] = 0.19,
                ["y"] = 0.54,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Twilight Fortress",
        ["spellID"] = 445424,
        ["type"] = "spell",
    },
    ["spell:445440"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Cinderbrew Meadery",
                ["mapID"] = 2248,
                ["nodeKey"] = "Travel:CINDERBREW_MEADERY_DUNGEON",
                ["x"] = 0.76,
                ["y"] = 0.45,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Flaming Brewery",
        ["spellID"] = 445440,
        ["type"] = "spell",
    },
    ["spell:445441"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Darkflame Cleft",
                ["mapID"] = 2214,
                ["nodeKey"] = "Travel:DARKFLAME_CLEFT_DUNGEON",
                ["x"] = 0.56,
                ["y"] = 0.21,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Warding Candles",
        ["spellID"] = 445441,
        ["type"] = "spell",
    },
    ["spell:445443"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The Rookery",
                ["mapID"] = 2339,
                ["nodeKey"] = "Travel:THE_ROOKERY_DUNGEON",
                ["x"] = 0.317,
                ["y"] = 0.358,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Fallen Stormriders",
        ["spellID"] = 445443,
        ["type"] = "spell",
    },
    ["spell:445444"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Priory of the Sacred Flame",
                ["mapID"] = 2215,
                ["nodeKey"] = "Travel:PRIORY_OF_THE_SACRED_FLAME_DUNGEON",
                ["x"] = 0.412,
                ["y"] = 0.496,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Light's Reverence",
        ["spellID"] = 445444,
        ["type"] = "spell",
    },
    ["spell:446540"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Portal Room",
                ["mapID"] = 2339,
                ["nodeKey"] = "Travel:DORNOGAL_PORTAL_ROOM",
                ["x"] = 0.4127,
                ["y"] = 0.2743,
            },
        },
        ["name"] = "Teleport: Dornogal",
        ["spellID"] = 446540,
        ["type"] = "spell",
    },
    ["spell:464256"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Siege of Boralus",
                ["mapID"] = 895,
                ["nodeKey"] = "Travel:SIEGE_OF_BORALUS_DUNGEON_HORDE",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.88,
                ["y"] = 0.51,
            },
        },
        ["faction"] = "Horde",
        ["isDungeon"] = true,
        ["name"] = "Path of the Besieged Harbor",
        ["spellID"] = 464256,
        ["type"] = "spell",
    },
    ["spell:467546"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Cinderbrew Meadery",
                ["mapID"] = 2248,
                ["nodeKey"] = "Travel:CINDERBREW_MEADERY_DUNGEON",
                ["x"] = 0.76,
                ["y"] = 0.45,
            },
        },
        ["isDungeon"] = true,
        ["name"] = "Path of the Waterworks",
        ["spellID"] = 467546,
        ["type"] = "spell",
    },
    ["spell:467553"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The MOTHERLODE!!",
                ["mapID"] = 862,
                ["nodeKey"] = "Travel:THE_MOTHERLODE_DUNGEON_ALLIANCE",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.4,
                ["y"] = 0.72,
            },
        },
        ["faction"] = "Alliance",
        ["isDungeon"] = true,
        ["name"] = "Path of the Azerite Refinery",
        ["spellID"] = 467553,
        ["type"] = "spell",
    },
    ["spell:467555"] = {
        ["castTime"] = 10,
        ["cooldown"] = 28800,
        ["destinations"] = {
            [1] = {
                ["destination"] = "The MOTHERLODE!!",
                ["mapID"] = 862,
                ["nodeKey"] = "Travel:THE_MOTHERLODE_DUNGEON_HORDE",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.56,
                ["y"] = 0.6,
            },
        },
        ["faction"] = "Horde",
        ["isDungeon"] = true,
        ["name"] = "Path of the Azerite Refinery",
        ["spellID"] = 467555,
        ["type"] = "spell",
    },
    ["spell:49358"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Stonard",
                ["mapID"] = 76,
                ["nodeKey"] = "Travel:STONARD",
                ["x"] = 0.4984,
                ["y"] = 0.5581,
            },
        },
        ["name"] = "Teleport: Stonard",
        ["spellID"] = 49358,
        ["type"] = "spell",
    },
    ["spell:49359"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Theramore",
                ["mapID"] = 70,
                ["nodeKey"] = "Travel:THERAMORE",
                ["x"] = 0.66,
                ["y"] = 0.49,
            },
        },
        ["name"] = "Teleport: Theramore",
        ["spellID"] = 49359,
        ["type"] = "spell",
    },
    ["spell:50977"] = {
        ["castTime"] = 10,
        ["class"] = "DEATHKNIGHT",
        ["cooldown"] = 60,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Acherus",
                ["mapID"] = 648,
                ["nodeKey"] = "Travel:ACHERUS",
                ["x"] = 0.2743,
                ["y"] = 0.3043,
            },
        },
        ["name"] = "Death Gate",
        ["spellID"] = 50977,
        ["type"] = "spell",
    },
    ["spell:53140"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Dalaran (Northrend)",
                ["mapID"] = 125,
                ["nodeKey"] = "Travel:DALARAN_NORTHREND",
                ["x"] = 0.5592,
                ["y"] = 0.4678,
            },
        },
        ["name"] = "Teleport: Dalaran - Northrend",
        ["spellID"] = 53140,
        ["type"] = "spell",
    },
    ["spell:556"] = {
        ["castTime"] = 10,
        ["class"] = "SHAMAN",
        ["cooldown"] = 900,
        ["destinations"] = {},
        ["name"] = "Astral Recall",
        ["spellID"] = 556,
        ["type"] = "spell",
    },
    ["spell:88342"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Tol Barad Camp",
                ["mapID"] = 245,
                ["nodeKey"] = "Travel:TOL_BARAD_ALLIANCE",
                ["requirements"] = {
                    ["faction"] = "Alliance",
                },
                ["x"] = 0.724,
                ["y"] = 0.562,
            },
        },
        ["name"] = "Teleport: Tol Barad",
        ["spellID"] = 88342,
        ["type"] = "spell",
    },
    ["spell:88344"] = {
        ["castTime"] = 10,
        ["class"] = "MAGE",
        ["cooldown"] = 0,
        ["destinations"] = {
            [1] = {
                ["destination"] = "Tol Barad Camp",
                ["mapID"] = 245,
                ["nodeKey"] = "Travel:TOL_BARAD_HORDE",
                ["requirements"] = {
                    ["faction"] = "Horde",
                },
                ["x"] = 0.531,
                ["y"] = 0.76,
            },
        },
        ["name"] = "Teleport: Tol Barad",
        ["spellID"] = 88344,
        ["type"] = "spell",
    },
}

-- The reference omits this normal Northrend option. Coordinates cross-checked
-- against the player guide on Blizzard's forum (link in the attribution notice).
local northrend = QR.TeleportDestinationData["item:48933"].destinations
northrend[#northrend + 1] = {
    destination = "Icecrown (Wormhole)", choiceText = "Icecrown",
    mapID = 118, x = 0.65, y = 0.31, nodeKey = "Travel:ICECROWN_WORMHOLE",
}

-- The selected Draenor zone still has four random landings. Keep the device in
-- the inventory, but do not turn a zone-centre placeholder into a precise route.
QR.TeleportDestinationData["item:112059"].isRandom = true

-- Preserve QuickRoute equipment metadata while correcting cast times and adding
-- newly catalogued abilities. Runtime availability still requires actual ownership.
for key, supplement in pairs(QR.TeleportDestinationData) do
    local id = tonumber(key:match(":(%d+)$"))
    local target
    if supplement.type ~= "spell" then
        target = QR.TeleportItemsData
    elseif supplement.class then
        target = QR.ClassTeleportSpells
        if supplement.class == "MAGE" then
            target = QR.MageTeleports[supplement.faction] or QR.MageTeleports.Shared
            for _, group in pairs(QR.MageTeleports) do
                if group[id] then target = group; break end
            end
        end
    elseif supplement.race then
        target = QR.RacialTeleportSpells
    else
        target = QR.DungeonTeleportSpells and QR.DungeonTeleportSpells[id]
            and QR.DungeonTeleportSpells or QR.GeneralTeleportSpells
    end
    local data = target[id] or {}
    -- Existing QuickRoute coordinates were verified in the retail client.
    -- Keep those corrections over older reference aliases and interior maps.
    if #supplement.destinations == 1 and data.mapID and data.x and data.y and not data.isDynamic then
        local destination = supplement.destinations[1]
        destination.mapID, destination.x, destination.y = data.mapID, data.x, data.y
        destination.destination = data.destination or destination.destination
        destination.nodeKey = data.nodeKey
    end
    for _, destination in ipairs(supplement.destinations) do
        if #supplement.destinations > 1 then destination.choiceText = destination.destination end
    end
    for _, field in ipairs({"name", "castTime", "cooldown", "spellID"}) do
        if supplement[field] ~= nil then data[field] = supplement[field] end
    end
    data.type = data.type == "engineer" and supplement.type == "toy" and "toy" or data.type or supplement.type
    data.travelDestinationKey = key
    data.class = data.class or supplement.class
    data.race = data.race or supplement.race
    data.faction = data.faction or supplement.faction or "both"
    if #supplement.destinations > 1 then
        data.isDynamic = true
        data.multiDestination = true
    end
    if not data.destination then data.destination = supplement.name end
    if #supplement.destinations == 1 and not supplement.isRandom then
        for _, field in ipairs({"mapID", "x", "y", "requirements"}) do data[field] = supplement.destinations[1][field] end
        data.isDynamic = false
    end
    data.isRandom = supplement.isRandom or nil
    target[id] = data
end
