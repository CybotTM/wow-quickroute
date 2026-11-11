-- DataCollection.lua
-- Opt-in observations kept in SavedVariables for the owner to read later.
--
-- An addon cannot send anything anywhere. "Collection" means small ring
-- buffers under QR.db.observations that end up in the SavedVariables file on
-- this computer when the client writes it. Nothing is recorded unless
-- QR.db.dataCollection is true, and every hook runs its recording inside
-- pcall, so a recording can fail without touching routing.
--
-- The switch is its own setting, next to the diagnostic trace and the zone
-- survey, and governs only these six lists: the zone survey has its own
-- switch. DataCollection:SetEnabled is the one writer of the setting.
-- DataCollection.unsavedCount counts the writes since the last reload, for
-- the save reminder in Diagnostics.lua.
--
-- Six recordings:
--   landings          where a teleport QuickRoute knows actually put the player
--   unknownTeleports  a cast QuickRoute does not know, followed by a loading screen;
--                     with spell, both ends, the game maps (GetInstanceInfo) and
--                     the faction, enough to curate a portal the data lacks
--   noRoute           a route calculation that ended without a route
--   stepTimes         measured time between map arrivals on a followed route,
--                     and start-to-arrival for the whole route, against the estimate
--   rejectedSteps     a step the player refused
--   calcTimes         how long a route calculation took
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, pcall, tostring, tonumber, type = pairs, ipairs, pcall, tostring, tonumber, type
local string_format = string.format
local math_floor, math_huge, math_sqrt, math_min, math_max = math.floor, math.huge, math.sqrt, math.min, math.max
local table_remove, table_concat = table.remove, table.concat
local coroutine_running = coroutine.running
local date, GetTime = date, GetTime
local UnitFactionGroup = UnitFactionGroup

QR.DataCollection = { unsavedCount = 0 }
local DataCollection = QR.DataCollection

-- Ring buffer sizes. The whole table is rewritten on every logout, so it stays
-- in the tens of entries per list.
local CAPS = {
    landings = 40,
    unknownTeleports = 30,
    noRoute = 40,
    stepTimes = 60,
    rejectedSteps = 30,
    calcTimes = 50,
}
local ORDER = { "landings", "unknownTeleports", "noRoute", "stepTimes", "rejectedSteps", "calcTimes" }
DataCollection.CAPS = CAPS
local MAX_COUNTER = 1000000000

-- A known teleport's loading screen, or the map change it causes, has to begin
-- within this many seconds of the cast succeeding.
local KNOWN_WINDOW = 20
-- A teleport that lands on the same map without a loading screen happens right
-- after the cast. A longer window would file a walk as a teleport landing.
local SAME_MAP_WINDOW = 5
-- On the same map, less than this (normalized map units) is not a teleport.
local MIN_MOVE = 0.05
-- An unknown spell counts only when the loading screen follows at once: any
-- spell cast just before walking through a portal would otherwise be filed.
local UNKNOWN_WINDOW = 3
-- Once a loading screen started, how long the landing may take to resolve.
local LANDING_WINDOW = 90
-- Retries while the client still reports a continent or no position.
local LANDING_RETRIES = 20
local RETRY_DELAY = 0.5
-- On the same map, a landing farther than this from the expected point is
-- flagged as a mismatch (normalized map units).
local MISMATCH_DISTANCE = 0.02
-- A followed route counts as arrived within this distance of the destination.
local ARRIVAL_RADIUS = 0.02
-- A route that has not arrived after this long is dropped, not recorded.
local MAX_FOLLOW = 7200
-- A route that takes this many times its estimate was abandoned, not
-- followed slowly: it is dropped, not recorded. Never less than FOLLOW_FLOOR.
local FOLLOW_FACTOR = 5
local FOLLOW_FLOOR = 300
local SAMPLE_INTERVAL = 1

