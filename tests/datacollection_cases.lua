-------------------------------------------------------------------------------
-- datacollection_cases.lua
-- The travel-observation cases (QR.DataCollection: the opt-in switch, the six
-- recordings kept in QR.db.observations, /qrdata), shared by
-- test_datacollection.lua (retail) and test_forever_datacollection.lua
-- (QR_TEST_FLAVOR=forever). Not named test_*.lua, so the runner does not pick
-- it up on its own. The two data sets use different map IDs; FIXTURES holds
-- each flavor's.
-------------------------------------------------------------------------------

local T, QR, MockWoW, flavor = ...

local DC = QR.DataCollection
local PC = QR.PathCalculator
local ZS = QR.ZoneSurvey
local prefix = "DataCollection (" .. flavor .. "): "

local FIXTURES = {
    retail = {
        stormwind = 84, ironforge = 87, continent = 13,
        -- An unknown teleport: Stormwind to Orgrimmar.
        unknownFrom = { mapID = 84, x = 0.5, y = 0.5 },
        unknownTo = { mapID = 85, x = 0.4, y = 0.6 },
        -- A third map no route plan leads to.
        offPlan = 85,
        -- The owner's Delve-O-Bot crossing of 2026-11-11: Northern Barrens to
        -- Harandar, game maps 1 (Kalimdor) and 2694 (Harandar).
        gossipFrom = { mapID = 10, x = 0.7873, y = 0.9103, instanceMapID = 1, instanceName = "Kalimdor" },
        gossipTo = { mapID = 2413, x = 0.3672, y = 0.4963, instanceMapID = 2694, instanceName = "Harandar" },
    },
    forever = {
        stormwind = 1453, ironforge = 1455, continent = 1415,
        -- The Dalaran portal to Stormwind the owner took on Forever
        -- (scripts/data/forever_observed_portals.json).
        unknownFrom = { mapID = 1416, x = 0.1209, y = 0.5641 },
        unknownTo = { mapID = 1453, x = 0.4987, y = 0.8667 },
        offPlan = 1454,
        -- The same crossing on maps the Forever data knows; the game maps
        -- are those of the retail trace.
        gossipFrom = { mapID = 1416, x = 0.1209, y = 0.5641, instanceMapID = 1, instanceName = "Kalimdor" },
        gossipTo = { mapID = 1453, x = 0.4987, y = 0.8667, instanceMapID = 2694, instanceName = "Harandar" },
    },
}
local F = FIXTURES[flavor]
assert(F, "no fixture for flavor " .. tostring(flavor))

-- Teleport: Ironforge (mage); both data sets land it at 0.2730, 0.7330.
local IRONFORGE = 3562
-- Teleport: Stormwind; both data sets land it at 0.4965, 0.8725.
local STORMWIND = 3561

-- Everything a test here borrows, put back afterwards.
local function snapshot()
    return {
        collection = QR.db.dataCollection,
        observations = QR.db.observations,
        surveyEnabled = QR.db.zoneSurveyEnabled,
        surveyChoice = QR.db.zoneSurveyChoice,
        zoneSurvey = QR.db.zoneSurvey,
        pendingCast = DC.pendingCast,
        follow = DC.follow,
        interaction = DC.interaction,
        unitName = _G.UnitName,
        unitGUID = _G.UnitGUID,
        issecret = _G.issecretvalue,
        unsaved = DC.unsavedCount,
        captures = ZS.unsavedCaptures,
        crossings = ZS.unsavedCrossings,
        closeCount = QR.MainFrame and QR.MainFrame.closeCount,
        isShowing = QR.MainFrame and QR.MainFrame.isShowing,
        locked = QR.db.destinationLocked,
        lastDestination = QR.db.lastDestination,
        autoDestination = QR.db.autoDestination,
        priority = QR.db.waypointPriority,
    }
end

local function restore(saved)
    QR.db.dataCollection = saved.collection
    QR.db.observations = saved.observations
    QR.db.zoneSurveyEnabled = saved.surveyEnabled
    QR.db.zoneSurveyChoice = saved.surveyChoice
    QR.db.zoneSurvey = saved.zoneSurvey
    DC.pendingCast = saved.pendingCast
    DC.follow = saved.follow
    DC.interaction = saved.interaction
    _G.UnitName, _G.UnitGUID, _G.issecretvalue = saved.unitName, saved.unitGUID, saved.issecret
    DC.unsavedCount = saved.unsaved
    ZS.unsavedCaptures, ZS.unsavedCrossings = saved.captures, saved.crossings
    if QR.MainFrame then
        QR.MainFrame.closeCount, QR.MainFrame.isShowing = saved.closeCount, saved.isShowing
    end
    QR.db.destinationLocked, QR.db.autoDestination = saved.locked, saved.autoDestination
    QR.db.lastDestination = saved.lastDestination
    QR.db.waypointPriority = saved.priority
    ZS:ForgetArrivalState()
    DC:ApplySetting()
    local reminder = QR.Diagnostics and QR.Diagnostics.Reminder
    if reminder and reminder.Refresh then reminder:Refresh() end
end

--- Run fn with the switch set to `on`, empty observations and the survey off.
local function withCollection(on, fn)
    local saved = snapshot()
    MockWoW:Reset()
    QR.db.dataCollection = on
    QR.db.observations = nil
    QR.db.zoneSurveyEnabled = false
    DC.pendingCast, DC.follow, DC.interaction = nil, nil, nil
    DC.unsavedCount = 0
    QR.db.lastDestination, QR.db.destinationLocked = nil, false
    local ok, err = pcall(fn)
    restore(saved)
    MockWoW:Reset()
    if not ok then error(err, 0) end
end

local function list(name)
    local store = QR.db.observations
    return type(store) == "table" and type(store[name]) == "table" and store[name] or {}
end

local function event(name, ...)
    local handler = DC.frame and DC.frame:GetScript("OnEvent")
    if handler then handler(DC.frame, name, ...) end
end

local function at(mapID, x, y)
    MockWoW.config.currentMapID = mapID
    MockWoW.config.playerX, MockWoW.config.playerY = x, y
end

--- Cast from Stormwind (or `from`), go through a loading screen that takes
-- `loadSeconds`, land where told.
local function castAndLand(spellID, toMap, toX, toY, from, loadSeconds)
    from = from or { mapID = F.stormwind, x = 0.5, y = 0.5 }
    at(from.mapID, from.x, from.y)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spellID)
    event("LOADING_SCREEN_ENABLED")
    if loadSeconds then MockWoW.config.baseTime = MockWoW.config.baseTime + loadSeconds end
    at(toMap, toX, toY)
    event("LOADING_SCREEN_DISABLED")
end

-------------------------------------------------------------------------------
-- The switch
-------------------------------------------------------------------------------

T:run(prefix .. "the switch defaults to off", function(t)
    local savedDB, savedQRdb = QuickRouteDB, QR.db
    local ok, err = pcall(function()
        QuickRouteDB = nil
        QR:Initialize()
        t:assertFalse(QR.db.dataCollection,
            "a fresh install has dataCollection=" .. tostring(QR.db.dataCollection))
        QuickRouteDB = { dataCollection = "yes" }
        QR:Initialize()
        t:assertFalse(QR.db.dataCollection,
            "a non-boolean saved value is reset, got " .. tostring(QR.db.dataCollection))
    end)
    QuickRouteDB, QR.db = savedDB, savedQRdb
    t:assertTrue(ok, "Initialize ran: " .. tostring(err))
end)

T:run(prefix .. "the settings panel has its own checkbox for the switch", function(t)
    local controls = QR.SettingsPanel.controls or {}
    local control = controls.dataCollection
    t:assertNotNil(control, "a dataCollection control is registered")
    if not control then return end
    t:assertEqual("dataCollection", control.dbKey, "the control writes dataCollection")
    t:assertNotNil(controls.zoneSurveyEnabled, "the zone survey keeps its own checkbox")
    t:assert(control ~= controls.zoneSurveyEnabled and control.setting ~= controls.zoneSurveyEnabled.setting,
        "and it is a different control")
    withCollection(true, function()
        QR.db.zoneSurveyEnabled = true
        DC.follow = { startedAt = 0 }
        control.setting._setValue(false)
        t:assertFalse(QR.db.dataCollection,
            "unticking writes false, got " .. tostring(QR.db.dataCollection))
        t:assertNil(DC.follow, "and drops the route being timed")
        t:assertTrue(QR.db.zoneSurveyEnabled, "the zone survey setting is left alone")
        control.setting._setValue(true)
        t:assertTrue(QR.db.dataCollection, "ticking writes true")
    end)
end)

-- All ten languages translate every string (the practice since the zone
-- survey strings); esMX shares the esES block.
T:run(prefix .. "every locale translates the new strings, and says the data stays local", function(t)
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
    local chunk = loadfile(scriptDir .. "../QuickRoute/Localization.lua")
    t:assertNotNil(chunk, "Localization.lua loads")
    if not chunk then return end
    local savedLocale = MockWoW.config.locale
    local keys = { "SETTINGS_DATA_COLLECTION", "SETTINGS_DATA_COLLECTION_TT", "DATA_COLLECTION_ON",
        "DATA_COLLECTION_OFF", "DATA_COLLECTION_CLEARED", "DATA_COLLECTION_COUNTS",
        "SAVE_REMINDER_OBSERVATIONS_NAME", "SAVE_REMINDER_OBSERVATIONS_NEW" }
    local english = {}
    for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU",
        "koKR", "zhCN", "zhTW", "itIT" }) do
        MockWoW.config.locale = locale
        pcall(chunk, "QuickRoute", QR)
        for _, key in ipairs(keys) do
            local value = QR.L[key]
            t:assert(value ~= key, locale .. " sets " .. key .. ", got " .. tostring(value))
            if locale == "enUS" then
                english[key] = value
            else
                t:assert(value ~= english[key],
                    locale .. " translates " .. key .. ", got the English " .. tostring(value))
            end
        end
        local tooltip = QR.L["SETTINGS_DATA_COLLECTION_TT"]
        t:assertNotNil(tooltip:find("SavedVariables", 1, true),
            locale .. " tooltip names the SavedVariables file: " .. tooltip)
        local ok, text = pcall(string.format, QR.L["DATA_COLLECTION_COUNTS"], 1, 2, 3, 4, 5, 6)
        t:assertTrue(ok, locale .. " counts format takes six numbers: " .. tostring(text))
        t:assertNil(tostring(text):find("%d", 1, true), locale .. " counts format has no seventh number: " .. tostring(text))
        local okNew, line = pcall(string.format, QR.L["SAVE_REMINDER_OBSERVATIONS_NEW"], 7)
        t:assertTrue(okNew and line:find("7", 1, true) ~= nil,
            locale .. " reminder line takes the count: " .. tostring(line))
    end
    MockWoW.config.locale = "enUS"
    pcall(chunk, "QuickRoute", QR)
    MockWoW.config.locale = savedLocale
    t:assertEqual("Destination:", QR.L["DESTINATION"], "English is restored")
end)

-------------------------------------------------------------------------------
-- (a) Teleport landings
-------------------------------------------------------------------------------

