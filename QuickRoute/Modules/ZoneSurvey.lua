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
local math_floor = math.floor
local table_concat, table_sort = table.concat, table.sort
local date = date

QR.ZoneSurvey = {}
local ZoneSurvey = QR.ZoneSurvey

-- A full clear-out is better than an unbounded table in SavedVariables, and the
-- game has fewer maps than this. If it is ever hit, something is recording
-- instance floors in a loop and the cap is the signal.
local MAX_RECORDS = 3000

-- How often the player's position is sampled while the survey is on.
--
-- A doorway is recorded from the last sample taken BEFORE the loading screen,
-- so this interval is the error bar on where the doorway stands: at a run
-- speed of about 7 yards a second, half a second is roughly 3.5 yards. That is
-- far inside what the graph needs -- Portals.lua currently carries several
-- entries at the 0.50, 0.50 zone centre, which is wrong by half a zone.
local SAMPLE_INTERVAL = 0.5

-- Distinct doorways are told apart at 1/200 of the map, about 15-25 yards.
-- Deliberately coarser than the sample error above rather than finer: two
-- samples of one portal must not become two doorways. Two portals that really
-- do stand within one bucket merge instead, which is the safer failure -- a
-- merged pair is visible as one doorway with a high count, a split one looks
-- like two portals that do not exist.
local ENDPOINT_BUCKETS = 200

-- Per map pair. A player who uses one portal a hundred times writes one entry;
-- this bounds the case where the crossing is a teleport spell cast from
-- wherever the player happened to stand, which has no fixed departure point.
local MAX_ENDPOINTS = 6

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

-- The map the last capture recorded, and whether a loading screen happened
-- since. Together they say how the player got from one to the other.
local lastMapID = nil
local loadedSince = false

-- Where the player was standing, sampled while the world is loaded, and the
-- copy taken the moment a loading screen ended. The copy is the one that
-- matters: the sampler resumes at the destination and overwrites the live
-- value within half a second, while the capture that reads it is debounced by
-- a second and a half.
local lastPosition = nil
local departurePosition = nil

--- Read where the player is, or nil when the client cannot say.
local function ReadPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if type(mapID) ~= "number" then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos.x, pos.y
    if pos.GetXY then x, y = pos:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { mapID = mapID, x = x, y = y }
end

--- Take one position sample. Called on a timer while the survey is on.
function ZoneSurvey:SamplePosition()
    local position = ReadPosition()
    if position then lastPosition = position end
    return position
end

--- Note that a loading screen happened, so the next transition is not a walk.
--
-- This is also the only moment at which the far side of a doorway can still be
-- read. The player is already at the destination by the time anything else
-- runs, and OnUpdate does not fire while the loading screen is up, so the last
-- sample still describes the point the player walked into.
function ZoneSurvey:NoteLoadingScreen()
    loadedSince = true
    departurePosition = lastPosition
end

--- Forget where the player came from and how they got there.
-- Used when the survey is switched off and by Clear, so that whatever happens
-- while nothing is being recorded cannot become the first crossing afterwards.
function ZoneSurvey:ForgetArrivalState()
    lastMapID = nil
    loadedSince = false
    lastPosition = nil
    departurePosition = nil
end

--- Remember both ends of one doorway.
--
-- The destination of a portal is not in any exported client table. It is not
-- that wago.tools happens not to carry it: SpellTargetPosition is a server-side
-- table, so no client export ever will. Walking through the doorway is the only
-- way to see it, and this is what turns that walk into data.
--
-- Bucketed and counted rather than appended. A doorway is a fixed point, so
-- repeated uses land in one bucket and raise its count; a teleport spell cast
-- from wherever the player stood scatters across buckets at a count of one
-- each. That difference is the signal for reading the report -- a high count
-- is a doorway, a scatter of ones is not.
local function RecordEndpoints(entry, from, to)
    -- Both ends or nothing. A doorway with one end known is not a doorway, and
    -- the client can decline to give a position at either moment.
    if type(from.x) ~= "number" or type(from.y) ~= "number" then return end
    if type(to.x) ~= "number" or type(to.y) ~= "number" then return end

    if type(entry.endpoints) ~= "table" then entry.endpoints = {} end
    local key = string_format("%d:%d",
        math_floor(from.x * ENDPOINT_BUCKETS), math_floor(from.y * ENDPOINT_BUCKETS))
    local seen = entry.endpoints[key]
    if seen then
        seen.count = (tonumber(seen.count) or 0) + 1
        return
    end

    local n = 0
    for _ in pairs(entry.endpoints) do n = n + 1 end
    if n >= MAX_ENDPOINTS then return end

    entry.endpoints[key] = {
        -- Rounded to the precision the data files use, as Capture does.
        fromX = tonumber(string_format("%.4f", from.x)),
        fromY = tonumber(string_format("%.4f", from.y)),
        toX = tonumber(string_format("%.4f", to.x)),
        toY = tonumber(string_format("%.4f", to.y)),
        count = 1,
    }
