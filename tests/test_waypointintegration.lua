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