T:run(prefix .. "a known teleport's landing is recorded against the data", function(t)
    withCollection(true, function()
        castAndLand(IRONFORGE, F.ironforge, 0.2750, 0.7350)
        local landings = list("landings")
        t:assertEqual(1, #landings, "one landing recorded, got " .. #landings)
        local e = landings[1]
        if not e then return end
        t:assertEqual(IRONFORGE, e.id, "the teleport id")
        t:assertEqual(IRONFORGE, e.spellID, "the cast spell")
        t:assertEqual("spell", e.kind, "the kind")
        t:assertEqual(F.stormwind, e.fromMapID, "cast in Stormwind")
        t:assertEqual(F.ironforge, e.toMapID, "landed in Ironforge")
        t:assertEqual(0.275, e.toX, "landing x")
        t:assertEqual(F.ironforge, e.expMapID, "the data expects Ironforge")
        t:assertEqual(0.273, e.expX, "and x 0.273")
        t:assertFalse(e.mismatch, "0.0028 apart is not a mismatch, distance=" .. tostring(e.distance))
        t:assertTrue(e.loading, "landed through a loading screen")
        t:assertNotNil(e.seen, "timestamped")
        t:assertNil(DC.pendingCast, "nothing left pending")
    end)
end)

T:run(prefix .. "a known teleport records nothing while switched off", function(t)
    withCollection(false, function()
        castAndLand(IRONFORGE, F.ironforge, 0.2750, 0.7350)
        t:assertEqual(0, #list("landings"), "no landing while off, got " .. #list("landings"))
        -- The same driver records once switched on: the off result is the guard.
        QR.db.dataCollection = true
        castAndLand(IRONFORGE, F.ironforge, 0.2750, 0.7350)
        t:assertEqual(1, #list("landings"), "the driver itself records when on")
    end)
end)

T:run(prefix .. "a landing far from the data is flagged", function(t)
    withCollection(true, function()
        castAndLand(IRONFORGE, F.ironforge, 0.60, 0.60)
        local e = list("landings")[1]
        t:assertNotNil(e, "the landing is recorded")
        if not e then return end
        t:assertTrue(e.mismatch, "flagged, distance=" .. tostring(e.distance))
        t:assertGreaterThan(e.distance, 0.3, "the distance is recorded")
    end)
end)

T:run(prefix .. "a continent map after the loading screen is skipped", function(t)
    withCollection(true, function()
        castAndLand(IRONFORGE, F.continent, 0.5, 0.5)
        t:assertEqual(0, #list("landings"), "the continent is not the landing")
        t:assertNotNil(DC.pendingCast, "the cast is still waiting for the zone")
        at(F.ironforge, 0.2740, 0.7340)
        event("ZONE_CHANGED_NEW_AREA")
        local e = list("landings")[1]
        t:assertEqual(F.ironforge, e and e.toMapID, "the zone after it is, got " .. tostring(e and e.toMapID))
    end)
end)

T:run(prefix .. "a cast in combat starts nothing", function(t)
    withCollection(true, function()
        MockWoW.config.inCombatLockdown = true
        at(F.stormwind, 0.5, 0.5)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IRONFORGE)
        t:assertNil(DC.pendingCast, "no pending cast from combat, got " .. tostring(DC.pendingCast))
        MockWoW.config.inCombatLockdown = false
    end)
end)

T:run(prefix .. "a teleport without a landing in its window records nothing", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IRONFORGE)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 30
        event("LOADING_SCREEN_ENABLED")
        at(F.ironforge, 0.2740, 0.7340)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("landings"), "a loading screen 30 s later is not this cast's")
    end)
end)

T:run(prefix .. "a same-map teleport without a loading screen is recorded", function(t)
    withCollection(true, function()
        -- Teleport: Stormwind, cast inside Stormwind.
        at(F.stormwind, 0.2, 0.2)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", STORMWIND)
        at(F.stormwind, 0.4965, 0.8725)
        event("ZONE_CHANGED")
        local e = list("landings")[1]
        t:assertNotNil(e, "the jump is recorded")
        if not e then return end
        t:assertEqual(STORMWIND, e.id, "as Teleport: Stormwind")
        t:assertFalse(e.loading, "without a loading screen")
        t:assertEqual(0, e.distance, "on the expected point, distance=" .. tostring(e.distance))
    end)
end)

T:run(prefix .. "an item teleport is matched through its on-use spell", function(t)
    local itemID, data
    for id, d in pairs(QR.TeleportItemsData) do
        if d.mapID and d.x and d.y and not d.isDynamic and not d.travelDestinationKey
            and (not itemID or id < itemID) then
            itemID, data = id, d
        end
    end
    if not itemID and flavor == "forever" then
        -- Forever's generated items all carry a travelDestinationKey; any item
        -- with a fixed landing will do for the on-use spell lookup.
        for id, d in pairs(QR.TeleportItemsData) do
            if d.mapID and d.x and d.y and not d.isDynamic and (not itemID or id < itemID) then
                itemID, data = id, d
            end
        end
    end
    t:assertNotNil(itemID, "the data has an item with a fixed landing")
    if not itemID then return end
    local savedGetItemSpell = C_Item.GetItemSpell
    local savedIndex, savedItems = DC.spellIndex, DC.itemSpells
    C_Item.GetItemSpell = function(id)
        if id == itemID then return "Use", 990001 end
    end
    DC.spellIndex, DC.itemSpells = nil, nil
    local ok, err = pcall(withCollection, true, function()
        castAndLand(990001, data.mapID, data.x, data.y)
        local e = list("landings")[1]
        t:assertNotNil(e, "the item's landing is recorded")
        if not e then return end
        t:assertEqual(itemID, e.id, "under the item id, got " .. tostring(e.id))
        t:assertEqual(990001, e.spellID, "with the spell it cast")
        t:assertEqual(data.type, e.kind, "and the item's kind")
    end)
    C_Item.GetItemSpell = savedGetItemSpell
    DC.spellIndex, DC.itemSpells = savedIndex, savedItems
    t:assertTrue(ok, "ran: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- (b) Unknown teleports
-------------------------------------------------------------------------------

T:run(prefix .. "an unknown spell followed by a loading screen is recorded", function(t)
    withCollection(true, function()
        local to = F.unknownTo
        castAndLand(990002, to.mapID, to.x, to.y, F.unknownFrom)
        local entries = list("unknownTeleports")
        t:assertEqual(1, #entries, "one unknown teleport, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual(990002, e.spellID, "the spell")
        t:assertEqual("Spell 990002", e.name, "its name")
        t:assertEqual(F.unknownFrom.mapID, e.fromMapID, "from map " .. F.unknownFrom.mapID)
        t:assertEqual(F.unknownTo.mapID, e.toMapID, "to map " .. F.unknownTo.mapID)
        t:assertEqual(0, #list("landings"), "and not as a known landing")
    end)
end)

-- What scripts/data/forever_observed_portals.json needs for a portal: both
-- ends with map and position, the faction, and how long the loading screen
-- took; the game map from GetInstanceInfo tells a phased or instanced copy
-- apart. The instance values here are synthetic and differ on purpose, so a
-- from/to swap shows.
T:run(prefix .. "an unknown teleport carries what a curated portal entry needs", function(t)
    withCollection(true, function()
        local from, to = F.unknownFrom, F.unknownTo
        at(from.mapID, from.x, from.y)
        MockWoW.config.instanceMapID, MockWoW.config.instanceName = 9001, "Departure"
        MockWoW.config.playerFaction = "Alliance"
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 990004)
        event("LOADING_SCREEN_ENABLED")
        MockWoW.config.baseTime = MockWoW.config.baseTime + 5
        MockWoW.config.instanceMapID, MockWoW.config.instanceName = 9002, "Arrival"
        at(to.mapID, to.x, to.y)
        event("LOADING_SCREEN_DISABLED")
        local e = list("unknownTeleports")[1]
        t:assertNotNil(e, "recorded")
        if not e then return end
        t:assertEqual(from.mapID, e.fromMapID, "from map")
        t:assertEqual(from.x, e.fromX, "from x")
        t:assertEqual(from.y, e.fromY, "from y")
        t:assertEqual(to.mapID, e.toMapID, "to map")
        t:assertEqual(to.x, e.toX, "to x")
        t:assertEqual(to.y, e.toY, "to y")
        t:assertEqual(990004, e.spellID, "spell id")
        t:assertEqual("Spell 990004", e.name, "spell name")
        t:assertEqual(9001, e.fromInstanceMapID, "game map at the cast, got " .. tostring(e.fromInstanceMapID))
        t:assertEqual("Departure", e.fromInstanceName, "its name")
        t:assertEqual(9002, e.toInstanceMapID, "game map at the landing, got " .. tostring(e.toInstanceMapID))
        t:assertEqual("Arrival", e.toInstanceName, "its name")
        t:assertEqual("Alliance", e.faction, "the faction")
        t:assertEqual(5, e.loadingSeconds, "the loading screen took 5 s, got " .. tostring(e.loadingSeconds))
    end)
end)

T:run(prefix .. "an unknown teleport records nothing while switched off", function(t)
    withCollection(false, function()
        local to = F.unknownTo
        castAndLand(990002, to.mapID, to.x, to.y, F.unknownFrom)
        t:assertEqual(0, #list("unknownTeleports"), "nothing while off")
        QR.db.dataCollection = true
        castAndLand(990002, to.mapID, to.x, to.y, F.unknownFrom)
        t:assertEqual(1, #list("unknownTeleports"), "the driver itself records when on")
    end)
end)

T:run(prefix .. "an unknown spell without an immediate loading screen is not a teleport", function(t)
    withCollection(true, function()
        local from, to = F.unknownFrom, F.unknownTo
        at(from.mapID, from.x, from.y)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 990003)
        at(to.mapID, to.x, to.y)
        event("ZONE_CHANGED_NEW_AREA")
        t:assertEqual(0, #list("unknownTeleports"), "a map change alone is not enough")

        at(from.mapID, from.x, from.y)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 990003)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 10
        event("LOADING_SCREEN_ENABLED")
        at(to.mapID, to.x, to.y)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("unknownTeleports"), "nor a loading screen 10 s after the cast")
    end)
end)

-------------------------------------------------------------------------------
-- NPC teleports: a gossip option that starts a loading screen
-------------------------------------------------------------------------------

-- The dialog's NPC as the client gives it: UnitName("npc") and the creature
-- GUID, whose sixth part is the NPC ID.
local function talkTo(name, npcID)
    local realName = _G.UnitName
    _G.UnitName = function(unit)
        if unit == "npc" then return name end
        return realName(unit)
    end
    _G.UnitGUID = function(unit)
        if unit == "npc" and npcID then return "Creature-0-3767-1-1234-" .. npcID .. "-00006F2A1B" end
        return nil
    end
end

local function onGameMap(point)
    at(point.mapID, point.x, point.y)
    MockWoW.config.instanceMapID, MockWoW.config.instanceName = point.instanceMapID, point.instanceName
end

--- The owner's retail trace of 2026-11-11, 20:38:57 to 20:39:06, event for
-- event with its GetTime values. `castAt`, when given, adds the cast of
-- "Summon Delve-O-Bot 7001" (467465): the trace does not record casts, only
-- that the stored unknownTeleports entry put one within 3 s before the
-- loading screen.
local function delveBotCrossing(castAt)
    local cfg = MockWoW.config
    local from, to = F.gossipFrom, F.gossipTo
    onGameMap(from)
    MockWoW.config.playerFaction = "Alliance"
    talkTo("Delve-O-Bot 7001", 232267)
    local function clock(g) cfg.baseTime = g end
    local cast_done = false
    -- Cast before the step at `g` when the cast time lies before it.
    local function cast(g)
        if castAt and castAt <= g and not cast_done then
            clock(castAt)
            event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 467465)
            cast_done = true
        end
    end
    cast(2500480.376)
    clock(2500480.376)
    event("GOSSIP_SHOW")
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
    cast(2500481.738)
    clock(2500481.738)
    event("GOSSIP_CLOSED", false)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
    event("GOSSIP_CLOSED", false)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 0)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 0)
    cast(2500481.886)
    clock(2500481.886)
    event("LOADING_SCREEN_ENABLED")
    -- During and right after the loading screen the client reports no map.
    at(nil, nil, nil)
    MockWoW.config.instanceMapID, MockWoW.config.instanceName = to.instanceMapID, to.instanceName
    clock(2500487.478)
    event("PLAYER_ENTERING_WORLD", false, false)
    event("LOADING_SCREEN_DISABLED")
    -- Another NPC's interaction on arrival.
    talkTo("Unknown", 212407)
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 79)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 79)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 79)
    clock(2500489.042)
    onGameMap(to)
    event("ZONE_CHANGED_NEW_AREA")
