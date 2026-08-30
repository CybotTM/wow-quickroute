-------------------------------------------------------------------------------
-- test_data_validation.lua
-- Data integrity tests for TeleportItems, Portals, and Localization data
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local VALID_TYPES = {
    [QR.TeleportTypes.HEARTHSTONE] = true,
    [QR.TeleportTypes.TOY] = true,
    [QR.TeleportTypes.ITEM] = true,
    [QR.TeleportTypes.SPELL] = true,
    [QR.TeleportTypes.ENGINEER] = true,
}

local VALID_FACTIONS = { Alliance = true, Horde = true, both = true }

local VALID_PORTAL_TYPES = { portal = true, boat = true, zeppelin = true, tram = true }

-------------------------------------------------------------------------------
-- Helper: count format placeholders (%s, %d, %f, etc.) in a string
-------------------------------------------------------------------------------
local function countPlaceholders(str)
    local count = 0
    -- Match %[flags][width][.precision]specifier but skip %%
    for _ in str:gmatch("%%[^%%]") do
        count = count + 1
    end
    -- Subtract escaped %% which we counted
    for _ in str:gmatch("%%%%") do
        count = count - 1
    end
    return count
end

-------------------------------------------------------------------------------
-- 1. TeleportItemsData field validation
-------------------------------------------------------------------------------

T:run("Data: TeleportItemsData has entries", function(t)
    local count = 0
    for _ in pairs(QR.TeleportItemsData) do count = count + 1 end
    t:assertGreaterThan(count, 0, "TeleportItemsData is not empty")
    t:assertGreaterThan(count, 20, "TeleportItemsData has >20 entries")
end)

T:run("Data: TeleportItemsData entries have required fields", function(t)
    for id, data in pairs(QR.TeleportItemsData) do
        local prefix = "[" .. id .. "] "

        -- Required: name (string)
        t:assert(type(data.name) == "string" and #data.name > 0,
            prefix .. "has non-empty name")

        -- Required: destination (string)
        t:assert(type(data.destination) == "string" and #data.destination > 0,
            prefix .. "has non-empty destination")

        -- Required: type (valid enum)
        t:assert(VALID_TYPES[data.type],
            prefix .. "has valid type '" .. tostring(data.type) .. "'")

        -- Required: faction (valid value)
        t:assert(VALID_FACTIONS[data.faction],
            prefix .. "has valid faction '" .. tostring(data.faction) .. "'")

        -- Required: cooldown (non-negative number)
        t:assert(type(data.cooldown) == "number" and data.cooldown >= 0,
            prefix .. "has valid cooldown " .. tostring(data.cooldown))

        -- Optional mapID: must be number if present (nil for dynamic)
        if data.mapID ~= nil then
            t:assert(type(data.mapID) == "number" and data.mapID > 0,
                prefix .. "mapID is positive number")
        end

        -- If mapID present, x and y should be present for non-dynamic
        if data.mapID and not data.isDynamic then
            t:assert(type(data.x) == "number",
                prefix .. "has x coordinate")
            t:assert(type(data.y) == "number",
                prefix .. "has y coordinate")
        end
    end
end)

T:run("Data: TeleportItemsData coordinates are in 0-1 range", function(t)
    for id, data in pairs(QR.TeleportItemsData) do
        if data.x then
            t:assert(data.x >= 0 and data.x <= 1,
                "[" .. id .. "] x=" .. data.x .. " in range [0,1]")
        end
        if data.y then
            t:assert(data.y >= 0 and data.y <= 1,
                "[" .. id .. "] y=" .. data.y .. " in range [0,1]")
        end
    end
end)

T:run("Data: TeleportItemsData IDs are positive integers", function(t)
    for id, _ in pairs(QR.TeleportItemsData) do
        t:assert(type(id) == "number" and id > 0 and id == math.floor(id),
            "ID " .. tostring(id) .. " is a positive integer")
    end
end)

-------------------------------------------------------------------------------
-- 2. ClassTeleportSpells field validation
-------------------------------------------------------------------------------

T:run("Data: ClassTeleportSpells has entries", function(t)
    local count = 0
    for _ in pairs(QR.ClassTeleportSpells) do count = count + 1 end
    t:assertGreaterThan(count, 0, "ClassTeleportSpells is not empty")
end)

T:run("Data: ClassTeleportSpells entries have required fields", function(t)
    local validClasses = {
        DEATHKNIGHT = true, MONK = true, DRUID = true,
        DEMONHUNTER = true, SHAMAN = true, EVOKER = true,
    }

    for id, data in pairs(QR.ClassTeleportSpells) do
        local prefix = "[" .. id .. "] "

        t:assert(type(data.name) == "string" and #data.name > 0,
            prefix .. "has name")
        t:assert(type(data.destination) == "string" and #data.destination > 0,
            prefix .. "has destination")
        t:assert(data.type == QR.TeleportTypes.SPELL,
            prefix .. "type is SPELL")
        t:assert(type(data.class) == "string" and validClasses[data.class],
            prefix .. "has valid class '" .. tostring(data.class) .. "'")
        t:assert(type(data.cooldown) == "number" and data.cooldown >= 0,
            prefix .. "has valid cooldown")

        if data.mapID and not data.isDynamic then
            t:assert(type(data.x) == "number" and type(data.y) == "number",
                prefix .. "has coordinates when mapID is set")
        end
    end
end)

-------------------------------------------------------------------------------
-- 3. RacialTeleportSpells field validation
-------------------------------------------------------------------------------

T:run("Data: RacialTeleportSpells has entries", function(t)
    t:assertNotNil(QR.RacialTeleportSpells, "RacialTeleportSpells exists")
    local count = 0
    for _ in pairs(QR.RacialTeleportSpells) do count = count + 1 end
    t:assertGreaterThan(count, 0, "RacialTeleportSpells is not empty")
end)

T:run("Data: RacialTeleportSpells entries have required fields", function(t)
    for id, data in pairs(QR.RacialTeleportSpells) do
        local prefix = "[" .. id .. "] "

        t:assert(type(data.name) == "string" and #data.name > 0,
            prefix .. "has name")
        t:assert(type(data.destination) == "string" and #data.destination > 0,
            prefix .. "has destination")
        t:assert(data.type == QR.TeleportTypes.SPELL,
            prefix .. "type is SPELL")
        t:assert(VALID_FACTIONS[data.faction],
            prefix .. "has valid faction")
        t:assert(type(data.race) == "string" and #data.race > 0,
            prefix .. "has race")
        t:assert(type(data.cooldown) == "number" and data.cooldown >= 0,
            prefix .. "has valid cooldown")

        if data.mapID and not data.isDynamic then
            t:assert(type(data.x) == "number" and type(data.y) == "number",
                prefix .. "has coordinates when mapID is set")
        end
    end
end)

-------------------------------------------------------------------------------
-- 4. MageTeleports field validation
-------------------------------------------------------------------------------

