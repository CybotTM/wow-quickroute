-- Luacheck configuration for WoW Addon development
-- Run: luacheck QuickRoute/

-- Use Lua 5.1 (WoW uses Lua 5.1/LuaJIT)
std = "lua51"

-- WoW global variables (read-write)
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
    "C_TaskQuest",

    -- WoW API functions
    "GetItemInfo",
    "GetItemIcon",
    "GetSpellInfo",
    "GetSpellLink",
    "GetSpellTexture",
    "GetSpellCooldown",
    "GetItemCount",
    "GetItemCooldown",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetContainerItemID",
    "GetInventoryItemID",
    "IsFlyableArea",
    "IsSpellKnown",
    "IsInInstance",
    "IsAtBank",
    "IsControlKeyDown",
    "PlayerHasToy",
    "InCombatLockdown",
    "GetLocale",
    "GetBuildInfo",
    "GetBindLocation",
    "GetCursorPosition",
    "GetQuestLink",
    "GetAchievementLink",
    "GetNumFactions",
    "GetFactionInfo",
    "SetPortraitToTexture",
    "PlaySound",
    "hooksecurefunc",
    "wipe",
    "GameTooltip",
    "GameTooltip_Hide",
    "UiMapPoint",

    -- WoW UI globals
    "UISpecialFrames",
    "ObjectiveTrackerFrame",
    "QuestMapFrame",
    "Minimap",
    "SOUNDKIT",
    "Settings",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "MinimalSliderWithSteppersMixin",

    -- WoW constants
    "NUM_BAG_SLOTS",
    "INVSLOT_TRINKET1",
    "INVSLOT_TRINKET2",
    "INVSLOT_FINGER1",
    "INVSLOT_FINGER2",
    "INVSLOT_TABARD",

    -- SavedVariables
    "QuickRouteDB",

    -- TomTom (optional)
    "TomTom",

    -- Slash command globals
    "SLASH_QR1",
    "SLASH_QR2",
    "SLASH_QRWP1",
    "SLASH_QRDEBUG1",
    "SLASH_QRHELP1",
    "SLASH_QRTEST1",
    "SLASH_QRPATH1",
    "SLASH_QRCD1",
    "SLASH_QRINV1",
    "SLASH_QRGRAPH1",
    "SLASH_QRZONE1",
    "SLASH_QRDEBUGPATH1",
    "SLASH_QRSCAN1",
    "SLASH_QRTELEPORTS1",

    -- Addon compartment functions (referenced in TOC)
    "QuickRoute_OnAddonCompartmentClick",
    "QuickRoute_OnAddonCompartmentEnter",
    "QuickRoute_OnAddonCompartmentLeave",
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
    "131", -- Unused implicitly defined global variable
    "211", -- Unused local variable (common: cached globals, ADDON_NAME)
    "212", -- Unused argument (common in callbacks)
    "213", -- Unused loop variable
    "631", -- Line too long
}

-- Max line length (warning only, suppressed via 631 above)
max_line_length = 150

-- Exclude in-game test files from some checks
files["**/Tests/**"] = {
    ignore = {"111"} -- Setting undefined global (for test setup)
}
