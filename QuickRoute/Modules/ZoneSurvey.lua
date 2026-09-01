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
local pairs, ipairs, pcall, tostring, tonumber = pairs, ipairs, pcall, tostring, tonumber
local string_format = string.format
local table_concat, table_sort = table.concat, table.sort
local date = date

QR.ZoneSurvey = {}
local ZoneSurvey = QR.ZoneSurvey

-- A full clear-out is better than an unbounded table in SavedVariables, and the
-- game has fewer maps than this. If it is ever hit, something is recording
-- instance floors in a loop and the cap is the signal.
local MAX_RECORDS = 3000

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

--- Note that a loading screen happened, so the next transition is not a walk.
function ZoneSurvey:NoteLoadingScreen()
    loadedSince = true
end

--- Record how the player arrived at a map.
-- Zone boxes are rectangles and overlap across a whole continent, so geometry
-- cannot say which zones border each other -- measured against the current
-- tables it claims 148 pairs that are not neighbours, Durotar to Mulgore among
-- them. A player crossing from one zone to the next can.
--
-- A crossing with no loading screen is a walk or a flight, and both follow the
-- ground. One with a loading screen is a portal or an instance and says
-- nothing about geography, so the two are counted apart rather than mixed.
local function RecordArrival(store, mapID)
    local from = lastMapID
    lastMapID = mapID
    local hadLoadingScreen = loadedSince
    loadedSince = false

    if not from or from == mapID then return end
    local record = store[mapID]
    if not record then return end

    record.from = record.from or {}
    -- Read defensively: this table comes back from SavedVariables, which is a
    -- file on disk that survives version changes and hand-editing. An entry
    -- missing one of its counters would otherwise throw here and take the whole
    -- capture with it.
    local entry = record.from[from] or {}
    entry.walked = entry.walked or 0
    entry.loaded = entry.loaded or 0
    if hadLoadingScreen then
        entry.loaded = entry.loaded + 1
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
        from = existing and existing.from or nil,
        seen = date("%Y-%m-%d %H:%M:%S"),
    }
    RecordArrival(store, mapID)
    return mapID
end

function ZoneSurvey:Clear()
    if QR.db then QR.db.zoneSurvey = {} end
    -- Also forget where the player came from, so the first capture after a
    -- clear does not invent an arrival from a map no longer on record.
    lastMapID = nil
    loadedSince = false
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

    return table_concat(lines, "\n")
end

function ZoneSurvey:Initialize()
    if QR.db then
        if QR.db.zoneSurveyEnabled == nil then
            QR.db.zoneSurveyEnabled = true
        end
        QR.db.zoneSurvey = QR.db.zoneSurvey or {}
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event)
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