T:run("Data: MageTeleports has Alliance, Horde, Shared tables", function(t)
    t:assertNotNil(QR.MageTeleports.Alliance, "Alliance table exists")
    t:assertNotNil(QR.MageTeleports.Horde, "Horde table exists")
    t:assertNotNil(QR.MageTeleports.Shared, "Shared table exists")

    local allianceCount, hordeCount, sharedCount = 0, 0, 0
    for _ in pairs(QR.MageTeleports.Alliance) do allianceCount = allianceCount + 1 end
    for _ in pairs(QR.MageTeleports.Horde) do hordeCount = hordeCount + 1 end
    for _ in pairs(QR.MageTeleports.Shared) do sharedCount = sharedCount + 1 end

    t:assertGreaterThan(allianceCount, 0, "Alliance has mage teleports")
    t:assertGreaterThan(hordeCount, 0, "Horde has mage teleports")
    t:assertGreaterThan(sharedCount, 0, "Shared has mage teleports")
end)

T:run("Data: MageTeleports entries have required fields", function(t)
    for factionName, factionTable in pairs(QR.MageTeleports) do
        for id, data in pairs(factionTable) do
            local prefix = factionName .. "[" .. id .. "] "

            t:assert(type(data.name) == "string" and #data.name > 0,
                prefix .. "has name")
            t:assert(type(data.destination) == "string" and #data.destination > 0,
                prefix .. "has destination")
            t:assert(data.type == QR.TeleportTypes.SPELL,
                prefix .. "type is SPELL")
            t:assert(data.class == "MAGE",
                prefix .. "class is MAGE")
            t:assert(type(data.cooldown) == "number" and data.cooldown >= 0,
                prefix .. "has valid cooldown")
            t:assert(type(data.mapID) == "number" and data.mapID > 0,
                prefix .. "has positive mapID")
            t:assert(type(data.x) == "number" and data.x >= 0 and data.x <= 1,
                prefix .. "x in range [0,1]")
            t:assert(type(data.y) == "number" and data.y >= 0 and data.y <= 1,
                prefix .. "y in range [0,1]")
        end
    end
end)

T:run("Data: No duplicate spell IDs across MageTeleports factions", function(t)
    local seen = {}
    for factionName, factionTable in pairs(QR.MageTeleports) do
        for id, _ in pairs(factionTable) do
            t:assert(not seen[id],
                "Spell " .. id .. " in " .. factionName .. " not duplicated (first in " .. tostring(seen[id]) .. ")")
            seen[id] = factionName
        end
    end
end)

-------------------------------------------------------------------------------
-- 5. PortalHubs field validation
-------------------------------------------------------------------------------

T:run("Data: PortalHubs has entries", function(t)
    local count = 0
    for _ in pairs(QR.PortalHubs) do count = count + 1 end
    t:assertGreaterThan(count, 0, "PortalHubs is not empty")
end)

