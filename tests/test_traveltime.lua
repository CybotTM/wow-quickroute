-------------------------------------------------------------------------------
-- test_traveltime.lua
-- Tests for QR.TravelTime module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
end

-------------------------------------------------------------------------------
-- 1. CalculateDistance
-------------------------------------------------------------------------------

T:run("CalculateDistance: same point returns 0", function(t)
    local d = QR.TravelTime:CalculateDistance(0.5, 0.5, 0.5, 0.5)
    t:assertEqual(0, d, "Distance between same point is 0")
end)

T:run("CalculateDistance: unit distance along X", function(t)
    local d = QR.TravelTime:CalculateDistance(0, 0, 1, 0)
    t:assertEqual(1, d, "Distance along X axis is 1")
end)

T:run("CalculateDistance: unit distance along Y", function(t)
    local d = QR.TravelTime:CalculateDistance(0, 0, 0, 1)
    t:assertEqual(1, d, "Distance along Y axis is 1")
end)

T:run("CalculateDistance: diagonal distance", function(t)
    local d = QR.TravelTime:CalculateDistance(0, 0, 1, 1)
    -- sqrt(2) ~= 1.4142
    t:assertGreaterThan(d, 1.4, "Diagonal > 1.4")
    local withinRange = d < 1.5
    t:assertTrue(withinRange, "Diagonal < 1.5")
end)

T:run("CalculateDistance: fractional coordinates", function(t)
    local d = QR.TravelTime:CalculateDistance(0.1, 0.2, 0.4, 0.6)
    t:assertGreaterThan(d, 0, "Distance > 0 for different points")
end)

-------------------------------------------------------------------------------
-- 2. YardsToTime
-------------------------------------------------------------------------------

-- These covered EstimateDistanceTime, which lost its last production caller
-- when EstimateWalkingTime was rewritten to scale each axis separately. They
-- now exercise YardsToTime, the shared step both remaining callers go through.

T:run("YardsToTime: zero distance returns 0", function(t)
    local time = QR.TravelTime:YardsToTime(0, false)
    t:assertEqual(0, time, "Zero distance = 0 time")
end)

T:run("YardsToTime: flying is faster than ground", function(t)
    local groundTime = QR.TravelTime:YardsToTime(1000, false)
    local flyTime = QR.TravelTime:YardsToTime(1000, true)
    t:assertGreaterThan(groundTime, flyTime, "Ground time > fly time")
end)

T:run("YardsToTime: returns positive for positive distance", function(t)
    local time = QR.TravelTime:YardsToTime(500, false)
    t:assertGreaterThan(time, 0, "Positive distance gives positive time")
end)

-------------------------------------------------------------------------------
-- 3. EstimateWalkingTime
-------------------------------------------------------------------------------

T:run("EstimateWalkingTime: same point returns 0", function(t)
    local time = QR.TravelTime:EstimateWalkingTime(0.5, 0.5, 0.5, 0.5, false)
    t:assertEqual(0, time, "Walking time for same point is 0")
end)

T:run("EstimateWalkingTime: positive for different points", function(t)
    local time = QR.TravelTime:EstimateWalkingTime(0, 0, 1, 0, false)
    t:assertGreaterThan(time, 0, "Walking time > 0 for different points")
end)

T:run("EstimateWalkingTime: flying is faster", function(t)
    local walkTime = QR.TravelTime:EstimateWalkingTime(0, 0, 1, 0, false)
    local flyTime = QR.TravelTime:EstimateWalkingTime(0, 0, 1, 0, true)
    t:assertGreaterThan(walkTime, flyTime, "Flying is faster than walking")
end)

-------------------------------------------------------------------------------
-- 4. GetTeleportTime
-------------------------------------------------------------------------------

T:run("GetTeleportTime: nil data returns 0", function(t)
    local time = QR.TravelTime:GetTeleportTime(nil)
    t:assertEqual(0, time, "Nil data returns 0")
end)

T:run("GetTeleportTime: hearthstone includes cast time", function(t)
    local data = { type = QR.TeleportTypes.HEARTHSTONE }
    local time = QR.TravelTime:GetTeleportTime(data)
    -- hearthstone: 10s cast + 8s load = 18s
    local expected = QR.TravelTime.CAST_TIMES.hearthstone + QR.TravelTime.LOADING_TIMES.hearthstone
    t:assertEqual(expected, time, "Hearthstone time = cast + load")
end)

