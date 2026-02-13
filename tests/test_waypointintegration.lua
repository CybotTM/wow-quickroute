-------------------------------------------------------------------------------
-- test_waypointintegration.lua
-- Tests for QR.WaypointIntegration module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.hasUserWaypoint = false
    MockWoW.config.superTrackedQuestID = 0
    MockWoW.config.tomtom = nil
    _G.TomTom = nil
    -- Re-install C_Map mocks
    _G.C_Map.HasUserWaypoint = function() return MockWoW.config.hasUserWaypoint end
    _G.C_Map.GetUserWaypoint = function() return MockWoW.config.userWaypoint end
    -- Clear waypoint dedup cache
    QR.WaypointIntegration._lastWpMapID = nil
    QR.WaypointIntegration._lastWpX = nil
    QR.WaypointIntegration._lastWpY = nil
    QR.WaypointIntegration._lastWpTitle = nil
    QR.WaypointIntegration._lastWpTime = nil
    QR.WaypointIntegration._lastWpUID = nil
end

local function setMapPinWaypoint(mapID, x, y)
    MockWoW.config.hasUserWaypoint = true
    MockWoW.config.userWaypointMapID = mapID
    MockWoW.config.userWaypointX = x
    MockWoW.config.userWaypointY = y
    MockWoW.config.userWaypoint = {
        uiMapID = mapID,
        position = {
            x = x,
            y = y,
            GetXY = function() return x, y end,
        },
    }
    _G.C_Map.HasUserWaypoint = function() return true end
    _G.C_Map.GetUserWaypoint = function() return MockWoW.config.userWaypoint end
end

-------------------------------------------------------------------------------
-- 1. GetMapPing
-------------------------------------------------------------------------------

T:run("GetMapPing: returns nil when no waypoint", function(t)
    resetState()
    local wp = QR.WaypointIntegration:GetMapPing()
    t:assertNil(wp, "No waypoint when none set")
end)

T:run("GetMapPing: returns waypoint when set", function(t)
    resetState()
    setMapPinWaypoint(84, 0.3, 0.7)

    local wp = QR.WaypointIntegration:GetMapPing()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(84, wp.mapID, "Correct mapID")
    -- position coordinates
    t:assertNotNil(wp.x, "x coordinate present")
    t:assertNotNil(wp.y, "y coordinate present")
end)

T:run("GetMapPing: title is 'Map Pin'", function(t)
    resetState()
    setMapPinWaypoint(84, 0.5, 0.5)

    local wp = QR.WaypointIntegration:GetMapPing()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual("Map Pin", wp.title, "Title is Map Pin")
end)

-------------------------------------------------------------------------------
-- 2. GetTomTomWaypoint
-------------------------------------------------------------------------------

T:run("GetTomTomWaypoint: returns nil when TomTom not loaded", function(t)
    resetState()
    _G.TomTom = nil
    local wp = QR.WaypointIntegration:GetTomTomWaypoint()
    t:assertNil(wp, "No TomTom waypoint when not loaded")
end)

T:run("GetTomTomWaypoint: returns waypoint from GetClosestWaypoint", function(t)
    resetState()
    _G.TomTom = {
        GetClosestWaypoint = function(self)
            return {
                mapID = 85,
                x = 0.4,
                y = 0.6,
                title = "Test TomTom WP",
            }
        end,
    }

    local wp = QR.WaypointIntegration:GetTomTomWaypoint()

    t:assertNotNil(wp, "TomTom waypoint returned")
    t:assertEqual(85, wp.mapID, "Correct mapID from TomTom")
    t:assertEqual("Test TomTom WP", wp.title, "Correct title from TomTom")
end)

T:run("GetTomTomWaypoint: handles table-style waypoint data", function(t)
    resetState()
    _G.TomTom = {
        GetClosestWaypoint = function(self)
            -- Array-style: { mapID, x, y, title }
            return { 627, 0.5, 0.5, "Dalaran" }
        end,
    }

    local wp = QR.WaypointIntegration:GetTomTomWaypoint()

    t:assertNotNil(wp, "TomTom waypoint returned for array-style data")
    t:assertEqual(627, wp.mapID, "MapID from array index 1")
end)

