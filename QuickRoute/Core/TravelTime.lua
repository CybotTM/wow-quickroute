-- TravelTime.lua
-- Travel time constants and estimation calculations
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local math_sqrt = math.sqrt
local math_ceil = math.ceil

-------------------------------------------------------------------------------
-- TravelTime Module
-------------------------------------------------------------------------------
QR.TravelTime = {}

local TravelTime = QR.TravelTime

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Loading screen times for different travel types (in seconds)
TravelTime.LOADING_TIMES = {
    portal = 5,         -- Portal loading screen
    hearthstone = 8,    -- Hearthstone loading screen
    teleport = 3,       -- Mage teleport loading screen
    boat = 180,         -- Boat travel time (includes boarding wait)
    tram = 60,          -- Deeprun Tram travel time
    flight = 0,         -- Flight path (calculated separately)
    zeppelin = 90,      -- Zeppelin travel time
    walk = 0,           -- Walking (no loading)
}

-- Cast times for abilities (in seconds)
TravelTime.CAST_TIMES = {
    hearthstone = 10,   -- Hearthstone cast time
    portal = 10,        -- Portal cast time (for mage portals)
    teleport = 0,       -- Instant teleport spells
    item = 0,           -- Most items are instant
    toy = 0,            -- Most toys are instant
}

-- Travel speeds (yards per second)
TravelTime.SPEEDS = {
    walking = 7,        -- Base walking speed
    running = 7,        -- Running (same as walking without mount)
    mounted_ground = 14, -- 100% ground mount
    mounted_flying = 18, -- 280% flying mount (average)
    epic_flying = 21,   -- 310% flying mount
}

-- Flight master speed, yards per second.
--
-- An estimate, like every other constant in this file -- LOADING_TIMES.boat and
-- SPEEDS.mounted_flying are the same kind of number. What is NOT estimated is
-- the distance it divides: flight point positions come from the client's own
-- TaxiNodes table, so the geometry is exact and only the scalar is guessed.
--
-- To recalibrate: take a flight whose endpoints are both in QR.FlightPoints,
-- time it, and divide the world distance between them by the seconds.
TravelTime.FLIGHT_SPEED = 30

-- Time on the ground per flight: talking to the flight master, the takeoff and
-- landing animations. Charged once per flight edge rather than per hop.
TravelTime.FLIGHT_OVERHEAD = 20

-- Map scale factors (approximate yards per coordinate unit)
-- Most maps are roughly 1000 yards per 1.0 coordinate difference
TravelTime.MAP_SCALE = 1000

-------------------------------------------------------------------------------
-- Time Estimation Methods
-------------------------------------------------------------------------------

--- Yards per coordinate unit on a given map.
-- MAP_SCALE is one number for every map in the game, which is wrong by a wide
-- margin at both ends: a city and a continent-sized zone do not share a scale.
-- C_Map.GetMapWorldSize reports the real size and it is static per map, so the
-- lookup is cached. Falls back to MAP_SCALE when the API says nothing, which
-- is what every caller got before.
-- Only successful lookups are cached: a map the client had no size for may
-- answer later, and caching the fallback would pin the wrong number forever.
local mapScaleCache = {}
function TravelTime:GetMapScale(mapID)
    if not mapID then
        return self.MAP_SCALE, self.MAP_SCALE
    end
    local cached = mapScaleCache[mapID]
    if cached then
        return cached[1], cached[2]
    end
    if C_Map and C_Map.GetMapWorldSize then
        -- Two values: width and height, both in yards. Using width for both
        -- axes prices a north-south walk by the map's east-west extent, which
        -- on a map that is not square is wrong by its aspect ratio.
        local ok, width, height = pcall(C_Map.GetMapWorldSize, mapID)
        if ok and type(width) == "number" and width > 0 then
            if type(height) ~= "number" or height <= 0 then
                height = width
            end
            mapScaleCache[mapID] = { width, height }
            return width, height
        end
    end
    return self.MAP_SCALE, self.MAP_SCALE
end

--- Drop the cached scales (used by tests).
function TravelTime:ClearMapScaleCache()
    wipe(mapScaleCache)
end

--- Convert a distance in yards to travel time at the appropriate mount speed.
-- @param yards number Distance in yards
-- @param canFly boolean Whether the player can fly there
-- @return number Travel time in seconds, rounded up
function TravelTime:YardsToTime(yards, canFly)
    local speed = canFly and self.SPEEDS.mounted_flying or self.SPEEDS.mounted_ground
    return math_ceil(yards / speed)
