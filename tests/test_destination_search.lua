-------------------------------------------------------------------------------
-- test_destination_search.lua
-- Tests for unified destination search
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
end

-------------------------------------------------------------------------------
-- 1. Data Availability
-------------------------------------------------------------------------------

T:run("DestSearch: CAPITAL_CITIES exposed on QR", function(t)
    t:assertNotNil(QR.CAPITAL_CITIES, "QR.CAPITAL_CITIES exists")
    t:assertEqual("table", type(QR.CAPITAL_CITIES))
end)

T:run("DestSearch: CAPITAL_CITIES has expected cities", function(t)
    local cities = QR.CAPITAL_CITIES
    t:assertNotNil(cities["Stormwind City"], "Stormwind")
    t:assertNotNil(cities["Orgrimmar"], "Orgrimmar")
    t:assertNotNil(cities["Valdrakken"], "Valdrakken")
end)

T:run("DestSearch: each city has mapID, x, y, faction", function(t)
    for name, data in pairs(QR.CAPITAL_CITIES) do
        t:assertNotNil(data.mapID, name .. " has mapID")
        t:assertNotNil(data.x, name .. " has x")
        t:assertNotNil(data.y, name .. " has y")
        t:assertNotNil(data.faction, name .. " has faction")
    end
end)

T:run("DestSearch: localization keys exist for search", function(t)
    local L = QR.L
    t:assertNotNil(L["DEST_SEARCH_PLACEHOLDER"], "placeholder key")
    t:assertNotNil(L["DEST_SEARCH_ACTIVE_WAYPOINT"], "active waypoint header")
    t:assertNotNil(L["DEST_SEARCH_CITIES"], "cities header")
    t:assertNotNil(L["DEST_SEARCH_DUNGEONS"], "dungeons header")
    t:assertNotNil(L["DEST_SEARCH_NO_RESULTS"], "no results key")
    t:assertNotNil(L["DEST_SEARCH_ROUTE_TO_TT"], "route tooltip key")
end)

-------------------------------------------------------------------------------
-- 2. Module Structure
-------------------------------------------------------------------------------

T:run("DestSearch: module exists", function(t)
    t:assertNotNil(QR.DestinationSearch, "QR.DestinationSearch exists")
end)

T:run("DestSearch: has expected methods", function(t)
    local DS = QR.DestinationSearch
    t:assertNotNil(DS.CollectResults, "CollectResults exists")
    t:assertNotNil(DS.Initialize, "Initialize exists")
    t:assertNotNil(DS.HideDropdown, "HideDropdown exists")
    t:assertNotNil(DS.RegisterCombat, "RegisterCombat exists")
end)

-------------------------------------------------------------------------------
-- 3. Data Collection
-------------------------------------------------------------------------------

T:run("DestSearch: CollectResults returns grouped data", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")
    t:assertNotNil(results, "results not nil")
    t:assertNotNil(results.waypoints, "waypoints group")
    t:assertNotNil(results.cities, "cities group")
    t:assertNotNil(results.dungeons, "dungeons group")
end)

T:run("DestSearch: cities filtered by Alliance faction", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    local hasStormwind, hasOrgrimmar, hasValdrakken = false, false, false
    for _, city in ipairs(results.cities) do
        if city.name == "Stormwind City" then hasStormwind = true end
        if city.name == "Orgrimmar" then hasOrgrimmar = true end
        if city.name == "Valdrakken" then hasValdrakken = true end
    end
    t:assertTrue(hasStormwind, "Alliance sees Stormwind")
    t:assertFalse(hasOrgrimmar, "Alliance doesn't see Orgrimmar")
    t:assertTrue(hasValdrakken, "Alliance sees neutral Valdrakken")
end)

T:run("DestSearch: cities filtered by Horde faction", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    local hasStormwind, hasOrgrimmar = false, false
    for _, city in ipairs(results.cities) do
        if city.name == "Stormwind City" then hasStormwind = true end
        if city.name == "Orgrimmar" then hasOrgrimmar = true end
    end
    t:assertFalse(hasStormwind, "Horde doesn't see Stormwind")
    t:assertTrue(hasOrgrimmar, "Horde sees Orgrimmar")
end)

T:run("DestSearch: search filters cities by name", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local all = DS:CollectResults("")
    local filtered = DS:CollectResults("storm")

    t:assertTrue(#filtered.cities > 0, "At least one city matches 'storm'")
    t:assertTrue(#filtered.cities < #all.cities, "Fewer than all cities match 'storm'")
end)

T:run("DestSearch: empty search returns all faction cities", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    -- 5 Alliance + 6 neutral (Dalaran x2, Shattrath, Oribos, Valdrakken, Dornogal) = 11
    t:assertTrue(#results.cities >= 10, "At least 10 cities for Alliance: got " .. #results.cities)
end)

T:run("DestSearch: cities sorted alphabetically", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    for i = 2, #results.cities do
        t:assertTrue(results.cities[i-1].name <= results.cities[i].name,
            "Cities sorted: " .. results.cities[i-1].name .. " <= " .. results.cities[i].name)
    end
end)

T:run("DestSearch: dungeons grouped by tier", function(t)
    resetState()
    -- Initialize DungeonData
    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    -- Should have dungeon tiers if DungeonData is scanned
    if QR.DungeonData and QR.DungeonData.scanned then
        t:assertTrue(#results.dungeons > 0, "Has dungeon tiers")
        for _, tier in ipairs(results.dungeons) do
            t:assertNotNil(tier.tierName, "Tier has name")
            t:assertNotNil(tier.instances, "Tier has instances")
        end
    end
end)
