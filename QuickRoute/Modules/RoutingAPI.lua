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
    end
    return {
        movementUnknownMaps = unknown,
        taxiTimeIsHeuristic = flight,
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
    local handle = { cancelled = false }
    handle.generation = QR.PathCalculator:CalculatePathAsync(mapID, x, y, title, function(route, failure)
        if handle.cancelled then return end
        if not route then
            callback(nil, Detached(failure or { reason = "no_connection" }))
            return
        end
        callback(Detached({
            apiVersion = API.VERSION,
            target = { mapID = mapID, x = x, y = y, title = title },
            totalTime = route.totalTime,
            steps = PublicSteps(route.steps),
            assumptions = Assumptions(route.steps),
        }))
    end)
    return handle
end

--- Withdraw a request. The callback is not called afterwards.
-- @param handle table The handle CalculateRoute returned
-- @return boolean True when the handle was one this session issued
function API:Cancel(handle)
    if type(handle) ~= "table" or handle.generation == nil then return false end
    handle.cancelled = true
    if QR.PathCalculator.asyncGeneration == handle.generation then
        QR.PathCalculator:CancelAsync()
    end
    return true
end

--- Refuse one connection for this session, as the player's "Cannot use" does.
-- A consumer that learns a step is unusable can report it without QuickRoute
-- recording anything about the character.
function API:RejectStep(from, to)
    return QR.PathCalculator:ExcludeEdge(from, to)
end

--- Take back a refusal.
function API:AcceptStep(from, to)
    return QR.PathCalculator:IncludeEdge(from, to)
end

-- The name other addons look for. Kept deliberately small: everything that acts
-- on the player stays on QuickRoute's side of the line.
_G.QuickRouteAPI = API
