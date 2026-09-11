-- ZoneSurvey.lua
-- Records what the client says about each map the player stands on, so the
-- questions the exported tables cannot answer can be settled by travelling.
--
-- The wago.tools exports give map geometry and taxi data, but not which map
-- the client actually places a player on, nor whether the addon's own tables
-- know that map. Both are visible from inside the game and nowhere else, and
-- `/qrverifymap` answers them one map at a time by hand. This does it on every
-- zone change and keeps the answers in SavedVariables.
--
-- One record per map, so a lap of the world costs a bounded amount of space
-- rather than one entry per doorway. Revisits update the record and bump a
-- counter instead of appending.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, pcall, tostring, tonumber, type =
    pairs, ipairs, pcall, tostring, tonumber, type
local string_format = string.format
local math_floor, math_min, math_huge = math.floor, math.min, math.huge
local table_concat, table_sort = table.concat, table.sort
local date, GetTime = date, GetTime

QR.ZoneSurvey = {}
local ZoneSurvey = QR.ZoneSurvey

-- Stop adding new maps at the cap; revisits preserve the existing evidence.
local MAX_RECORDS = 3000

-- How often the player's position is sampled while the survey is on.
--
-- Sampling is a fallback when the loading-screen event cannot read a position.
-- Frame delays, movement speed and loading order prevent a fixed yard accuracy.
local SAMPLE_INTERVAL = 0.5
local MAX_SAMPLE_AGE = 2

-- Bucket both endpoints. Different arrivals from the same departure location
-- must remain separate observations. Bucket size is map-relative, not yards.
local ENDPOINT_BUCKETS = 200

-- Per map pair. A player who uses one portal a hundred times writes one entry;
-- this bounds the case where the crossing is a teleport spell cast from
-- wherever the player happened to stand, which has no fixed departure point.
local MAX_ENDPOINTS = 6
local MAX_ORIGINS = 64
-- Aggregate budgets matter more than multiplying the individual limits:
-- 3,000 * 64 * 6 endpoint records would be excessive diagnostic memory.
local MAX_TOTAL_ORIGINS = 6000
local MAX_TOTAL_ENDPOINTS = 6000
local MAX_COUNTER = 1000000000
local countedStore, totalOrigins, totalEndpoints = nil, 0, 0
local Sanitize