T:run("Data: PortalHubs entries have required fields", function(t)
    for hubName, hub in pairs(QR.PortalHubs) do
        local prefix = hubName .. ": "

        t:assert(type(hub.mapID) == "number" and hub.mapID > 0,
            prefix .. "has positive mapID")
        t:assert(type(hub.x) == "number" and hub.x >= 0 and hub.x <= 1,
            prefix .. "x in range [0,1]")
        t:assert(type(hub.y) == "number" and hub.y >= 0 and hub.y <= 1,
            prefix .. "y in range [0,1]")
        t:assert(VALID_FACTIONS[hub.faction],
            prefix .. "has valid faction")
        t:assert(type(hub.portals) == "table" and #hub.portals > 0,
            prefix .. "has at least one portal")

        -- Validate each portal in the hub
        for i, portal in ipairs(hub.portals) do
            local pPrefix = prefix .. "portal[" .. i .. "]: "

            t:assert(type(portal.destination) == "string" and #portal.destination > 0,
                pPrefix .. "has destination")
            t:assert(type(portal.mapID) == "number" and portal.mapID > 0,
                pPrefix .. "has positive mapID")
            t:assert(type(portal.x) == "number" and portal.x >= 0 and portal.x <= 1,
                pPrefix .. "x in range [0,1]")
            t:assert(type(portal.y) == "number" and portal.y >= 0 and portal.y <= 1,
                pPrefix .. "y in range [0,1]")

            -- Faction if present must be valid
            if portal.faction then
                t:assert(VALID_FACTIONS[portal.faction],
                    pPrefix .. "has valid faction")
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- 6. StandalonePortals field validation
-------------------------------------------------------------------------------

T:run("Data: StandalonePortals has entries", function(t)
    t:assert(type(QR.StandalonePortals) == "table", "StandalonePortals is a table")
    t:assertGreaterThan(#QR.StandalonePortals, 0, "StandalonePortals is not empty")
end)

T:run("Data: StandalonePortals entries have required fields", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        local prefix = "StandalonePortal[" .. i .. "]: "

        t:assert(type(portal.name) == "string" and #portal.name > 0,
            prefix .. "has name")
        t:assert(VALID_FACTIONS[portal.faction],
            prefix .. "has valid faction")
        t:assert(VALID_PORTAL_TYPES[portal.type],
            prefix .. "has valid type '" .. tostring(portal.type) .. "'")
        t:assert(type(portal.travelTime) == "number" and portal.travelTime > 0,
            prefix .. "has positive travelTime")

        -- from location
        t:assert(type(portal.from) == "table", prefix .. "has 'from' table")
        t:assert(type(portal.from.mapID) == "number" and portal.from.mapID > 0,
            prefix .. "from.mapID is positive")
        t:assert(type(portal.from.x) == "number" and portal.from.x >= 0 and portal.from.x <= 1,
            prefix .. "from.x in range [0,1]")
        t:assert(type(portal.from.y) == "number" and portal.from.y >= 0 and portal.from.y <= 1,
            prefix .. "from.y in range [0,1]")

        -- to location
        t:assert(type(portal.to) == "table", prefix .. "has 'to' table")
        t:assert(type(portal.to.mapID) == "number" and portal.to.mapID > 0,
            prefix .. "to.mapID is positive")
        t:assert(type(portal.to.x) == "number" and portal.to.x >= 0 and portal.to.x <= 1,
            prefix .. "to.x in range [0,1]")
        t:assert(type(portal.to.y) == "number" and portal.to.y >= 0 and portal.to.y <= 1,
            prefix .. "to.y in range [0,1]")
    end
end)

-------------------------------------------------------------------------------
-- 7. GetTeleportDataByID cross-checks
-------------------------------------------------------------------------------

T:run("Data: GetTeleportDataByID finds items from all tables", function(t)
    -- Pick one ID from each table
    local hearthstoneData = QR:GetTeleportDataByID(6948)
    t:assertNotNil(hearthstoneData, "Hearthstone (6948) found")
    t:assertEqual("Hearthstone", hearthstoneData.name, "Hearthstone name correct")

    -- Class spell
    local deathGateData = QR:GetTeleportDataByID(50977)
    t:assertNotNil(deathGateData, "Death Gate (50977) found")
    t:assertEqual("Death Gate", deathGateData.name, "Death Gate name correct")

    -- Racial spell
    local moleMachineData = QR:GetTeleportDataByID(265225)
    t:assertNotNil(moleMachineData, "Mole Machine (265225) found")
    t:assertEqual("Mole Machine", moleMachineData.name, "Mole Machine name correct")

    -- Mage teleport (Alliance)
    local stormwindMage = QR:GetTeleportDataByID(3561)
    t:assertNotNil(stormwindMage, "Mage Teleport: Stormwind (3561) found")

    -- Mage teleport (Shared)
    local shattrathMage = QR:GetTeleportDataByID(33690)
    t:assertNotNil(shattrathMage, "Mage Teleport: Shattrath (33690) found")

    -- Nonexistent ID
    local missing = QR:GetTeleportDataByID(999999999)
    t:assertNil(missing, "Nonexistent ID returns nil")
end)

T:run("Data: GetTeleportsToMap returns matching entries", function(t)
    -- Stormwind (mapID 84) should have many teleports pointing to it
    local stormwindTeleports = QR:GetTeleportsToMap(84)
    local count = 0
    for _ in pairs(stormwindTeleports) do count = count + 1 end
    t:assertGreaterThan(count, 0, "Found teleports to Stormwind (84)")

    -- Nonexistent mapID should return empty
    local noResults = QR:GetTeleportsToMap(999999)
    local emptyCount = 0
    for _ in pairs(noResults) do emptyCount = emptyCount + 1 end
    t:assertEqual(0, emptyCount, "No teleports to nonexistent mapID")
end)

-------------------------------------------------------------------------------
-- 8. German format string placeholder consistency
-------------------------------------------------------------------------------

T:run("Data: German translations have same placeholder count as English", function(t)
    -- Collect all English format strings (those containing %s or %d)
    local savedLocale = MockWoW.config.locale

    -- First, load English and record format strings
    MockWoW.config.locale = "enUS"
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
    local locFile = scriptDir .. "../QuickRoute/Localization.lua"
    local chunk, err = loadfile(locFile)
    t:assertNotNil(chunk, "Localization.lua loads: " .. tostring(err))
    if not chunk then
        MockWoW.config.locale = savedLocale
        return
    end

    pcall(chunk, "QuickRoute", QR)

    -- Collect English format strings
    local englishFormats = {}
    local rawL = QR.L
    -- We need to iterate the rawset keys, not through metatable
    -- Use rawget to check if key was explicitly set
    local formatKeys = {
        "ADDON_LOADED", "SHOWING_TELEPORTS", "ESTIMATED_TRAVEL_TIME",
        "STEP_GO_TO", "STEP_GO_TO_IN_ZONE", "STEP_TAKE_PORTAL",
        "STEP_TAKE_BOAT", "STEP_TAKE_ZEPPELIN", "STEP_TAKE_TRAM",
        "STEP_TELEPORT_TO", "ACTION_USE_TELEPORT",
        "WAYPOINT_SET", "CANNOT_FIND_LOCATION",
        "FOUND_TELEPORTS", "SECURE_BUTTONS_INITIALIZED", "POOL_EXHAUSTED",
        "DEBUG_ERROR_GRAPH", "DEBUG_ERROR_PATH",
        "LOC_IN_BAGS", "LOC_IN_BANK_BAG",
    }

    for _, key in ipairs(formatKeys) do
        local val = rawget(rawL, key)
        if val and type(val) == "string" then
            local count = countPlaceholders(val)
            if count > 0 then
                englishFormats[key] = { text = val, count = count }
            end
        end
    end

    -- Now load German
    MockWoW.config.locale = "deDE"
    pcall(chunk, "QuickRoute", QR)

    -- Check each German format string has same placeholder count
    for key, enInfo in pairs(englishFormats) do
        local deVal = rawget(rawL, key)
        if deVal and type(deVal) == "string" then
            local deCount = countPlaceholders(deVal)
            t:assertEqual(enInfo.count, deCount,
                key .. " placeholder count: EN=" .. enInfo.count ..
                " DE=" .. deCount ..
                " (EN: '" .. enInfo.text .. "', DE: '" .. deVal .. "')")
        end
    end

    -- Restore English
    MockWoW.config.locale = "enUS"
    pcall(chunk, "QuickRoute", QR)
    MockWoW.config.locale = savedLocale
end)

-------------------------------------------------------------------------------
-- 9. No ID collisions across data tables
-------------------------------------------------------------------------------

T:run("Data: No ID collisions between TeleportItemsData and ClassTeleportSpells", function(t)
    for id, _ in pairs(QR.ClassTeleportSpells) do
        t:assertNil(QR.TeleportItemsData[id],
            "ClassSpell " .. id .. " not in TeleportItemsData")
    end
end)

T:run("Data: No ID collisions between TeleportItemsData and RacialTeleportSpells", function(t)
    for id, _ in pairs(QR.RacialTeleportSpells) do
        t:assertNil(QR.TeleportItemsData[id],
            "RacialSpell " .. id .. " not in TeleportItemsData")
    end
end)

T:run("Data: No ID collisions between ClassTeleportSpells and RacialTeleportSpells", function(t)
    for id, _ in pairs(QR.RacialTeleportSpells) do
        t:assertNil(QR.ClassTeleportSpells[id],
            "RacialSpell " .. id .. " not in ClassTeleportSpells")
    end
end)

-------------------------------------------------------------------------------
-- 10. Engineer items have profession field
-------------------------------------------------------------------------------

T:run("Data: Engineer items have profession field", function(t)
    for id, data in pairs(QR.TeleportItemsData) do
        if data.type == QR.TeleportTypes.ENGINEER then
            t:assert(data.profession == "Engineering",
                "[" .. id .. "] engineer item has profession='Engineering'")
        end
    end
end)

-------------------------------------------------------------------------------
-- 11. Dynamic items have isDynamic flag
-------------------------------------------------------------------------------

T:run("Data: Items without mapID have isDynamic or isRandom flag", function(t)
    for id, data in pairs(QR.TeleportItemsData) do
        if data.mapID == nil then
            t:assert(data.isDynamic or data.isRandom,
                "[" .. id .. "] " .. data.name .. " without mapID has isDynamic or isRandom")
        end
    end
end)

-------------------------------------------------------------------------------
-- 12. Horde faction tests (verify faction-dependent logic works for both sides)
-------------------------------------------------------------------------------

T:run("Data: Horde portal filtering returns Horde-accessible hubs", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()

    -- Horde should see Orgrimmar Portal Room
    t:assertNotNil(portals.hubs["Orgrimmar Portal Room"],
        "Horde sees Orgrimmar Portal Room")
    -- Horde should see Dazar'alor
    t:assertNotNil(portals.hubs["Dazar'alor"],
        "Horde sees Dazar'alor")
    -- Horde should NOT see Stormwind Portal Room
    t:assertNil(portals.hubs["Stormwind Portal Room"],
        "Horde does NOT see Stormwind Portal Room")
    -- Horde should NOT see Boralus
    t:assertNil(portals.hubs["Boralus"],
        "Horde does NOT see Boralus")
    -- Horde should see neutral hubs
    t:assertNotNil(portals.hubs["Oribos"],
        "Horde sees neutral Oribos")
    t:assertNotNil(portals.hubs["Valdrakken"],
        "Horde sees neutral Valdrakken")
    t:assertNotNil(portals.hubs["Dornogal"],
        "Horde sees neutral Dornogal")

    -- Standalone portals: Horde should see zeppelins
    local hasZeppelin = false
    for _, p in ipairs(portals.standalone) do
        if p.type == "zeppelin" then hasZeppelin = true; break end
    end
    t:assertTrue(hasZeppelin, "Horde has zeppelin transport")

    -- Horde should NOT see Alliance tram
    local hasTram = false
    for _, p in ipairs(portals.standalone) do
        if p.type == "tram" then hasTram = true; break end
    end
    t:assertFalse(hasTram, "Horde does NOT have Deeprun Tram")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Data: Alliance portal filtering returns Alliance-accessible hubs", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local portals = QR:GetAvailablePortals()

    -- Alliance should see Stormwind Portal Room
    t:assertNotNil(portals.hubs["Stormwind Portal Room"],
        "Alliance sees Stormwind Portal Room")
    -- Alliance should see Boralus
    t:assertNotNil(portals.hubs["Boralus"],
        "Alliance sees Boralus")
    -- Alliance should NOT see Orgrimmar Portal Room
    t:assertNil(portals.hubs["Orgrimmar Portal Room"],
        "Alliance does NOT see Orgrimmar Portal Room")
    -- Alliance should NOT see Dazar'alor
    t:assertNil(portals.hubs["Dazar'alor"],
        "Alliance does NOT see Dazar'alor")

    -- Alliance should see tram
    local hasTram = false
    for _, p in ipairs(portals.standalone) do
        if p.type == "tram" then hasTram = true; break end
    end
    t:assertTrue(hasTram, "Alliance has Deeprun Tram")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Data: Horde inventory scan filters faction-restricted items", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    -- Scan toys as Horde
    QR.PlayerInventory:ScanToys()

    -- Horde should not have Alliance-only beacon (95567 Kirin Tor Beacon)
    t:assertNil(QR.PlayerInventory.toys[95567],
        "Horde does not have Alliance Kirin Tor Beacon toy")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Data: Horde mage teleports are separate from Alliance", function(t)
    -- Verify no overlap between Alliance and Horde mage teleports
    for id, _ in pairs(QR.MageTeleports.Alliance) do
        t:assertNil(QR.MageTeleports.Horde[id],
            "Alliance mage spell " .. id .. " not in Horde table")
    end
    for id, _ in pairs(QR.MageTeleports.Horde) do
        t:assertNil(QR.MageTeleports.Alliance[id],
            "Horde mage spell " .. id .. " not in Alliance table")
    end
end)

T:run("Data: Neutral portal hubs have faction-tagged portals", function(t)
    -- Dalaran (Broken Isles) has faction-specific portals
    local dalaran = QR.PortalHubs["Dalaran (Broken Isles)"]
    t:assertNotNil(dalaran, "Dalaran (Broken Isles) hub exists")

    local hasAlliancePortal = false
    local hasHordePortal = false
    for _, portal in ipairs(dalaran.portals) do
        if portal.faction == "Alliance" then hasAlliancePortal = true end
        if portal.faction == "Horde" then hasHordePortal = true end
    end
    t:assertTrue(hasAlliancePortal, "Dalaran has Alliance-tagged portals")
    t:assertTrue(hasHordePortal, "Dalaran has Horde-tagged portals")
end)

-------------------------------------------------------------------------------
-- Guild Cloak Items
-------------------------------------------------------------------------------

T:run("Data: Guild cloak items exist and have correct fields", function(t)
    local guildCloaks = {
        [63206] = { name = "Wrap of Unity", faction = "Alliance", mapID = 84 },
        [63207] = { name = "Wrap of Unity", faction = "Horde", mapID = 85 },
        [65360] = { name = "Cloak of Coordination", faction = "Alliance", mapID = 84 },
        [65274] = { name = "Cloak of Coordination", faction = "Horde", mapID = 85 },
        [63352] = { name = "Shroud of Cooperation", faction = "Alliance", mapID = 84 },
        [63353] = { name = "Shroud of Cooperation", faction = "Horde", mapID = 85 },
    }

    for id, expected in pairs(guildCloaks) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, "Guild cloak " .. id .. " (" .. expected.name .. ") exists")
        if data then
            t:assertEqual(expected.name, data.name, "[" .. id .. "] name matches")
            t:assertEqual(expected.faction, data.faction, "[" .. id .. "] faction matches")
            t:assertEqual(expected.mapID, data.mapID, "[" .. id .. "] mapID matches")
            t:assertEqual(QR.TeleportTypes.ITEM, data.type, "[" .. id .. "] type is ITEM")
            t:assert(data.cooldown and data.cooldown > 0, "[" .. id .. "] has positive cooldown")
        end
    end
end)

T:run("Data: Shroud of Cooperation has longer cooldown than Wrap of Unity", function(t)
    local wrap = QR.TeleportItemsData[63206]
    local shroud = QR.TeleportItemsData[63352]
    t:assertNotNil(wrap, "Wrap of Unity exists")
    t:assertNotNil(shroud, "Shroud of Cooperation exists")
    if wrap and shroud then
        t:assert(shroud.cooldown > wrap.cooldown,
            "Shroud cooldown (" .. shroud.cooldown .. ") > Wrap cooldown (" .. wrap.cooldown .. ")")
    end
end)

-------------------------------------------------------------------------------
-- Zone Portals
-------------------------------------------------------------------------------

T:run("Data: Twilight Highlands zone portals exist", function(t)
    local foundTHtoSW = false
    local foundTHtoOG = false
    local foundTHtoDorn = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from and portal.from.mapID == 241 then
            if portal.to and portal.to.mapID == 84 then foundTHtoSW = true end
            if portal.to and portal.to.mapID == 85 then foundTHtoOG = true end
            if portal.to and portal.to.mapID == 2339 then foundTHtoDorn = true end
        end
    end
    t:assertTrue(foundTHtoSW, "TH -> Stormwind portal exists")
    t:assertTrue(foundTHtoOG, "TH -> Orgrimmar portal exists")
    t:assertTrue(foundTHtoDorn, "TH -> Dornogal portal exists")
end)

T:run("Data: Hallowfall to Dornogal portal exists", function(t)
    local found = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from and portal.from.mapID == 2215 and portal.to and portal.to.mapID == 2339 then
            found = true
            t:assertTrue(portal.bidirectional, "Hallowfall portal is bidirectional")
            t:assertEqual("both", portal.faction, "Hallowfall portal is neutral")
        end
    end
    t:assertTrue(found, "Hallowfall -> Dornogal portal exists")
end)

T:run("Data: Zone portals have valid bidirectional flag", function(t)
    local zonePortalMaps = { [241] = true, [2215] = true }
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from and zonePortalMaps[portal.from.mapID] then
            t:assertTrue(portal.bidirectional == true,
                portal.name .. " is bidirectional")
            t:assert(portal.travelTime and portal.travelTime > 0,
                portal.name .. " has positive travel time")
        end
    end
end)

-------------------------------------------------------------------------------
-- Hearthstone Toy Variants
-------------------------------------------------------------------------------

T:run("Data: Hearthstone toy variants are isDynamic with no mapID", function(t)
    local hearthstoneVariants = {
        54452, 93672, 162973, 163045, 165669, 165670, 165802,
        166746, 166747, 168907, 172179, 180290, 184353, 183716,
        182773, 188952, 190196, 190237, 193588, 200630, 206195, 212337,
    }
    for _, id in ipairs(hearthstoneVariants) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, "Hearthstone variant " .. id .. " exists")
        if data then
            t:assertTrue(data.isDynamic == true, "[" .. id .. "] " .. data.name .. " is isDynamic")
            t:assertNil(data.mapID, "[" .. id .. "] " .. data.name .. " has no mapID")
            t:assertEqual("Bound Location", data.destination, "[" .. id .. "] " .. data.name .. " destination is Bound Location")
            t:assertEqual(1800, data.cooldown, "[" .. id .. "] " .. data.name .. " has 30min cooldown")
            t:assertEqual(QR.TeleportTypes.TOY, data.type, "[" .. id .. "] " .. data.name .. " is TOY type")
        end
    end
end)

