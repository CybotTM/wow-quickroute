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

--- Capture the current map, if there is one to capture.
-- @return number|nil The mapID recorded, or nil when nothing was
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
        x = x and tonumber(string.format("%.4f", x)) or nil,
        y = y and tonumber(string.format("%.4f", y)) or nil,
        continent = QR.GetContinentForZone and QR.GetContinentForZone(mapID) or nil,
        adjacent = CountAdjacent(mapID),
        graphNodes = CountGraphNodes(mapID),
        flightPoint = flight and (flight.node or true) or nil,
        flightAlt = flight and flight.alt and (flight.alt.node or true) or nil,
        visits = (existing and existing.visits or 0) + 1,
        seen = date("%Y-%m-%d %H:%M:%S"),
    }
    return mapID
end

function ZoneSurvey:Clear()
    if QR.db then QR.db.zoneSurvey = {} end
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
        string.format("| Records | %d |", self:Count()),
        "",
        "| map | name | type | parent | x | y | continent | adj | nodes | flight | visits |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    }
    local ids = {}
    for mapID in pairs((QR.db and QR.db.zoneSurvey) or {}) do
        ids[#ids + 1] = mapID
    end
    table.sort(ids)
    for _, mapID in ipairs(ids) do
        local r = QR.db.zoneSurvey[mapID]
        lines[#lines + 1] = string.format(
            "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d |",
            mapID, tostring(r.name or "?"), tostring(r.mapType or "?"),
            tostring(r.parent or "-"), tostring(r.x or "-"), tostring(r.y or "-"),
            tostring(r.continent or "-"), tostring(r.adjacent or "-"),
            tostring(r.graphNodes or "-"), tostring(r.flightPoint or "-"),
            r.visits or 0)
    end
    return table.concat(lines, "\n")
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
    frame:SetScript("OnEvent", function()
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
        QR:Print(string.format("Zone survey: %d record(s). /qrsurvey clear|on|off|here",
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