-------------------------------------------------------------------------------
-- Value guards. Everything read back from SavedVariables or from the client is
-- checked; under addon restrictions the client hands out secret values.
-------------------------------------------------------------------------------

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IsFinite(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math_huge and value < math_huge
end

local function IsID(value)
    return IsFinite(value) and value > 0 and value == math_floor(value)
end

local function IsCoordinate(value)
    return IsFinite(value) and value >= 0 and value <= 1
end

local function Round(value, places)
    if not IsFinite(value) then return nil end
    return tonumber(string_format("%." .. (places or 4) .. "f", value))
end

local function Counter(value)
    local number = Public(value) and tonumber(value) or nil
    if not IsFinite(number) or number < 0 then return 0 end
    return math_min(math_floor(number), MAX_COUNTER)
end

local function Distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math_sqrt(dx * dx + dy * dy)
end

--- True while the switch is on.
function DataCollection:IsOn()
    return QR.db ~= nil and QR.db.dataCollection == true
end

local function IsOn()
    return DataCollection:IsOn()
end

-- debugprofilestop, read only while recording: the clock is shared with the
-- route search budget, and a reading taken while switched off would be a
-- side effect of a feature that is supposed to be absent.
local function Clock()
    local clock = _G.debugprofilestop
    if type(clock) ~= "function" then return nil end
    local ok, value = pcall(clock)
    if ok and IsFinite(value) then return value end
    return nil
end

-------------------------------------------------------------------------------
-- Store
-------------------------------------------------------------------------------

local function Store()
    if type(QR.db.observations) ~= "table" then QR.db.observations = {} end
    return QR.db.observations
end

local function List(name)
    local store = Store()
    if type(store[name]) ~= "table" then store[name] = {} end
    return store[name]
end

--- Append one entry, or count a repeat of an entry with the same key.
-- @return table|nil The stored entry; nil when the switch is off
function DataCollection:Push(name, entry, key)
    if not IsOn() or not CAPS[name] then return nil end
    local list = List(name)
    local seen = date("%Y-%m-%d %H:%M:%S")
    if key then
        for i = #list, 1, -1 do
            local prior = list[i]
            if type(prior) == "table" and prior.key == key then
                prior.count = math_min(Counter(prior.count) + 1, MAX_COUNTER)
                prior.seen = seen
                self.unsavedCount = (self.unsavedCount or 0) + 1
                return prior
            end
        end
        entry.key = key
        entry.count = 1
    end
    entry.seen = seen
    list[#list + 1] = entry
    -- A repeat above changes the saved data too, so both count as unsaved.
    self.unsavedCount = (self.unsavedCount or 0) + 1
    while #list > CAPS[name] do
        table_remove(list, 1)
    end
    return entry
end

--- Keep only the known lists, only table entries, and at most the cap of each.
local function Sanitize(store)
    local clean = {}
    if type(store) ~= "table" then store = {} end
    for _, name in ipairs(ORDER) do
        local kept = {}
        if type(store[name]) == "table" then
            for _, entry in ipairs(store[name]) do
                if type(entry) == "table" then kept[#kept + 1] = entry end
            end
        end
        while #kept > CAPS[name] do table_remove(kept, 1) end
        clean[name] = kept
    end
    return clean
end

--- Count of each recording, in display order.
function DataCollection:Counts()
    local counts = {}
    local store = QR.db and type(QR.db.observations) == "table" and QR.db.observations or {}
    for i, name in ipairs(ORDER) do
        counts[i] = type(store[name]) == "table" and #store[name] or 0
    end
    return counts
end

function DataCollection:Clear()
    if not QR.db then return end
    QR.db.observations = nil
    -- Nothing left that a crash could lose.
    self.unsavedCount = 0
    self:Forget()
end

--- Drop everything in flight: a pending cast and a followed route.
-- Called when the switch goes off, so nothing that happened while off can be
-- recorded once it is on again. The zone survey is not touched: it has its own
-- switch and keeps its own state.
function DataCollection:Forget()
    self.pendingCast = nil
    self.follow = nil
end

--- Switch the observations on or off. The settings checkbox and /qrdata both
-- come through here, so the in-flight state and the save reminder follow.
function DataCollection:SetEnabled(enabled)
    if not QR.db then return end
    QR.db.dataCollection = enabled == true
    if not QR.db.dataCollection then self:Forget() end
    self:ApplySetting()
    local reminder = QR.Diagnostics and QR.Diagnostics.Reminder
    if reminder and reminder.Refresh then reminder:Refresh() end
end

-------------------------------------------------------------------------------
-- Positions
-------------------------------------------------------------------------------

--- True for a continent or world map (UiMap type 0-2). Right after a loading
-- screen the client can report one before the zone resolves.
local function IsContinentMap(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return false end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if not ok or not Public(info) or type(info) ~= "table" then return false end
    return IsFinite(info.mapType) and info.mapType <= 2
end

--- Where the player is, resolved the way the router resolves points.
-- @return table|nil {mapID, x, y}; nil while the client cannot say
-- @return boolean True when the client still reports a continent
local function PlayerPoint()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, raw = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not IsID(raw) then return nil end
    if IsContinentMap(raw) then return nil, true end
    local PC = QR.PathCalculator
    if not (PC and PC.GetPlayerPosition) then return nil end
    local mapID, x, y = PC:GetPlayerPosition(raw)
    if not IsID(mapID) or not IsCoordinate(x) or not IsCoordinate(y) then return nil end
    return { mapID = mapID, x = x, y = y }
end

local function Point(prefix, entry, point)
    if not point then return end
    entry[prefix .. "MapID"] = point.mapID
    entry[prefix .. "X"] = Round(point.x)
    entry[prefix .. "Y"] = Round(point.y)
end

--- The game map the player is on, read the way the diagnostic trace reads it
-- (Diagnostics.GameMapFields: GetInstanceInfo and the best UI map).
-- @return table|nil instanceMapID, instanceName, instanceType, ... ; nil when unknown
local function GameMap()
    local D = QR.Diagnostics
    if not (D and D.GameMapFields) then return nil end
    local fields = {}
    local ok = pcall(D.GameMapFields, fields)
    if not ok then return nil end
    return fields
end

local function Faction()
    if not UnitFactionGroup then return nil end
    local ok, faction = pcall(UnitFactionGroup, "player")
    if ok and Public(faction) and type(faction) == "string" and #faction <= 32 then return faction end
    return nil
end

-------------------------------------------------------------------------------
-- (a) and (b): teleport landings
--
-- UNIT_SPELLCAST_SUCCEEDED gives the spell that was cast. For a spell that is
-- the teleport id; for an item or a toy it is the item's on-use spell, and
-- QuickRoute's data has no item -> spell column. C_Item.GetItemSpell supplies
-- it, as Hearthstone.lua already does for the hearthstone set. The secure
-- button that was clicked is not used: it misses every teleport used from the
-- bags, the toy box or an action bar.
-------------------------------------------------------------------------------

local function IndexSpells()
    local index = {}
    local function add(source, kind)
        for id, data in pairs(source or {}) do
            if IsID(id) and type(data) == "table" and not index[id] then
                index[id] = { id = id, kind = data.type or kind, data = data }
            end
        end
    end
    add(QR.ClassTeleportSpells, "spell")
    add(QR.RacialTeleportSpells, "spell")
    add(QR.GeneralTeleportSpells, "spell")
    for _, group in pairs(QR.MageTeleports or {}) do add(group, "spell") end
    add(QR.DungeonTeleportSpells, "dungeon")
    return index
end

--- Map one item's on-use spell to the item.
function DataCollection:ResolveItemSpell(itemID)
    local data = QR.TeleportItemsData and QR.TeleportItemsData[itemID]
    if not data or not (C_Item and C_Item.GetItemSpell) then return end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and IsID(spellID) and not self.itemSpells[spellID] then
        self.itemSpells[spellID] = { id = itemID, kind = data.type or "item", data = data }
    end
end

--- The teleport a spell cast belongs to, or nil.
function DataCollection:FindTeleport(spellID)
    if not self.spellIndex then
        self.spellIndex = IndexSpells()
        self.itemSpells = {}
        -- Once per session. An item whose data the client has not loaded yet
        -- is resolved by GET_ITEM_INFO_RECEIVED instead.
        for itemID in pairs(QR.TeleportItemsData or {}) do self:ResolveItemSpell(itemID) end
    end
    return self.spellIndex[spellID] or self.itemSpells[spellID]
end

--- Where the data expects a teleport to land.
-- @return table|nil {mapID, x, y}, the candidate count
local function ExpectedLanding(teleport, landing)
    local TD = QR.TeleportDestinations
    if not (TD and TD.GetDestinations) then return nil, 0 end
    local ok, candidates = pcall(TD.GetDestinations, TD, teleport.id, teleport.data)
    if not ok or type(candidates) ~= "table" then return nil, 0 end
    local best, bestDistance
    for _, candidate in ipairs(candidates) do
        if type(candidate) == "table" and IsID(candidate.mapID)
            and IsCoordinate(candidate.x) and IsCoordinate(candidate.y) then
            local d = candidate.mapID == landing.mapID and Distance(candidate, landing) or math_huge
            if not best or d < bestDistance then best, bestDistance = candidate, d end
        end
    end
    return best, #candidates
end

local function SpellName(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or not Public(info) or type(info) ~= "table" then return nil end
    local name = info.name
    if Public(name) and type(name) == "string" and #name <= 128 then return name end
    return nil
end

function DataCollection:RecordLanding(pending, landing)
    local teleport = pending.teleport
    if teleport then
        local entry = { id = teleport.id, kind = teleport.kind, spellID = pending.spellID,
            loading = pending.sawLoading == true }
        Point("from", entry, pending.from)
        Point("to", entry, landing)
        local expected, candidates = ExpectedLanding(teleport, landing)
        entry.candidates = candidates
        if expected then
            Point("exp", entry, expected)
            if expected.mapID == landing.mapID then
                local d = Distance(expected, landing)
                entry.distance = Round(d)
                entry.mismatch = d > MISMATCH_DISTANCE
            else
                entry.mismatch = true
            end
        end
        local key = string_format("%d:%d:%.3f:%.3f", teleport.id, landing.mapID, landing.x, landing.y)
        return self:Push("landings", entry, key)
    end
    -- A spell of the player's own (a mount, a combat spell cast just before a
    -- portal) is not a teleport candidate. It is still written, flagged, so a
    -- portal whose click the client reports as a player spell is not lost.
    local entry = { spellID = pending.spellID, name = SpellName(pending.spellID), faction = Faction(),
        playerSpell = pending.playerSpell or nil }
    Point("from", entry, pending.from)
    Point("to", entry, landing)
    -- The game maps on both sides: a portal between two phased or instanced
    -- copies shows up here and not in the UI map IDs.
    local fromGame, toGame = pending.fromGame, GameMap()
    entry.fromInstanceMapID = fromGame and fromGame.instanceMapID or nil
    entry.fromInstanceName = fromGame and fromGame.instanceName or nil
    if toGame then
        entry.toInstanceMapID = toGame.instanceMapID
        entry.toInstanceName = toGame.instanceName
        entry.toInstanceType = toGame.instanceType
    end
    if pending.sawLoading and IsFinite(pending.loadingAt) then
        entry.loadingSeconds = Round(GetTime() - pending.loadingAt, 1)
    end
    local key = string_format("%d:%d:%.2f:%.2f", pending.spellID, landing.mapID, landing.x, landing.y)
    return self:Push("unknownTeleports", entry, key)
end

--- Read the landing for the pending cast, once the zone has resolved.
function DataCollection:TryLanding()
    local pending = self.pendingCast
    if not pending or pending.loading then return end
    if not IsOn() then self.pendingCast = nil; return end
    local now = GetTime()
    if pending.sawLoading then
        if now - pending.loadingAt > LANDING_WINDOW then self.pendingCast = nil; return end
    elseif not pending.teleport then
        -- An unknown spell is a teleport candidate only with a loading screen.
        if now - pending.castAt > UNKNOWN_WINDOW then self.pendingCast = nil end
        return
    elseif now - pending.castAt > KNOWN_WINDOW then
        self.pendingCast = nil
        return
    end

    local landing, continent = PlayerPoint()
    if not landing then
        -- A continent or no position: the zone has not resolved yet. Retry a
        -- bounded number of times, then wait for the next zone event.
        if (continent or pending.sawLoading) and pending.attempts < LANDING_RETRIES
            and C_Timer and C_Timer.NewTimer then
            pending.attempts = pending.attempts + 1
            C_Timer.NewTimer(RETRY_DELAY, function()
                if self.pendingCast ~= pending then return end
                local ok, err = pcall(self.TryLanding, self)
                if not ok then
                    self.pendingCast = nil
                    QR:Debug("DataCollection: " .. tostring(err))
                end
            end)
        end
        return
    end
    if not pending.sawLoading then
        if landing.mapID == pending.from.mapID then
            -- Same map without a loading screen: only a jump right after the
            -- cast is a teleport.
            if now - pending.castAt > SAME_MAP_WINDOW then self.pendingCast = nil; return end
            if Distance(landing, pending.from) < MIN_MOVE then return end
        end
    end
    self.pendingCast = nil
    self:RecordLanding(pending, landing)
end

function DataCollection:OnSpellSucceeded(unit, spellID)
    if not Public(unit) or unit ~= "player" or not IsID(spellID) then return end
    -- No teleport is cast in combat; skip the position reads there.
    if InCombatLockdown and InCombatLockdown() then return end
    -- A cast during a loading screen that is already under way does not
    -- replace the one that caused it.
    if self.pendingCast and self.pendingCast.sawLoading then return end
    local from = PlayerPoint()
    if not from then self.pendingCast = nil; return end
    local teleport = self:FindTeleport(spellID)
    local playerSpell = false
    local isPlayerSpell = _G.IsPlayerSpell
    if not teleport and type(isPlayerSpell) == "function" then
        local ok, known = pcall(isPlayerSpell, spellID)
        playerSpell = ok and Public(known) and known == true
    end
    self.pendingCast = {
        playerSpell = playerSpell,
        spellID = spellID,
        teleport = teleport,
        from = from,
        -- Only an unknown cast needs its game map; it is read now, before the
        -- loading screen moves the player.
        fromGame = not teleport and GameMap() or nil,
        castAt = GetTime(),
        attempts = 0,
    }
end

function DataCollection:OnLoadingScreen()
    local pending = self.pendingCast
    if not pending then return end
    local now = GetTime()
    if pending.sawLoading then
        -- A second loading screen before the landing was read: whatever the
        -- player landed on is no longer this cast's landing.
        self.pendingCast = nil
        return
    end
    local window = pending.teleport and KNOWN_WINDOW or UNKNOWN_WINDOW
    if now - pending.castAt > window then self.pendingCast = nil; return end
    pending.loading = true
    pending.sawLoading = true
    pending.loadingAt = now
    pending.attempts = 0
end

-------------------------------------------------------------------------------
-- (c) and (f): route calculations
--
-- CalculatePath is the one function every consumer goes through, so it is
-- wrapped rather than each caller. The wrapper calls the original directly:
-- inside an asynchronous search CalculatePath yields, and Lua 5.1 cannot yield
-- across pcall. Only the recording runs in pcall.
-------------------------------------------------------------------------------

local requestClock = {}
DataCollection.requestClock = requestClock
local requestCount = 0

local function InAsyncSearch(PC)
    local running = PC.asyncRunning
    return running and coroutine_running() == running.thread and running or nil
end

function DataCollection:RecordNoRoute(failure, destMapID, destX, destY, source)
    local entry = {
        reason = type(failure) == "table" and tostring(failure.reason) or tostring(failure),
        source = source,
        toMapID = IsID(destMapID) and destMapID or nil,
        toX = Round(destX),
        toY = Round(destY),
    }
    local PC = QR.PathCalculator
    local ok, mapID, x, y = pcall(PC.GetPlayerPosition, PC)
    if ok and IsID(mapID) then
        entry.fromMapID, entry.fromX, entry.fromY = mapID, Round(x), Round(y)
    end
    local key = string_format("%s:%s:%s:%s:%s:%s", entry.reason, tostring(source),
        tostring(entry.fromMapID), tostring(entry.toMapID),
        tostring(Round(destX, 3)), tostring(Round(destY, 3)))
    return self:Push("noRoute", entry, key)
end

function DataCollection:AfterCalculation(PC, started, route, failure, destMapID, destX, destY)
    local running = InAsyncSearch(QR.PathCalculator)
    if running then
        running.dcFound = route ~= nil
        running.dcPathNodes = route and type(route.path) == "table" and #route.path or nil
    end
    if not route then
        self:RecordNoRoute(failure, destMapID, destX, destY, running and running.consumer or "direct")
    end
    -- Asynchronous searches are timed by ResumeAsync, from request to result.
    if not running and started then
        local finished = Clock()
        if finished then
            self:Push("calcTimes", {
                ms = Round(finished - started, 1),
                async = false,
                found = route ~= nil,
                pathNodes = route and type(route.path) == "table" and #route.path or nil,
            })
        end
    end
end

function DataCollection:InstallRouteHooks()
    local PC = QR.PathCalculator
    if not PC or self.routeHooksInstalled then return end
    self.routeHooksInstalled = true

    local calculate = PC.CalculatePath
    -- Only the live calculator is recorded. A route context (the multi-stop
    -- planner's matrix, MultiRoute:OptimizeTour) calls the same function from
    -- other starts than the player's; its legs are neither failures nor
    -- timings of a route anybody asked for.
    PC.CalculatePath = function(calc, destMapID, destX, destY, destTitle)
        if calc ~= PC or not IsOn() then return calculate(calc, destMapID, destX, destY, destTitle) end
        local started = Clock()
        local route, failure = calculate(calc, destMapID, destX, destY, destTitle)
        pcall(DataCollection.AfterCalculation, DataCollection, calc, started, route, failure,
            destMapID, destX, destY)
        return route, failure
    end

    local async = PC.CalculatePathAsync
    PC.CalculatePathAsync = function(calc, ...)
        if calc == PC and IsOn() then
            -- The generation this request is about to get. Remembered by
            -- generation because the queue entry does not exist yet.
            if requestCount > 64 then
                requestClock, requestCount = {}, 0
                DataCollection.requestClock = requestClock
            end
            requestClock[(calc.asyncGeneration or 0) + 1] = Clock()
            requestCount = requestCount + 1
        end
        return async(calc, ...)
    end

    local resume = PC.ResumeAsync
    PC.ResumeAsync = function(calc, ...)
        local running = calc == PC and calc.asyncRunning or nil
        if running and IsOn() then
            running.dcSlices = (running.dcSlices or 0) + 1
            if not running.dcStarted then
                running.dcStarted = Clock()
                running.dcRequested = requestClock[running.generation]
                requestClock[running.generation] = nil
            end
        end
        resume(calc, ...)
        -- Finished when it is no longer the running request. The flag stops
        -- the same request from being recorded by an outer slice too.
        if running and running.dcSlices and not running.dcRecorded and calc.asyncRunning ~= running then
            running.dcRecorded = true
            pcall(function()
                local finished = Clock()
                local from = running.dcRequested or running.dcStarted
                if not (finished and from) then return end
                DataCollection:Push("calcTimes", {
                    ms = Round(finished - from, 1),
                    async = true,
                    slices = running.dcSlices,
                    consumer = running.consumer,
                    found = running.dcFound,
                    pathNodes = running.dcPathNodes,
                    superseded = running.superseded or nil,
                })
            end)
        end
    end

    -- (e) A refused step. Post-hook: the refusal itself is unchanged.
    if hooksecurefunc then
        hooksecurefunc(PC, "ExcludeEdge", function(calc, from, to, destination)
            pcall(DataCollection.RecordRejectedStep, DataCollection, calc, from, to, destination)
        end)
    end
end

-------------------------------------------------------------------------------
-- (e) Rejected steps
-------------------------------------------------------------------------------

function DataCollection:RecordRejectedStep(PC, from, to, destination)
    if from == nil or to == nil then return nil end
    local edges = PC and PC.graph and PC.graph.edges and PC.graph.edges[from]
    local edge = type(edges) == "table" and edges[to] or nil
    local entry = {
        from = tostring(from),
        to = tostring(to),
        stepType = type(edge) == "table" and edge.edgeType or nil,
    }
    if type(destination) == "table" and IsID(destination.mapID) then
        entry.toMapID = destination.mapID
        entry.toX = Round(destination.x)
        entry.toY = Round(destination.y)
    end
    local key = string_format("%s\1%s\1%s", entry.from, entry.to, tostring(entry.toMapID))
    return self:Push("rejectedSteps", entry, key)
end

-------------------------------------------------------------------------------
-- (d) Estimated against measured time on a followed route
--
-- The route panel recalculates from the player's position after every map
-- change, so its step list is replaced on each arrival and its "current step"
-- is a guess from the map alone. Timing is therefore kept on the plan as it
-- was when the destination was first shown: each arrival on a map that plan
-- leads to closes a leg (the steps up to that map, their summed estimate, the
-- measured seconds). An arrival on a map outside the plan ends leg timing for
-- the route; start-to-arrival is still recorded, flagged as having diverged.
-------------------------------------------------------------------------------

local function DestinationKey(waypoint)
    return string_format("%d:%.3f:%.3f", waypoint.mapID, waypoint.x, waypoint.y)
end

--- Stop timing: the route is gone, cleared, replaced or abandoned. One last
-- sample first, so an arrival that happened since the last tick is still
-- recorded.
--
-- Abandonment is decided by the waypoint, never by the route window: the
-- window hides itself when combat starts, and travelling with it closed on
-- TomTom's arrow is supported. A route ends when WaypointIntegration reports
-- the waypoint cleared (OnWaypointCleared) or resolved to another destination
-- (OnWaypointResolved), on UI:ClearRoute, on a route for another destination
-- or without steps on the panel, or past its time limit.
function DataCollection:EndFollow()
    if not self.follow then return end
    pcall(self.SampleRoute, self)
    self.follow = nil
end

-- What a waypoint signal, and a later sample, does to a followed route is
-- judged against what the panel would show on its next refresh
-- (UI:RefreshRoute):
--   * While QR.db.destinationLocked is set and QR.db.lastDestination is valid,
--     the panel routes to lastDestination whatever the quest or pin does. A
--     follow for that destination is kept; a follow for any other is ended,
--     also without a waypoint event (a map click or a multi-stop leg chosen
--     with the window closed only saves and locks). A map pin or
--     super-tracking event clears the lock before WaypointIntegration is told.
--   * Without a waypoint, a super-tracked quest or a map pin, the panel falls
--     back to lastDestination. When that is the followed destination the route
--     goes on with its own source, marked `fallback`; the next event is judged
--     the same way again.
--   * Routes the panel showed as "saved" and the dungeon offer's route are not
--     ended by a waypoint signal (owner's decision); only the panel
--     (ClearRoute, UpdateRoute) or the time limit ends them.
local LOCKABLE = { locked = true, map_click = true }
local EXEMPT = { saved = true, dungeon_offer = true }

local function Locked()
    return QR.db ~= nil and QR.db.destinationLocked == true
end

local function Exempt(follow)
    return EXEMPT[follow.source] or false
end

local function ValidDestination(dest)
    return type(dest) == "table" and IsID(dest.mapID) and IsCoordinate(dest.x) and IsCoordinate(dest.y)
end

--- The destination key the panel is locked to, or nil when it is not locked
-- (RefreshRoute uses the lock only with a usable lastDestination).
local function LockedKey()
    if not Locked() then return nil end
    local dest = QR.db.lastDestination
    if not ValidDestination(dest) then return nil end
    return DestinationKey(dest)
end

--- True when the panel would fall back to the followed destination: nothing
-- else to route to and QR.db.lastDestination is that destination. Reads only
-- what RefreshRoute reads for its fallback, plus TomTom's own waypoint (which
-- the panel would route to first); never GetActiveWaypoint.
local function PanelFallsBackTo(follow)
    local dest = QR.db and QR.db.lastDestination
    if not ValidDestination(dest) or DestinationKey(dest) ~= follow.key then
        return false
    end
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, quest = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if not ok or not Public(quest) or quest ~= 0 then return false end
    end
    if C_Map and C_Map.HasUserWaypoint then
        local ok, pin = pcall(C_Map.HasUserWaypoint)
        if not ok or not Public(pin) or pin then return false end
    end
    local WI = QR.WaypointIntegration
    if WI and WI.HasTomTom and WI.GetTomTomWaypoint then
        local ok, tomtom = pcall(function() return WI:HasTomTom() and WI:GetTomTomWaypoint() end)
        if not ok or tomtom then return false end
    end
    return true
end

--- End the route, unless the panel falls back to the same destination.
local function EndUnlessFallback(self, follow)
    if PanelFallsBackTo(follow) then
        follow.fallback = true
        return
    end
    self:EndFollow()
end

--- WaypointIntegration: the native map pin went away (USER_WAYPOINT_UPDATED
-- without a pin). Only a route to that pin, or a locked one the event has
-- just unlocked, is affected: a quest or TomTom route does not depend on the
-- pin, and a later change, if any, is judged by OnWaypointResolved.
function DataCollection:OnWaypointCleared()
    local follow = self.follow
    if not follow or not IsOn() then return end
    local source = follow.source
    if source ~= "mappin" and not (LOCKABLE[source] and not LockedKey()) then return end
    EndUnlessFallback(self, follow)
end

--- WaypointIntegration resolved the active waypoint after a change. The same
-- destination keeps the followed route; another ends it; none ends it unless
-- the panel falls back to the same destination.
function DataCollection:OnWaypointResolved(waypoint)
    local follow = self.follow
    if not follow or not IsOn() or Exempt(follow) then return end
    -- Locked: the panel routes to lastDestination, not to the waypoint.
    local locked = LockedKey()
    if locked then
        if locked ~= follow.key then self:EndFollow() end
        return
    end
    if ValidDestination(waypoint) then
        if DestinationKey(waypoint) ~= follow.key then self:EndFollow() end
        return
    end
    EndUnlessFallback(self, follow)
end

function DataCollection:OnRouteShown(result)
    if not IsOn() or type(result) ~= "table" then return end
    local waypoint = result.waypoint
    if type(waypoint) ~= "table" or not IsID(waypoint.mapID)
        or not IsCoordinate(waypoint.x) or not IsCoordinate(waypoint.y)
        or type(result.steps) ~= "table" or #result.steps == 0 then
        -- No route on screen any more: nothing to follow.
        self:EndFollow()
        return
    end
    local key = DestinationKey(waypoint)
    local now = GetTime()
    local follow = self.follow
    if follow and follow.key == key and now - follow.startedAt <= follow.limit then return end
    -- Another destination: the old one may just have been reached.
    self:EndFollow()
    local here = PlayerPoint()
    if not here then self.follow = nil; return end
    local steps = {}
    for i, step in ipairs(result.steps) do
        if type(step) ~= "table" then break end
        steps[i] = { type = tostring(step.type), time = IsFinite(step.time) and step.time or 0,
            destMapID = step.destMapID }
    end
    local estimate = IsFinite(result.totalTime) and result.totalTime > 0 and result.totalTime or nil
    local source = result.waypointSource
    if not (Public(source) and type(source) == "string") then source = waypoint.source end
    self.follow = {
        key = key,
        dest = { mapID = waypoint.mapID, x = waypoint.x, y = waypoint.y },
        -- WaypointIntegration and the route panel put the source on the
        -- result; a waypoint carries it only for saved and locked targets.
        source = Public(source) and type(source) == "string" and source or nil,
        estimate = estimate,
        limit = estimate and math_min(MAX_FOLLOW, math_max(FOLLOW_FLOOR, estimate * FOLLOW_FACTOR)) or MAX_FOLLOW,
        startedAt = now,
        legStart = now,
        legMap = here.mapID,
        steps = steps,
        legs = 0,
    }
end

local function CloseLeg(follow, upTo, toMapID, now)
    local types, estimate, seen = {}, 0, {}
    for i = 1, upTo do
        local step = follow.steps[i]
        estimate = estimate + step.time
        if not seen[step.type] then
            seen[step.type] = true
            types[#types + 1] = step.type
        end
    end
    DataCollection:Push("stepTimes", {
        kind = "leg",
        types = table_concat(types, "+"),
        steps = upTo,
        fromMapID = follow.legMap,
        toMapID = toMapID,
        estimated = Round(estimate, 1),
        measured = Round(now - follow.legStart, 1),
    })
    for _ = 1, upTo do table_remove(follow.steps, 1) end
    follow.legs = follow.legs + 1
end

--- Check the followed route against where the player is now.
function DataCollection:SampleRoute()
    local follow = self.follow
    if not follow then return end
    if not IsOn() then self.follow = nil; return end
    local now = GetTime()
    if now - follow.startedAt > follow.limit then self.follow = nil; return end
    local here = PlayerPoint()
    if not here then return end

    if here.mapID ~= follow.legMap then
        local upTo
        if not follow.diverged then
            for i, step in ipairs(follow.steps) do
                if step.destMapID == here.mapID then upTo = i; break end
            end
        end
        if upTo then
            CloseLeg(follow, upTo, here.mapID, now)
        else
            follow.diverged = true
        end
        follow.legMap = here.mapID
        follow.legStart = now
    end

    if here.mapID == follow.dest.mapID and Distance(here, follow.dest) <= ARRIVAL_RADIUS then
        if not follow.diverged and #follow.steps > 0 then
            CloseLeg(follow, #follow.steps, here.mapID, now)
        end
        local entry = {
            kind = "route",
            source = follow.source,
            steps = follow.legs,
            toMapID = follow.dest.mapID,
            estimated = Round(follow.estimate, 1),
            measured = Round(now - follow.startedAt, 1),
            diverged = follow.diverged or nil,
            fallback = follow.fallback or nil,
        }
        self.follow = nil
        self:Push("stepTimes", entry)
        return
    end

    -- A destination locked meanwhile without any waypoint event (a map click
    -- or a multi-stop leg with the window closed): the panel now routes there.
    local locked = LockedKey()
    if locked and locked ~= follow.key and not Exempt(follow) then self.follow = nil end
end

-------------------------------------------------------------------------------
-- Events and initialization
-------------------------------------------------------------------------------

function DataCollection:OnEvent(event, ...)
    if not IsOn() then
        if self.pendingCast or self.follow then self:Forget() end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        self:OnSpellSucceeded(unit, spellID)
    elseif event == "LOADING_SCREEN_ENABLED" then
        self:OnLoadingScreen()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        if self.itemSpells and IsID(itemID) then self:ResolveItemSpell(itemID) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if isLogin or isReload then self.pendingCast = nil; return end
        if self.pendingCast then self.pendingCast.loading = false end
        self:TryLanding()
    elseif event == "LOADING_SCREEN_DISABLED" then
        if self.pendingCast then self.pendingCast.loading = false end
        self:TryLanding()
    else
        -- ZONE_CHANGED, ZONE_CHANGED_INDOORS, ZONE_CHANGED_NEW_AREA
        self:TryLanding()
    end
end

function DataCollection:Initialize()
    -- Only an existing table is cleaned. A player who never switched the
    -- collection on gets no observations key in the file at all.
    if QR.db and QR.db.observations ~= nil then
        QR.db.observations = Sanitize(QR.db.observations)
    end
    self:InstallRouteHooks()
    if hooksecurefunc and QR.UI and QR.UI.UpdateRoute and not self.uiHookInstalled then
        hooksecurefunc(QR.UI, "UpdateRoute", function(_, result)
            pcall(DataCollection.OnRouteShown, DataCollection, result)
        end)
        self.uiHookInstalled = true
    end
    if hooksecurefunc and QR.UI and QR.UI.ClearRoute and not self.clearHookInstalled then
        -- The waypoint was cleared: the route on screen is gone.
        hooksecurefunc(QR.UI, "ClearRoute", function()
            pcall(DataCollection.EndFollow, DataCollection)
        end)
        self.clearHookInstalled = true
    end
    if not self.frame and CreateFrame then
        local frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, ...)
            local ok, err = pcall(DataCollection.OnEvent, DataCollection, event, ...)
            if not ok then QR:Debug("DataCollection: " .. tostring(err)) end
        end)
        frame.sampleElapsed = 0
        self.frame = frame
    end
    self:ApplySetting()
    QR:Debug("DataCollection initialized")
end

local EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "LOADING_SCREEN_ENABLED",
    "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "GET_ITEM_INFO_RECEIVED" }
DataCollection.EVENTS = EVENTS

local function OnUpdate(f, elapsed)
    if not DataCollection.follow then return end
    f.sampleElapsed = f.sampleElapsed + (elapsed or 0)
    if f.sampleElapsed < SAMPLE_INTERVAL then return end
    f.sampleElapsed = 0
    local ok, err = pcall(DataCollection.SampleRoute, DataCollection)
    if not ok then
        DataCollection.follow = nil
        QR:Debug("DataCollection: " .. tostring(err))
    end
end

--- Events and the sampling OnUpdate only while the switch is on, as the
-- diagnostic trace does: a player who records nothing pays nothing per frame.
-- RegisterEvent is guarded, the two clients do not know the same events.
function DataCollection:ApplySetting()
    local frame = self.frame
    if not frame then return end
    if IsOn() then
        for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
        frame.sampleElapsed = 0
        frame:SetScript("OnUpdate", OnUpdate)
    else
        if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
        frame:SetScript("OnUpdate", nil)
    end
end

-------------------------------------------------------------------------------
-- /qrdata
-------------------------------------------------------------------------------

function DataCollection:PrintStatus()
    local L = QR.L
    QR:Print(IsOn() and L["DATA_COLLECTION_ON"] or L["DATA_COLLECTION_OFF"])
    local c = self:Counts()
    QR:Print(string_format(L["DATA_COLLECTION_COUNTS"], c[1], c[2], c[3], c[4], c[5], c[6]))
end

SLASH_QRDATA1 = "/qrdata"
SlashCmdList["QRDATA"] = function(msg)
    local cmd = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    local L = QR.L
    if not QR.db then return end
    if cmd == "on" then
        DataCollection:SetEnabled(true)
        QR:Print(L["DATA_COLLECTION_ON"])
    elseif cmd == "off" then
        DataCollection:SetEnabled(false)
        QR:Print(L["DATA_COLLECTION_OFF"])
    elseif cmd == "clear" then
        DataCollection:Clear()
        QR:Print(L["DATA_COLLECTION_CLEARED"])
    else
        DataCollection:PrintStatus()
    end
end