local function IsFinite(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -math_huge and value < math_huge
end

local function IsMapID(value)
    return IsFinite(value) and value > 0 and value <= 10000000 and value == math_floor(value)
end

local function IsCoordinate(value)
    return IsFinite(value) and value >= 0 and value <= 1
end

local function Counter(value)
    if issecretvalue and issecretvalue(value) then return 0 end
    local number = tonumber(value)
    return IsFinite(number) and number >= 0 and math_min(math_floor(number), MAX_COUNTER) or 0
end

local function Increment(value)
    return math_min(Counter(value) + 1, MAX_COUNTER)
end

local function Scalar(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if IsFinite(value) or type(value) == "boolean"
        or (type(value) == "string" and #value <= 256) then return value end
    return nil
end

local function Endpoint(fromX, fromY, toX, toY, count)
    return {
        fromX = tonumber(string_format("%.4f", fromX)),
        fromY = tonumber(string_format("%.4f", fromY)),
        toX = tonumber(string_format("%.4f", toX)),
        toY = tonumber(string_format("%.4f", toY)),
        count = Counter(count),
    }
end

local function EndpointKey(endpoint)
    return string_format("%d:%d:%d:%d",
        math_floor(endpoint.fromX * ENDPOINT_BUCKETS), math_floor(endpoint.fromY * ENDPOINT_BUCKETS),
        math_floor(endpoint.toX * ENDPOINT_BUCKETS), math_floor(endpoint.toY * ENDPOINT_BUCKETS))
end

local function CountAdjacent(mapID)
    local adj = QR.ZoneAdjacencies and QR.ZoneAdjacencies[mapID]
    if not adj then return nil end
    local n = 0
    for _ in pairs(adj) do n = n + 1 end
    return n
end

local function CountGraphNodes(mapID)
    local graph = QR.PathCalculator and QR.PathCalculator.graph
    if not graph then return nil end
    local n = 0
    for _, data in pairs(graph.nodes or {}) do
        if data.mapID == mapID then n = n + 1 end
    end
    return n
end

local function RecordCount(store)
    local n = 0
    for _ in pairs(store) do n = n + 1 end
    return n
end

local function GetStore()
    local store = QR.db.zoneSurvey
    if type(store) ~= "table" or store ~= countedStore then
        store = Sanitize(store)
        QR.db.zoneSurvey = store
    end
    return store
end

-- The map the last capture recorded, and whether a loading screen happened
-- since. Together they say how the player got from one to the other.
local lastMapID = nil
local loadedSince = false
local loadingDeparture, loadingArrival

-- The last sample taken, and the last one taken on a DIFFERENT map. Two are
-- kept rather than one because the departure point has to be found by map, not
-- by time.
--
-- The first attempt copied the live sample when PLAYER_ENTERING_WORLD arrived,
-- on the assumption that OnUpdate could not have run yet and the copy was
-- therefore still the point the player walked into. Measured against a real
-- session that is false: of 30 loading-screen crossings, 29 had a copy that
-- already described the ARRIVAL, and the departure-map check below threw them
-- away. One survived, presumably on timing jitter.
--
-- Keeping the previous map's last sample makes the lookup independent of when
-- the sampler resumes. Whichever of the two was taken on the map the player
-- left is the departure point, and if neither was, nothing is recorded.
local lastPosition = nil
local previousMapPosition = nil

--- Read where the player is, or nil when the client cannot say.
local function ReadPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not IsMapID(mapID) then return nil end
    local pos
    ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or (issecretvalue and issecretvalue(pos)) then return nil end
    if not pos then return nil end
    local x, y
    ok, x, y = pcall(function()
        if pos.GetXY then return pos:GetXY() end
        return pos.x, pos.y
    end)
    if not ok or not IsCoordinate(x) or not IsCoordinate(y) then return nil end
    return { mapID = mapID, x = x, y = y, sampledAt = GetTime() }
end

--- Take one position sample. Called on a timer while the survey is on.
-- A sample on a new map pushes the previous map's last sample aside rather than
-- discarding it: that displaced one is the departure point of whatever crossing
-- just happened.
function ZoneSurvey:SamplePosition()
    if not (QR.db and QR.db.zoneSurveyEnabled) or InCombatLockdown() then
        self:ForgetArrivalState()
        return nil
    end
    local position = ReadPosition()
    if not position then return nil end
    if lastPosition and lastPosition.mapID ~= position.mapID then
        previousMapPosition = lastPosition
    end
    lastPosition = position
    if loadedSince and not loadingArrival and position.mapID ~= lastMapID then
        loadingArrival = position
    end
    return position
end

--- The last position sampled on a given map, if it is still one of the two.
local function PositionOnMap(mapID)
    for _, position in pairs({ lastPosition, previousMapPosition }) do
        local age = GetTime() - position.sampledAt
        if position.mapID == mapID and age >= 0 and age <= MAX_SAMPLE_AGE then return position end
    end
    return nil
end

--- Note that a loading screen happened, so the next transition is not a walk.
function ZoneSurvey:NoteLoadingScreen()
    if not loadedSince then
        loadingDeparture = PositionOnMap(lastMapID)
        loadingArrival = nil
    end
    loadedSince = true
end

--- Freeze departure before loading replaces the map and position APIs.
function ZoneSurvey:BeginLoadingScreen()
    if loadedSince then
        -- Two loads before a capture are not evidence of a direct crossing.
        self:ForgetArrivalState()
    end
    local position = ReadPosition()
    if position and position.mapID == lastMapID then
        loadingDeparture = position
    else
        loadingDeparture = PositionOnMap(lastMapID)
    end
    loadedSince = true
    loadingArrival = nil
    if self.frame then
        self.frame.captureGeneration = (self.frame.captureGeneration or 0) + 1
        self.frame.pending = false
    end
end

--- Forget where the player came from and how they got there.
-- Used when the survey is switched off and by Clear, so that whatever happens
-- while nothing is being recorded cannot become the first crossing afterwards.
function ZoneSurvey:ForgetArrivalState()
    lastMapID = nil
    loadedSince = false
    lastPosition = nil
    previousMapPosition = nil
    loadingDeparture, loadingArrival = nil, nil
    if self.frame then
        self.frame.captureGeneration = (self.frame.captureGeneration or 0) + 1
        self.frame.pending = false
        self.frame.sampleElapsed = 0
    end
end

--- Remember both ends of one doorway.
--
-- The destination of a portal is not in any exported client table. It is not
-- that wago.tools happens not to carry it: SpellTargetPosition is a server-side
-- table, so no client export ever will. Walking through the doorway is the only
-- way to see it, and this is what turns that walk into data.
--
-- Loading screens also occur for spells, instances and scripted transport.
-- Repetition supports an endpoint candidate; it does not identify a portal.
local function RecordEndpoints(entry, from, to)
    -- Both ends or nothing. A doorway with one end known is not a doorway, and
    -- the client can decline to give a position at either moment.
    if not IsCoordinate(from.x) or not IsCoordinate(from.y) then return end
    if not IsCoordinate(to.x) or not IsCoordinate(to.y) then return end

    if type(entry.endpoints) ~= "table" then entry.endpoints = {} end
    -- Bucket the same rounded coordinates that survive a reload. Bucketing
    -- raw .00499 and then saving .0050 otherwise changes identity on load.
    local endpoint = Endpoint(from.x, from.y, to.x, to.y, 1)
    local key = EndpointKey(endpoint)
    local seen = entry.endpoints[key]
    if type(seen) == "table" then
        seen.count = Increment(seen.count)
        return
    end

    local n = 0
    for _ in pairs(entry.endpoints) do n = n + 1 end
    if n >= MAX_ENDPOINTS or totalEndpoints >= MAX_TOTAL_ENDPOINTS then return end

    entry.endpoints[key] = endpoint
    totalEndpoints = totalEndpoints + 1
end

--- Record how the player arrived at a map.
-- Zone boxes are rectangles and overlap across a whole continent, so geometry
-- cannot say which zones border each other -- measured against the current
-- tables it claims 148 pairs that are not neighbours, Durotar to Mulgore among
-- them. A player crossing from one zone to the next can.
--
-- The legacy `walked` field means no loading screen was observed. It can also
-- represent a taxi or scripted flight; neither category proves adjacency.
local function RecordArrival(store, mapID)
    local from = lastMapID
    lastMapID = mapID
    local hadLoadingScreen = loadedSince
    loadedSince = false
    local departure, arrival = loadingDeparture, loadingArrival
    loadingDeparture, loadingArrival = nil, nil

    if not from or from == mapID then return end
    if hadLoadingScreen and arrival and arrival.mapID ~= mapID then return end
    local record = store[mapID]
    if not record then return end

    -- Everything below comes back from SavedVariables, a file on disk that
    -- survives version changes and hand-editing, so nothing about its shape is
    -- given. Guarding only the counters was half a job: a non-table entry threw
    -- on the first index. A throw here is caught by the pcall around Capture,
    -- so the addon survives -- what is lost is that zone's record.
    --
    -- tonumber rather than a plain nil test, so "3" from a hand-edited file
    -- counts and "corrupt" restarts at zero instead of throwing on the add.
    if type(record.from) ~= "table" then record.from = {} end
    local entry = record.from[from]
    if not entry then
        if totalOrigins >= MAX_TOTAL_ORIGINS or RecordCount(record.from) >= MAX_ORIGINS then return end
        totalOrigins = totalOrigins + 1
    end
    if type(entry) ~= "table" then entry = {} end
    entry.walked = Counter(entry.walked)
    entry.loaded = Counter(entry.loaded)
    if hadLoadingScreen then
        entry.loaded = Increment(entry.loaded)
        -- Endpoints are observations of loading-screen transport only.
        if departure and departure.mapID == from then
            RecordEndpoints(entry, departure, arrival and arrival.mapID == mapID and arrival
                or { mapID = mapID, x = record.x, y = record.y })
        end
    else
        entry.walked = Increment(entry.walked)
    end
    record.from[from] = entry
end

--- Capture the current map, if there is one to capture.
-- @return number|nil The mapID recorded, or nil when nothing was recorded --
--   the survey is switched off, the client has no map for the player, or the
--   record cap has been reached.
function ZoneSurvey:Capture()
    if not (QR.db and QR.db.zoneSurveyEnabled) or InCombatLockdown() then
        self:ForgetArrivalState()
        return nil
    end
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not IsMapID(mapID) then return nil end

    local store = GetStore()

    local existing = store[mapID]
    if not existing and RecordCount(store) >= MAX_RECORDS then
        QR:Debug("ZoneSurvey: record cap reached, not adding map " .. tostring(mapID))
        self:ForgetArrivalState()
        return nil
    end

    local info
    if C_Map.GetMapInfo then
        ok, info = pcall(C_Map.GetMapInfo, mapID)
        if not ok or (issecretvalue and issecretvalue(info)) or type(info) ~= "table" then info = nil end
    end
    local x, y
    local position = ReadPosition()
    if position and position.mapID == mapID then x, y = position.x, position.y end

    local flight = QR.FlightPoints and QR.FlightPoints[mapID]

    store[mapID] = {
        name = info and Scalar(info.name) or nil,
        mapType = info and Scalar(info.mapType) or nil,
        parent = info and Scalar(info.parentMapID) or nil,
        -- Rounded because four decimals is the precision the data files use,
        -- and a full float per visit is noise in a diff.
        x = x and tonumber(string_format("%.4f", x)) or nil,
        y = y and tonumber(string_format("%.4f", y)) or nil,
        continent = QR.GetContinentForZone and QR.GetContinentForZone(mapID) or nil,
        adjacent = CountAdjacent(mapID),
        graphNodes = CountGraphNodes(mapID),
        flightPoint = flight and (flight.node or true) or nil,
        flightAlt = flight and flight.alt and (flight.alt.node or true) or nil,
        visits = Increment(type(existing) == "table" and existing.visits),
        -- Carried forward, because the record is rebuilt rather than patched
        -- and the arrivals are the part that accumulates across a session.
        -- Only a table survives the carry-forward. Sanitize clears the store
        -- on load, but a record can also be reached before any capture has
        -- touched it, so the shape is re-checked where it is copied.
        from = (type(existing) == "table" and type(existing.from) == "table")
            and existing.from or nil,
        seen = date("%Y-%m-%d %H:%M:%S"),
    }
    RecordArrival(store, mapID)
    return mapID
end

function ZoneSurvey:Clear()
    if QR.db then
        QR.db.zoneSurvey = {}
        countedStore, totalOrigins, totalEndpoints = QR.db.zoneSurvey, 0, 0
    end
    -- Also forget where the player came from, so the first capture after a
    -- clear does not invent an arrival from a map no longer on record.
    self:ForgetArrivalState()
end

function ZoneSurvey:Count()
    if not QR.db then return 0 end
    return RecordCount(GetStore())
end

--- Render the survey as markdown for the copyable window.
function ZoneSurvey:Render()
    local lines = {
        "## QuickRoute Zone Survey",
        "",
        string_format("| Records | %d |", self:Count()),
        "",
        "| map | name | type | parent | x | y | continent | adj | nodes | flight | visits |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    }
    local ids = {}
    for mapID in pairs((QR.db and QR.db.zoneSurvey) or {}) do
        ids[#ids + 1] = mapID
    end
    table_sort(ids)
    for _, mapID in ipairs(ids) do
        local r = QR.db.zoneSurvey[mapID]
        lines[#lines + 1] = string_format(
            "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d |",
            mapID, tostring(r.name or "?"), tostring(r.mapType or "?"),
            tostring(r.parent or "-"), tostring(r.x or "-"), tostring(r.y or "-"),
            tostring(r.continent or "-"), tostring(r.adjacent or "-"),
            tostring(r.graphNodes or "-"), tostring(r.flightPoint or "-"),
            r.visits or 0)
    end

    -- The legacy `walked` counter records absence of an observed load only.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Observed crossings"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Walked means no loading screen was observed; it may include taxi or scripted flights. These counts do not prove that zones border each other."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| into | from | walked | loaded |"
    lines[#lines + 1] = "|---|---|---|---|"
    local any = false
    for _, mapID in ipairs(ids) do
        local r = QR.db.zoneSurvey[mapID]
        local froms = {}
        for f in pairs(r.from or {}) do froms[#froms + 1] = f end
        table_sort(froms)
        for _, f in ipairs(froms) do
            local e = r.from[f]
            lines[#lines + 1] = string_format("| %d | %d | %d | %d |",
                mapID, f, e.walked or 0, e.loaded or 0)
            any = true
        end
    end
    if not any then
        lines[#lines + 1] = "| - | - | - | - |"
    end

    -- Loading-screen endpoint candidates require transport identification
    -- before anyone promotes their coordinates into the routing data.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Observed doorways (unverified transport)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string_format(
        "Samples every %.1fs; endpoint buckets are 1/%d of each map. Loading screens and repeat counts do not prove a portal exists.",
        SAMPLE_INTERVAL, ENDPOINT_BUCKETS)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| from map | at x | at y | into map | at x | at y | times |"
    lines[#lines + 1] = "|---|---|---|---|---|---|---|"
    local anyDoor = false
    for _, mapID in ipairs(ids) do
        local r = QR.db.zoneSurvey[mapID]
        local froms = {}
        for f in pairs(r.from or {}) do froms[#froms + 1] = f end
        table_sort(froms)
        for _, f in ipairs(froms) do
            local keys = {}
            for k in pairs(r.from[f].endpoints or {}) do keys[#keys + 1] = k end
            table_sort(keys)
            for _, k in ipairs(keys) do
                local e = r.from[f].endpoints[k]
                lines[#lines + 1] = string_format("| %d | %s | %s | %d | %s | %s | %d |",
                    f, tostring(e.fromX), tostring(e.fromY),
                    mapID, tostring(e.toX), tostring(e.toY), e.count or 0)
                anyDoor = true
            end
        end
    end
    if not anyDoor then
        lines[#lines + 1] = "| - | - | - | - | - | - | - |"
    end

    return table_concat(lines, "\n")
end

--- Rebuild the saved store from bounded, validated scalar records. Rebuilding
-- also discards unknown nested tables and migrates departure-only endpoint keys.
Sanitize = function(store)
    if type(store) ~= "table" then store = {} end
    local clean, dropped, records = {}, 0, 0
    local allOrigins, allEndpoints = 0, 0
    for mapID, record in pairs(store) do
        if not IsMapID(mapID) or type(record) ~= "table" or records >= MAX_RECORDS then
            dropped = dropped + 1
        else
            local saved = { visits = Counter(record.visits) }
            for _, field in ipairs({ "name", "mapType", "parent", "continent", "adjacent",
                "graphNodes", "flightPoint", "flightAlt", "seen" }) do
                saved[field] = Scalar(record[field])
            end
            if IsCoordinate(record.x) then saved.x = record.x end
            if IsCoordinate(record.y) then saved.y = record.y end
            if type(record.from) == "table" then
                saved.from = {}
                local origins = 0
                for origin, entry in pairs(record.from) do
                    if not IsMapID(origin) or type(entry) ~= "table" or origins >= MAX_ORIGINS
                        or allOrigins >= MAX_TOTAL_ORIGINS then
                        dropped = dropped + 1
                    else
                        local arrival = { walked = Counter(entry.walked), loaded = Counter(entry.loaded) }
                        if type(entry.endpoints) == "table" then
                            arrival.endpoints = {}
                            local endpoints = 0
                            for _, door in pairs(entry.endpoints) do
                                if type(door) ~= "table" or not IsCoordinate(door.fromX)
                                    or not IsCoordinate(door.fromY) or not IsCoordinate(door.toX)
                                    or not IsCoordinate(door.toY) then
                                    dropped = dropped + 1
                                else
                                    local endpoint = Endpoint(door.fromX, door.fromY, door.toX, door.toY, door.count)
                                    local key = EndpointKey(endpoint)
                                    local prior = arrival.endpoints[key]
                                    if prior then
                                        prior.count = Counter(prior.count + Counter(door.count))
                                    elseif endpoints < MAX_ENDPOINTS and allEndpoints < MAX_TOTAL_ENDPOINTS then
                                        arrival.endpoints[key] = endpoint
                                        endpoints = endpoints + 1
                                        allEndpoints = allEndpoints + 1
                                    else
                                        dropped = dropped + 1
                                    end
                                end
                            end
                        end
                        saved.from[origin] = arrival
                        origins = origins + 1
                        allOrigins = allOrigins + 1
                    end
                end
            elseif record.from ~= nil then
                dropped = dropped + 1
            end
            clean[mapID] = saved
            records = records + 1
        end
    end
    countedStore, totalOrigins, totalEndpoints = clean, allOrigins, allEndpoints
    return clean, dropped
end

function ZoneSurvey:Initialize()
    if QR.db then
        if QR.db.zoneSurveyEnabled == nil then
            QR.db.zoneSurveyEnabled = true
        end
        local store, dropped = Sanitize(QR.db.zoneSurvey or {})
        QR.db.zoneSurvey = store
        if dropped > 0 then
            QR:Debug(string_format("ZoneSurvey: dropped %d malformed record(s) on load", dropped))
        end
    end

    self:ForgetArrivalState()
    if self.frame then return end
    local frame = CreateFrame("Frame")
    frame.sampleElapsed = 0
    frame.captureGeneration = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not (QR.db and QR.db.zoneSurveyEnabled) or InCombatLockdown() then
            if lastMapID or lastPosition or loadedSince then ZoneSurvey:ForgetArrivalState() end
            return
        end
        self.sampleElapsed = self.sampleElapsed + elapsed
        if self.sampleElapsed < SAMPLE_INTERVAL then return end
        self.sampleElapsed = 0
        ZoneSurvey:SamplePosition()
    end)
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("LOADING_SCREEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(_, event)
        if not (QR.db and QR.db.zoneSurveyEnabled) or InCombatLockdown()
            or event == "PLAYER_REGEN_DISABLED" then
            ZoneSurvey:ForgetArrivalState()
            return
        end
        if event == "LOADING_SCREEN_ENABLED" then
            ZoneSurvey:BeginLoadingScreen()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            ZoneSurvey:NoteLoadingScreen()
            -- Preserve the earliest arrival available; a capture 1.5 seconds
            -- later may already describe where the player walked after landing.
            ZoneSurvey:SamplePosition()
        end
        if frame.pending then return end
        frame.pending = true
        local generation = frame.captureGeneration
        C_Timer.After(1.5, function()
            if generation ~= frame.captureGeneration then return end
            frame.pending = false
            if InCombatLockdown() then
                ZoneSurvey:ForgetArrivalState()
                return
            end
            local ok, err = pcall(function() return ZoneSurvey:Capture() end)
            if not ok then
                ZoneSurvey:ForgetArrivalState()
                QR:Debug("ZoneSurvey capture failed: " .. tostring(err))
            end
        end)
    end)
    self.frame = frame
    QR:Debug("ZoneSurvey initialized")
end

SLASH_QRSURVEY1 = "/qrsurvey"
SlashCmdList["QRSURVEY"] = function(msg)
    local cmd = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "clear" then
        ZoneSurvey:Clear()
        QR:Print("Zone survey cleared.")
    elseif cmd == "off" then
        if QR.db then QR.db.zoneSurveyEnabled = false end
        -- Immediately, not at the next zone change: switching off and back on
        -- without moving would otherwise keep the stale map.
        ZoneSurvey:ForgetArrivalState()
        QR:Print("Zone survey off.")
    elseif cmd == "on" then
        if QR.db then QR.db.zoneSurveyEnabled = true end
        QR:Print("Zone survey on.")
    elseif cmd == "here" then
        local mapID = ZoneSurvey:Capture()
        QR:Print(mapID and ("Recorded map " .. mapID) or "Nothing recorded.")
    else
        local report = ZoneSurvey:Render()
        QR:Print(string_format("Zone survey: %d record(s). /qrsurvey clear|on|off|here",
            ZoneSurvey:Count()))
        -- Same copy window the other diagnostics use.
        if QR.UI and QR.UI.CopyDebugToClipboard then
            QR.UI:CopyDebugToClipboard()
            if QR.UI.copyFrame and QR.UI.copyFrame.editBox then
                QR.UI.copyFrame.editBox:SetText(report)
                QR.UI.copyFrame.editBox:HighlightText()
            end
        end
    end
end