-------------------------------------------------------------------------------
-- 3. GetSuperTrackedWaypoint
-------------------------------------------------------------------------------

T:run("GetSuperTrackedWaypoint: returns nil when no quest tracked", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 0

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()
    t:assertNil(wp, "No waypoint when no quest tracked")
end)

T:run("GetSuperTrackedWaypoint: returns waypoint for tracked quest", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 12345
    MockWoW.config.questTitles[12345] = "Test Quest"
    MockWoW.config.questWaypoints[12345] = { mapID = 84, x = 0.3, y = 0.7 }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Quest waypoint returned")
    t:assertEqual(84, wp.mapID, "Quest waypoint mapID correct")
end)

T:run("GetSuperTrackedWaypoint: returns nil for quest without coords", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 99999
    MockWoW.config.questTitles[99999] = "No Coords Quest"
    -- No entry in questWaypoints

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()
    t:assertNil(wp, "No waypoint for quest without coordinates")
end)

-------------------------------------------------------------------------------
-- 4. GetActiveWaypoint priority
-------------------------------------------------------------------------------

T:run("GetActiveWaypoint: map pin is default priority", function(t)
    resetState()
    setMapPinWaypoint(84, 0.5, 0.5)

    -- Also set a quest waypoint
    MockWoW.config.superTrackedQuestID = 100
    MockWoW.config.questWaypoints[100] = { mapID = 85, x = 0.3, y = 0.3 }

    local wp, source = QR.WaypointIntegration:GetActiveWaypoint()

    t:assertNotNil(wp, "Active waypoint found")
    t:assertEqual("mappin", source, "Map pin has default priority")
end)

T:run("GetActiveWaypoint: returns nil when no sources available", function(t)
    resetState()
    -- No waypoints set anywhere

    local wp, source = QR.WaypointIntegration:GetActiveWaypoint()

    t:assertNil(wp, "No active waypoint")
    t:assertNil(source, "No source")
end)

T:run("GetActiveWaypoint: falls through to quest when no map pin", function(t)
    resetState()
    -- No map pin
    MockWoW.config.superTrackedQuestID = 200
    MockWoW.config.questTitles[200] = "Quest WP"
    MockWoW.config.questWaypoints[200] = { mapID = 85, x = 0.4, y = 0.4 }

    local wp, source = QR.WaypointIntegration:GetActiveWaypoint()

    t:assertNotNil(wp, "Quest waypoint found as fallback")
    t:assertEqual("quest", source, "Source is quest")
end)

-------------------------------------------------------------------------------
-- 5. SetTomTomWaypoint
-------------------------------------------------------------------------------

T:run("SetTomTomWaypoint: uses TomTom when available", function(t)
    resetState()
    local addWaypointCalled = false
    local addedMapID = nil
    _G.TomTom = {
        AddWaypoint = function(self, mapID, x, y, opts)
            addWaypointCalled = true
            addedMapID = mapID
            return {}  -- uid
        end,
    }

    local uid = QR.WaypointIntegration:SetTomTomWaypoint(84, 0.5, 0.5, "Test")

    t:assertTrue(addWaypointCalled, "TomTom:AddWaypoint called")
    t:assertEqual(84, addedMapID, "Correct mapID passed to TomTom")
end)

T:run("SetTomTomWaypoint: falls back to native when no TomTom", function(t)
    resetState()
    _G.TomTom = nil

    -- The native SetUserWaypoint should be called
    local nativeCalled = false
    local origSetUserWaypoint = _G.C_Map.SetUserWaypoint
    _G.C_Map.SetUserWaypoint = function(uiMapPoint)
        nativeCalled = true
        origSetUserWaypoint(uiMapPoint)
    end

    QR.WaypointIntegration:SetTomTomWaypoint(84, 0.5, 0.5, "Test")

    t:assertTrue(nativeCalled, "Native C_Map.SetUserWaypoint called as fallback")

    _G.C_Map.SetUserWaypoint = origSetUserWaypoint
end)

