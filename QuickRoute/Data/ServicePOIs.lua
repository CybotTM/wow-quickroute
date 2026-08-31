-- ServicePOIs.lua
-- Static coordinates for common service NPCs (Auction House, Bank, Void Storage, Crafting Table)
-- in capital cities. Used by ServiceRouter to find nearest service via Dijkstra.
--
-- Darnassus (89) and Undercity (90) are deliberately absent. Both cities were
-- destroyed in Battle for Azeroth and the maps the client still ships for them
-- are the pre-destruction versions, reachable only by talking to Zidormi. In
-- the default phase a character walks into a burned tree or a plague-flooded
-- ruin, and the services below are not standing. The addon cannot tell which
-- phase a player is in, so it does not offer them at all -- the same call this
-- file already makes for pre-revamp Silvermoon (110). See issue #3.
local ADDON_NAME, QR = ...

QR.ServicePOIs = {
    AUCTION_HOUSE = {
        -- Alliance
        { mapID = 84,   x = 0.6105, y = 0.7064, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.2549, y = 0.7468, faction = "Alliance" },  -- Ironforge
        { mapID = 103,  x = 0.4842, y = 0.6925, faction = "Alliance" },  -- Exodar
        { mapID = 1161, x = 0.7195, y = 0.1298, faction = "Alliance" },  -- Boralus
        -- Horde
        { mapID = 85,   x = 0.5430, y = 0.6295, faction = "Horde" },     -- Orgrimmar
        { mapID = 88,   x = 0.3920, y = 0.5296, faction = "Horde" },     -- Thunder Bluff
        -- Map switched from 110 to the revamped Silvermoon 2393. Both maps
        -- exist and are both named "Silvermoon"; 2393 is the one the player
        -- stands on. These coordinates were surveyed on 110 and have NOT
        -- been re-surveyed on the new layout.
        { mapID = 2393, x = 0.6748, y = 0.3048, faction = "Horde" },     -- Silvermoon
        { mapID = 1165, x = 0.4228, y = 0.3283, faction = "Horde" },     -- Dazar'alor
        -- Neutral
        { mapID = 125,  x = 0.4264, y = 0.6397, faction = "both" },      -- Dalaran (Northrend)
        { mapID = 627,  x = 0.4264, y = 0.5545, faction = "both" },      -- Dalaran (Broken Isles)
        { mapID = 1670, x = 0.5844, y = 0.5576, faction = "both" },      -- Oribos
        { mapID = 2112, x = 0.4686, y = 0.5695, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.5542, y = 0.5632, faction = "both" },      -- Dornogal
    },
    BANK = {
        -- Alliance
        { mapID = 84,   x = 0.6282, y = 0.6995, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.3530, y = 0.6270, faction = "Alliance" },  -- Ironforge
        { mapID = 103,  x = 0.4734, y = 0.6435, faction = "Alliance" },  -- Exodar
        { mapID = 1161, x = 0.7600, y = 0.1657, faction = "Alliance" },  -- Boralus
        -- Horde
        { mapID = 85,   x = 0.5330, y = 0.6455, faction = "Horde" },     -- Orgrimmar
        { mapID = 88,   x = 0.4530, y = 0.5230, faction = "Horde" },     -- Thunder Bluff
        -- Coordinates surveyed on map 110, not re-surveyed on 2393.
        { mapID = 2393, x = 0.5780, y = 0.2190, faction = "Horde" },     -- Silvermoon
        { mapID = 1165, x = 0.4468, y = 0.3538, faction = "Horde" },     -- Dazar'alor
        -- Neutral
        { mapID = 125,  x = 0.4777, y = 0.6335, faction = "both" },      -- Dalaran (Northrend)
        { mapID = 627,  x = 0.4777, y = 0.5310, faction = "both" },      -- Dalaran (Broken Isles)
        { mapID = 1670, x = 0.6176, y = 0.4818, faction = "both" },      -- Oribos
        { mapID = 2112, x = 0.5720, y = 0.3425, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.4952, y = 0.5188, faction = "both" },      -- Dornogal
    },
    VOID_STORAGE = {
        -- Alliance
        { mapID = 84,   x = 0.6253, y = 0.7025, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.3550, y = 0.6240, faction = "Alliance" },  -- Ironforge
        -- Horde
        { mapID = 85,   x = 0.5350, y = 0.6430, faction = "Horde" },     -- Orgrimmar
        -- Neutral
        { mapID = 2112, x = 0.5730, y = 0.3420, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.4945, y = 0.5200, faction = "both" },      -- Dornogal
    },
    CRAFTING_TABLE = {
        { mapID = 2339, x = 0.4780, y = 0.5280, faction = "both" },      -- Dornogal
        { mapID = 2112, x = 0.3580, y = 0.6240, faction = "both" },      -- Valdrakken
    },
}

-- Service type metadata for display and slash commands
QR.ServiceTypes = {
    AUCTION_HOUSE  = { icon = "Interface\\Icons\\INV_Misc_Coin_01", slashAlias = "ah" },
    BANK           = { icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue", slashAlias = "bank" },
    VOID_STORAGE   = { icon = "Interface\\Icons\\Spell_Nature_AstralRecalGroup", slashAlias = "void" },
    CRAFTING_TABLE = { icon = "Interface\\Icons\\Trade_Blacksmithing", slashAlias = "craft" },
}