T:run("Data: Covenant hearthstones are cosmetic (not sanctum teleports)", function(t)
    -- These were previously incorrectly set as covenant sanctum teleports
    local covenantHS = {
        [184353] = "Kyrian Hearthstone",
        [183716] = "Venthyr Sinstone",
        [180290] = "Night Fae Hearthstone",
        [182773] = "Necrolord Hearthstone",
    }
    for id, expectedName in pairs(covenantHS) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, expectedName .. " exists")
        if data then
            t:assertEqual(expectedName, data.name, "[" .. id .. "] name is correct")
            t:assertTrue(data.isDynamic == true, expectedName .. " is isDynamic (bound location)")
            t:assertNil(data.mapID, expectedName .. " has no fixed mapID")
        end
    end
end)

T:run("Data: Item 188952 is Dominated Hearthstone, not Night Fae", function(t)
    local data = QR.TeleportItemsData[188952]
    t:assertNotNil(data, "Item 188952 exists")
    if data then
        t:assertEqual("Dominated Hearthstone", data.name, "188952 is Dominated Hearthstone")
        t:assertTrue(data.isDynamic == true, "Dominated HS is isDynamic")
    end
end)

T:run("Data: Item 190237 is Broker Translocation Matrix, not Theater of Pain", function(t)
    local data = QR.TeleportItemsData[190237]
    t:assertNotNil(data, "Item 190237 exists")
    if data then
        t:assertEqual("Broker Translocation Matrix", data.name, "190237 is Broker Translocation Matrix")
        t:assertTrue(data.isDynamic == true, "Broker Translocation Matrix is isDynamic")
    end
end)

