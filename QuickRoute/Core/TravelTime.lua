-- TravelTime.lua
-- Travel time constants and estimation calculations
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local math_sqrt = math.sqrt
local math_ceil = math.ceil
local math_max = math.max
local type, pcall = type, pcall

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

local function BooleanCall(fn, ...)
    if not fn then return false end
    local ok, result = pcall(fn, ...)
    return ok and Public(result) and result == true
end

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
    teleport = 10,      -- Mage teleports have a ten-second cast
    item = 0,           -- Most items are instant
    toy = 0,            -- Most toys are instant
}

-- Travel speeds (yards per second)
TravelTime.SPEEDS = {
    walking = 7,        -- Base walking speed
    running = 7,        -- Running (same as walking without mount)
    apprentice_ground = 11.2, -- 60% bonus: base 7 * 1.6
    mounted_ground = 14, -- 100% ground mount
    expert_flying = 17.5, -- 150% bonus: base 7 * 2.5
    mounted_flying = 26.6, -- 280% bonus: base 7 * 3.8
    epic_flying = 28.7,  -- 310% bonus: base 7 * 4.1
}

-- Blizzard's GetUnitSpeed reports current and maximum movement speeds;
-- C_PlayerInfo.GetGlidingInfo reports actual skyriding forward speed. Never
-- apply one zone's flight permission to a destination in another zone.
local mountCache
local function RidingKnown(id)
    local spellBook = _G.C_SpellBook
    return BooleanCall(spellBook and spellBook.IsSpellKnown or IsSpellKnown, id)
end

local function MountCapabilities()
    local now = GetTime and GetTime() or 0
    if not Number(now) then now = 0 end
    if mountCache and now >= mountCache.time and now - mountCache.time < 1 then
        return mountCache.usable, mountCache.steady
    end
    local usableMount, steadyFlightMount = false, false
    if C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID then
        local ok, mounts = pcall(C_MountJournal.GetMountIDs)
        if ok and type(mounts) == "table" then
            for _, id in ipairs(mounts) do
                local success, _, _, _, _, usable, _, _, _, _, _, collected, _, steady =
                    pcall(C_MountJournal.GetMountInfoByID, id)
                if success and Public(usable) and Public(collected) and usable == true and collected == true then
                    usableMount = true
                    if Public(steady) and steady == true then steadyFlightMount = true end
                end
            end
        end
    end
    mountCache = { time = now, usable = usableMount, steady = steadyFlightMount }
    return usableMount, steadyFlightMount
end

local function ComputeMovementSpeed(self, mapID, mode)
    local currentMap
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, value = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and Number(value) then currentMap = value end
    end
    local here = mapID ~= nil and mapID == currentMap
    local runSpeed, flightSpeed, measuredSpeed = self.SPEEDS.running, 0, 0
    if here and _G.GetUnitSpeed then
        local ok, current, run, flight = pcall(_G.GetUnitSpeed, "player")
        if ok then
            if Number(run) and run > 0 then runSpeed = run end
            if Number(flight) then flightSpeed = flight end
            if Number(current) then measuredSpeed = current end
        end
    end
    if mode == "walk" or (here and BooleanCall(_G.IsIndoors)) then return self.SPEEDS.running end

    local mounted = here and BooleanCall(_G.IsMounted)
    local usableMount, steadyFlightMount = MountCapabilities()
    local ground = runSpeed
    if mounted or usableMount then
        local trainedSpeed = RidingKnown(33391) or RidingKnown(34090) or RidingKnown(34091) or RidingKnown(90265)
        ground = math_max(runSpeed, trainedSpeed and self.SPEEDS.mounted_ground or self.SPEEDS.apprentice_ground)
    end
    if not here or mode == false or mode == "ground" then return ground end

    local flightAllowed = BooleanCall(_G.IsFlyableArea)
    local advancedAllowed = BooleanCall(_G.IsAdvancedFlyableArea)
    local playerInfo = _G.C_PlayerInfo
    if advancedAllowed and playerInfo and playerInfo.GetGlidingInfo then
        local ok, gliding, canGlide, forwardSpeed = pcall(playerInfo.GetGlidingInfo)
        if ok and Public(gliding) and Public(canGlide) and gliding == true and canGlide == true
            and Number(forwardSpeed) and forwardSpeed > ground then
            return forwardSpeed
        end
    end
    if flightAllowed and (steadyFlightMount or BooleanCall(_G.IsFlying)) then
        if flightSpeed > ground then return math_max(flightSpeed, measuredSpeed) end
        if steadyFlightMount then
            -- A usable collected flight mount is capability evidence even while
            -- unmounted. Only apply faster ranks when the spellbook confirms it.
            local trainedSpeed = RidingKnown(90265) and self.SPEEDS.epic_flying
                or (RidingKnown(34091) and self.SPEEDS.mounted_flying or self.SPEEDS.expert_flying)
            return math_max(ground, trainedSpeed)
        end
    end
    return ground
end

local movementCache = {}
function TravelTime:ClearMovementCache()
    wipe(movementCache)
    mountCache = nil
end

function TravelTime:GetMovementSpeed(mapID, mode)
    local now = GetTime and GetTime() or 0
    if not Number(now) then now = 0 end
    local key = tostring(mapID) .. ":" .. tostring(mode)
    local cached = movementCache[key]
    if cached and now >= cached.time and now - cached.time < 1 then return cached.speed end
    local speed = ComputeMovementSpeed(self, mapID, mode)
    movementCache[key] = { time = now, speed = speed }
    return speed
end

function TravelTime:CanFly(mapID)
    return self:GetMovementSpeed(mapID, true) > self:GetMovementSpeed(mapID, false)
end

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
        if ok and Number(width) and width > 0 then
            if not Number(height) or height <= 0 then
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
function TravelTime:YardsToTime(yards, canFly, mapID)
    local speed = mapID and self:GetMovementSpeed(mapID, canFly)
        or (canFly and self.SPEEDS.mounted_flying or self.SPEEDS.mounted_ground)
    return math_ceil(yards / speed)
end

--- Get teleport time based on teleport type
-- Includes cast time + loading time
-- @param teleportData table Teleport data from TeleportItemsData
-- @return number Total teleport time in seconds
function TravelTime:GetTeleportTime(teleportData, teleportID, sourceType)
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
        -- Individual spell metadata below overrides this conservative default.
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

    if Number(teleportData.castTime) then castTime = teleportData.castTime end
    local spellID = teleportData.spellID
    if not spellID and sourceType == "spell" then spellID = teleportID end
    if not spellID and teleportID and sourceType ~= "spell" and C_Item and C_Item.GetItemSpell then
        local ok, _, itemSpellID = pcall(C_Item.GetItemSpell, teleportID)
        if ok and Number(itemSpellID) and itemSpellID > 0 then spellID = itemSpellID end
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and Number(info.castTime) then
            castTime = info.castTime / 1000
        end
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
    local sourceType = actualSourceType or (teleportData and teleportData.type == QR.TeleportTypes.SPELL and "spell" or "item")
    local baseTime = self:GetTeleportTime(teleportData, teleportID, sourceType)

    if not includeCooldownWait then
        return baseTime
    end

    -- Get cooldown remaining if CooldownTracker is available
    if QR.CooldownTracker then
        sourceType = actualSourceType or "item"
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

    return self:YardsToTime(yards, canFly, mapID)
end
