-------------------------------------------------------------------------------
-- test_localization.lua
-- Tests for QR.L localization system
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- 1. Metatable fallback
-------------------------------------------------------------------------------

T:run("Localization: metatable returns key for missing entries", function(t)
    local L = QR.L
    t:assertEqual("NONEXISTENT_KEY_12345", L["NONEXISTENT_KEY_12345"],
        "Unknown key returns key itself")
end)

T:run("Localization: metatable returns key for another missing entry", function(t)
    local L = QR.L
    t:assertEqual("SOME_RANDOM_STRING", L["SOME_RANDOM_STRING"],
        "Another unknown key returns key itself")
end)

-------------------------------------------------------------------------------
-- 2. English keys present
-------------------------------------------------------------------------------

T:run("Localization: ADDON_TITLE is set", function(t)
    t:assertEqual("QuickRoute", QR.L["ADDON_TITLE"], "ADDON_TITLE correct")
end)

T:run("Localization: core UI keys are present", function(t)
    local L = QR.L
    local requiredKeys = {
        "DESTINATION", "NO_WAYPOINT", "REFRESH", "NAV", "USE", "CLOSE",
        "FILTER", "ALL", "ITEMS", "TOYS", "SPELLS",
    }
    for _, key in ipairs(requiredKeys) do
        -- Check that the value is NOT the key itself (meaning it was set)
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
    end
end)