T:run("Data: Item 166746 is Fire Eater's Hearthstone, not Mechagon wormhole", function(t)
    local data = QR.TeleportItemsData[166746]
    t:assertNotNil(data, "Item 166746 exists")
    if data then
        t:assertEqual("Fire Eater's Hearthstone", data.name, "166746 is Fire Eater's Hearthstone")
        t:assertTrue(data.isDynamic == true, "Fire Eater's HS is isDynamic")
    end
end)

-------------------------------------------------------------------------------
-- Kirin Tor Ring Upgrades
-------------------------------------------------------------------------------

T:run("Data: All Kirin Tor ring tiers exist", function(t)
    local kirinTorRings = {
        -- Base
        40585, 40586, 44934, 44935,
        -- Inscribed
        45688, 45689, 45690, 45691,
        -- Etched
        48954, 48955, 48956, 48957,
        -- Runed
        51557, 51558, 51559, 51560,
        -- Empowered (Legion)
        139599,
    }
    for _, id in ipairs(kirinTorRings) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, "Kirin Tor ring " .. id .. " exists")
        if data then
            t:assert(data.name:find("Kirin Tor"), "[" .. id .. "] name contains 'Kirin Tor'")
            t:assertEqual(QR.TeleportTypes.ITEM, data.type, "[" .. id .. "] type is ITEM")
            t:assertEqual(1800, data.cooldown, "[" .. id .. "] cooldown is 30min")
        end
    end
end)

T:run("Data: Empowered Ring goes to Legion Dalaran, others to Northrend", function(t)
    local empowered = QR.TeleportItemsData[139599]
    t:assertNotNil(empowered, "Empowered Ring exists")
    if empowered then
        t:assertEqual(627, empowered.mapID, "Empowered Ring goes to Legion Dalaran")
    end

    -- Check a base ring goes to Northrend
    local base = QR.TeleportItemsData[40586]
    t:assertNotNil(base, "Base Band of the Kirin Tor exists")
    if base then
        t:assertEqual(125, base.mapID, "Base ring goes to Northrend Dalaran")
    end
end)

-------------------------------------------------------------------------------
-- New Special Items
-------------------------------------------------------------------------------

T:run("Data: New special teleport items exist", function(t)
    local specialItems = {
        [50287]  = { name = "Boots of the Bay", mapID = 210 },
        [142469] = { name = "Violet Seal of the Grand Magus", mapID = 42 },
        [166560] = { name = "Captain's Signet of Command", faction = "Alliance", mapID = 1161 },
        [166559] = { name = "Commander's Signet of Battle", faction = "Horde", mapID = 1165 },
        [118663] = { name = "Relic of Karabor", faction = "Alliance", mapID = 539 },
        [118662] = { name = "Bladespire Relic", faction = "Horde", mapID = 525 },
        [243056] = { name = "Delver's Mana-Bound Ethergate", mapID = 2339 },
    }
    for id, expected in pairs(specialItems) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, expected.name .. " (" .. id .. ") exists")
        if data then
            t:assertEqual(expected.name, data.name, "[" .. id .. "] name matches")
            t:assertEqual(expected.mapID, data.mapID, "[" .. id .. "] mapID matches")
            if expected.faction then
                t:assertEqual(expected.faction, data.faction, "[" .. id .. "] faction matches")
            end
            t:assert(data.cooldown and data.cooldown > 0, "[" .. id .. "] has positive cooldown")
        end
    end
end)

T:run("Data: BfA faction signets have matching factions", function(t)
    local alliance = QR.TeleportItemsData[166560]
    local horde = QR.TeleportItemsData[166559]
    t:assertNotNil(alliance, "Alliance signet exists")
    t:assertNotNil(horde, "Horde signet exists")
    if alliance and horde then
        t:assertEqual("Alliance", alliance.faction, "Captain's Signet is Alliance")
        t:assertEqual("Horde", horde.faction, "Commander's Signet is Horde")
    end
end)

-------------------------------------------------------------------------------
-- New Mage Spells
-------------------------------------------------------------------------------

T:run("Data: Ancient Teleport: Dalaran exists in Shared mage spells", function(t)
    local spell = QR.MageTeleports.Shared[120145]
    t:assertNotNil(spell, "Ancient Teleport: Dalaran exists")
    if spell then
        t:assertEqual(25, spell.mapID, "Goes to Hillsbrad Foothills (Dalaran Crater)")
        t:assertEqual("MAGE", spell.class, "Is a mage spell")
    end
end)

T:run("Data: Teleport: Hall of the Guardian exists in Shared mage spells", function(t)
    local spell = QR.MageTeleports.Shared[193759]
    t:assertNotNil(spell, "Teleport: Hall of the Guardian exists")
    if spell then
        t:assertEqual(734, spell.mapID, "Goes to Hall of the Guardian")
        t:assertEqual("MAGE", spell.class, "Is a mage spell")
    end
end)

-------------------------------------------------------------------------------
-- New Toys
-------------------------------------------------------------------------------

