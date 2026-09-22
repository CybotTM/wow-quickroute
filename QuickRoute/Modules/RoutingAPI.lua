-- RoutingAPI.lua
-- A versioned routing contract for other addons.
--
-- QuickRoute is one of several addons a player runs that put an arrow on the
-- screen. A consumer that wants a route should not have to reach into
-- PathCalculator's singleton state to get one, and asking for a route must
-- never take over the player's pin or start travelling.
--
-- The contract is therefore narrow on purpose: ask for a route, get a detached
-- answer or a named failure, and cancel what you asked for. Anything that acts
-- on the player stays with the consumer.
local ADDON_NAME, QR = ...
local type, pairs, ipairs = type, pairs, ipairs

local API = { VERSION = 2 }
QR.RoutingAPI = API

-- Handles this session issued, keyed by an opaque token. A handle is only
-- honoured when it came from here: the generation is a small consecutive
-- integer, so accepting any table carrying one let an addon cancel whatever
-- calculation happened to be in flight by guessing.
local issued = setmetatable({}, { __mode = "k" })

-- Which requests replace each other. A request that names an owner replaces
-- the earlier requests of that owner and no others; a request without one
-- replaces nothing and ends only by its answer or by Cancel. Before version 2
-- every addon shared one key, so one addon's request cancelled another's.
-- The two prefixes keep an owner's name from ever matching an anonymous key.
local anonymousRequests = 0
local function OwnerKey(owner)
    return QR.ROUTE_CONSUMER.API .. ":owner:" .. owner
end
local function ConsumerKey(owner)
    if owner then return OwnerKey(owner) end
    anonymousRequests = anonymousRequests + 1
    return QR.ROUTE_CONSUMER.API .. ":request:" .. anonymousRequests
end

-- How many contract requests may wait for the calculator at once. One
-- calculation runs at a time, first come first served, so every waiting request
-- delays the player's own route behind it. With one shared key there was never
-- more than one; with a key per request, an addon that asks on every update
-- without an owner would queue without end. A request past the limit is refused
-- at once, so nobody else's request is touched.
API.MAX_PENDING = 8

-- Count the contract's live requests, queued or running, and whether one of
-- them belongs to `key`. Read from the calculator itself, so the count cannot
-- drift from what is actually waiting.
local function PendingRequests(key)
    local pc = QR.PathCalculator
    local prefix = QR.ROUTE_CONSUMER.API .. ":"
    local count, hasKey = 0, false
    local function note(request)
        if request.superseded or type(request.consumer) ~= "string" then return end
        if request.consumer:sub(1, #prefix) ~= prefix then return end
        count = count + 1
        if request.consumer == key then hasKey = true end
    end
    for _, request in ipairs(pc.asyncQueue or {}) do note(request) end
    if pc.asyncRunning then note(pc.asyncRunning) end
    return count, hasKey
end

--- Tell one consumer that its request was replaced.
-- A superseded request's callback is dropped without a word, and a consumer
-- that hears nothing cannot tell a slow route from a dead one. The calculator
-- calls this through the request's `onSuperseded`: when the same owner asks
-- again while the request is queued or running, and when CancelAsync drops
-- every request. Idempotent: a handle is notified once.
local function NotifySuperseded(handle)
    if handle.cancelled then return end
    handle.cancelled = true
    local notify = handle.callback
    local function tell()
        -- Re-checked at fire time, as publish does. A consumer that cancels
        -- between the supersede and this tick was still called, which is the
        -- one thing Cancel documents will not happen.
        if handle.withdrawn then return end
        notify(nil, { reason = "superseded", retryable = false })
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, tell) else tell() end
end

