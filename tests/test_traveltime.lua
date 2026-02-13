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
-- 2. EstimateDistanceTime
-------------------------------------------------------------------------------

T:run("EstimateDistanceTime: zero distance returns 0", function(t)
    local time = QR.TravelTime:EstimateDistanceTime(0, false)
    t:assertEqual(0, time, "Zero distance = 0 time")
end)

T:run("EstimateDistanceTime: flying is faster than ground", function(t)
    local groundTime = QR.TravelTime:EstimateDistanceTime(1.0, false)
    local flyTime = QR.TravelTime:EstimateDistanceTime(1.0, true)
    t:assertGreaterThan(groundTime, flyTime, "Ground time > fly time")
end)

T:run("EstimateDistanceTime: returns positive for positive distance", function(t)
    local time = QR.TravelTime:EstimateDistanceTime(0.5, false)
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