end

--- Record how the player arrived at a map.
-- Zone boxes are rectangles and overlap across a whole continent, so geometry
-- cannot say which zones border each other -- measured against the current
-- tables it claims 148 pairs that are not neighbours, Durotar to Mulgore among
-- them. A player crossing from one zone to the next can.
--
-- A crossing with no loading screen is a walk or a flight, and both follow the
-- ground. One with a loading screen is a portal or an instance and says
-- nothing about geography, so the two are counted apart rather than mixed --
-- and the loaded case is where both ends of the doorway get recorded.
local function RecordArrival(store, mapID)
    local from = lastMapID
    lastMapID = mapID
    local hadLoadingScreen = loadedSince
    loadedSince = false
    local departure = departurePosition
    departurePosition = nil

    if not from or from == mapID then return end
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
    if type(entry) ~= "table" then entry = {} end
    entry.walked = tonumber(entry.walked) or 0
    entry.loaded = tonumber(entry.loaded) or 0
    if hadLoadingScreen then
        entry.loaded = entry.loaded + 1
        -- Only for a loaded crossing, and only when the departure sample was
        -- taken on the map the player actually left. A walk needs no endpoints
        -- -- the two zones share a border, and the crossing point is not a
        -- fixed doorway.
        if departure and departure.mapID == from then
            RecordEndpoints(entry, departure, { mapID = mapID, x = record.x, y = record.y })
        end
    else
        entry.walked = entry.walked + 1
    end
    record.from[from] = entry
end

--- Capture the current map, if there is one to capture.
-- @return number|nil The mapID recorded, or nil when nothing was recorded --
--   the survey is switched off, the client has no map for the player, or the
--   record cap has been reached.
function ZoneSurvey:Capture()
    if not (QR.db and QR.db.zoneSurveyEnabled) then return nil end
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end

    QR.db.zoneSurvey = QR.db.zoneSurvey or {}
    local store = QR.db.zoneSurvey

    local existing = store[mapID]
    if not existing and RecordCount(store) >= MAX_RECORDS then
        QR:Debug("ZoneSurvey: record cap reached, not adding map " .. tostring(mapID))
        return nil
    end

    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local x, y
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos and pos.GetXY then
            x, y = pos:GetXY()
        end
    end

    local flight = QR.FlightPoints and QR.FlightPoints[mapID]

    store[mapID] = {
        name = info and info.name or nil,
        mapType = info and info.mapType or nil,
        parent = info and info.parentMapID or nil,
        -- Rounded because four decimals is the precision the data files use,
        -- and a full float per visit is noise in a diff.
        x = x and tonumber(string_format("%.4f", x)) or nil,
        y = y and tonumber(string_format("%.4f", y)) or nil,
        continent = QR.GetContinentForZone and QR.GetContinentForZone(mapID) or nil,
        adjacent = CountAdjacent(mapID),
        graphNodes = CountGraphNodes(mapID),
        flightPoint = flight and (flight.node or true) or nil,
        flightAlt = flight and flight.alt and (flight.alt.node or true) or nil,
        visits = (existing and existing.visits or 0) + 1,
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
    if QR.db then QR.db.zoneSurvey = {} end
    -- Also forget where the player came from, so the first capture after a
    -- clear does not invent an arrival from a map no longer on record.
    self:ForgetArrivalState()
end

function ZoneSurvey:Count()
    if not (QR.db and QR.db.zoneSurvey) then return 0 end
    return RecordCount(QR.db.zoneSurvey)
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

    -- Observed crossings. A walk or a flight follows the ground, so it is
    -- evidence that two zones border each other; a portal is not, and is
    -- counted separately rather than thrown away.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Observed crossings"
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

    -- Both ends of every doorway walked through. This is the part no exported
    -- table can supply: a portal's destination lives in a server-side table, so
    -- walking through it is the only way to see it.
    --
    -- Read the count, not just the row. A doorway is a fixed point, so it
    -- accumulates; a teleport spell cast from wherever the player stood leaves
    -- a scatter of separate rows at one each.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### Observed doorways"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string_format(
        "Departure point accurate to about %.1f yards; distinct doorways told apart at 1/%d of the map.",
        SAMPLE_INTERVAL * 7, ENDPOINT_BUCKETS)
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