end

--- Get teleport time based on teleport type
-- Includes cast time + loading time
-- @param teleportData table Teleport data from TeleportItemsData
-- @return number Total teleport time in seconds
function TravelTime:GetTeleportTime(teleportData)
    if not teleportData then
        return 0
    end

    local teleportType = teleportData.type
    local castTime = 0
    local loadTime = 0

    -- Determine cast time
    if teleportType == QR.TeleportTypes.HEARTHSTONE or teleportData.isBoundHearth then
        castTime = self.CAST_TIMES.hearthstone
        loadTime = self.LOADING_TIMES.hearthstone
    elseif teleportType == QR.TeleportTypes.SPELL then
        -- Mage teleports are instant, class spells may vary
        if teleportData.class == "MAGE" then
            castTime = self.CAST_TIMES.teleport
            loadTime = self.LOADING_TIMES.teleport
        else
            castTime = self.CAST_TIMES.teleport
            loadTime = self.LOADING_TIMES.portal
        end
    elseif teleportType == QR.TeleportTypes.TOY then
        castTime = self.CAST_TIMES.toy
        loadTime = self.LOADING_TIMES.portal
    elseif teleportType == QR.TeleportTypes.ITEM then
        castTime = self.CAST_TIMES.item
        loadTime = self.LOADING_TIMES.portal
    elseif teleportType == QR.TeleportTypes.ENGINEER then
        castTime = self.CAST_TIMES.item
        loadTime = self.LOADING_TIMES.portal
    else
        -- Default fallback
        loadTime = self.LOADING_TIMES.portal
    end

    return castTime + loadTime
end

--- Get portal travel time (loading time only)
-- @return number Portal loading time in seconds
function TravelTime:GetPortalTime()
    return self.LOADING_TIMES.portal
end

--- Get transport travel time based on type
-- @param transportType string "boat", "tram", "zeppelin", or "portal"
-- @return number Travel time in seconds
function TravelTime:GetTransportTime(transportType)
    return self.LOADING_TIMES[transportType] or self.LOADING_TIMES.portal
end

--- Get effective total travel time for a teleport
-- Includes base teleport time plus optional cooldown wait
-- @param teleportID number The item/spell ID
-- @param teleportData table Teleport data from TeleportItemsData
-- @param includeCooldownWait boolean Whether to add cooldown wait time
-- @return number Total effective time in seconds
function TravelTime:GetEffectiveTime(teleportID, teleportData, includeCooldownWait, actualSourceType)
    local baseTime = self:GetTeleportTime(teleportData)

    if not includeCooldownWait then
        return baseTime
    end

    -- Get cooldown remaining if CooldownTracker is available
    if QR.CooldownTracker then
        local sourceType = actualSourceType or "item"
        if not actualSourceType and teleportData.type == QR.TeleportTypes.SPELL then
            sourceType = "spell"
        elseif not actualSourceType and teleportData.type == QR.TeleportTypes.TOY then
            sourceType = "toy"
        end

        local cooldown = QR.CooldownTracker:GetCooldown(teleportID, sourceType)
        if cooldown and cooldown.remaining > 0 then
            baseTime = baseTime + cooldown.remaining
        end
    end

    return baseTime
end

--- Calculate distance between two points on the same map
-- Uses Pythagorean theorem on normalized coordinates
-- @param x1 number First point X (0-1)
-- @param y1 number First point Y (0-1)
-- @param x2 number Second point X (0-1)
-- @param y2 number Second point Y (0-1)
-- @return number Distance in coordinate units
function TravelTime:CalculateDistance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math_sqrt(dx * dx + dy * dy)
end

--- Estimate walking time between two points on the same map
-- @param x1 number First point X (0-1)
-- @param y1 number First point Y (0-1)
-- @param x2 number Second point X (0-1)
-- @param y2 number Second point Y (0-1)
-- @param canFly boolean Whether the player can fly in the zone
-- @return number Estimated travel time in seconds
function TravelTime:EstimateWalkingTime(x1, y1, x2, y2, canFly, mapID)
    -- Scale each axis by its own extent. Normalized coordinates say nothing
    -- about the shape of the map, so a single scale prices north-south travel
    -- by the east-west size.
    local width, height = self:GetMapScale(mapID)
    local dx = (x2 - x1) * width
    local dy = (y2 - y1) * height
    local yards = math_sqrt(dx * dx + dy * dy)

    return self:YardsToTime(yards, canFly)
end
