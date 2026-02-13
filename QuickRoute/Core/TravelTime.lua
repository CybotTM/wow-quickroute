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

-- Map scale factors (approximate yards per coordinate unit)
-- Most maps are roughly 1000 yards per 1.0 coordinate difference
TravelTime.MAP_SCALE = 1000

-------------------------------------------------------------------------------
-- Time Estimation Methods
-------------------------------------------------------------------------------

--- Estimate travel time based on distance
-- Uses walking speed if canFly is false, flying speed otherwise
-- @param distance number Distance in coordinate units (0-1 scale)
-- @param canFly boolean Whether the player can fly in the zone
-- @return number Estimated travel time in seconds
function TravelTime:EstimateDistanceTime(distance, canFly)
    -- Convert coordinate distance to approximate yards
    local yards = distance * self.MAP_SCALE

    -- Select speed based on flight capability
    local speed
    if canFly then
        speed = self.SPEEDS.mounted_flying
    else
        speed = self.SPEEDS.mounted_ground
    end

    -- Calculate time = distance / speed
    local time = yards / speed

    return math_ceil(time)
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
    if teleportType == QR.TeleportTypes.HEARTHSTONE then
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
function TravelTime:GetEffectiveTime(teleportID, teleportData, includeCooldownWait)
    local baseTime = self:GetTeleportTime(teleportData)

    if not includeCooldownWait then
        return baseTime
    end

    -- Get cooldown remaining if CooldownTracker is available
    if QR.CooldownTracker then
        local sourceType = "item"
        if teleportData.type == QR.TeleportTypes.SPELL then
            sourceType = "spell"
        elseif teleportData.type == QR.TeleportTypes.TOY then
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
function TravelTime:EstimateWalkingTime(x1, y1, x2, y2, canFly)
    local distance = self:CalculateDistance(x1, y1, x2, y2)
    return self:EstimateDistanceTime(distance, canFly)
end