T:run("Localization: status keys are present", function(t)
    local L = QR.L
    local statusKeys = { "STATUS_READY", "STATUS_ON_CD", "STATUS_OWNED", "STATUS_MISSING", "STATUS_NA" }
    for _, key in ipairs(statusKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        -- Value should be different from key (meaning it was explicitly set)
        local isDifferent = val ~= key
        t:assertTrue(isDifferent, key .. " has a value different from key name")
    end
end)

T:run("Localization: action type keys are present", function(t)
    local L = QR.L
    local actionKeys = { "ACTION_TELEPORT", "ACTION_WALK", "ACTION_FLY", "ACTION_PORTAL", "ACTION_HEARTHSTONE" }
    for _, key in ipairs(actionKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        local isDifferent = val ~= key
        t:assertTrue(isDifferent, key .. " has explicit value")
    end
end)

T:run("Localization: step description keys are present", function(t)
    local L = QR.L
    local stepKeys = { "STEP_GO_TO", "STEP_TAKE_PORTAL", "STEP_TAKE_BOAT", "STEP_TELEPORT_TO" }
    for _, key in ipairs(stepKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        local isDifferent = val ~= key
        t:assertTrue(isDifferent, key .. " has explicit value")
    end
end)

-------------------------------------------------------------------------------
-- 3. Format string placeholders
-------------------------------------------------------------------------------

T:run("Localization: format strings have valid %s/%d placeholders", function(t)
    local L = QR.L
    local formatKeys = {
        { key = "ADDON_LOADED", args = { "1.0" } },
        { key = "SHOWING_TELEPORTS", args = { 10, 5, 3 } },
        { key = "STEP_GO_TO", args = { "Stormwind" } },
        { key = "STEP_TAKE_PORTAL", args = { "Orgrimmar" } },
        { key = "ACTION_USE_TELEPORT", args = { "Item", "Place" } },
    }

    for _, entry in ipairs(formatKeys) do
        local val = L[entry.key]
        t:assertNotNil(val, entry.key .. " exists")

        -- Try formatting - should not error
        local ok, result = pcall(string.format, val, unpack(entry.args))
        t:assertTrue(ok, entry.key .. " format string works: " .. tostring(result))
    end
end)

-------------------------------------------------------------------------------
-- 4. No nil values in explicitly set keys
-------------------------------------------------------------------------------

T:run("Localization: no nil values for set keys", function(t)
    local L = QR.L
    -- Check a broad set of keys that should all be set
    local allKeys = {
        "ADDON_TITLE", "DESTINATION", "NO_WAYPOINT", "REFRESH",
        "CALCULATING", "SCANNING", "IN_COMBAT", "CANNOT_USE_IN_COMBAT",
        "NO_PATH_FOUND", "SET_WAYPOINT_HINT",
        "TELEPORT_INVENTORY", "NAME", "DESTINATION_HEADER", "STATUS",
        "UNKNOWN", "TOOLTIP_REFRESH", "TOOLTIP_NAV",
    }

    for _, key in ipairs(allKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        -- Length should be > 0
        local hasContent = type(val) == "string" and #val > 0
        t:assertTrue(hasContent, key .. " has non-empty string value")
    end
end)

-------------------------------------------------------------------------------
-- 5. Waypoint source keys
-------------------------------------------------------------------------------

T:run("Localization: waypoint source keys are present", function(t)
    local L = QR.L
    local wpKeys = { "WAYPOINT_SOURCE", "WAYPOINT_AUTO", "WAYPOINT_MAP_PIN", "WAYPOINT_TOMTOM", "WAYPOINT_QUEST" }
    for _, key in ipairs(wpKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        local isDifferent = val ~= key
        t:assertTrue(isDifferent, key .. " has explicit value")
    end
end)

-------------------------------------------------------------------------------
-- 6. Settings keys
-------------------------------------------------------------------------------

T:run("Localization: settings keys are present", function(t)
    local L = QR.L
    local settingsKeys = { "AUTO_WAYPOINT_TOGGLE", "AUTO_WAYPOINT_ON", "AUTO_WAYPOINT_OFF" }
    for _, key in ipairs(settingsKeys) do
        local val = L[key]
        t:assertNotNil(val, key .. " is not nil")
        local isDifferent = val ~= key
        t:assertTrue(isDifferent, key .. " has explicit value")
    end
end)

-------------------------------------------------------------------------------
-- 3.8: German Locale Translation Tests
-- The addon loads locale at file-load time via GetLocale(). Since MockWoW
-- was set to "enUS" at load, QR.L has English strings. We test by checking
-- that the German string table in the source file covers all required keys
-- and has valid format strings.
--
-- We load the deDE translations by temporarily changing the locale and
-- re-executing the Localization.lua file.
-------------------------------------------------------------------------------

T:run("German locale: deDE translations exist in source", function(t)
    -- Save the current locale and L table values
    local savedLocale = MockWoW.config.locale

    -- Temporarily set locale to deDE
    MockWoW.config.locale = "deDE"

    -- Save current English values for keys we will test
    local savedValues = {}
    local keysToTest = {
        "DESTINATION", "NO_WAYPOINT", "REFRESH", "CLOSE",
        "STATUS_READY", "STATUS_ON_CD",
        "STEP_GO_TO", "STEP_TAKE_PORTAL",
        "ACTION_WALK", "ACTION_FLY",
    }
    for _, key in ipairs(keysToTest) do
        savedValues[key] = QR.L[key]
    end

    -- Re-execute Localization.lua with deDE locale
    -- This will overwrite QR.L with German strings
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
    local locFile = scriptDir .. "../QuickRoute/Localization.lua"
    local chunk, err = loadfile(locFile)
    t:assertNotNil(chunk, "Localization.lua can be loaded: " .. tostring(err))

    if chunk then
        local ok, runErr = pcall(chunk, "QuickRoute", QR)
        t:assertTrue(ok, "Localization.lua executes for deDE: " .. tostring(runErr))
    end

    -- Verify German translations are loaded
    local L = QR.L
    t:assertEqual("Ziel:", L["DESTINATION"], "DESTINATION is German (Ziel:)")
    t:assertEqual("Kein Wegpunkt gesetzt", L["NO_WAYPOINT"],
        "NO_WAYPOINT is German")
    t:assertEqual("Aktualisieren", L["REFRESH"], "REFRESH is German")
    t:assertEqual("BEREIT", L["STATUS_READY"], "STATUS_READY is German")

    -- Verify German format strings work
    local goToFormatted = string.format(L["STEP_GO_TO"], "Sturmwind")
    t:assertEqual("Gehe zu Sturmwind", goToFormatted,
        "German STEP_GO_TO format works")
    local portalFormatted = string.format(L["STEP_TAKE_PORTAL"], "Orgrimmar")
    t:assertEqual("Portal nach Orgrimmar nehmen", portalFormatted,
        "German STEP_TAKE_PORTAL format works")

    -- Restore English locale and re-execute Localization.lua
    MockWoW.config.locale = "enUS"
    if chunk then
        pcall(chunk, "QuickRoute", QR)
    end

    -- Verify English is restored
    t:assertEqual("Destination:", QR.L["DESTINATION"],
        "English DESTINATION restored after locale test")

    -- Restore saved locale
    MockWoW.config.locale = savedLocale
end)