end

T:run(prefix .. "a teleport from an NPC's dialog is filed under the NPC, not a spell cast before it", function(t)
    withCollection(true, function()
        -- The cast placed before the dialog opened. The trace cannot say when
        -- it was; the cases below cover a cast inside the dialog and after it.
        delveBotCrossing(2500479.9)
        local entries = list("unknownTeleports")
        t:assertEqual(1, #entries, "one crossing, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual("npc", e.cause, "the dialog is the cause, got " .. tostring(e.cause))
        t:assertEqual("Delve-O-Bot 7001", e.npc, "the NPC, got " .. tostring(e.npc))
        t:assertEqual(232267, e.npcID, "its ID from the GUID, got " .. tostring(e.npcID))
        t:assertEqual(3, e.interactionType, "a gossip interaction, got " .. tostring(e.interactionType))
        t:assertNil(e.spellID, "no spellID, got " .. tostring(e.spellID))
        t:assertEqual(467465, e.castSpellID, "the cast kept beside it, got " .. tostring(e.castSpellID))
        t:assertEqual("Spell 467465", e.castName, "with its name, got " .. tostring(e.castName))
        t:assertEqual(1.99, e.castSeconds, "1.99 s before the loading screen, got " .. tostring(e.castSeconds))
        t:assertEqual(0.15, e.npcSeconds, "the dialog closed 0.15 s before it, got " .. tostring(e.npcSeconds))
        t:assertEqual(F.gossipFrom.mapID, e.fromMapID, "from the NPC's map, got " .. tostring(e.fromMapID))
        t:assertEqual(F.gossipFrom.x, e.fromX, "at the NPC, x " .. tostring(e.fromX))
        t:assertEqual(F.gossipFrom.y, e.fromY, "at the NPC, y " .. tostring(e.fromY))
        t:assertEqual(F.gossipTo.mapID, e.toMapID, "to the arrival map, got " .. tostring(e.toMapID))
        t:assertEqual(F.gossipTo.x, e.toX, "arrival x " .. tostring(e.toX))
        t:assertEqual(1, e.fromInstanceMapID, "from game map 1, got " .. tostring(e.fromInstanceMapID))
        t:assertEqual(2694, e.toInstanceMapID, "to game map 2694, got " .. tostring(e.toInstanceMapID))
        t:assertEqual(7.2, e.loadingSeconds, "7.2 s from loading screen to landing, got " .. tostring(e.loadingSeconds))
        t:assertEqual("Alliance", e.faction, "the faction")
        t:assertEqual("Creature", e.npcType, "the GUID's type, got " .. tostring(e.npcType))
        t:assertEqual(string.format("npc:Creature:232267:%d:%.2f:%.2f", F.gossipTo.mapID, F.gossipTo.x, F.gossipTo.y), e.key,
            "keyed by the NPC, got " .. tostring(e.key))
        t:assertNil(DC.pendingCast, "nothing left in flight")
    end)
end)

T:run(prefix .. "a cast inside the dialog leaves the dialog the cause", function(t)
    withCollection(true, function()
        delveBotCrossing(2500481.0)
        local e = list("unknownTeleports")[1]
        t:assertEqual("npc", e and e.cause, "the dialog closed after the cast, got " .. tostring(e and e.cause))
        t:assertEqual(467465, e and e.castSpellID, "the cast is kept")
    end)
end)

T:run(prefix .. "a cast after the dialog closed is the cause, the dialog is kept beside it", function(t)
    withCollection(true, function()
        delveBotCrossing(2500481.8)
        local entries = list("unknownTeleports")
        t:assertEqual(1, #entries, "one crossing, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual("spell", e.cause, "the later cast is the cause, got " .. tostring(e.cause))
        t:assertEqual(467465, e.spellID, "as spellID, got " .. tostring(e.spellID))
        t:assertNil(e.castSpellID, "not twice")
        t:assertEqual(232267, e.npcID, "the dialog's NPC beside it, got " .. tostring(e.npcID))
        t:assertEqual(0.15, e.npcSeconds, "closed 0.15 s before the loading screen, got " .. tostring(e.npcSeconds))
        t:assertEqual(F.gossipFrom.mapID, e.fromMapID, "from where the cast was")
    end)
end)

T:run(prefix .. "a teleport from a dialog without any cast is recorded", function(t)
    withCollection(true, function()
        delveBotCrossing(nil)
        local entries = list("unknownTeleports")
        t:assertEqual(1, #entries, "one crossing, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual("npc", e.cause, "the dialog, got " .. tostring(e.cause))
        t:assertEqual(232267, e.npcID, "the NPC")
        t:assertNil(e.castSpellID, "no cast, got " .. tostring(e.castSpellID))
        t:assertEqual(F.gossipTo.mapID, e.toMapID, "the landing")
    end)
end)

-- The owner's second Delve-O-Bot crossing, 2026-11-11 21:29:54 to 21:30:03,
-- Harandar to a delve in the Eastern Kingdoms: here the client sent the
-- loading screen before GOSSIP_CLOSED. No cast was recorded with it, so it
-- went unrecorded before. The landing positions are not in the trace.
T:run(prefix .. "a loading screen that starts before the dialog's close is the NPC's", function(t)
    withCollection(true, function()
        local cfg = MockWoW.config
        local from = F.gossipTo
        local to = flavor == "forever" and { mapID = F.unknownFrom.mapID, continent = F.continent }
            -- The client reported continent 2537 first; the mock's continent
            -- is 13.
            or { mapID = 2512, continent = F.continent }
        onGameMap(from)
        talkTo("Delve-O-Bot 7001", 232267)
        cfg.baseTime = 2503537.331
        event("GOSSIP_SHOW")
        event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
        cfg.baseTime = 2503539.013
        event("LOADING_SCREEN_ENABLED")
        event("GOSSIP_CLOSED", false)
        event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
        event("GOSSIP_CLOSED", false)
        event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 0)
        event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 0)
        cfg.baseTime = 2503545.428
        -- A continent first, then the zone.
        at(to.continent, 0.5, 0.5)
        cfg.instanceMapID, cfg.instanceName = 0, "Eastern Kingdoms"
        event("PLAYER_ENTERING_WORLD", false, false)
        event("LOADING_SCREEN_DISABLED")
        at(to.mapID, 0.5, 0.5)
        event("ZONE_CHANGED_NEW_AREA")
        local entries = list("unknownTeleports")
        t:assertEqual(1, #entries, "one crossing, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual("npc", e.cause, "the open dialog, got " .. tostring(e.cause))
        t:assertEqual(232267, e.npcID, "the bot, got " .. tostring(e.npcID))
        t:assertEqual(0, e.npcSeconds, "no close before the loading screen: 0 s, got " .. tostring(e.npcSeconds))
        t:assertEqual(from.mapID, e.fromMapID, "from the bot's map, got " .. tostring(e.fromMapID))
        t:assertEqual(to.mapID, e.toMapID, "to the zone, got " .. tostring(e.toMapID))
        t:assertEqual(0, e.toInstanceMapID, "game map 0, got " .. tostring(e.toInstanceMapID))
    end)
end)

T:run(prefix .. "a dialog left open for long is no cause", function(t)
    withCollection(true, function()
        local from, to = F.gossipFrom, F.gossipTo
        onGameMap(from)
        talkTo("Delve-O-Bot 7001", 232267)
        event("GOSSIP_SHOW")
        -- Its close never reported; the player walks into a portal later.
        MockWoW.config.baseTime = MockWoW.config.baseTime + 600
        event("LOADING_SCREEN_ENABLED")
        onGameMap(to)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("unknownTeleports"), "a dialog opened 600 s before files nothing")
    end)
end)

T:run(prefix .. "a loading screen long after a dialog closed is not the NPC's", function(t)
    withCollection(true, function()
        local from, to = F.gossipFrom, F.gossipTo
        onGameMap(from)
        talkTo("Innkeeper", 6740)
        event("GOSSIP_SHOW")
        event("GOSSIP_CLOSED", false)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 10
        event("LOADING_SCREEN_ENABLED")
        onGameMap(to)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("unknownTeleports"), "a portal walked into 10 s later is no NPC teleport")
    end)
end)

T:run(prefix .. "an interaction that is no gossip dialog is no cause", function(t)
    withCollection(true, function()
        local from, to = F.gossipFrom, F.gossipTo
        onGameMap(from)
        talkTo("Merchant", 1234)
        -- Merchant (Enum.PlayerInteractionType.Merchant = 5), no GOSSIP_SHOW.
        event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
        event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
        event("LOADING_SCREEN_ENABLED")
        onGameMap(to)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("unknownTeleports"), "closing a vendor before a portal files nothing")
    end)
end)

--- One closed gossip dialog with `name`/`npcID` at the current position.
local function dialog(name, npcID)
    talkTo(name, npcID)
    event("GOSSIP_SHOW")
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
    event("GOSSIP_CLOSED", false)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
end

local function loadInto(point)
    event("LOADING_SCREEN_ENABLED")
    onGameMap(point)
    event("LOADING_SCREEN_DISABLED")
end

T:run(prefix .. "a second NPC's teleport carries that NPC, not the one talked to before", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        dialog("Innkeeper", 6740)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        at(F.gossipFrom.mapID, 0.5, 0.5)
        dialog("Delve-O-Bot 7001", 232267)
        loadInto(F.gossipTo)
        local e = list("unknownTeleports")[1]
        t:assertEqual(232267, e and e.npcID, "the bot, got " .. tostring(e and e.npcID))
        t:assertEqual(0.5, e and e.fromX, "from where the bot stood, got " .. tostring(e and e.fromX))
    end)
end)

T:run(prefix .. "the loading screen uses up the dialog", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        dialog("Delve-O-Bot 7001", 232267)
        loadInto(F.gossipTo)
        -- A second loading screen within 2 s of the close, somewhere else.
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1
        loadInto({ mapID = F.stormwind, x = 0.5, y = 0.5 })
        t:assertEqual(1, #list("unknownTeleports"), "only the first crossing is the NPC's")
    end)
end)

T:run(prefix .. "a later hide does not move the dialog's close", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        dialog("Delve-O-Bot 7001", 232267)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 1.9
        event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 0)
        MockWoW.config.baseTime = MockWoW.config.baseTime + 0.6
        loadInto(F.gossipTo)
        t:assertEqual(0, #list("unknownTeleports"), "2.5 s after the close is too late")
    end)
end)

