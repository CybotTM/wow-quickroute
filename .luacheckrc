-- Luacheck configuration for WoW Addon development
-- Run: luacheck QuickRoute/

-- Use Lua 5.1 (WoW uses Lua 5.1/LuaJIT)
std = "lua51"

-- WoW global variables
globals = {
    -- Addon namespace
    "QR",

    -- WoW API globals
    "CreateFrame",
    "UIParent",
    "GetTime",
    "UnitClass",
    "UnitFactionGroup",
    "UnitName",
    "GetProfessions",
    "GetProfessionInfo",
    "SlashCmdList",
    "SLASH_QR1",
    "SLASH_QR2",
    "SLASH_QRWP1",
    "SLASH_QRDEBUG1",
    "SLASH_QRHELP1",
    "SLASH_QRTEST1",
    "WorldMapFrame",
    "GameFontNormal",
    "GameFontNormalLarge",
    "GameFontNormalSmall",
    "GameFontHighlight",
    "GameFontHighlightSmall",

    -- WoW API namespaces
    "C_Map",
    "C_Container",
    "C_Spell",
    "C_Item",
    "C_SuperTrack",
    "C_QuestLog",
    "C_ToyBox",
    "C_Timer",

    -- WoW API functions
    "GetItemInfo",
    "GetItemIcon",
    "GetSpellInfo",
    "GetSpellLink",
    "GetItemCount",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetInventoryItemID",
    "IsFlyableArea",
    "IsSpellKnown",
    "PlayerHasToy",
    "InCombatLockdown",
    "GetLocale",
    "hooksecurefunc",
    "wipe",
    "GameTooltip",
    "GameTooltip_Hide",
    "UiMapPoint",

    -- WoW UI globals
    "UISpecialFrames",
    "ObjectiveTrackerFrame",

    -- SavedVariables
    "QuickRouteDB",

    -- TomTom (optional)
    "TomTom",

    -- Slash command globals
    "SLASH_QRPATH1",
    "SLASH_QRCD1",
    "SLASH_QRINV1",
}

-- Read-only globals
read_globals = {
    "print",
    "pairs",
    "ipairs",
    "type",
    "tostring",
    "tonumber",
    "setmetatable",
    "getmetatable",
    "pcall",
    "xpcall",
    "error",
    "assert",
    "select",
    "unpack",
    "next",
    "rawget",
    "rawset",
    "date",
    "string",
    "table",
    "math",
    "bit",
}

-- Ignore certain warnings
ignore = {
    "212", -- Unused argument (common in callbacks)
    "213", -- Unused loop variable
}

-- Max line length
max_line_length = 150

-- Exclude test files from some checks
files["**/Tests/**"] = {
    ignore = {"111"} -- Setting undefined global (for test setup)
}