T:run("GetTeleportTime: mage teleport is fast", function(t)
    local data = { type = QR.TeleportTypes.SPELL, class = "MAGE" }
    local time = QR.TravelTime:GetTeleportTime(data)
    -- Mage teleport: 0 cast + 3 load = 3
    local expected = QR.TravelTime.CAST_TIMES.teleport + QR.TravelTime.LOADING_TIMES.teleport
    t:assertEqual(expected, time, "Mage teleport time correct")
end)

T:run("GetTeleportTime: toy includes loading time", function(t)
    local data = { type = QR.TeleportTypes.TOY }
    local time = QR.TravelTime:GetTeleportTime(data)
    t:assertGreaterThan(time, 0, "Toy has non-zero teleport time")
end)

T:run("GetTeleportTime: item includes loading time", function(t)
    local data = { type = QR.TeleportTypes.ITEM }
    local time = QR.TravelTime:GetTeleportTime(data)
    t:assertGreaterThan(time, 0, "Item has non-zero teleport time")
end)

-------------------------------------------------------------------------------
-- 5. GetPortalTime
-------------------------------------------------------------------------------

T:run("GetPortalTime: returns portal loading time", function(t)
    local time = QR.TravelTime:GetPortalTime()
    t:assertEqual(QR.TravelTime.LOADING_TIMES.portal, time, "Portal time matches constant")
end)

-------------------------------------------------------------------------------
-- 6. GetTransportTime
-------------------------------------------------------------------------------

T:run("GetTransportTime: boat returns boat time", function(t)
    local time = QR.TravelTime:GetTransportTime("boat")
    t:assertEqual(QR.TravelTime.LOADING_TIMES.boat, time, "Boat time correct")
end)

T:run("GetTransportTime: tram returns tram time", function(t)
    local time = QR.TravelTime:GetTransportTime("tram")
    t:assertEqual(QR.TravelTime.LOADING_TIMES.tram, time, "Tram time correct")
end)

T:run("GetTransportTime: zeppelin returns zeppelin time", function(t)
    local time = QR.TravelTime:GetTransportTime("zeppelin")
    t:assertEqual(QR.TravelTime.LOADING_TIMES.zeppelin, time, "Zeppelin time correct")
end)

T:run("GetTransportTime: unknown type falls back to portal", function(t)
    local time = QR.TravelTime:GetTransportTime("unknown")
    t:assertEqual(QR.TravelTime.LOADING_TIMES.portal, time, "Unknown falls back to portal time")
end)

-------------------------------------------------------------------------------
-- 7. GetEffectiveTime
-------------------------------------------------------------------------------

T:run("GetEffectiveTime: without cooldown wait returns base time", function(t)
    resetState()
    local data = { type = QR.TeleportTypes.HEARTHSTONE }
    local baseTime = QR.TravelTime:GetTeleportTime(data)
    local effectiveTime = QR.TravelTime:GetEffectiveTime(6948, data, false)
    t:assertEqual(baseTime, effectiveTime, "Effective time = base time without cooldown wait")
end)

T:run("GetEffectiveTime: with cooldown wait adds remaining", function(t)
    resetState()
    -- Set up a cooldown on item 6948 with 20s remaining
    MockWoW.config.baseTime = 1000010
    MockWoW.config.itemCooldowns[6948] = { start = 1000000, duration = 30, enable = 1 }

    local data = { type = QR.TeleportTypes.HEARTHSTONE }
    local baseTime = QR.TravelTime:GetTeleportTime(data)
    local effectiveTime = QR.TravelTime:GetEffectiveTime(6948, data, true)
    t:assertGreaterThan(effectiveTime, baseTime, "Effective time > base time with cooldown")
end)

-------------------------------------------------------------------------------
-- 8. Constants sanity checks
-------------------------------------------------------------------------------

T:run("Speed constants: flying > ground > walking", function(t)
    t:assertGreaterThan(QR.TravelTime.SPEEDS.mounted_flying, QR.TravelTime.SPEEDS.mounted_ground,
        "Flying > ground speed")
    t:assertGreaterThan(QR.TravelTime.SPEEDS.epic_flying, QR.TravelTime.SPEEDS.mounted_flying,
        "Epic flying > regular flying")
end)