T:run(prefix .. "a reload drops the dialog", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        dialog("Delve-O-Bot 7001", 232267)
        event("PLAYER_ENTERING_WORLD", false, true)
        loadInto(F.gossipTo)
        t:assertEqual(0, #list("unknownTeleports"), "nothing from before the reload")
    end)
end)

T:run(prefix .. "switching off drops the dialog", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        dialog("Delve-O-Bot 7001", 232267)
        DC:SetEnabled(false)
        DC:SetEnabled(true)
        loadInto(F.gossipTo)
        t:assertEqual(0, #list("unknownTeleports"), "nothing from before the switch went off")
    end)
end)

T:run(prefix .. "a GameObject's ID is stored with its type", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        talkTo("Portal", nil)
        _G.UnitGUID = function(unit)
            if unit == "npc" then return "GameObject-0-3767-1-1234-232267-00006F2A1B" end
            return nil
        end
        event("GOSSIP_SHOW")
        event("GOSSIP_CLOSED", false)
        loadInto(F.gossipTo)
        local e = list("unknownTeleports")[1]
        t:assertEqual("GameObject", e and e.npcType, "the type, got " .. tostring(e and e.npcType))
        t:assertTrue(e ~= nil and e.key:find("npc:GameObject:232267:", 1, true) == 1,
            "a key apart from the creature with that number, got " .. tostring(e and e.key))
    end)
end)

