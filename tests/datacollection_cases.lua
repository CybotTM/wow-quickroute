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
    },
    forever = {
        stormwind = 1453, ironforge = 1455, continent = 1415,
        -- The Dalaran portal to Stormwind the owner took on Forever
        -- (scripts/data/forever_observed_portals.json).
        unknownFrom = { mapID = 1416, x = 0.1209, y = 0.5641 },
        unknownTo = { mapID = 1453, x = 0.4987, y = 0.8667 },
        offPlan = 1454,
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
        unsaved = DC.unsavedCount,
        captures = ZS.unsavedCaptures,
        crossings = ZS.unsavedCrossings,
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
    DC.unsavedCount = saved.unsaved
    ZS.unsavedCaptures, ZS.unsavedCrossings = saved.captures, saved.crossings
    ZS:ForgetArrivalState()
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
    DC.pendingCast, DC.follow = nil, nil
    DC.unsavedCount = 0
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

local function ironforgeRoute()
    return {
        waypoint = { mapID = F.ironforge, x = 0.3, y = 0.7, title = "Ironforge", source = "test" },
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
