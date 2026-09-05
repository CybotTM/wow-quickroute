-- ServicePOIs.lua
-- Static coordinates for common service NPCs (Auction House, Bank, Void Storage, Crafting Table)
-- in capital cities. Used by ServiceRouter to find nearest service via Dijkstra.
--
-- Darnassus (89) and Undercity (90) are deliberately absent. Both cities were
-- destroyed in Battle for Azeroth and the maps the client still ships for them
-- are the pre-destruction versions, reachable only by talking to Zidormi. In
-- the default phase a character walks into a burned tree or a plague-flooded
-- ruin, and the old services are not standing. Until their service positions
-- are verified for each phase, these points remain omitted. See issue #3.
-- Midnight Silvermoon points below are on the new map 2393, independently
-- surveyed with screenshots by Tayder (2026-02-26):
-- https://www.method.gg/guides/location-of-the-auction-house-bank-notable-npcs-and-vendors-in-midnight-silvermoon-city
-- Its shared services are accessible to both factions; the separate enclave
-- services remain Horde-only. Old map 110 coordinates must not be copied here.
local ADDON_NAME, QR = ...

QR.ServicePOIs = {
    AUCTION_HOUSE = {
        -- Alliance
        { mapID = 84,   x = 0.6105, y = 0.7064, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.2549, y = 0.7468, faction = "Alliance" },  -- Ironforge
        { mapID = 103,  x = 0.4842, y = 0.6925, faction = "Alliance" },  -- Exodar
        -- Brassbolt, player-surveyed Boralus/Legion coordinates and access:
        -- https://www.wowhead.com/npc=35594/brassbolt-mechawrench#comments
        { mapID = 1161, x = 0.7708, y = 0.1407, faction = "Alliance", requiresEngineering = true }, -- Boralus
        -- Horde
        { mapID = 85,   x = 0.5430, y = 0.6295, faction = "Horde" },     -- Orgrimmar
        { mapID = 88,   x = 0.3920, y = 0.5296, faction = "Horde" },     -- Thunder Bluff
        { mapID = 2393, x = 0.6764, y = 0.7074, faction = "Horde" },     -- Silvermoon Horde enclave
        -- https://www.wowhead.com/guide/dazaralor-horde-city-important-locations
        { mapID = 1165, x = 0.44, y = 0.40, faction = "Horde", requiresEngineering = true }, -- Dazar'alor
        -- Neutral
        { mapID = 2393, x = 0.5028, y = 0.7486, faction = "both" },      -- Silvermoon shared district
        -- Northrend's Like Clockwork auctioneers became public in Cataclysm;
        -- do not apply Legion's engineering restriction to this older city.
        -- https://www.wowhead.com/npc=35607/reginald-arcfire#comments
        { mapID = 125,  x = 0.3878, y = 0.2515, faction = "both" },      -- Dalaran (Northrend)
        { mapID = 627,  x = 0.392, y = 0.259, faction = "both", requiresEngineering = true }, -- Dalaran (Broken Isles)
        -- https://www.wowchakra.com/wow/guia-de-ingenieria-de-shadowlands
        -- https://www.wow-professions.com/guides/shadowlands-engineering-guide
        { mapID = 1670, x = 0.384, y = 0.438, faction = "both", requiresEngineering = true }, -- Oribos
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
        { mapID = 2393, x = 0.7204, y = 0.6487, faction = "Horde" },     -- Silvermoon Horde enclave
        { mapID = 1165, x = 0.4468, y = 0.3538, faction = "Horde" },     -- Dazar'alor
        -- Neutral
        { mapID = 2393, x = 0.5064, y = 0.6543, faction = "both" },      -- Silvermoon shared district
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