T:run("MAP_SCALE: is positive", function(t)
    t:assertGreaterThan(QR.TravelTime.MAP_SCALE, 0, "MAP_SCALE > 0")
end)

-------------------------------------------------------------------------------
-- Per-map scale
-------------------------------------------------------------------------------

-- Regression: every map used one hard-coded 1000-yard scale, so a walk across
-- a city and a walk across a continent-sized zone were priced the same per
-- coordinate unit. C_Map.GetMapWorldSize reports the real size.
T:run("GetMapScale: uses the map's real world size when the client reports one", function(t)
    MockWoW:Reset()
    QR.TravelTime:ClearMapScaleCache()
    MockWoW.config.mapWorldSizes[84] = 2400

    t:assertEqual(2400, QR.TravelTime:GetMapScale(84),
        "the reported world size wins over MAP_SCALE")
    t:assertEqual(QR.TravelTime.MAP_SCALE, QR.TravelTime:GetMapScale(9999),
        "an unknown map falls back to MAP_SCALE")
    t:assertEqual(QR.TravelTime.MAP_SCALE, QR.TravelTime:GetMapScale(nil),
        "no map at all falls back to MAP_SCALE")
end)

T:run("EstimateWalkingTime: a larger map costs more time for the same distance", function(t)
    MockWoW:Reset()
    QR.TravelTime:ClearMapScaleCache()
    MockWoW.config.mapWorldSizes[84] = 500     -- small city map
    MockWoW.config.mapWorldSizes[85] = 4000    -- large zone

    local small = QR.TravelTime:EstimateWalkingTime(0.0, 0.0, 0.5, 0.0, false, 84)
    local large = QR.TravelTime:EstimateWalkingTime(0.0, 0.0, 0.5, 0.0, false, 85)

    t:assertGreaterThan(large, small,
        "the same coordinate distance takes longer on the bigger map ("
            .. tostring(small) .. " vs " .. tostring(large) .. ")")
end)

T:run("EstimateWalkingTime: each axis is scaled by its own extent", function(t)
    MockWoW:Reset()
    QR.TravelTime:ClearMapScaleCache()
    -- A map three times wider than it is tall.
    MockWoW.config.mapWorldSizes[84] = { 3000, 1000 }

    local eastWest   = QR.TravelTime:EstimateWalkingTime(0.0, 0.5, 1.0, 0.5, false, 84)
    local northSouth = QR.TravelTime:EstimateWalkingTime(0.5, 0.0, 0.5, 1.0, false, 84)

    t:assertGreaterThan(eastWest, northSouth,
        "crossing the long axis takes longer than the short one ("
            .. tostring(eastWest) .. " vs " .. tostring(northSouth) .. ")")
end)

T:run("GetMapScale: a size the client does not report is not cached", function(t)
    MockWoW:Reset()
    QR.TravelTime:ClearMapScaleCache()

    local before = QR.TravelTime:GetMapScale(4242)
    t:assertEqual(QR.TravelTime.MAP_SCALE, before, "falls back while the client says nothing")

    MockWoW.config.mapWorldSizes[4242] = 2000
    local after = QR.TravelTime:GetMapScale(4242)
    t:assertEqual(2000, after,
        "and picks the real size up once it is available (got " .. tostring(after) .. ")")
end)

T:run("Flight constants are pinned to the values the data was calibrated for", function(t)
    -- Doubling either moved 107 graph edges with the whole suite green. They
    -- are estimates, and estimates get recalibrated -- but a recalibration is
    -- a deliberate data change, not something a refactor should do quietly.
    -- TravelTime.lua says how to redo it: time one flight between two points
    -- that are both in QR.FlightPoints and divide the world distance by the
    -- seconds. Change the number here in the same commit.
    t:assertEqual(30, QR.TravelTime.FLIGHT_SPEED,
        "FLIGHT_SPEED is 30 yards per second")
    t:assertEqual(20, QR.TravelTime.FLIGHT_OVERHEAD,
        "FLIGHT_OVERHEAD is 20 seconds for talking to the master and landing")
end)
