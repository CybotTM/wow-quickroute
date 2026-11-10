-------------------------------------------------------------------------------
-- test_forever_data.lua
-- Runs only with QR_TEST_FLAVOR=forever: the addon loaded through
-- QuickRoute_Camelot.toc on a mock of the WoW Forever client.
--
-- Every map ID the Forever data names has to be one of Forever's own UiMap IDs
-- (the Classic set, Stormwind 1453). A retail ID (Stormwind 84) anywhere in it
-- means a record was copied rather than converted, and the route built from it
-- would point at a map the Forever client does not have.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local foreverMaps = MockWoW.foreverMapDatabase

-- Field names that hold a uiMapID, wherever they appear in the data.
local MAP_FIELDS = {
    mapID = true, zone = true, continentMapID = true,
    hub = true, hubHorde = true, hubAlliance = true,
}
-- Tables keyed by uiMapID.
local MAP_KEYED = {
    FlightPoints = true, ZoneAdjacencies = true, StaticDungeonEntrances = true,
    ZoneToContinent = true,
}
-- Every data table the retail Data\ files define and Data\Forever\ replaces.
local DATA_TABLES = {
    "TeleportTypes", "TeleportItemsData", "ClassTeleportSpells", "RacialTeleportSpells",
    "GeneralTeleportSpells", "MageTeleports", "DungeonTeleportSpells", "TeleportDestinationData",
    "CAPITAL_CITIES", "PortalHubs", "StandalonePortals",
    "TravelTransitions", "TravelPhaseGroups", "TravelHolidayIcons",
    "Continents", "ZoneToContinent", "ContinentNameMapIDs", "ZoneAdjacencies", "CrossContinentTravel",
    "StaticDungeonEntrances", "FlightPoints", "ServicePOIs", "ServiceTypes",
    "HearthstoneLocations", "DestinationCatalog",
}

--- Collect every uiMapID the table names, with a path for the message.
local function collectMapIDs(value, path, out, keyedByMap)
    if type(value) ~= "table" then return end
    for key, item in pairs(value) do
        local here = path .. "." .. tostring(key)
        if keyedByMap and type(key) == "number" then
            out[#out + 1] = { id = key, path = here }
        end
        if MAP_FIELDS[key] and type(item) == "number" then
            out[#out + 1] = { id = item, path = here }
        elseif key == "zones" and type(item) == "table" then
            for i, id in ipairs(item) do out[#out + 1] = { id = id, path = here .. "." .. i } end
        else
            collectMapIDs(item, here, out, false)
        end
    end
end

T:run("Forever: the runner loaded QuickRoute_Camelot.toc on a Forever client", function(t)
    local loader = package.loaded["addon_loader"]
    t:assertEqual("QuickRoute_Camelot.toc", loader and loader.toc, "TOC the suite loaded")
    t:assertTrue(QR.IsForever, "QR.IsForever on a client whose WOW_PROJECT_ID is WOW_PROJECT_CAMELOT")
    t:assertEqual(0, #(loader and loader.failedFiles or {}), "files that failed to load")
end)

T:run("Forever: no retail location data file is loaded", function(t)
    local loader = package.loaded["addon_loader"]
    local shared = { ["Data/Provenance.lua"] = true, ["Data/DataAccess.lua"] = true }
    local stray = {}
    for _, file in ipairs(loader and loader.files or {}) do
        if file:match("^Data/") and not file:match("^Data/Forever/") and not shared[file] then
            stray[#stray + 1] = file
        end
    end
    t:assertEqual(0, #stray, "retail Data files in the Forever load (" .. table.concat(stray, ", ") .. ")")
end)

T:run("Forever: every data table the retail files define is defined", function(t)
    for _, name in ipairs(DATA_TABLES) do
        t:assertEqual("table", type(QR[name]), "QR." .. name .. " type")
    end
end)

T:run("Forever: every map ID in the Forever data is a Forever UiMap ID", function(t)
    local ids = {}
    for _, name in ipairs(DATA_TABLES) do
        collectMapIDs(QR[name], name, ids, MAP_KEYED[name])
    end
    t:assertGreaterThan(#ids, 200, "map references found in the Forever data")
    local bad = {}
    for _, ref in ipairs(ids) do
        if not foreverMaps[ref.id] then bad[#bad + 1] = ref.path .. "=" .. tostring(ref.id) end
    end
    t:assertEqual(0, #bad, "map IDs that are not Forever UiMap IDs (" .. table.concat(bad, ", ", 1, math.min(#bad, 10)) .. ")")
end)

T:run("Forever: flight points are Forever's own taxi nodes", function(t)
    local stormwind = QR.FlightPoints[1453]
    t:assertNotNil(stormwind, "Stormwind City (1453) has a flight master")
    t:assertEqual("Stormwind, Elwynn", stormwind and stormwind.node, "Stormwind flight master node")
    t:assertNil(QR.FlightPoints[84], "no entry under the retail Stormwind ID 84")
    local zones = 0
    for _ in pairs(QR.FlightPoints) do zones = zones + 1 end
    t:assertGreaterThan(zones, 30, "zones with a Forever flight master")
end)

T:run("Forever: converted points are marked estimated", function(t)
    for name, city in pairs(QR.CAPITAL_CITIES) do
        t:assertEqual(QR.Provenance.ESTIMATED, city.provenance, "capital " .. name .. " provenance")
    end
    for service, points in pairs(QR.ServicePOIs) do
        for i, point in ipairs(points) do
            t:assertEqual(QR.Provenance.ESTIMATED, point.provenance, service .. " " .. i .. " provenance")
        end
    end
end)

T:run("Forever: the quest and NPC catalogue is empty", function(t)
    local catalog = QR.DestinationCatalog
    t:assertEqual(0, #catalog.quests, "quests")
    t:assertEqual(0, #catalog.npcs, "npcs")
    t:assertEqual(0, #catalog.vendors, "vendors")
end)

T:run("Forever: continents are Forever's", function(t)
    t:assertEqual(1415, QR.Continents.EASTERN_KINGDOMS.continentMapID, "Eastern Kingdoms continent map")
    t:assertEqual(1414, QR.Continents.KALIMDOR.continentMapID, "Kalimdor continent map")
    t:assertEqual("EASTERN_KINGDOMS", QR.GetContinentForZone(1453), "continent of Stormwind City 1453")
    t:assertEqual("KALIMDOR", QR.GetContinentForZone(1454), "continent of Orgrimmar 1454")
    t:assertNil(QR.GetContinentForZone(84), "retail Stormwind 84 has no continent on Forever")
end)

T:run("Forever: the phase window is not loaded and the route tab has no phase button", function(t)
    t:assertNil(QR.PhasePanel, "QR.PhasePanel")
    if QR.UI and QR.MainFrame and QR.MainFrame.Show then
        QR.MainFrame:Show()
        local frame = QR.UI.frame
        t:assertNotNil(frame, "route tab content exists")
        t:assertNil(frame and frame.phaseButton, "phase button on the route tab")
        QR.MainFrame:Hide()
    end
end)