T:run("Data: New destination toys exist with correct mapIDs", function(t)
    local destToys = {
        [140324] = { name = "Mobile Telemancy Beacon", mapID = 680 },
        [129276] = { name = "Beginner's Guide to Dimensional Rifting", mapID = 630 },
        [202046] = { name = "Lucky Tortollan Charm", mapID = 942 },
        [253629] = { name = "Personal Key to the Arcantina", mapID = 2393 },
    }
    for id, expected in pairs(destToys) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, expected.name .. " (" .. id .. ") exists")
        if data then
            t:assertEqual(expected.name, data.name, "[" .. id .. "] name matches")
            t:assertEqual(expected.mapID, data.mapID, "[" .. id .. "] mapID matches")
            t:assertEqual(QR.TeleportTypes.TOY, data.type, "[" .. id .. "] type is TOY")
        end
    end
end)

T:run("Data: Random destination toys are flagged isRandom", function(t)
    local randomToys = { 64457, 136849, 140493, 153004 }
    for _, id in ipairs(randomToys) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, "Random toy " .. id .. " exists")
        if data then
            t:assertTrue(data.isRandom == true, "[" .. id .. "] " .. data.name .. " is isRandom")
            t:assertNil(data.mapID, "[" .. id .. "] " .. data.name .. " has no fixed mapID")
        end
    end
end)

-------------------------------------------------------------------------------
-- Brawler's Guild Rings
-------------------------------------------------------------------------------

T:run("Data: Brawler's Guild rings exist with correct factions", function(t)
    local brawlerRings = {
        [95050]  = { name = "The Brassiest Knuckle", faction = "Horde", mapID = 85 },
        [95051]  = { name = "The Brassiest Knuckle", faction = "Alliance", mapID = 84 },
        [118908] = { name = "Pit Fighter's Punching Ring", faction = "Horde", mapID = 85 },
        [118907] = { name = "Pit Fighter's Punching Ring", faction = "Alliance", mapID = 84 },
        [144392] = { name = "Pugilist's Powerful Punching Ring", faction = "Horde", mapID = 85 },
        [144391] = { name = "Pugilist's Powerful Punching Ring", faction = "Alliance", mapID = 84 },
    }
    for id, expected in pairs(brawlerRings) do
        local data = QR.TeleportItemsData[id]
        t:assertNotNil(data, expected.name .. " (" .. id .. ") exists")
        if data then
            t:assertEqual(expected.faction, data.faction, "[" .. id .. "] faction is " .. expected.faction)
            t:assertEqual(expected.mapID, data.mapID, "[" .. id .. "] mapID is " .. expected.mapID)
            t:assertEqual(3600, data.cooldown, "[" .. id .. "] cooldown is 1 hour")
            t:assertEqual(11, data.equipSlot, "[" .. id .. "] equipSlot is 11 (finger)")
        end
    end
end)

-------------------------------------------------------------------------------
-- equipSlot validation
-------------------------------------------------------------------------------

T:run("Data: All equippable items have correct equipSlot", function(t)
    local slotExpectations = {
        -- Back (15): guild cloaks + Mountebank's
        { ids = {63206, 63207, 65360, 65274, 63352, 63353, 169064}, slot = 15, label = "back" },
        -- Ring (11): Kirin Tor + Brawler's + BfA signets + Violet Seal
        { ids = {40585, 40586, 44934, 44935, 45688, 45689, 45690, 45691,
                 48954, 48955, 48956, 48957, 51557, 51558, 51559, 51560,
                 139599, 142469, 166559, 166560,
                 95050, 95051, 118907, 118908, 144391, 144392}, slot = 11, label = "finger" },
        -- Feet (8)
        { ids = {28585, 142298, 50287}, slot = 8, label = "feet" },
        -- Neck (2)
        { ids = {32757}, slot = 2, label = "neck" },
        -- Tabard (19)
        { ids = {46874, 63378, 63379}, slot = 19, label = "tabard" },
        -- Trinket (13)
        { ids = {103678}, slot = 13, label = "trinket" },
    }
    for _, group in ipairs(slotExpectations) do
        for _, id in ipairs(group.ids) do
            local data = QR.TeleportItemsData[id]
            t:assertNotNil(data, "Item " .. id .. " exists")
            if data then
                t:assertEqual(group.slot, data.equipSlot,
                    "[" .. id .. "] " .. (data.name or "?") .. " equipSlot is " .. group.slot .. " (" .. group.label .. ")")
            end
        end
    end
end)

T:run("Data: Non-equippable items have NO equipSlot", function(t)
    -- Hearthstone toys, mage spells, engineering items should NOT have equipSlot
    local nonEquippable = {6948, 54452, 93672, 162973, 163045, 140192, 110560, 3561, 3562, 120145}
    for _, id in ipairs(nonEquippable) do
        local data = QR.TeleportItemsData[id]
        if data then
            t:assertNil(data.equipSlot, "[" .. id .. "] " .. (data.name or "?") .. " has no equipSlot")
        end
    end
end)

T:run("Data: Signet of the Kirin Tor (40585) base ring exists", function(t)
    local data = QR.TeleportItemsData[40585]
    t:assertNotNil(data, "Signet of the Kirin Tor exists")
    if data then
        t:assertEqual("Signet of the Kirin Tor", data.name, "Name matches")
        t:assertEqual(125, data.mapID, "Goes to Dalaran Northrend")
        t:assertEqual(1800, data.cooldown, "30min cooldown")
        t:assertEqual(11, data.equipSlot, "equipSlot is finger (11)")
    end
end)

-------------------------------------------------------------------------------
-- journalInstanceID to name, checked against the live client
-------------------------------------------------------------------------------

-- Regression: twelve entries bound a journalInstanceID to the wrong dungeon.
-- The Nexus carried The Oculus's id, Atal'Dazar carried Kings' Rest's, and the
-- Caverns of Time and Icecrown groups were rotated. Nothing noticed, because no
-- test ever compared an id against the name the game gives it.
--
-- The expected pairs below were read off a live 12.1.0.69497 client with
-- EJ_GetInstanceInfo. Extend this table whenever an entrance is added: an entry
-- whose id and name disagree is the defect this guards against.
local EXPECTED_INSTANCE_NAMES = {
    [184]  = "End Time",
    [185]  = "Well of Eternity",
    [186]  = "Hour of Twilight",
    [251]  = "Old Hillsbrad",
    [255]  = "Black Morass",
    [276]  = "Halls of Reflection",
    [278]  = "Pit of Saron",
    [280]  = "The Forge of Souls",
    [281]  = "The Nexus",
    [282]  = "The Oculus",
    [968]  = "Atal'Dazar",
    [1041] = "Kings' Rest",
    -- 12.0.7 and 12.1.0 content, added in the same pass
    [1298] = "Operation: Floodgate",
    [1299] = "Windrunner Spire",
    [1302] = "Manaforge Omega",
    [1303] = "Eco-Dome Al'dani",
    [1305] = "Sporefall",
    [1311] = "Den of Nalorakk",
    [1317] = "The Tidebound Grotto",
    [1320] = "The Venomous Abyss",
    [1322] = "Altar of Fangs",
}