-- Every result is a fresh deep copy. A consumer can hold it, read it and change
-- its own copy; nothing it does reaches QuickRoute's state or another
-- consumer's copy.
--
-- A read-only proxy was the obvious alternative and does not work here: the
-- client runs Lua 5.1, where __len and __pairs are not honoured for tables, so
-- a proxied step list would report a length of zero to every consumer that
-- iterates it.
local function Detached(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, field in pairs(value) do copy[key] = Detached(field) end
    return copy
end

-- Only the fields the contract names travel to a consumer. Adding a field here
-- is a contract change; leaking the whole internal step table would make every
-- internal rename one too.
local STEP_FIELDS = {
    "type", "action", "time", "from", "to",
    "navMapID", "navX", "navY", "navTitle",
    "destMapID", "destX", "destY",
    "collapsed", "collapsedCount", "mandatoryAnchor",
    "destApproximate", "destDefault",
}

local function PublicSteps(steps)
    local out = {}
    for index, step in ipairs(steps or {}) do
        local copy = {}
        for _, field in ipairs(STEP_FIELDS) do copy[field] = step[field] end
        if type(step.waypoints) == "table" then
            local anchors = {}
            for anchorIndex, anchor in ipairs(step.waypoints) do
                anchors[anchorIndex] = {
                    mapID = anchor.mapID, x = anchor.x, y = anchor.y,
                    title = anchor.title, mandatory = anchor.mandatory,
                }
            end
            copy.waypoints = anchors
        end
        out[index] = copy
    end
    return out
end

-- What the estimate rests on. A consumer comparing two backends needs to know
-- that a leg on another map was priced from a zone model rather than measured,
-- and that a flight time is a horizontal-distance heuristic.
local function Assumptions(steps)
    local maps, unknown, flight = {}, {}, false
    -- A hearthstone bound to an inn this character has not been observed using
    -- lands where a catalogue says that inn is. The step carries the flag; this
    -- lifts it to where a consumer comparing two backends will see it.
    local approximate = {}
    for _, step in ipairs(steps or {}) do
        local mapID = step.navMapID or step.destMapID
        if mapID and not maps[mapID] then
            maps[mapID] = true
            if QR.TravelTime and QR.TravelTime.RemoteFlightEligibility
                and QR.TravelTime:RemoteFlightEligibility(mapID) == "unknown" then
                unknown[#unknown + 1] = mapID
            end
        end
        if step.type == "flight" then flight = true end
        if step.destApproximate then
            approximate[#approximate + 1] = { from = step.from, to = step.to,
                mapID = step.destMapID, defaulted = step.destDefault or nil }
        end
    end
    return {
        movementUnknownMaps = unknown,
        taxiTimeIsHeuristic = flight,
        approximateLandings = approximate,
        loadingScreenSeconds = QR.db and QR.db.loadingScreenTime or nil,
    }
end

--- The contract version this build implements.
-- @return number
function API:GetVersion()
    return self.VERSION
end

--- Ask for a route.
-- Calculation is spread across frames in budgeted slices. The callback receives either
-- a detached result or nil plus a failure table naming the reason.
-- Nothing here sets a waypoint, changes the player's pin or starts travel.
-- @param request table {mapID, x, y, title, role, owner}. `owner` is a
--   non-empty string, usually the calling addon's name. A new request with an
--   owner replaces that owner's earlier request; without one, requests run
--   independently.
-- @param callback function Receives (result, failure)
-- @return table|nil A handle for Cancel, or nil plus a failure: `invalid_request`
--   for a bad request, `busy` (retryable) when MAX_PENDING requests are waiting
function API:CalculateRoute(request, callback)
    if type(request) ~= "table" or type(callback) ~= "function" then
        return nil, { reason = "invalid_request" }
    end
    local mapID, x, y = request.mapID, request.x, request.y
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil, { reason = "invalid_request" }
    end
    local title = type(request.title) == "string" and request.title or nil
    local owner = request.owner
    if owner ~= nil and (type(owner) ~= "string" or owner == "") then
        return nil, { reason = "invalid_request" }
    end
    -- What the target is, not only where. A consumer that asks for a quest
    -- location has to be able to tell an active objective from a catalogued
    -- one, and arrival never completes either.
    local role = type(request.role) == "string" and request.role or QR.TargetIdentity.ROLE.REFERENCE
    -- An owner that already has a request waiting replaces it, so the queue
    -- does not grow and the request is always taken.
    local pending, replaces = PendingRequests(owner and OwnerKey(owner))
    if not replaces and pending >= API.MAX_PENDING then
        return nil, { reason = "busy", retryable = true }
    end
    local handle = { cancelled = false }
    issued[handle] = true

    -- A second request of the same owner supersedes the first inside
    -- PathCalculator, so the first consumer would simply never hear again.
    -- Silence is not one of the two answers this contract promises, so the
    -- superseded request is told.
    handle.callback = callback

    local function publish(route, failure)
        -- `cancelled` alone: Cancel sets both, and supersession sets only
        -- `cancelled`, so testing `withdrawn` here could never change anything.
        if handle.cancelled then return end
        if not route then
            callback(nil, Detached(failure or { reason = "no_connection" }))
            return
        end
        callback(Detached({
            apiVersion = API.VERSION,
            target = {
                mapID = mapID, x = x, y = y, title = title,
                role = role,
                roleLabel = QR.TargetIdentity:Describe(role),
                arrivalCompletes = QR.TargetIdentity:ArrivalCompletes(),
            },
            totalTime = route.totalTime,
            steps = PublicSteps(route.steps),
            assumptions = Assumptions(route.steps),
        }))
    end

    -- The consumer key is what keeps QuickRoute's own route panel, its dungeon
    -- offer and each calling addon out of each other's way: they queue rather
    -- than destroy each other. Each request's supersession notice is bound to
    -- its own handle, so the notice the calculator sends for an earlier request
    -- reaches that request and never the one being made.
    handle.generation = QR.PathCalculator:CalculatePathAsync(mapID, x, y, title, function(route, failure)
        -- A short route finishes inside the first budget, so without this the
        -- callback could run before CalculateRoute returned and the consumer
        -- would not yet hold the handle it is expected to cancel with.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() publish(route, failure) end)
        else
            publish(route, failure)
        end
    end, {
        consumer = ConsumerKey(owner),
        onSuperseded = function() NotifySuperseded(handle) end,
    })
    return handle
end

--- Withdraw a request. The callback is not called afterwards.
-- @param handle table The handle CalculateRoute returned
-- @return boolean True when the handle was one this session issued
function API:Cancel(handle)
    if type(handle) ~= "table" or not issued[handle] then return false end
    handle.cancelled = true
    -- Distinct from `cancelled`, which supersession also sets: this says the
    -- consumer withdrew, and nothing may call it again.
    handle.withdrawn = true
    -- Exactly this request. Cancelling everything took the dungeon offer's
    -- search and the route panel's with it.
    QR.PathCalculator:CancelRequest(handle.generation)
    return true
end

--- Refuse one connection for one destination, as the player's "Cannot use" does.
-- The destination is required. Without it the refusal was stamped "applies
-- everywhere" and closed the connection for the player's own routes too.
-- @param destination table {mapID, x, y}
-- @return boolean False when the destination is missing
function API:RejectStep(from, to, destination)
    if type(destination) ~= "table" or type(destination.mapID) ~= "number" then return false end
    return QR.PathCalculator:ExcludeEdge(from, to, destination)
end

--- Take back a refusal.
function API:AcceptStep(from, to)
    return QR.PathCalculator:IncludeEdge(from, to)
end

-- The name other addons look for. Kept deliberately small: everything that acts
-- on the player stays on QuickRoute's side of the line.
_G.QuickRouteAPI = API