--- Drop anything in the loaded store that is not the shape this module writes.
-- Checked once, here, rather than guarded at every read. The store comes back
-- from SavedVariables, so nothing about it is given -- and a value of the wrong
-- type does not announce itself: a `from` field holding a string survived every
-- guard downstream, because RecordArrival returns before its own check when
-- there is no previous map yet, which is exactly the state after a login. The
-- first `/qrsurvey` then died in `pairs`.
--
-- One pass on load beats a guard per read: the reads can then say what they
-- mean, and a shape this module never writes cannot reach them at all.
--
-- Clearing keys while traversing is deliberate and permitted. Lua 5.1 on `next`:
-- "The behavior of next is undefined if, during the traversal, you assign any
-- value to a non-existent field in the table. You may however modify existing
-- fields. In particular, you may clear existing fields." This only ever clears
-- fields that exist, and never adds one. Measured on this interpreter as well:
-- traversing 200 keys while clearing 100 of them visits all 200.
local function Sanitize(store)
    if type(store) ~= "table" then return {}, 0 end
    local dropped = 0
    for mapID, record in pairs(store) do
        if type(mapID) ~= "number" or type(record) ~= "table" then
            store[mapID] = nil
            dropped = dropped + 1
        elseif record.from ~= nil then
            if type(record.from) ~= "table" then
                record.from = nil
                dropped = dropped + 1
            else
                for origin, entry in pairs(record.from) do
                    if type(origin) ~= "number" or type(entry) ~= "table" then
                        record.from[origin] = nil
                        dropped = dropped + 1
                    else
                        entry.walked = tonumber(entry.walked) or 0
                        entry.loaded = tonumber(entry.loaded) or 0
                        if entry.endpoints ~= nil then
                            if type(entry.endpoints) ~= "table" then
                                entry.endpoints = nil
                                dropped = dropped + 1
                            else
                                for key, door in pairs(entry.endpoints) do
                                    -- Every coordinate has to be a number: the
                                    -- renderer prints them and RecordEndpoints
                                    -- adds to the count, and a string from a
                                    -- hand-edited file throws at the add.
                                    if type(door) ~= "table"
                                        or type(door.fromX) ~= "number" or type(door.fromY) ~= "number"
                                        or type(door.toX) ~= "number" or type(door.toY) ~= "number" then
                                        entry.endpoints[key] = nil
                                        dropped = dropped + 1
                                    else
                                        door.count = tonumber(door.count) or 0
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return store, dropped
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

    local frame = CreateFrame("Frame")
    -- The position sampler. Two client calls twice a second, and only while the
    -- survey is switched on -- with it off this costs the elapsed accumulation
    -- and nothing else.
    --
    -- Nothing in combat, like the rest of the addon. The cost is not the reason
    -- here; the reason is that a doorway is not walked into mid-fight, so the
    -- samples would be pure overhead. What it costs is a portal taken within
    -- half a second of a fight ending, whose departure point is then the last
    -- sample from before the fight and is discarded by the map check.
    frame.sampleElapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not (QR.db and QR.db.zoneSurveyEnabled) then return end
        if InCombatLockdown() then return end
        self.sampleElapsed = self.sampleElapsed + elapsed
        if self.sampleElapsed < SAMPLE_INTERVAL then return end
        self.sampleElapsed = 0
        ZoneSurvey:SamplePosition()
    end)
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event)
        -- While the survey is off, nothing is recorded -- so nothing may be
        -- remembered either. Letting loadedSince and lastMapID accumulate here
        -- means the first capture after switching back on describes a crossing
        -- between two zones the player never crossed directly, classified by a
        -- loading screen that belonged to some other journey. That is precisely
        -- the kind of invented evidence this recorder exists to avoid.
        if not (QR.db and QR.db.zoneSurveyEnabled) then
            ZoneSurvey:ForgetArrivalState()
            return
        end
        -- A loading screen means the next crossing was a portal or an
        -- instance, not a step over a border. Noted before the debounce, so it
        -- is not lost when the two events arrive together.
        if event == "PLAYER_ENTERING_WORLD" then
            ZoneSurvey:NoteLoadingScreen()
        end
        -- The map the client reports right on the event is sometimes still the
        -- old one, so the capture waits a beat. Debounced, because a zone
        -- change can fire both events together.
        if frame.pending then return end
        frame.pending = true
        C_Timer.After(1.5, function()
            frame.pending = false
            -- Dropped in combat, not postponed. A capture that runs once the
            -- fight is over describes wherever the player ended up, which is
            -- the invented evidence the comment above refuses; and the arrival
            -- state it would have been measured against no longer applies.
            if InCombatLockdown() then
                ZoneSurvey:ForgetArrivalState()
                return
            end
            local ok, err = pcall(function() return ZoneSurvey:Capture() end)
            if not ok then
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