T:run(prefix .. "a known teleport cast after a dialog stays a known landing", function(t)
    withCollection(true, function()
        onGameMap(F.gossipFrom)
        talkTo("Delve-O-Bot 7001", 232267)
        event("GOSSIP_SHOW")
        event("GOSSIP_CLOSED", false)
        castAndLand(IRONFORGE, F.ironforge, 0.2730, 0.7330, F.gossipFrom)
        t:assertEqual(1, #list("landings"), "the landing of the known teleport")
        t:assertEqual(0, #list("unknownTeleports"), "and no NPC teleport")
    end)
end)

T:run(prefix .. "an NPC whose name and GUID are secret is recorded without them", function(t)
    withCollection(true, function()
        local secret = {}
        talkTo("Delve-O-Bot 7001", 232267)
        local realName, realGUID = _G.UnitName, _G.UnitGUID
        _G.UnitName = function(unit)
            if unit == "npc" then secret.name = "Delve-O-Bot 7001"; return secret.name end
            return realName(unit)
        end
        _G.UnitGUID = function(unit)
            if unit == "npc" then secret.guid = realGUID(unit); return secret.guid end
            return realGUID(unit)
        end
        _G.issecretvalue = function(value)
            return value ~= nil and (value == secret.name or value == secret.guid)
        end
        local from, to = F.gossipFrom, F.gossipTo
        onGameMap(from)
        event("GOSSIP_SHOW")
        event("GOSSIP_CLOSED", false)
        event("LOADING_SCREEN_ENABLED")
        onGameMap(to)
        event("LOADING_SCREEN_DISABLED")
        local e = list("unknownTeleports")[1]
        t:assertNotNil(e, "the crossing is still recorded")
        if not e then return end
        t:assertEqual("npc", e.cause, "as an NPC teleport")
        t:assertNil(e.npc, "without the secret name, got " .. tostring(e.npc))
        t:assertNil(e.npcID, "without an ID read from the secret GUID, got " .. tostring(e.npcID))
    end)
end)

-------------------------------------------------------------------------------
-- (c) Routes without a result
-------------------------------------------------------------------------------

T:run(prefix .. "a calculation without a route is recorded", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        local route, failure = PC:CalculatePath(0, 0.5, 0.5)
        t:assertNil(route, "the calculation fails")
        local entries = list("noRoute")
        t:assertEqual(1, #entries, "one entry, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertEqual(failure and failure.reason, e.reason, "with the failure reason")
        t:assertEqual("direct", e.source, "from a direct call")
        t:assertEqual(F.stormwind, e.fromMapID, "from where the player stands")
        t:assertEqual(0.5, e.toX, "to the requested x")

        PC:CalculatePath(0, 0.5, 0.5)
        t:assertEqual(1, #list("noRoute"), "a repeat is collapsed")
        t:assertEqual(2, list("noRoute")[1].count, "and counted")
    end)
end)

T:run(prefix .. "an asynchronous calculation without a route names its consumer", function(t)
    withCollection(true, function()
        local delivered = false
        PC:CalculatePathAsync(0, 0.5, 0.5, nil, function() delivered = true end,
            { consumer = QR.ROUTE_CONSUMER.API })
        t:assertTrue(delivered, "the search finished")
        local e = list("noRoute")[1]
        t:assertEqual("api", e and e.source, "source is the consumer, got " .. tostring(e and e.source))
    end)
end)

T:run(prefix .. "a calculation without a route records nothing while switched off", function(t)
    withCollection(false, function()
        local route = PC:CalculatePath(0, 0.5, 0.5)
        t:assertNil(route, "the calculation fails")
        t:assertEqual(0, #list("noRoute"), "nothing recorded while off")
    end)
end)

-------------------------------------------------------------------------------
-- (f) Calculation time
-------------------------------------------------------------------------------

T:run(prefix .. "a synchronous calculation is timed", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        local route = PC:CalculatePath(F.stormwind, 0.6, 0.6)
        t:assertNotNil(route, "a route within Stormwind")
        local entries = list("calcTimes")
        t:assertEqual(1, #entries, "one timing, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertFalse(e.async, "synchronous")
        t:assertTrue(e.found, "found")
        t:assertGreaterThan(e.ms, 0, "a measured duration")
        t:assertGreaterThan(e.pathNodes, 1, "and the path length")
    end)
end)

T:run(prefix .. "an asynchronous calculation is timed from request to result", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        local got
        PC:CalculatePathAsync(F.stormwind, 0.6, 0.6, nil, function(route) got = route end,
            { consumer = QR.ROUTE_CONSUMER.API })
        t:assertNotNil(got, "the search delivered a route")
        local entries = list("calcTimes")
        t:assertEqual(1, #entries, "one timing, not one per layer, got " .. #entries)
        local e = entries[1]
        if not e then return end
        t:assertTrue(e.async, "asynchronous")
        t:assertEqual("api", e.consumer, "for its consumer")
        t:assertGreaterThan(e.slices, 0, "with a slice count")
        t:assertTrue(e.found, "found")
        t:assertGreaterThan(e.ms, 0, "a measured duration")
    end)
end)

T:run(prefix .. "calculations are not timed while switched off", function(t)
    withCollection(false, function()
        at(F.stormwind, 0.5, 0.5)
        PC:CalculatePath(F.stormwind, 0.6, 0.6)
        PC:CalculatePathAsync(F.stormwind, 0.6, 0.6, nil, function() end, { consumer = QR.ROUTE_CONSUMER.API })
        t:assertEqual(0, #list("calcTimes"), "nothing while off")
    end)
end)

T:run(prefix .. "a failing recording does not break routing", function(t)
    withCollection(true, function()
        local savedPush = DC.Push
        DC.Push = function() error("recording failed") end
        at(F.stormwind, 0.5, 0.5)
        local ok, route = pcall(PC.CalculatePath, PC, F.stormwind, 0.6, 0.6)
        local ok2, failRoute, failure = pcall(PC.CalculatePath, PC, 0, 0.5, 0.5)
        local ok3 = pcall(castAndLand, IRONFORGE, F.ironforge, 0.2750, 0.7350)
        DC.Push = savedPush
        t:assertTrue(ok, "the calculation does not raise")
        t:assertNotNil(route, "and still returns its route")
        t:assertTrue(ok2 and failRoute == nil and failure ~= nil, "a failure still returns its failure")
        t:assertTrue(ok3, "the event handler does not raise")
    end)
end)

-------------------------------------------------------------------------------
-- (e) Rejected steps
-------------------------------------------------------------------------------

local function anyEdge()
    if not PC.graph or PC.graphDirty then PC:BuildGraph() end
    for from, edges in pairs(PC.graph.edges) do
        for to, edge in pairs(edges) do return from, to, edge end
    end
end

T:run(prefix .. "a refused step is recorded with its type and destination", function(t)
    withCollection(true, function()
        local from, to, edge = anyEdge()
        t:assertNotNil(from, "the graph has an edge")
        if not from then return end
        PC:ExcludeEdge(from, to, { mapID = F.ironforge, x = 0.3, y = 0.7 })
        PC:IncludeEdge(from, to)
        local e = list("rejectedSteps")[1]
        t:assertNotNil(e, "the refusal is recorded")
        if not e then return end
        t:assertEqual(from, e.from, "from node")
        t:assertEqual(to, e.to, "to node")
        t:assertEqual(edge.edgeType, e.stepType, "the step type")
        t:assertEqual(F.ironforge, e.toMapID, "the destination")
    end)
end)

T:run(prefix .. "a refused step records nothing while switched off", function(t)
    withCollection(false, function()
        local from, to = anyEdge()
        t:assertTrue(PC:ExcludeEdge(from, to, { mapID = F.ironforge, x = 0.3, y = 0.7 }), "the refusal itself works")
        PC:IncludeEdge(from, to)
        t:assertEqual(0, #list("rejectedSteps"), "nothing recorded while off")
    end)
end)

-------------------------------------------------------------------------------
-- (d) Estimated against measured time
-------------------------------------------------------------------------------

-- The source sits on the result, where WaypointIntegration puts it
-- (result.waypointSource), not on the waypoint.
local function ironforgeRoute()
    return {
        waypoint = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" },
        waypointSource = "test",
        totalTime = 100,
        steps = {
            { type = "walk", time = 20, fromMapID = F.stormwind, destMapID = F.stormwind },
            { type = "portal", time = 10, fromMapID = F.stormwind, destMapID = F.ironforge },
            { type = "walk", time = 30, fromMapID = F.ironforge, destMapID = F.ironforge },
        },
    }
end

local function followIronforge()
    at(F.stormwind, 0.5, 0.5)
    DC:OnRouteShown(ironforgeRoute())
    MockWoW.config.baseTime = MockWoW.config.baseTime + 40
    at(F.ironforge, 0.5, 0.5)
    DC:SampleRoute()
    MockWoW.config.baseTime = MockWoW.config.baseTime + 25
    at(F.ironforge, 0.3, 0.7)
    DC:SampleRoute()
end

T:run(prefix .. "a followed route records each leg and the whole trip", function(t)
    withCollection(true, function()
        followIronforge()
        local entries = list("stepTimes")
        t:assertEqual(3, #entries, "two legs and the trip, got " .. #entries)
        local leg, last, trip = entries[1], entries[2], entries[3]
        if not trip then return end
        t:assertEqual("walk+portal", leg.types, "first leg covers the walk and the portal")
        t:assertEqual(30, leg.estimated, "estimated 20+10")
        t:assertEqual(40, leg.measured, "measured 40")
        t:assertEqual(F.ironforge, leg.toMapID, "ending in Ironforge")
        t:assertEqual("walk", last.types, "the last leg is the walk")
        t:assertEqual(25, last.measured, "measured 25")
        t:assertEqual("route", trip.kind, "then the trip")
        t:assertEqual("test", trip.source, "with the source the result carries, got " .. tostring(trip.source))
        t:assertEqual(100, trip.estimated, "against the route's estimate")
        t:assertEqual(65, trip.measured, "measured start to arrival")
        t:assertNil(trip.diverged, "on plan")
        t:assertNil(DC.follow, "and the route is no longer followed")
    end)
end)

T:run(prefix .. "a followed route records nothing while switched off", function(t)
    withCollection(false, function()
        followIronforge()
        t:assertEqual(0, #list("stepTimes"), "nothing while off")
        t:assertNil(DC.follow, "and nothing followed")
    end)
end)

T:run(prefix .. "leaving the plan stops leg timing but keeps the trip", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        at(F.offPlan, 0.5, 0.5)
        DC:SampleRoute()
        at(F.ironforge, 0.3, 0.7)
        DC:SampleRoute()
        local entries = list("stepTimes")
        t:assertEqual(1, #entries, "only the trip, got " .. #entries)
        t:assertTrue(entries[1] and entries[1].diverged, "flagged as diverged")
    end)
end)

T:run(prefix .. "the route panel hands its routes to the timer", function(t)
    withCollection(true, function()
        local savedFrame = QR.UI.frame
        QR.UI.frame = nil  -- UpdateRoute returns at once; the hook still runs
        at(F.stormwind, 0.5, 0.5)
        local ok, err = pcall(QR.UI.UpdateRoute, QR.UI, ironforgeRoute())
        QR.UI.frame = savedFrame
        t:assertTrue(ok, "UpdateRoute ran: " .. tostring(err))
        t:assertEqual(F.ironforge, DC.follow and DC.follow.dest.mapID,
            "the shown route is followed, got " .. tostring(DC.follow and DC.follow.dest.mapID))
    end)
end)

-------------------------------------------------------------------------------
-- The zone survey is not under this switch
--
-- PR #121 first put the survey behind the observation switch; the owner
-- decided against that. These cases are #121's survey cases turned around.
-------------------------------------------------------------------------------

T:run(prefix .. "the zone survey records with the observations switched off", function(t)
    withCollection(false, function()
        QR.db.zoneSurveyEnabled = true
        QR.db.zoneSurvey = {}
        ZS:ForgetArrivalState()
        at(F.stormwind, 0.5, 0.5)
        t:assertEqual(F.stormwind, ZS:Capture(), "the survey on and the observations off: it records")
        t:assertEqual(1, ZS:Count(), "one map stored")
        QR.db.zoneSurveyEnabled = false
        QR.db.zoneSurvey = {}
        QR.db.dataCollection = true
        t:assertNil(ZS:Capture(), "the observations on do not switch the survey on")
    end)
end)

T:run(prefix .. "switching the observations off keeps the survey's crossing in flight", function(t)
    withCollection(true, function()
        QR.db.zoneSurveyEnabled = true
        QR.db.zoneSurvey = {}
        ZS:ForgetArrivalState()
        ZS.unsavedCaptures, ZS.unsavedCrossings = 0, 0
        at(F.stormwind, 0.5, 0.5)
        ZS:Capture()
        -- Off by the setting, and the event path that drops in-flight state.
        DC.pendingCast = { loading = true }
        DC:SetEnabled(false)
        event("ZONE_CHANGED")
        at(F.ironforge, 0.5, 0.5)
        ZS:Capture()
        t:assertEqual(1, ZS.unsavedCrossings,
            "the crossing Stormwind -> Ironforge is recorded, got " .. tostring(ZS.unsavedCrossings))
    end)
end)

-------------------------------------------------------------------------------
-- /qrdata
-------------------------------------------------------------------------------

T:run(prefix .. "/qrdata off stops every recording and leaves the survey alone", function(t)
    withCollection(true, function()
        QR.db.zoneSurveyEnabled = true
        QR.db.zoneSurvey = {}
        ZS:ForgetArrivalState()
        at(F.stormwind, 0.5, 0.5)
        -- Things in flight when the switch goes off.
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IRONFORGE)
        event("LOADING_SCREEN_ENABLED")
        DC:OnRouteShown(ironforgeRoute())

        SlashCmdList["QRDATA"]("off")
        t:assertFalse(QR.db.dataCollection, "the switch is off")
        t:assertNil(DC.pendingCast, "the pending cast is dropped")
        t:assertNil(DC.follow, "the followed route is dropped")
        t:assertTrue(QR.db.zoneSurveyEnabled, "the survey setting is untouched")

        at(F.ironforge, 0.3, 0.7)
        event("LOADING_SCREEN_DISABLED")
        DC:SampleRoute()
        castAndLand(990002, F.unknownTo.mapID, F.unknownTo.x, F.unknownTo.y, F.unknownFrom)
        PC:CalculatePath(0, 0.5, 0.5)
        PC:CalculatePath(F.stormwind, 0.6, 0.6)
        local from, to = anyEdge()
        PC:ExcludeEdge(from, to, nil)
        PC:IncludeEdge(from, to)
        for _, name in ipairs({ "landings", "unknownTeleports", "noRoute", "stepTimes",
            "rejectedSteps", "calcTimes" }) do
            t:assertEqual(0, #list(name), name .. " stays empty after /qrdata off, got " .. #list(name))
        end
        at(F.stormwind, 0.5, 0.5)
        t:assertEqual(F.stormwind, ZS:Capture(), "and the zone survey still records")
    end)
end)

T:run(prefix .. "/qrdata on, clear and the status line", function(t)
    withCollection(false, function()
        local printed = {}
        local savedPrint = QR.Print
        QR.Print = function(_, msg) printed[#printed + 1] = msg end
        local ok, err = pcall(function()
            SlashCmdList["QRDATA"]("on")
            t:assertTrue(QR.db.dataCollection, "on switches it on")
            PC:CalculatePath(0, 0.5, 0.5)
            DC:Push("landings", {})
            printed = {}
            SlashCmdList["QRDATA"]("")
            t:assertEqual(QR.L["DATA_COLLECTION_ON"], printed[1], "the status names the switch")
            t:assertEqual(string.format(QR.L["DATA_COLLECTION_COUNTS"], 1, 0, 1, 0, 0, 1),
                printed[2], "and counts each recording, without the survey")
            SlashCmdList["QRDATA"]("clear")
            t:assertEqual(0, #list("landings") + #list("noRoute") + #list("calcTimes"),
                "clear empties the recordings")
        end)
        QR.Print = savedPrint
        t:assertTrue(ok, "ran: " .. tostring(err))
    end)
end)

T:run(prefix .. "nothing is written to SavedVariables while switched off", function(t)
    withCollection(false, function()
        QR.db.observations = nil
        DC:Initialize()
        t:assertNil(QR.db.observations, "Initialize adds no observations key, got "
            .. tostring(QR.db.observations))
        SlashCmdList["QRDATA"]("clear")
        t:assertNil(QR.db.observations, "nor does /qrdata clear, got " .. tostring(QR.db.observations))
    end)
end)

T:run(prefix .. "corrupt saved observations are cleaned on load", function(t)
    withCollection(true, function()
        local calc = {}
        for i = 1, 60 do calc[i] = { ms = i } end
        QR.db.observations = { landings = "corrupt", noRoute = { 1, { reason = "x" }, "s" },
            calcTimes = calc, unknownList = {} }
        local wrapped = PC.CalculatePath
        DC:Initialize()
        local store = QR.db.observations
        t:assertEqual(0, #store.landings, "a non-table list becomes empty")
        t:assertEqual(1, #store.noRoute, "non-table entries are dropped, got " .. #store.noRoute)
        t:assertEqual(50, #store.calcTimes, "a list is cut to its cap, got " .. #store.calcTimes)
        t:assertEqual(60, store.calcTimes[50].ms, "keeping the newest")
        t:assertNil(store.unknownList, "unknown keys are dropped")
        t:assertEqual(wrapped, PC.CalculatePath, "a second Initialize does not wrap again")
    end)
end)

-------------------------------------------------------------------------------
-- What the save reminder reads
-------------------------------------------------------------------------------

T:run(prefix .. "every write counts as unsaved, a clear resets the count", function(t)
    withCollection(true, function()
        DC:Push("noRoute", { reason = "test" }, "k1")
        t:assertEqual(1, DC.unsavedCount, "a new entry counts once, got " .. tostring(DC.unsavedCount))
        DC:Push("noRoute", { reason = "test" }, "k1")
        t:assertEqual(1, #list("noRoute"), "the repeat is collapsed")
        t:assertEqual(2, DC.unsavedCount,
            "a collapsed repeat changes the saved count too, got " .. tostring(DC.unsavedCount))
        -- A failed calculation writes two lists: noRoute and calcTimes.
        PC:CalculatePath(0, 0.5, 0.5)
        t:assertEqual(4, DC.unsavedCount, "a hook's writes count too, got " .. tostring(DC.unsavedCount))
        SlashCmdList["QRDATA"]("clear")
        t:assertEqual(0, DC.unsavedCount, "clear: nothing left to lose, got " .. tostring(DC.unsavedCount))
        QR.db.dataCollection = false
        PC:CalculatePath(0, 0.5, 0.5)
        DC:Push("noRoute", { reason = "test" }, "k1")
        t:assertEqual(0, DC.unsavedCount, "nothing counted while off, got " .. tostring(DC.unsavedCount))
    end)
end)

-------------------------------------------------------------------------------
-- Review round 1
-------------------------------------------------------------------------------

T:run(prefix .. "the multi-stop planner's legs are not recorded", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        local context = PC:CreateRouteContext({ excludeCooldowns = true })
        t:assertNotNil(context, "a route context like MultiRoute:OptimizeTour builds")
        if not context then return end
        context:CalculatePathFrom(F.ironforge, 0.5, 0.5, 0, 0.5, 0.5, { excludeCooldowns = true })
        local leg = context:CalculatePathFrom(F.ironforge, 0.5, 0.5, F.ironforge, 0.6, 0.6,
            { excludeCooldowns = true })
        t:assertNotNil(leg, "the planner's leg still gets its route")
        t:assertEqual(0, #list("noRoute"), "a failed leg is no route failure, got " .. #list("noRoute"))
        t:assertEqual(0, #list("calcTimes"), "legs are not timed, got " .. #list("calcTimes"))
        PC:CalculatePath(0, 0.5, 0.5)
        t:assertEqual(1, #list("noRoute"), "the live calculator still records")
    end)
end)

T:run(prefix .. "the calculation wrapper does nothing while switched off", function(t)
    withCollection(false, function()
        local calls = 0
        local saved = DC.AfterCalculation
        DC.AfterCalculation = function(...) calls = calls + 1; return saved(...) end
        local ok, err = pcall(function()
            at(F.stormwind, 0.5, 0.5)
            PC:CalculatePath(F.stormwind, 0.6, 0.6)
            t:assertEqual(0, calls, "off: the recording step is not reached, got " .. calls)
            QR.db.dataCollection = true
            PC:CalculatePath(F.stormwind, 0.6, 0.6)
            t:assertEqual(1, calls, "on: it is, got " .. calls)
        end)
        DC.AfterCalculation = saved
        t:assertTrue(ok, "ran: " .. tostring(err))
    end)
end)

T:run(prefix .. "an asynchronous request leaves no clock reading while switched off", function(t)
    withCollection(false, function()
        for k in pairs(DC.requestClock) do DC.requestClock[k] = nil end
        at(F.stormwind, 0.5, 0.5)
        PC:CalculatePathAsync(F.stormwind, 0.6, 0.6, nil, function() end, { consumer = QR.ROUTE_CONSUMER.API })
        t:assertNil(next(DC.requestClock), "no request clock while off")
    end)
end)

T:run(prefix .. "every list keeps only its cap, newest last", function(t)
    withCollection(true, function()
        for name, cap in pairs(DC.CAPS) do
            for i = 1, cap + 5 do DC:Push(name, { n = i }) end
            local entries = list(name)
            t:assertEqual(cap, #entries, name .. " is cut to " .. cap .. ", got " .. #entries)
            t:assertEqual(6, entries[1] and entries[1].n, name .. " dropped the five oldest")
            t:assertEqual(cap + 5, entries[#entries] and entries[#entries].n, name .. " kept the newest")
        end
    end)
end)

T:run(prefix .. "a second loading screen before the landing drops the cast", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IRONFORGE)
        event("LOADING_SCREEN_ENABLED")
        event("LOADING_SCREEN_ENABLED")
        t:assertNil(DC.pendingCast, "the cast is dropped")
        at(F.ironforge, 0.2750, 0.7350)
        event("LOADING_SCREEN_DISABLED")
        t:assertEqual(0, #list("landings"), "and nothing is filed as its landing")
    end)
end)

T:run(prefix .. "a cast during the loading screen does not replace the teleport", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IRONFORGE)
        event("LOADING_SCREEN_ENABLED")
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 990002)
        at(F.ironforge, 0.2750, 0.7350)
        event("LOADING_SCREEN_DISABLED")
        local e = list("landings")[1]
        t:assertEqual(IRONFORGE, e and e.id, "the landing belongs to the teleport, got " .. tostring(e and e.id))
        t:assertEqual(F.stormwind, e and e.fromMapID, "cast from Stormwind")
        t:assertEqual(0, #list("unknownTeleports"), "the later cast is no unknown teleport")
    end)
end)

T:run(prefix .. "a player spell before a loading screen is flagged, not dropped", function(t)
    local saved = _G.IsPlayerSpell
    _G.IsPlayerSpell = function(id) return id == 990005 end
    local ok, err = pcall(withCollection, true, function()
        local to = F.unknownTo
        castAndLand(990005, to.mapID, to.x, to.y, F.unknownFrom)
        castAndLand(990006, to.mapID, to.x, to.y, F.unknownFrom)
        local entries = list("unknownTeleports")
        t:assertEqual(2, #entries, "both are kept, got " .. #entries)
        t:assertTrue(entries[1] and entries[1].playerSpell, "the player's own spell is flagged")
        t:assertNil(entries[2] and entries[2].playerSpell, "another spell is not")
    end)
    _G.IsPlayerSpell = saved
    t:assertTrue(ok, "ran: " .. tostring(err))
end)

T:run(prefix .. "a failing landing retry does not raise from the timer", function(t)
    withCollection(true, function()
        local savedTimer, savedTry = C_Timer.NewTimer, DC.TryLanding
        local queued
        C_Timer.NewTimer = function(_, fn) queued = fn; return { Cancel = function() end } end
        local ok, err = pcall(function()
            castAndLand(IRONFORGE, F.continent, 0.5, 0.5)
            t:assertNotNil(queued, "the continent schedules a retry")
            DC.TryLanding = function() error("retry failed") end
            local fired = pcall(queued)
            t:assertTrue(fired, "the timer callback does not raise")
            t:assertNil(DC.pendingCast, "and drops the cast")
        end)
        C_Timer.NewTimer, DC.TryLanding = savedTimer, savedTry
        t:assertTrue(ok, "ran: " .. tostring(err))
    end)
end)

T:run(prefix .. "events and sampling are registered only while switched on", function(t)
    withCollection(false, function()
        local frame = DC.frame
        t:assertNotNil(frame, "the frame exists")
        if not frame then return end
        DC:SetEnabled(false)
        for _, name in ipairs(DC.EVENTS) do
            t:assertFalse(frame:IsEventRegistered(name), "off: " .. name .. " is not registered")
        end
        t:assertNil(frame:GetScript("OnUpdate"), "off: no OnUpdate")
        DC:SetEnabled(true)
        for _, name in ipairs(DC.EVENTS) do
            t:assertTrue(frame:IsEventRegistered(name), "on: " .. name .. " is registered")
        end
        t:assertNotNil(frame:GetScript("OnUpdate"), "on: OnUpdate samples the route")
        -- Named, not read from DC.EVENTS: a name missing from that list is
        -- what this has to catch.
        for _, name in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "LOADING_SCREEN_ENABLED", "GOSSIP_SHOW",
            "GOSSIP_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
            t:assertTrue(frame:IsEventRegistered(name), "on: " .. name .. " is registered")
        end
        DC:SetEnabled(false)
        t:assertFalse(frame:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"), "off again: unregistered")
    end)
end)

local function arrive()
    at(F.ironforge, 0.3, 0.7)
    DC:SampleRoute()
end

T:run(prefix .. "a cleared route is no longer timed", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        t:assertNotNil(DC.follow, "followed")
        local savedFrame = QR.UI.frame
        QR.UI.frame = nil   -- ClearRoute returns at once; the hook still runs
        QR.UI:ClearRoute()
        QR.UI.frame = savedFrame
        t:assertNil(DC.follow, "dropped when the waypoint is cleared")
        arrive()
        t:assertEqual(0, #list("stepTimes"), "nothing recorded afterwards")
    end)
end)

-- Abandonment is decided by the waypoint, not by the window: MainFrame hides
-- itself when combat starts, and travelling with it closed is supported.
T:run(prefix .. "a closed route window, a combat hide included, keeps the timing", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        QR.MainFrame.closeCount = (QR.MainFrame.closeCount or 0) + 1   -- ESC or the close button
        pcall(QR.MainFrame.Hide, QR.MainFrame, "combat")                -- the combat-enter hide
        DC:SampleRoute()
        t:assertNotNil(DC.follow, "still followed with the window closed")
        arrive()
        t:assertEqual(3, #list("stepTimes"), "both legs and the trip recorded, got " .. #list("stepTimes"))
    end)
end)

--- Run fn with the route window closed the way production has it: the
-- frame hidden, MainFrame not showing. WaypointIntegration then does not
-- reach the panel, and the panel's own methods are counted, not run.
local function withWindowClosed(fn)
    local WI = QR.WaypointIntegration
    local frame = QR.UI.frame
    local wasShown = frame and frame:IsShown()
    local savedShow, savedRefresh = QR.UI.Show, QR.UI.RefreshRoute
    local savedPending, savedTimer = WI._pendingTriggers, C_Timer.NewTimer
    local calls = { show = 0, refresh = 0 }
    QR.UI.Show = function() calls.show = calls.show + 1 end
    QR.UI.RefreshRoute = function() calls.refresh = calls.refresh + 1 end
    -- The debounce runs at once.
    C_Timer.NewTimer = function(_, cb) cb(); return { Cancel = function() end } end
    if frame then frame:Hide() end
    QR.MainFrame.isShowing = false
    local ok, err = pcall(fn, WI, calls)
    QR.UI.Show, QR.UI.RefreshRoute = savedShow, savedRefresh
    C_Timer.NewTimer = savedTimer
    WI._pendingTriggers = savedPending
    WI:ClearQuestCoordCache()
    if frame and wasShown then frame:Show() end
    if not ok then error(err, 0) end
end

local function placePin(mapID, x, y)
    MockWoW.config.hasUserWaypoint = true
    MockWoW.config.userWaypoint = { uiMapID = mapID,
        position = { x = x, y = y, GetXY = function() return x, y end } }
end

local function sourcedRoute(source)
    local route = ironforgeRoute()
    route.waypointSource = source
    return route
end

--- Fire a client event through WaypointIntegration's own handler, the way
-- the client delivers it (the handler unlocks a locked destination on a pin
-- or super-tracking event before it reports the change). MockWoW:Reset drops
-- handlers, so the hooks are registered again for the call.
local function fireWired(event, ...)
    local WI = QR.WaypointIntegration
    local savedFrames, savedRegistered = {}, WI.hooksRegistered
    for i, frame in ipairs(MockWoW.eventFrames) do savedFrames[i] = frame end
    local ok, err = pcall(function(...)
        WI.hooksRegistered = false
        WI:RegisterHooks()
        MockWoW:FireEvent(event, ...)
    end, ...)
    MockWoW.eventFrames, WI.hooksRegistered = savedFrames, savedRegistered
    if not ok then error(err, 0) end
end

local function removePin()
    MockWoW.config.hasUserWaypoint, MockWoW.config.userWaypoint = false, nil
end

--- Run fn with a super-tracked quest whose objective is at `quest`.
local function withQuest(quest, fn)
    local cfg = MockWoW.config
    local savedSuper, savedWps = cfg.superTrackedQuestID, cfg.questWaypoints
    cfg.superTrackedQuestID = 4242
    cfg.questWaypoints = { [4242] = quest }
    local ok, err = pcall(fn)
    cfg.superTrackedQuestID, cfg.questWaypoints = savedSuper, savedWps
    if not ok then error(err, 0) end
end

T:run(prefix .. "a map pin removed with the window closed ends a route to it", function(t)
    withCollection(true, function()
        withWindowClosed(function(_, calls)
            at(F.stormwind, 0.5, 0.5)
            placePin(F.ironforge, 0.3, 0.7)
            DC:OnRouteShown(sourcedRoute("mappin"))
            removePin()
            fireWired("USER_WAYPOINT_UPDATED")
            t:assertEqual(0, calls.refresh, "the closed panel is not refreshed")
            t:assertNil(DC.follow, "the follow ends on the waypoint signal")
            arrive()
            t:assertEqual(0, #list("stepTimes"), "nothing recorded afterwards, got " .. #list("stepTimes"))
        end)
    end)
end)

T:run(prefix .. "a map pin removed in combat ends the route before the deferral", function(t)
    withCollection(true, function()
        withWindowClosed(function(WI)
            at(F.stormwind, 0.5, 0.5)
            placePin(F.ironforge, 0.3, 0.7)
            DC:OnRouteShown(sourcedRoute("mappin"))
            MockWoW.config.inCombatLockdown = true
            removePin()
            fireWired("USER_WAYPOINT_UPDATED")
            MockWoW.config.inCombatLockdown = false
            t:assertNil(DC.follow, "ended in combat")
            WI._waypointChangePending = false
        end)
    end)
end)

T:run(prefix .. "a pin that clears on arrival still records the trip", function(t)
    withCollection(true, function()
        withWindowClosed(function()
            at(F.stormwind, 0.5, 0.5)
            placePin(F.ironforge, 0.3, 0.7)
            DC:OnRouteShown(sourcedRoute("mappin"))
            at(F.ironforge, 0.3, 0.7)   -- arrived; no sample since
            removePin()
            fireWired("USER_WAYPOINT_UPDATED")
            local trip = list("stepTimes")[#list("stepTimes")]
            t:assertEqual("route", trip and trip.kind, "the trip is recorded by the last sample")
        end)
    end)
end)

-- A pin that is not the destination: removing it changes nothing the route
-- depends on.
for _, priority in ipairs({ "quest", "mappin" }) do
    T:run(prefix .. "an unrelated pin removed keeps a quest route (priority " .. priority .. ")", function(t)
        withCollection(true, function()
            QR.db.autoDestination = false
            QR.db.waypointPriority = priority
            withQuest({ mapID = F.ironforge, x = 0.3, y = 0.7 }, function()
                withWindowClosed(function()
                    at(F.stormwind, 0.5, 0.5)
                    DC:OnRouteShown(sourcedRoute("quest"))
                    removePin()
                    fireWired("USER_WAYPOINT_UPDATED")
                    t:assertEqual("quest", DC.follow and DC.follow.source, "the quest route is still followed")
                end)
            end)
        end)
    end)
end

T:run(prefix .. "QuickRoute's own step pin cleared on arrival keeps the quest route", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.waypointPriority = nil
        withQuest({ mapID = F.ironforge, x = 0.3, y = 0.7 }, function()
            withWindowClosed(function(WI)
                at(F.stormwind, 0.5, 0.5)
                -- The step pin SetTomTomWaypoint's native fallback leaves.
                placePin(F.stormwind, 0.6, 0.6)
                WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = true, F.stormwind, 0.6, 0.6
                local _, source = WI:GetActiveWaypoint()
                t:assertEqual("quest", source, "the own pin is not the active waypoint")
                DC:OnRouteShown(sourcedRoute(source))
                at(F.stormwind, 0.6, 0.6)
                removePin()
                local ok, err = pcall(fireWired, "USER_WAYPOINT_UPDATED")
                WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = nil, nil, nil, nil
                t:assertTrue(ok, "ran: " .. tostring(err))
                t:assertEqual("quest", DC.follow and DC.follow.source, "the quest route is still followed")
            end)
        end)
    end)
end)

T:run(prefix .. "a new pin in the player's zone with the window closed ends the old trip", function(t)
    withCollection(true, function()
        QR.db.autoDestination = true
        QR.db.waypointPriority = "mappin"
        withWindowClosed(function(_, calls)
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("mappin"))
            placePin(F.stormwind, 0.7, 0.7)
            fireWired("USER_WAYPOINT_UPDATED")
            t:assertEqual(0, calls.show + calls.refresh, "same zone, window closed: the panel is not reached")
            t:assertNil(DC.follow, "the old trip ends")
        end)
    end)
end)

T:run(prefix .. "the same destination reported again keeps the trip", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.waypointPriority = "mappin"
        withWindowClosed(function(WI)
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("mappin"))
            placePin(F.ironforge, 0.3, 0.7)
            WI:OnWaypointChanged("TomTom:Waypoint")
            t:assertNotNil(DC.follow, "kept: the waypoint still leads to the same place")
        end)
    end)
end)

-- A locked destination (map click, multi-stop leg; "locked" once the window
-- routes to it again) stays only while the lock does. The real events unlock
-- it first; then the new waypoint, or none, decides.
for _, source in ipairs({ "locked", "map_click" }) do
    T:run(prefix .. "a " .. source .. " route ends once a pin or quest change unlocks it", function(t)
        for _, case in ipairs({ "pin placed", "super-tracking", "pin removed" }) do
            withCollection(true, function()
                QR.db.autoDestination = false
                QR.db.waypointPriority = "mappin"
                QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
                withQuest({ mapID = F.stormwind, x = 0.7, y = 0.7 }, function()
                    withWindowClosed(function()
                        at(F.stormwind, 0.5, 0.5)
                        QR.db.destinationLocked = true
                        DC:OnRouteShown(sourcedRoute(source))
                        if case == "pin placed" then
                            placePin(F.stormwind, 0.7, 0.7)
                            fireWired("USER_WAYPOINT_UPDATED")
                        elseif case == "super-tracking" then
                            fireWired("SUPER_TRACKING_CHANGED")
                        else
                            removePin()
                            fireWired("USER_WAYPOINT_UPDATED")
                        end
                        t:assertFalse(QR.db.destinationLocked, case .. ": the event unlocked it")
                        t:assertNil(DC.follow, source .. ", " .. case .. ": ended once unlocked")
                    end)
                end)
            end)
        end
    end)

    T:run(prefix .. "a " .. source .. " route is kept while it stays locked", function(t)
        withCollection(true, function()
            QR.db.autoDestination = false
            QR.db.waypointPriority = "mappin"
            QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
            withWindowClosed(function(WI)
                at(F.stormwind, 0.5, 0.5)
                QR.db.destinationLocked = true
                DC:OnRouteShown(sourcedRoute(source))
                placePin(F.stormwind, 0.7, 0.7)
                WI:OnWaypointChanged("TomTom:Waypoint")   -- a change that does not unlock
                t:assertNotNil(DC.follow, source .. ": kept while locked")
                DC:SampleRoute()
                t:assertNotNil(DC.follow, source .. ": and through a sample")
            end)
        end)
    end)
end

-- After the pin is removed with nothing else to route to, the panel falls
-- back to lastDestination: the same destination, so the trip goes on.
T:run(prefix .. "a locked route whose pin goes, with nothing else tracked, goes on under its own source", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
        withWindowClosed(function()
            at(F.stormwind, 0.5, 0.5)
            QR.db.destinationLocked = true
            DC:OnRouteShown(sourcedRoute("map_click"))
            removePin()
            fireWired("USER_WAYPOINT_UPDATED")
            t:assertFalse(QR.db.destinationLocked, "unlocked by the event")
            t:assertEqual("map_click", DC.follow and DC.follow.source, "followed on, still as map_click")
            t:assertTrue(DC.follow and DC.follow.fallback, "marked as the panel's fallback")
            arrive()
            local trip = list("stepTimes")[#list("stepTimes")]
            t:assertEqual("route", trip and trip.kind, "and the trip is recorded")
            t:assertEqual("map_click", trip and trip.source, "with its own source")
            t:assertTrue(trip and trip.fallback, "and the fallback mark")
        end)
    end)
end)

T:run(prefix .. "a cleared quest with nothing else tracked follows the panel's fallback", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
        withWindowClosed(function()
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("quest"))
            fireWired("SUPER_TRACKING_CHANGED")   -- nothing super-tracked, no pin
            t:assertEqual("quest", DC.follow and DC.follow.source,
                "the panel falls back to the same destination; got " .. tostring(DC.follow and DC.follow.source))
            t:assertTrue(DC.follow and DC.follow.fallback, "marked as the fallback")
        end)
    end)
end)

-- Review round 5: a fallback is not an exemption. The next event is judged
-- as the panel's next refresh would judge it.
for _, start in ipairs({ "quest turned in", "own step pin cleared on arrival" }) do
    for _, source in ipairs({ "map_click", "locked" }) do
        T:run(prefix .. "a " .. source .. " route after its fallback (" .. start .. ") ends on the next quest", function(t)
            withCollection(true, function()
                QR.db.autoDestination = false
                QR.db.waypointPriority = nil
                QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
                withWindowClosed(function(WI)
                    at(F.stormwind, 0.5, 0.5)
                    QR.db.destinationLocked = true
                    DC:OnRouteShown(sourcedRoute(source))
                    if start == "quest turned in" then
                        fireWired("SUPER_TRACKING_CHANGED")   -- nothing tracked any more
                    else
                        placePin(F.stormwind, 0.6, 0.6)
                        WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = true, F.stormwind, 0.6, 0.6
                        removePin()
                        local ok, err = pcall(fireWired, "USER_WAYPOINT_UPDATED")
                        WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = nil, nil, nil, nil
                        t:assertTrue(ok, "ran: " .. tostring(err))
                    end
                    t:assertEqual(source, DC.follow and DC.follow.source, "after the fallback: kept as " .. source)
                    t:assertTrue(DC.follow and DC.follow.fallback, "marked as the fallback")
                    withQuest({ mapID = F.stormwind, x = 0.8, y = 0.2 }, function()
                        fireWired("SUPER_TRACKING_CHANGED")   -- the next quest accepted
                        local _, panelSource = WI:GetActiveWaypoint()
                        t:assertEqual("quest", panelSource, "the panel would route to the quest")
                        t:assertNil(DC.follow, "and the old destination is no longer followed")
                    end)
                end)
            end)
        end)
    end
end

-- A map click or a multi-stop leg chosen with the window closed saves and
-- locks another destination without any waypoint event.
T:run(prefix .. "a destination locked elsewhere ends the route at the next sample", function(t)
    withCollection(true, function()
        withWindowClosed(function()
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("quest"))
            DC:SampleRoute()
            t:assertNotNil(DC.follow, "followed")
            QR.db.lastDestination = { mapID = F.stormwind, x = 0.8, y = 0.2, title = "elsewhere" }
            QR.db.destinationLocked = true
            DC:SampleRoute()
            t:assertNil(DC.follow, "the panel now routes elsewhere: ended")
        end)
    end)
end)

-- RefreshRoute honours the lock only with a usable lastDestination.
T:run(prefix .. "a lock without a destination is no lock", function(t)
    withCollection(true, function()
        withWindowClosed(function()
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("quest"))
            QR.db.lastDestination = nil
            QR.db.destinationLocked = true
            DC:SampleRoute()
            t:assertNotNil(DC.follow, "nothing to route to instead: still followed")
        end)
    end)
end)

-- The clear that combat postponed is run again by ResumeDeferredWaypointWork,
-- without the event handler's unlock: a destination locked by then stays.
T:run(prefix .. "a postponed clear keeps a route that is locked again", function(t)
    withCollection(true, function()
        QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
        withQuest({ mapID = F.stormwind, x = 0.8, y = 0.2 }, function()
            withWindowClosed(function(WI)
                at(F.stormwind, 0.5, 0.5)
                QR.db.destinationLocked = true
                DC:OnRouteShown(sourcedRoute("map_click"))
                WI:OnWaypointCleared("combat-resume")
                t:assertEqual("map_click", DC.follow and DC.follow.source, "locked: still followed")
            end)
        end)
    end)
end)

-- Review round 6: a change and a clear in one fight. Combat defers both;
-- the clear must not replace the owed change, or the new quest is never
-- resolved after the fight.
T:run(prefix .. "a quest change and a pin clear in one fight end the old quest route", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.waypointPriority = nil
        withQuest({ mapID = F.ironforge, x = 0.3, y = 0.7 }, function()
            withWindowClosed(function(WI)
                at(F.stormwind, 0.5, 0.5)
                DC:OnRouteShown(sourcedRoute("quest"))
                MockWoW.config.inCombatLockdown = true
                local ok, err = pcall(function()
                    MockWoW.config.questWaypoints[4243] = { mapID = F.stormwind, x = 0.8, y = 0.2 }
                    MockWoW.config.superTrackedQuestID = 4243   -- the next quest
                    fireWired("SUPER_TRACKING_CHANGED")
                    removePin()
                    fireWired("USER_WAYPOINT_UPDATED")
                    t:assertEqual("changed", WI._waypointChangePending, "the change is still owed")
                end)
                MockWoW.config.inCombatLockdown = false
                t:assertTrue(ok, "ran: " .. tostring(err))
                t:assertNotNil(DC.follow, "in the fight nothing is resolved yet")
                WI:ResumeDeferredWaypointWork()   -- what leaving combat calls
                t:assertNil(DC.follow, "after the fight the new quest ends the old route")
            end)
        end)
    end)
end)

T:run(prefix .. "a pin clear alone in a fight is still resumed as a clear", function(t)
    withCollection(true, function()
        withWindowClosed(function(WI)
            WI._waypointChangePending = false
            MockWoW.config.inCombatLockdown = true
            removePin()
            local ok, err = pcall(fireWired, "USER_WAYPOINT_UPDATED")
            MockWoW.config.inCombatLockdown = false
            t:assertTrue(ok, "ran: " .. tostring(err))
            t:assertEqual("cleared", WI._waypointChangePending, "a clear is owed")
            WI._waypointChangePending = false
        end)
    end)
end)

-- The panel: with the window open, a change and a clear in one fight still
-- end in one refresh after it, and nothing is shown that was not.
T:run(prefix .. "the open panel after a change and a clear in one fight", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        withQuest({ mapID = F.stormwind, x = 0.8, y = 0.2 }, function()
            withWindowClosed(function(WI, calls)
                local savedTab = QR.MainFrame.activeTab
                QR.MainFrame.isShowing, QR.MainFrame.activeTab = true, "route"
                t:assertNotNil(QR.UI.frame, "the route panel exists")
                if QR.UI.frame then QR.UI.frame:Show() end   -- withWindowClosed hides it again afterwards
                MockWoW.config.inCombatLockdown = true
                local ok, err = pcall(function()
                    fireWired("SUPER_TRACKING_CHANGED")
                    removePin()
                    fireWired("USER_WAYPOINT_UPDATED")
                end)
                MockWoW.config.inCombatLockdown = false
                t:assertTrue(ok, "ran: " .. tostring(err))
                t:assertEqual(0, calls.refresh + calls.show, "nothing during the fight")
                WI:ResumeDeferredWaypointWork()
                t:assertEqual(1, calls.refresh, "one refresh after it, got " .. calls.refresh)
                t:assertEqual(0, calls.show, "and no window opened")
                QR.MainFrame.activeTab = savedTab
                if QR.UI.frame then QR.UI.frame:Hide() end
            end)
        end)
    end)
end)

T:run(prefix .. "a change while locked elsewhere ends the route", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.waypointPriority = "mappin"
        withWindowClosed(function(WI)
            at(F.stormwind, 0.5, 0.5)
            placePin(F.ironforge, 0.3, 0.7)
            DC:OnRouteShown(sourcedRoute("mappin"))
            QR.db.lastDestination = { mapID = F.stormwind, x = 0.8, y = 0.2, title = "elsewhere" }
            QR.db.destinationLocked = true
            WI:OnWaypointChanged("TomTom:Waypoint")   -- resolves to the same pin, but the panel is locked
            t:assertNil(DC.follow, "the panel routes to the locked destination: ended")
        end)
    end)
end)

-- RefreshRoute falls back only when C_Map.HasUserWaypoint is false, and that
-- counts QuickRoute's own step pin, which the active waypoint leaves out. With
-- that pin still on the map the panel clears its route instead.
T:run(prefix .. "QuickRoute's own pin on the map stops the saved fallback", function(t)
    withCollection(true, function()
        QR.db.autoDestination = false
        QR.db.lastDestination = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge" }
        withWindowClosed(function(WI)
            at(F.stormwind, 0.5, 0.5)
            DC:OnRouteShown(sourcedRoute("quest"))
            placePin(F.stormwind, 0.6, 0.6)
            WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = true, F.stormwind, 0.6, 0.6
            local ok, err = pcall(fireWired, "SUPER_TRACKING_CHANGED")
            WI._lastWpNative, WI._lastWpMapID, WI._lastWpX, WI._lastWpY = nil, nil, nil, nil
            t:assertTrue(ok, "ran: " .. tostring(err))
            t:assertNil(DC.follow, "a pin is on the map: no fallback, the route ends")
        end)
    end)
end)

for _, source in ipairs({ "saved", "dungeon_offer" }) do
    T:run(prefix .. "a " .. source .. " route is not ended by any waypoint event", function(t)
        withCollection(true, function()
            QR.db.autoDestination = false
            QR.db.waypointPriority = "mappin"
            withQuest({ mapID = F.stormwind, x = 0.7, y = 0.7 }, function()
                withWindowClosed(function()
                    at(F.stormwind, 0.5, 0.5)
                    DC:OnRouteShown(sourcedRoute(source))
                    placePin(F.stormwind, 0.7, 0.7)
                    fireWired("USER_WAYPOINT_UPDATED")
                    t:assertNotNil(DC.follow, source .. ": kept on a pin change")
                    fireWired("SUPER_TRACKING_CHANGED")
                    t:assertNotNil(DC.follow, source .. ": kept on a super-tracking change")
                    removePin()
                    fireWired("USER_WAYPOINT_UPDATED")
                    t:assertNotNil(DC.follow, source .. ": kept when the pin is removed")
                    -- A destination locked elsewhere is no waypoint signal either.
                    QR.db.lastDestination = { mapID = F.stormwind, x = 0.8, y = 0.2, title = "elsewhere" }
                    QR.db.destinationLocked = true
                    DC:SampleRoute()
                    t:assertNotNil(DC.follow, source .. ": kept when another destination is locked")
                end)
            end)
        end)
    end)
end

T:run(prefix .. "a route shown without steps ends the timing", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        DC:OnRouteShown({ waypoint = ironforgeRoute().waypoint, steps = {} })
        t:assertNil(DC.follow, "dropped")
        arrive()
        t:assertEqual(0, #list("stepTimes"), "nothing recorded")
    end)
end)

T:run(prefix .. "a trip far beyond its estimate is dropped, not recorded", function(t)
    withCollection(true, function()
        -- Estimate 100 s: the limit is 5 x 100 = 500 s.
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        MockWoW.config.baseTime = MockWoW.config.baseTime + 499
        arrive()
        t:assertEqual(3, #list("stepTimes"), "499 s is still recorded, got " .. #list("stepTimes"))
        QR.db.observations = nil
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        MockWoW.config.baseTime = MockWoW.config.baseTime + 501
        arrive()
        t:assertEqual(0, #list("stepTimes"), "501 s is abandoned, got " .. #list("stepTimes"))
        t:assertNil(DC.follow, "and no longer followed")
    end)
end)

-------------------------------------------------------------------------------
-- Review round 2
-------------------------------------------------------------------------------

T:run(prefix .. "a /reload with the switch on registers events and sampling again", function(t)
    withCollection(true, function()
        local frame = DC.frame
        t:assertNotNil(frame, "the frame exists")
        if not frame then return end
        frame:UnregisterAllEvents()
        frame:SetScript("OnUpdate", nil)
        DC:Initialize()
        for _, name in ipairs(DC.EVENTS) do
            t:assertTrue(frame:IsEventRegistered(name), "after Initialize " .. name .. " is registered")
        end
        t:assertNotNil(frame:GetScript("OnUpdate"), "and the sampling OnUpdate is set")
    end)
end)

local function routeWithEstimate(seconds)
    local route = ironforgeRoute()
    route.totalTime = seconds
    return route
end

T:run(prefix .. "a short trip gets at least 300 s", function(t)
    withCollection(true, function()
        -- Estimate 20 s: 5 x 20 = 100 s, raised to the 300 s floor.
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(routeWithEstimate(20))
        MockWoW.config.baseTime = MockWoW.config.baseTime + 299
        arrive()
        t:assertEqual(3, #list("stepTimes"), "299 s is still recorded, got " .. #list("stepTimes"))
    end)
end)

T:run(prefix .. "no trip is timed past 7200 s", function(t)
    withCollection(true, function()
        -- Estimate 2000 s: 5 x 2000 = 10000 s, capped at 7200 s.
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(routeWithEstimate(2000))
        MockWoW.config.baseTime = MockWoW.config.baseTime + 7201
        arrive()
        t:assertEqual(0, #list("stepTimes"), "7201 s is dropped, got " .. #list("stepTimes"))
        t:assertNil(DC.follow, "and no longer followed")
    end)
end)

T:run(prefix .. "an arrival just before the route is cleared is still recorded", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        at(F.ironforge, 0.3, 0.7)   -- arrived; no sample since
        local savedFrame = QR.UI.frame
        QR.UI.frame = nil
        QR.UI:ClearRoute()
        QR.UI.frame = savedFrame
        local trip = list("stepTimes")[#list("stepTimes")]
        t:assertEqual("route", trip and trip.kind, "the trip is recorded by the last sample")
        t:assertNil(DC.follow, "and the route is no longer followed")
    end)
end)

T:run(prefix .. "an arrival just before a new route is shown is still recorded", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        DC:OnRouteShown(ironforgeRoute())
        at(F.ironforge, 0.3, 0.7)   -- arrived; no sample since
        local nextRoute = ironforgeRoute()
        nextRoute.waypoint = { mapID = F.stormwind, x = 0.6, y = 0.6, title = "next" }
        nextRoute.steps = { { type = "portal", time = 10, fromMapID = F.ironforge, destMapID = F.stormwind } }
        DC:OnRouteShown(nextRoute)
        local trips = 0
        for _, e in ipairs(list("stepTimes")) do if e.kind == "route" then trips = trips + 1 end end
        t:assertEqual(1, trips, "the first trip is recorded, got " .. trips)
        t:assertEqual(F.stormwind, DC.follow and DC.follow.dest.mapID, "and the new route is followed")
    end)
end)

-------------------------------------------------------------------------------
-- Review round 7
-------------------------------------------------------------------------------

T:run(prefix .. "a synchronous calculation names its caller", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        PC:CalculatePath(F.stormwind, 0.6, 0.6)
        DC:CalculateTagged("quest-buttons", F.stormwind, 0.6, 0.6)
        DC:CalculateTagged("quest-buttons", 0, 0.5, 0.5)
        local times = list("calcTimes")
        t:assertEqual("direct", times[1] and times[1].consumer, "an untagged call is direct")
        t:assertEqual("quest-buttons", times[2] and times[2].consumer, "a tagged call names its caller")
        t:assertEqual("quest-buttons", list("noRoute")[1] and list("noRoute")[1].source,
            "and so does its failure")
        t:assertNil(DC.syncTag, "the tag is put back")
    end)
end)

T:run(prefix .. "a raising tagged calculation puts the tag back", function(t)
    withCollection(true, function()
        local saved = PC.CalculatePath
        PC.CalculatePath = function() error("search failed") end
        local ok = pcall(DC.CalculateTagged, DC, "service-router", F.stormwind, 0.6, 0.6)
        PC.CalculatePath = saved
        t:assertFalse(ok, "the error reaches the caller")
        t:assertNil(DC.syncTag, "and the tag is gone")
    end)
end)

T:run(prefix .. "the service router tags its candidates", function(t)
    withCollection(true, function()
        at(F.stormwind, 0.5, 0.5)
        QR.ServiceRouter:FindNearestLocation({ { mapID = F.stormwind, x = 0.6, y = 0.6 } })
        local e = list("calcTimes")[1]
        t:assertEqual("service-router", e and e.consumer, "got " .. tostring(e and e.consumer))
    end)
end)

-- A single | starts an escape in WoW's text (|c a colour); || prints one.
T:run(prefix .. "player-visible strings of the observations escape their pipes", function(t)
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
    local chunk = loadfile(scriptDir .. "../QuickRoute/Localization.lua")
    local savedLocale = MockWoW.config.locale
    for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }) do
        MockWoW.config.locale = locale
        pcall(chunk, "QuickRoute", QR)
        local text = QR.L["DATA_COLLECTION_COUNTS"]:gsub("||", "")
        t:assertNil(text:find("|", 1, true), locale .. " counts line has no single pipe: " .. QR.L["DATA_COLLECTION_COUNTS"])
    end
    MockWoW.config.locale = "enUS"
    pcall(chunk, "QuickRoute", QR)
    MockWoW.config.locale = savedLocale
    local source = io.open(scriptDir .. "../QuickRoute/QuickRoute.lua"):read("*a")
    local line = source:match('print%("  /qrdata[^\n]*')
    t:assertNotNil(line, "the help line exists")
    t:assertNil(line and line:gsub("||", ""):find("|", 1, true), "the /qrdata help line has no single pipe: " .. tostring(line))
end)