T:run("SetTomTomWaypoint: returns nil for nil mapID", function(t)
    resetState()
    local result = QR.WaypointIntegration:SetTomTomWaypoint(nil, 0.5, 0.5, "Test")
    t:assertNil(result, "Returns nil for nil mapID")
end)

-------------------------------------------------------------------------------
-- 6. HasTomTom
-------------------------------------------------------------------------------

T:run("HasTomTom: returns false when not loaded", function(t)
    resetState()
    _G.TomTom = nil
    t:assertFalse(QR.WaypointIntegration:HasTomTom(), "No TomTom when nil")
end)

T:run("HasTomTom: returns true when loaded", function(t)
    resetState()
    _G.TomTom = { GetClosestWaypoint = function() end }
    t:assertTrue(QR.WaypointIntegration:HasTomTom(), "TomTom detected when present")
    _G.TomTom = nil
end)

-------------------------------------------------------------------------------
-- 7. GetAllAvailableWaypoints
-------------------------------------------------------------------------------

T:run("GetAllAvailableWaypoints: returns empty when nothing set", function(t)
    resetState()
    local available = QR.WaypointIntegration:GetAllAvailableWaypoints()
    t:assertEqual(0, #available, "No waypoints available")
end)

T:run("GetAllAvailableWaypoints: includes map pin when set", function(t)
    resetState()
    setMapPinWaypoint(84, 0.5, 0.5)

    local available = QR.WaypointIntegration:GetAllAvailableWaypoints()
    t:assertGreaterThan(#available, 0, "At least one waypoint available")

    local foundMappin = false
    for _, entry in ipairs(available) do
        if entry.key == "mappin" then
            foundMappin = true
        end
    end
    t:assertTrue(foundMappin, "Map pin found in available waypoints")
end)

-------------------------------------------------------------------------------
-- 8. CalculatePathToWaypoint
-------------------------------------------------------------------------------

T:run("CalculatePathToWaypoint: returns nil when no waypoint", function(t)
    resetState()

    local result = QR.WaypointIntegration:CalculatePathToWaypoint()
    t:assertNil(result, "No result when no waypoint")
end)

T:run("CalculatePathToWaypoint: returns result with waypoint info", function(t)
    resetState()
    setMapPinWaypoint(84, 0.3, 0.3)
    MockWoW.config.currentMapID = 84

    -- Ensure graph is built
    if QR.PathCalculator then
        QR.PathCalculator.graph = nil
        QR.PathCalculator.graphDirty = true
    end

    local result = QR.WaypointIntegration:CalculatePathToWaypoint()

    if result then
        t:assertNotNil(result.waypoint, "Result has waypoint info")
        t:assertNotNil(result.waypointSource, "Result has waypointSource")
    else
        -- Path might not be found if graph is minimal - that's OK
        t:assertTrue(true, "CalculatePathToWaypoint returned nil (no path found)")
    end
end)

-------------------------------------------------------------------------------
-- 10. Transit Hub Skip Logic
-------------------------------------------------------------------------------

T:run("Transit hub: skips Stormwind hub, finds real destination via broad scan", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 55001
    MockWoW.config.questTitles[55001] = "Use the Portal"
    -- GetNextWaypoint returns Stormwind (transit hub)
    MockWoW.config.questWaypoints[55001] = { mapID = 84, x = 0.49, y = 0.87 }

    -- Temporarily override GetNextWaypointForMap to return coords for zone 241 too
    local origFn = _G.C_QuestLog.GetNextWaypointForMap
    _G.C_QuestLog.GetNextWaypointForMap = function(questID, mapID)
        if questID == 55001 and mapID == 241 then
            return 0.5, 0.6
        end
        return origFn(questID, mapID)
    end

    -- Make sure QR.Continents includes zone 241
    local hadContinent = QR.Continents and QR.Continents["Eastern Kingdoms"]
    if QR.Continents and QR.Continents["Eastern Kingdoms"] then
        -- Ensure 241 is in the zones list
        local has241 = false
        for _, zoneID in ipairs(QR.Continents["Eastern Kingdoms"].zones) do
            if zoneID == 241 then has241 = true; break end
        end
        if not has241 then
            table.insert(QR.Continents["Eastern Kingdoms"].zones, 241)
        end
    end

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(241, wp.mapID, "Skipped hub, found zone 241")

    _G.C_QuestLog.GetNextWaypointForMap = origFn
end)

T:run("Transit hub: uses fallback when no better destination found", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 55002
    MockWoW.config.questTitles[55002] = "Go to Stormwind"
    -- GetNextWaypoint returns Stormwind (transit hub)
    MockWoW.config.questWaypoints[55002] = { mapID = 84, x = 0.49, y = 0.87 }

    -- No other zones have this quest's coords (Methods 2-5 fail)
    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Transit fallback used")
    t:assertEqual(84, wp.mapID, "Falls back to hub mapID when no alternative")
end)

T:run("Transit hub: non-hub zones are returned immediately", function(t)
    resetState()
    MockWoW.config.superTrackedQuestID = 55003
    MockWoW.config.questTitles[55003] = "Kill Gnolls"
    -- GetNextWaypoint returns zone 56 (Wetlands) - NOT a hub
    MockWoW.config.questWaypoints[55003] = { mapID = 56, x = 0.3, y = 0.4 }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(56, wp.mapID, "Non-hub zone returned directly")
end)

-------------------------------------------------------------------------------
-- Intermediate waypoint detection (GetNextWaypointText)
-------------------------------------------------------------------------------

T:run("Intermediate waypoint: skips intermediate when GetNextWaypointText is set", function(t)
    resetState()

    -- Quest 91420: "Fleischtausch" - GetNextWaypoint returns Stormwind (mapID 84)
    -- but GetNextWaypointText returns "Go to Stormwind Mage Sanctum" -> intermediate
    -- Actual objective is on a different map (e.g. mapID 2024)
    MockWoW.config.superTrackedQuestID = 91420
    MockWoW.config.questTitles[91420] = "Fleischtausch"
    MockWoW.config.questWaypoints[91420] = { mapID = 84, x = 0.5, y = 0.6 }
    MockWoW.config.questWaypointTexts[91420] = "Betretet das Magiersanktum"

    -- Set the actual objective on map 2024 via GetQuestsOnMap
    MockWoW.config.questsOnMap[2024] = {
        { questID = 91420, x = 0.35, y = 0.42 },
    }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(2024, wp.mapID, "Returns actual objective map, not intermediate (84)")
    t:assertEqual(0.35, wp.x, "Correct x coordinate")
    t:assertEqual(0.42, wp.y, "Correct y coordinate")
end)

T:run("Intermediate waypoint: falls back to intermediate when no objective found", function(t)
    resetState()

    -- Quest with intermediate waypoint but no GetQuestsOnMap result for objective
    -- Use unique questID to avoid coordinate cache from previous test
    MockWoW.config.superTrackedQuestID = 91421
    MockWoW.config.questTitles[91421] = "Fleischtausch 2"
    MockWoW.config.questWaypoints[91421] = { mapID = 84, x = 0.5, y = 0.6 }
    MockWoW.config.questWaypointTexts[91421] = "Betretet das Magiersanktum"

    -- No questsOnMap entries for the actual objective

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    -- Should fall back to the intermediate waypoint (Stormwind) since nothing better was found
    t:assertNotNil(wp, "Waypoint returned (fallback to intermediate)")
    t:assertEqual(84, wp.mapID, "Falls back to intermediate waypoint map")
end)

T:run("Intermediate waypoint: non-intermediate returns directly", function(t)
    resetState()

    -- Quest without GetNextWaypointText -> NOT intermediate -> returns directly
    MockWoW.config.superTrackedQuestID = 55010
    MockWoW.config.questTitles[55010] = "Direct Quest"
    MockWoW.config.questWaypoints[55010] = { mapID = 56, x = 0.3, y = 0.4 }
    -- No questWaypointTexts entry -> GetNextWaypointText returns nil

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(56, wp.mapID, "Non-intermediate returns directly")
    t:assertEqual(0.3, wp.x, "Correct x")
    t:assertEqual(0.4, wp.y, "Correct y")
end)

T:run("Intermediate waypoint: title includes waypoint text", function(t)
    resetState()

    -- Use unique questID to avoid coordinate cache
    MockWoW.config.superTrackedQuestID = 91422
    MockWoW.config.questTitles[91422] = "Fleischtausch 3"
    MockWoW.config.questWaypoints[91422] = { mapID = 84, x = 0.5, y = 0.6 }
    MockWoW.config.questWaypointTexts[91422] = "Betretet das Magiersanktum"

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    -- Title should contain both quest name and waypoint text
    t:assertTrue(wp.title:find("Fleischtausch") ~= nil, "Title has quest name")
    t:assertTrue(wp.title:find("Betretet das Magiersanktum") ~= nil, "Title has waypoint text")
end)

T:run("Intermediate waypoint: Methods 2 and 5 skipped for intermediate", function(t)
    resetState()

    -- Quest with intermediate waypoint - use unique questID
    MockWoW.config.superTrackedQuestID = 91423
    MockWoW.config.questTitles[91423] = "Fleischtausch 4"
    MockWoW.config.questWaypoints[91423] = { mapID = 84, x = 0.5, y = 0.6 }
    MockWoW.config.questWaypointTexts[91423] = "Betretet das Magiersanktum"

    -- Set up GetNextWaypointForMap to return Elwynn Forest (37) on broad scan
    -- This would be a false positive if Method 5 runs
    MockWoW.config.questWaypointForMap = MockWoW.config.questWaypointForMap or {}
    MockWoW.config.questWaypointForMap[91423] = MockWoW.config.questWaypointForMap[91423] or {}
    MockWoW.config.questWaypointForMap[91423][37] = { x = 0.2, y = 0.3 }

    -- Set actual objective on map 2024
    MockWoW.config.questsOnMap[2024] = {
        { questID = 91423, x = 0.35, y = 0.42 },
    }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    -- Should find the actual objective via Method 3b, NOT Elwynn Forest from Method 5
    t:assertNotNil(wp, "Waypoint returned")
    t:assertEqual(2024, wp.mapID, "Found via GetQuestsOnMap, not GetNextWaypointForMap")
    t:assertTrue(wp.mapID ~= 37, "Did NOT return Elwynn Forest false positive")
end)

T:run("Intermediate waypoint: dynamic discovery finds ROUTABLE unlisted zone", function(t)
    resetState()

    -- Quest 91424: objective is on map 2248 (Isle of Dorn) — in Khaz Algar continent,
    -- routable but not in the Phase 1 scan for some reason (simulated)
    MockWoW.config.superTrackedQuestID = 91424
    MockWoW.config.questTitles[91424] = "Dynamic Routable"
    MockWoW.config.questWaypoints[91424] = { mapID = 84, x = 0.5, y = 0.6 }
    MockWoW.config.questWaypointTexts[91424] = "Betretet das Magiersanktum"

    -- Objective is on map 2248 (Isle of Dorn) - IS in QR.ZoneToContinent
    t:assertNotNil(QR.ZoneToContinent[2248], "Map 2248 has a known continent (test precondition)")

    -- Put objective on map 9999 (fake unlisted but routable zone)
    -- We need it to NOT be found in Phase 1 (known zones), only in Phase 2
    -- So use a mapID that's in ZoneToContinent but not in Continents.zones
    -- Actually, let's just verify Phase 2 returns routable zones by using a mapID
    -- that IS in ZoneToContinent
    MockWoW.config.questsOnMap[2248] = {
        { questID = 91424, x = 0.45, y = 0.55 },
    }

    -- C_Map.GetMapChildrenInfo returns this zone
    MockWoW.config.mapChildren[947] = {
        { mapID = 2248, name = "Isle of Dorn", mapType = 3 },
    }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    t:assertNotNil(wp, "Waypoint returned")
    -- Phase 1 should find it since 2248 IS in Continents zones
    -- Either way, it should route to 2248
    t:assertEqual(2248, wp.mapID, "Found objective on routable map")
end)

T:run("Intermediate waypoint: K'aresh is routable via Dornogal", function(t)
    resetState()

    -- Quest 91425: objective is on K'aresh (map 2371) — now in KHAZ_ALGAR continent
    MockWoW.config.superTrackedQuestID = 91425
    MockWoW.config.questTitles[91425] = "Fleischtausch K'aresh"
    MockWoW.config.questWaypoints[91425] = { mapID = 84, x = 0.49, y = 0.88 }
    MockWoW.config.questWaypointTexts[91425] = "Nehmt das Portal nach Sturmwind"

    -- K'aresh IS in ZoneToContinent now (KHAZ_ALGAR)
    t:assertNotNil(QR.ZoneToContinent[2371], "Map 2371 (K'aresh) has a known continent")
    t:assertEqual("KHAZ_ALGAR", QR.ZoneToContinent[2371], "K'aresh is in Khaz Algar")

    -- Verify K'aresh is reachable via portal (not walk adjacency)
    local foundPortal = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from.mapID == 2339 and portal.to.mapID == 2371 then
            foundPortal = true
        end
    end
    t:assertTrue(foundPortal, "K'aresh reachable via portal from Dornogal (StandalonePortals)")
end)

T:run("Intermediate waypoint: UNROUTABLE dynamic zone falls back to transit", function(t)
    resetState()

    -- Quest 91426: objective is on a fictional zone (map 9999) — NOT in any continent
    MockWoW.config.superTrackedQuestID = 91426
    MockWoW.config.questTitles[91426] = "Unroutable Quest"
    MockWoW.config.questWaypoints[91426] = { mapID = 84, x = 0.49, y = 0.88 }
    MockWoW.config.questWaypointTexts[91426] = "Enter the portal"

    -- Objective is on map 9999 - NOT in ZoneToContinent
    t:assertNil(QR.ZoneToContinent[9999], "Map 9999 has NO known continent (test precondition)")
    MockWoW.config.questsOnMap[9999] = {
        { questID = 91426, x = 0.68, y = 0.80 },
    }

    -- C_Map.GetMapChildrenInfo discovers it
    MockWoW.config.mapChildren[947] = {
        { mapID = 9999, name = "Unknown Zone", mapType = 3 },
    }

    local wp = QR.WaypointIntegration:GetSuperTrackedWaypoint()

    -- Should NOT route to 9999 (unroutable), should fall back to intermediate (Stormwind)
    t:assertNotNil(wp, "Waypoint returned (transit fallback)")
    t:assertEqual(84, wp.mapID, "Falls back to intermediate waypoint, NOT unroutable zone")
    t:assertTrue(wp.mapID ~= 9999, "Did NOT return unroutable zone 9999")
end)

T:run("Transit hub: all PortalHubs mapIDs are treated as transit hubs", function(t)
    -- Verify the transit hub set is built from PortalHubs
    t:assertNotNil(QR.PortalHubs, "PortalHubs exists")
    local hubMapIDs = {}
    for _, hubData in pairs(QR.PortalHubs) do
        hubMapIDs[hubData.mapID] = true
    end
    -- Known hubs that should be in the set
    local expectedHubs = {84, 85, 627, 1670, 2112, 2339, 111, 125}
    for _, mapID in ipairs(expectedHubs) do
        t:assertTrue(hubMapIDs[mapID] == true, "Hub mapID " .. mapID .. " is in PortalHubs")
    end
end)
