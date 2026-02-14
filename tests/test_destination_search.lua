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