T:run("StaticDungeonEntrances: journalInstanceIDs carry the name the client gives them", function(t)
    local seen = {}

    for mapID, entries in pairs(QR.StaticDungeonEntrances) do
        for _, entry in ipairs(entries) do
            local journalID, name = entry[1], entry[4]
            local expected = EXPECTED_INSTANCE_NAMES[journalID]
            if expected then
                seen[journalID] = true
                t:assertNotNil(string.find(name, expected, 1, true),
                    string.format("journalInstanceID %d on map %s is %s, repo says %q",
                        journalID, tostring(mapID), expected, tostring(name)))
            end
        end
    end

    local missing = {}
    for journalID in pairs(EXPECTED_INSTANCE_NAMES) do
        if not seen[journalID] then
            missing[#missing + 1] = journalID
        end
    end
    t:assertEqual(0, #missing,
        "every verified journalInstanceID still has an entrance entry (missing: "
            .. table.concat(missing, ", ") .. ")")
end)

-------------------------------------------------------------------------------
-- Maps that are not zones must never appear as graph or entrance keys
-------------------------------------------------------------------------------

-- Regression: the data files used dungeon, raid and continent uiMapIDs as if
-- they were zones — 67 and 68 are Maraudon, 11 is Wailing Caverns, 261 is the
-- Blood Furnace, 700 is Icecrown Citadel, 101 is the Outland continent, 378 is
-- the Wandering Isle. Each was then papered over with a 0.001s bridge edge to
-- the id that was actually meant, which hid the mistake from every existing
-- test while quietly registering content on the wrong map.
--
-- Identities confirmed with C_Map.GetMapInfo on a live 12.1.0.69497 client.
local NOT_ZONES = {
    [11]  = "Wailing Caverns (dungeon) -- Ashenvale is 63",
    [67]  = "Maraudon (dungeon) -- Feralas is 69",
    [68]  = "Maraudon (dungeon) -- Dustwallow Marsh is 70",
    [261] = "Blood Furnace (dungeon) -- Uldum is 249",
    [378] = "The Wandering Isle -- Kun-Lai Summit is 379",
    [700] = "Icecrown Citadel (raid) -- Twilight Highlands is 241",
    [809] = "Karazhan (dungeon)",
}

-- Every cosmic, world and continent map in the client's UiMap table, taken
-- from the 12.1.0 build rather than listed by hand. The hand-written list
-- above had caught 101 (Outland) and stopped there, so 876 -- the Kul Tiras
-- CONTINENT -- sat in the adjacency table labelled "Zandalar" and carried the
-- Crucible of Storms entrance until this sweep. The exhaustive set closes the
-- class instead of one member of it. As of this build no map here is used as
-- a zone anywhere in the addon, so an addition is a real finding: if a future
-- patch makes one of these genuinely walkable, move it out with a comment
-- saying so rather than deleting the check.
local CONTINENT_MAPS = {
    [12] = "Kalimdor (continent)",
    [13] = "Eastern Kingdoms (continent)",
    [101] = "Outland (continent)",
    [113] = "Northrend (continent)",
    [424] = "Pandaria (continent)",
    [572] = "Draenor (continent)",
    [619] = "Broken Isles (continent)",
    [875] = "Zandalar (continent)",
    [876] = "Kul Tiras (continent)",
    [905] = "Argus (continent)",
    [946] = "Cosmic (cosmic)",
    [947] = "Azeroth (world)",
    [948] = "The Maelstrom (continent)",
    [985] = "Eastern Kingdoms (continent)",
    [986] = "Kalimdor (continent)",
    [987] = "Outland (continent)",
    [988] = "Northrend (continent)",
    [989] = "Pandaria (continent)",
    [990] = "Draenor (continent)",
    [991] = "Zandalar (continent)",
    [992] = "Kul Tiras (continent)",
    [993] = "Broken Isles (continent)",
    [994] = "Argus (continent)",
    [1011] = "Zandalar (continent)",
    [1014] = "Kul Tiras (continent)",
    [1208] = "Eastern Kingdoms (continent)",
    [1209] = "Kalimdor (continent)",
    [1384] = "Northrend (continent)",
    [1467] = "Outland (continent)",
    [1504] = "Nazjatar (continent)",
    [1550] = "The Shadowlands (continent)",
    [1645] = "Torghast (continent)",
    [1647] = "The Shadowlands (continent)",
    [1922] = "Draenor (continent)",
    [1923] = "Pandaria (continent)",
    [1978] = "Dragon Isles (continent)",
    [2046] = "Zereth Mortis (continent)",
    [2055] = "Sepulcher of the First Ones (continent)",
    [2057] = "Dragon Isles (continent)",
    [2059] = "Resonant Peaks (continent)",
    [2147] = "Azeroth (continent)",
    [2149] = "Ohn'ahran Plains (continent)",
    [2252] = "Dragon Isles (continent)",
    [2274] = "Khaz Algar (continent)",
    [2276] = "Khaz Algar (continent)",
    [2481] = "Eastern Kingdoms (continent)",
    [2537] = "Quel'Thalas (continent)",
    [2561] = "Quel'Thalas (continent)",
}

for mapID, name in pairs(CONTINENT_MAPS) do
    if not NOT_ZONES[mapID] then
        NOT_ZONES[mapID] = name
    end
end

T:run("ZoneAdjacency: no dungeon, raid or continent map is used as a zone", function(t)
    for zoneID in pairs(QR.ZoneAdjacencies or {}) do
        t:assertNil(NOT_ZONES[zoneID],
            string.format("adjacency key %d is %s", zoneID, tostring(NOT_ZONES[zoneID])))
    end

    for zoneID, neighbours in pairs(QR.ZoneAdjacencies or {}) do
        for _, adj in ipairs(neighbours) do
            t:assertNil(NOT_ZONES[adj.zone],
                string.format("zone %d has an edge to %d, which is %s",
                    zoneID, adj.zone, tostring(NOT_ZONES[adj.zone])))
        end
    end

    for _, continent in pairs(QR.Continents or {}) do
        for _, zoneID in ipairs(continent.zones or {}) do
            t:assertNil(NOT_ZONES[zoneID],
                string.format("continent zone list carries %d, which is %s",
                    zoneID, tostring(NOT_ZONES[zoneID])))
        end
    end
end)

T:run("StaticDungeonEntrances: no dungeon, raid or continent map is used as a zone", function(t)
    for mapID in pairs(QR.StaticDungeonEntrances or {}) do
        t:assertNil(NOT_ZONES[mapID],
            string.format("entrance table is keyed on %d, which is %s",
                mapID, tostring(NOT_ZONES[mapID])))
    end
end)

-------------------------------------------------------------------------------
-- One zone per entrance table
-------------------------------------------------------------------------------

-- Regression: correcting one zone constant during this pass silently collided
-- it with a neighbour that already held the corrected value, so two zones'
-- entrances registered on the same map and one zone got none. Lua accepts two
-- keys holding the same number without complaint, which is why nothing noticed
-- until the table was read by eye.
T:run("StaticDungeonEntrances: no two zones share an entrance table", function(t)
    local count = 0
    for _ in pairs(QR.StaticDungeonEntrances) do
        count = count + 1
    end
    t:assertGreaterThan(count, 50, "the entrance table is populated")

    -- Every key is a distinct map by construction (they are table keys), so the
    -- collision shows up as a zone that lost its entries entirely. Check the
    -- zones this pass corrected still have their own.
    local mustHaveEntries = {
        [63]  = "Ashenvale",
        [70]  = "Dustwallow Marsh",
        [69]  = "Feralas",
        [71]  = "Tanaris",
        [102] = "Zangarmarsh",
        [108] = "Terokkar Forest",
        [104] = "Shadowmoon Valley (Outland)",
        [109] = "Netherstorm",
        [241] = "Twilight Highlands",
        [249] = "Uldum",
        [15]  = "Badlands",
    }
    for mapID, name in pairs(mustHaveEntries) do
        local entries = QR.StaticDungeonEntrances[mapID]
        t:assertNotNil(entries,
            string.format("%s (map %d) has an entrance table", name, mapID))
        if entries then
            t:assertGreaterThan(#entries, 0,
                string.format("%s (map %d) has at least one entrance", name, mapID))
        end
    end
end)

-------------------------------------------------------------------------------
-- The test loader must load exactly what the game loads
-------------------------------------------------------------------------------

-- Regression risk: tests/addon_loader.lua repeats the .toc's file list by hand.
-- The runner's load-failure guard only fires for files the loader knows about,
-- so a file added to the .toc and forgotten here is never loaded at all — and
-- the file-scope-QR bug class that guard exists to catch would be invisible for
-- it. The two lists are compared rather than trusted.
T:run("addon_loader: its file list matches QuickRoute.toc", function(t)
    local function readLines(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end

    local toc = readLines("QuickRoute/QuickRoute.toc")
    t:assertNotNil(toc, "QuickRoute.toc is readable")
    if not toc then return end

    local tocFiles = {}
    for line in toc:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:match("%.lua$") and not trimmed:match("^#") then
            -- The in-game test runner is deliberately not loaded by the suite.
            local normalized = trimmed:gsub("\\", "/")
            if not normalized:match("^Tests/") then
                tocFiles[#tocFiles + 1] = normalized
            end
        end
    end
    t:assertGreaterThan(#tocFiles, 20, "the .toc lists a plausible number of files")

    local loaderSource = readLines("tests/addon_loader.lua")
    t:assertNotNil(loaderSource, "addon_loader.lua is readable")
    if not loaderSource then return end

    local missing = {}
    for _, file in ipairs(tocFiles) do
        if not loaderSource:find('"' .. file .. '"', 1, true) then
            missing[#missing + 1] = file
        end
    end
    t:assertEqual(0, #missing,
        "every .toc file is in the loader list (missing: " .. table.concat(missing, ", ") .. ")")
end)

-------------------------------------------------------------------------------
-- Teleport destinations must be routable
-------------------------------------------------------------------------------

-- A teleport whose mapID is in no continent list cannot be reached by the
-- continent-routing strategies at all. It falls through to the flat 240s
-- cross-continent fallback, which links it to every hub on every continent
-- with no geographic meaning, and it never connects to anything physically at
-- the same place. Four Tol Barad teleports pointed at 773, an orphan UiMap,
-- while the graph modelled Tol Barad as 244.
T:run("Teleports: every destination map belongs to a continent", function(t)
    local tables = {
        TeleportItemsData = QR.TeleportItemsData,
        ClassTeleportSpells = QR.ClassTeleportSpells,
        RacialTeleportSpells = QR.RacialTeleportSpells,
        GeneralTeleportSpells = QR.GeneralTeleportSpells,
        MageTeleports = QR.MageTeleports,
    }
    -- Maps that are deliberately off the walking graph. Each is an instanced
    -- or orphan UiMap you arrive in and leave again by portal, so having no
    -- continent is correct for them rather than a data error.
    local OFF_GRAPH = {
        [734] = "Hall of the Guardian -- mage class hall, instanced",
        [715] = "Emerald Dreamway -- orphan UiMap, portal hub",
        [809] = "KNOWN WRONG: the client calls 809 Karazhan. Where Zen " ..
                "Pilgrimage actually lands is not settled -- issue #5. " ..
                "Listed here so a NEW orphan destination still fails.",
    }

    local orphans = {}
    local checked = 0

    local function visit(source, entry)
        if type(entry) ~= "table" then return end
        if type(entry.mapID) == "number" then
            checked = checked + 1
            if not QR.GetContinentForZone(entry.mapID) and not OFF_GRAPH[entry.mapID] then
                orphans[#orphans + 1] = string.format("%s: %s -> %d", source,
                    tostring(entry.destination or entry.name or "?"), entry.mapID)
            end
        end
        -- Faction and class tables nest one level deeper.
        for _, nested in pairs(entry) do
            if type(nested) == "table" and type(nested.mapID) == "number" then
                visit(source, nested)
            end
        end
    end

    for source, data in pairs(tables) do
        for _, entry in pairs(data or {}) do
            visit(source, entry)
        end
    end

    t:assertGreaterThan(checked, 50, "the sweep saw a plausible number of destinations")
    t:assertEqual(0, #orphans,
        "no teleport lands on a map outside every continent (" ..
        table.concat(orphans, ", ") .. ")")
end)

-------------------------------------------------------------------------------
-- Dungeon entrances sit on the map the client reports for their zone
-------------------------------------------------------------------------------

-- Verified against the live 12.1.0 UiMap table. Two zone constants held their
-- neighbour's id: Blackrock Mountain was registered on Hillsbrad Foothills (25)
-- instead of Burning Steppes (36), Stratholme on Redridge Mountains (49)
-- instead of Eastern Plaguelands (23). Whenever the Encounter Journal has not
-- supplied an entrance and the static fallback is used, routing to Molten Core
-- put its waypoint on the wrong map.
T:run("DungeonEntrances: landmark dungeons sit on the right map", function(t)
    local entrances = QR.StaticDungeonEntrances
    t:assertNotNil(entrances, "the static entrance table exists")
    if not entrances then return end

    local function namesOn(mapID)
        local found = {}
        -- Rows are { journalInstanceID, x, y, name, isRaid }.
        for _, entry in ipairs(entrances[mapID] or {}) do
            if entry[4] then
                found[entry[4]] = true
            end
        end
        return found
    end

    local burningSteppes = namesOn(36)
    local hillsbrad = namesOn(25)
    t:assertTrue(burningSteppes["Blackrock Depths"] or false,
        "Blackrock Depths is on Burning Steppes (36)")
    t:assertTrue(burningSteppes["Molten Core"] or false,
        "Molten Core is on Burning Steppes (36)")
    t:assertFalse(hillsbrad["Molten Core"] or false,
        "Molten Core is not on Hillsbrad Foothills (25)")

    local easternPlaguelands = namesOn(23)
    local redridge = namesOn(49)
    t:assertTrue(easternPlaguelands["Stratholme"] or false,
        "Stratholme is on Eastern Plaguelands (23)")
    t:assertFalse(redridge["Stratholme"] or false,
        "Stratholme is not on Redridge Mountains (49)")
end)

-- Reverting PathCalculator's Silvermoon entry to the map Midnight left behind
-- kept the suite green, so the value is asserted directly. 2393 sits under
-- Quel'Thalas (2537); 110 is the pre-revamp city.
T:run("PathCalculator: Silvermoon City uses the revamped map", function(t)
    local cities = QR.CAPITAL_CITIES
    t:assertNotNil(cities, "CAPITAL_CITIES is exported")
    if not cities then return end
    local silvermoon = cities["Silvermoon City"]
    t:assertNotNil(silvermoon, "Silvermoon City is a capital")
    if not silvermoon then return end
    t:assertEqual(2393, silvermoon.mapID,
        "Silvermoon City is uiMapID 2393, not the pre-revamp 110")
end)
