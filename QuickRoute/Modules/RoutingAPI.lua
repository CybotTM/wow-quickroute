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

local API = { VERSION = 1 }
QR.RoutingAPI = API

-- Handles this session issued, keyed by an opaque token. A handle is only
-- honoured when it came from here: the generation is a small consecutive
-- integer, so accepting any table carrying one let an addon cancel whatever
-- calculation happened to be in flight by guessing.
local issued = setmetatable({}, { __mode = "k" })
local inFlight = {}

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
-- Calculation spends a measured budget per frame. The callback receives either
-- a detached result or nil plus a failure table naming the reason.
-- Nothing here sets a waypoint, changes the player's pin or starts travel.
-- @param request table {mapID, x, y, title}
-- @param callback function Receives (result, failure)
-- @return table|nil A handle for Cancel, or nil plus a failure for a bad request
function API:CalculateRoute(request, callback)
    if type(request) ~= "table" or type(callback) ~= "function" then
        return nil, { reason = "invalid_request" }
    end
    local mapID, x, y = request.mapID, request.x, request.y
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil, { reason = "invalid_request" }
    end
    local title = type(request.title) == "string" and request.title or nil
    -- What the target is, not only where. A consumer that asks for a quest
    -- location has to be able to tell an active objective from a catalogued
    -- one, and arrival never completes either.
    local role = type(request.role) == "string" and request.role or QR.TargetIdentity.ROLE.REFERENCE
    local handle = { cancelled = false }
    issued[handle] = true

    -- A second request supersedes the first inside PathCalculator, so the first
    -- consumer would simply never hear again. Silence is not one of the two
    -- answers this contract promises, so the superseded request is told.
    handle.callback = callback

    local function publish(route, failure)
        -- `cancelled` alone: Cancel sets both, and supersession sets only
        -- `cancelled`, so testing `withdrawn` here could never change anything.
        if handle.cancelled then return end
        inFlight[1] = nil
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

    -- Registered after the calculator is asked, not before. The request below
    -- supersedes this contract's own earlier request and NotifySuperseded tells
    -- that consumer; with this handle already registered, it would have
    -- announced the new request as superseded by itself.
    --
    -- The consumer key is what keeps QuickRoute's own route panel, its dungeon
    -- offer and this contract out of each other's way: they queue rather than
    -- destroy each other, so a foreign addon's request is no longer cancelled
    -- because the player opened the route panel.
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
        consumer = QR.ROUTE_CONSUMER.API,
        onSuperseded = function() API:NotifySuperseded() end,
    })
    inFlight[1] = handle
    return handle
end

--- Tell the consumer in flight that its request was replaced.
-- A superseded request's callback is dropped without a word, and a consumer
-- that hears nothing cannot tell a slow route from a dead one. The calculator
-- calls this through the request's `onSuperseded`, which happens when this
-- contract is asked for a second route while the first is in flight, and when
-- something cancels every calculation. An internal calculation for the route
-- panel or the dungeon offer does not reach here: those carry their own
-- consumer key and supersede only their own requests. Idempotent: a handle is
-- notified once.
function API:NotifySuperseded()
    local previous = inFlight[1]
    if not previous or previous.cancelled then return false end
    previous.cancelled = true
    inFlight[1] = nil
    local notify = previous.callback
    if type(notify) ~= "function" then return true end
    local function tell()
        -- Re-checked at fire time, as publish does. A consumer that cancels
        -- between the supersede and this tick was still called, which is the
        -- one thing Cancel documents will not happen.
        if previous.withdrawn then return end
        notify(nil, { reason = "superseded", retryable = false })
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, tell) else tell() end
    return true
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
    if inFlight[1] == handle then inFlight[1] = nil end
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
