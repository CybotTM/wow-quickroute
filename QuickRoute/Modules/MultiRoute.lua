-- MultiRoute.lua
-- Bounded waypoint trips. Replan each leg from the actual player position so
-- consumed teleports and current cooldowns are not reused as if still ready.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local tonumber, tostring = tonumber, tostring
local format, gsub = string.format, string.gsub
local sort, remove, concat = table.sort, table.remove, table.concat
local resume, create, yield, status = coroutine.resume, coroutine.create, coroutine.yield, coroutine.status
local huge = math.huge

QR.MultiRoute = { stops = {}, completed = 0, generation = 0, MAX_STOPS = 20 }
local MR = QR.MultiRoute

local function finite(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value and value > -huge and value < huge
end

local function validStop(stop)
    return type(stop) == "table" and finite(stop.mapID) and stop.mapID > 0
        and stop.mapID % 1 == 0 and finite(stop.x) and stop.x >= 0 and stop.x <= 1
        and finite(stop.y) and stop.y >= 0 and stop.y <= 1
        and (stop.title == nil or (type(stop.title) == "string" and #stop.title <= 160))
end

-- Pasted text is literal display data. A FontString renders |c, |H and |T, so
-- an unescaped paste puts a live item link or a colour code into the status
-- label; title() escapes for the same reason.
local function display(text)
    return (gsub(tostring(text), "|", "||"))
end

local function title(stop)
    -- Imported text is literal display data, never executable commands or links.
    return gsub(tostring(stop.title or format("%d: %.1f, %.1f", stop.mapID, stop.x*100, stop.y*100)):sub(1, 160), "|", "||")
end

-- Split a pasted block into logical lines. A semicolon separates two waypoints
-- only when another /way command follows it, so a label that contains one
-- ("Cave; upper floor") survives instead of invalidating the import.
local function importLines(text)
    local lines, physical, position = {}, 0, 1
    -- The number in a warning has to be the line the player counts in their
    -- paste, so the physical line is tracked separately from the position in
    -- the list, which semicolon splits and dropped empty lines both shift.
    -- CR, LF and CRLF all end a line: a lone CR used to be kept inside the
    -- label and swallowed the waypoint behind it without a word.
    while position <= #text + 1 do
        -- One class scan, not two searches. "\r\n?" never matches in a paste
        -- with no carriage return, so it rescanned to the end of the text once
        -- per line: 47 ms for a 4096-line paste against 2.4 ms before, on the
        -- main thread, on the Start button.
        local breakAt = text:find("[\r\n]", position)
        local breakEnd = breakAt
        if breakAt and text:sub(breakAt, breakAt) == "\r" and text:sub(breakAt + 1, breakAt + 1) == "\n" then
            breakEnd = breakAt + 1
        end
        local raw = text:sub(position, (breakAt or #text + 1) - 1)
        -- A newline ends the line it terminates; it does not start another one.
        -- Counting the empty remainder after a trailing newline claimed a line
        -- the player never wrote, and no warning could ever name it.
        if breakAt == nil and raw == "" then break end
        physical = physical + 1
        if raw:find("%S") then
            local rest = raw
            while true do
                local head, tail = rest:match("^(.-);(%s*/way[%s#].*)$")
                if not head then break end
                -- A semicolon at the start of a line leaves an empty head. It
                -- is not something the player wrote, so it gets no warning.
                if head:find("%S") then lines[#lines + 1] = { text = head, line = physical } end
                rest = tail
            end
            lines[#lines + 1] = { text = rest, line = physical }
        end
        if not breakAt then break end
        position = breakEnd + 1
    end
    return lines, physical
end

-- Read one coordinate from the front of `text`. Returns the value, which
-- decimal mark it used, and what is left of the line.
--
-- A dot or a comma counts as a decimal mark only when digits follow it: "56,62"
-- is one value. A dot or comma with no digit behind it ends the number and is
-- dropped, so "60, near the tree" and "50. 60" read as 60 and 50. Any other
-- character after the number stays where it is and becomes part of the label.
-- Which mark was used travels with the value, because a line that uses both can
-- be read two ways and has to be refused rather than resolved one way in
-- silence.
local function readCoordinate(text)
    local value, mark, rest
    local digits, separator, fraction, tail = text:match("^(%d+)([%.,])(%d+)(.*)$")
    if digits then
        value = tonumber(digits .. "." .. fraction)
        mark = (separator == ",") and "comma" or "dot"
        rest = tail
    else
        local whole
        whole, rest = text:match("^(%d+)(.*)$")
        if not whole then return nil end
        value, mark = tonumber(whole), "plain"
    end
    local afterMark = rest:match("^[%.,](.*)$")
    if afterMark and not afterMark:match("^%d") then rest = afterMark end
    return value, mark, rest
end

-- Whether what is left after the second coordinate is a label, or the rest of
-- a number the reader stopped short of. A label may sit straight against the
-- value -- "60Bank", "60:Bank", "60-5 Label" -- and it may start with anything
-- but one thing: a decimal mark with a digit behind it, directly after a value
-- that has no fraction yet. Only that shape is a number cut in half. A value
-- that already carries its fraction cannot be continued, so "60.75,3 chests"
-- is 60.75 with the label ",3 chests".
local function labelFollows(text, mark)
    if mark ~= "plain" then return true end
    return not text:match("^[%.,]%d")
end

local function inRange(value)
    return value ~= nil and value >= 0 and value <= 100
end

-- The pattern the comma-separated shape below reads a pair with.
local SEPARATED_PAIR = "^(%d+%.?%d*)%s*,%s*(%d+%.?%d*)%s*(.-)%s*$"

-- Read a coordinate pair. Community guides separate the pair with a comma, and
-- some locales write the decimal point as one. Each value is consumed as a
-- whole token, so "50,57 56,62" is one pair and never four numbers, and
-- "50 56,62" keeps the second value's fraction instead of reading 56 and
-- leaving ",62" at the front of the label. Reading part of a number and
-- carrying the rest into the label moved the destination while both values
-- stayed in range, so nothing downstream could catch it.
-- @return number|nil x, number|nil y, string|nil label, string|nil reason,
--   table|nil candidates for reason "COMMA_CHOICE": { decimal = {x, y, label}, pair = {x, y, label} }
local function coordinatePair(rest)
    local x, xMark, afterX = readCoordinate(rest)
    local betweenPair = x and afterX:match("^%s+(.*)$")
    local y, yMark, afterY
    if betweenPair then y, yMark, afterY = readCoordinate(betweenPair) end
    -- A comma on the first value followed by a plain second value reads two
    -- ways. "50,57 56 Treasure" is:
    --   decimal: x = 50.57, y = 56, label "Treasure" (the comma is a decimal mark)
    --   pair:    x = 50, y = 57, label "56 Treasure" (the comma separates a
    --            compact pair, and the label starts with a number)
    -- The shape is exactly: digits, a comma, digits, whitespace, digits with no
    -- decimal mark of their own. It is a choice only when both readings are
    -- complete: the decimal reading needs a label boundary after the plain
    -- value and both of its values in 0..100, the pair reading needs its
    -- second value -- the digits after the comma -- in 0..100. The player
    -- picks; the parser returns both. When only one reading is complete, the
    -- line takes the path it took before the choice existed: the pair shape
    -- below, which accepts "50,57 150 Label" and refuses "50,570 56 Treasure".
    -- The mirror case is different: "50 56,62" could otherwise only mean a
    -- label of ",62", which no guide writes.
    if y and xMark == "comma" and yMark == "plain" then
        local sx, sy, tail = rest:match(SEPARATED_PAIR)
        local pairX, pairY = tonumber(sx), tonumber(sy)
        -- "0,0 0" reads as the same point either way; only the label would
        -- differ, and that is no choice worth stopping the import for.
        if labelFollows(afterY, yMark) and inRange(x) and inRange(y)
            and inRange(pairX) and inRange(pairY) and not (x == pairX and y == pairY) then
            return nil, nil, nil, "COMMA_CHOICE", {
                decimal = { x = x, y = y, label = (gsub(afterY, "^%s+", "")) },
                pair = { x = pairX, y = pairY, label = tail },
            }
        end
        y = nil
    end
    if y then
        -- Two values were read. From here the line is either this pair or
        -- refused -- never handed to the shape below, which would take the
        -- comma inside "50,57" as a separator and import (50, 57).
        if not labelFollows(afterY, yMark) then
            return nil, nil, nil, "BAD_COORDS"
        end
        -- One value writing its decimal point as a comma and the other as a
        -- point explains the line two ways: "50,57 56.62" is the pair 50.57
        -- and 56.62, or the pair 50 and 57 with a label that starts with a
        -- number. Both readings are complete, so the line names two different
        -- places and neither may be picked.
        --
        -- A plain first value next to a comma decimal, "50 56,62", reads the
        -- comma as the decimal mark: the other reading would leave ",62" as a
        -- label. That is still a choice -- "60,3 chests" could be the pair 60
        -- and 3 -- and it is the one the report this change answers asked for.
        if (xMark == "comma" and yMark == "dot")
            or (xMark == "dot" and yMark == "comma") then
            return nil, nil, nil, "AMBIGUOUS_COORDS"
        end
        return x, y, (gsub(afterY, "^%s+", ""))
    end
    -- "50,57 Bank" and "50, 57 Bank": the comma separates the pair. Reached only
    -- when no second value could be read above.
    local sx, sy, tail = rest:match(SEPARATED_PAIR)
    if sx then return tonumber(sx), tonumber(sy), tail end
    return nil
end

-- Localized zone names for the maps QuickRoute already models. Built once per
-- session from the client, so a pasted zone name resolves only to a map the
-- router knows; anything else is reported rather than guessed.
local zoneNameIndex
local function zoneNamesByLowerName()
    if zoneNameIndex then return zoneNameIndex end
    zoneNameIndex = {}
    if not (C_Map and C_Map.GetMapInfo) then return zoneNameIndex end
    local seen = {}
    local function add(mapID)
        if type(mapID) ~= "number" or seen[mapID] then return end
        seen[mapID] = true
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if not (ok and type(info) == "table" and type(info.name) == "string") then return end
        local key = info.name:lower()
        local bucket = zoneNameIndex[key]
        if not bucket then
            zoneNameIndex[key] = { mapID }
        elseif bucket[1] ~= mapID then
            bucket[#bucket + 1] = mapID
        end
    end
    for mapID in pairs(QR.ZoneAdjacencies or {}) do add(mapID) end
    for _, city in pairs(QR.CAPITAL_CITIES or {}) do add(city.mapID) end
    return zoneNameIndex
end

function MR:ResetZoneNameIndex()
    zoneNameIndex = nil
end

-- Resolve the map token of one /way line. Returns mapID, or nil plus a reason
-- key the import preview turns into a line-specific warning.
local function resolveMap(token)
    if token == nil then
        local current = QR.TravelTime and QR.TravelTime.GetCurrentMapID
            and QR.TravelTime:GetCurrentMapID()
        if not finite(current) then return nil, "NO_POSITION" end
        return current
    end
    if type(token) == "number" then return token end
    local matches = zoneNamesByLowerName()[token:lower()]
    if not matches then return nil, "UNKNOWN_MAP" end
    if #matches > 1 then return nil, "AMBIGUOUS_MAP" end
    return matches[1]
end

-- Split one /way body into a map token and a coordinate pair. The documented
-- three-number form keeps priority, so "/way 84 1 100 First" still reads 84 as
-- the map and never as a coordinate.
-- An ambiguous pair stops the parse where it is found. Falling through to the
-- next shape would read a different pair out of the same line -- the map token
-- and the first coordinate -- and accept it.
-- A line whose pair reads two ways returns the reason "COMMA_CHOICE", its map
-- token and both candidates, so the map is resolved the same way for either.
local function parseWayBody(body)
    local mapText, rest = body:match("^#(%d+)%s+(.+)$")
    if mapText then
        local x, y, label, reason, candidates = coordinatePair(rest)
        if x then return tonumber(mapText), x, y, label end
        if candidates then return tonumber(mapText), nil, nil, nil, reason, candidates end
        return nil, nil, nil, nil, reason or "BAD_COORDS"
    end
    mapText, rest = body:match("^(%d+)%s+(.+)$")
    if mapText then
        local x, y, label, reason, candidates = coordinatePair(rest)
        if x then return tonumber(mapText), x, y, label end
        if candidates then return tonumber(mapText), nil, nil, nil, reason, candidates end
        if reason then return nil, nil, nil, nil, reason end
        -- Two numbers follow the leading one, so this is the map form and its
        -- pair could not be read. Falling through to the next shape would pair
        -- the map token with the first coordinate and accept a destination on
        -- the player's current map -- a line that reads correctly to a human,
        -- imported as somewhere else entirely.
        if rest:match("^%d[%d%.,]*%s+%.?%d") then
            return nil, nil, nil, nil, "BAD_COORDS"
        end
    end
    local x, y, label, reason, candidates = coordinatePair(body)
    if x then return nil, x, y, label end
    if reason then return nil, nil, nil, nil, reason, candidates end
    local name, remainder = body:match("^(.-)%s+(%d.*)$")
    if name and name ~= "" then
        local nx, ny, nlabel, nreason, ncandidates = coordinatePair(remainder)
        if nx then return name, nx, ny, nlabel end
        if ncandidates then return name, nil, nil, nil, nreason, ncandidates end
        if nreason then return nil, nil, nil, nil, nreason end
    end
    return nil, nil, nil, nil, "BAD_COORDS"
end

-- The preview is shown in one status label, so the number of rows it can hold
-- is bounded. A paste of four thousand notes is within the input-size limit and
-- would otherwise build a status string of nearly two hundred kilobytes.
local MAX_REPORT_ENTRIES = 40

-- A rejection always gets a row: it is the reason the import stopped, and the
-- player cannot act on "some line was wrong".
local function addEntry(report, entry, always)
    report.suppressed = report.suppressed or 0
    -- Only the rows the preview renders spend the budget. Counting accepted
    -- rows against it let the label announce hidden problems that were in fact
    -- successfully imported stops, and MAX_STOPS already bounds those.
    if entry.status == "accepted" or always or report.shown < MAX_REPORT_ENTRIES then
        report.entries[#report.entries + 1] = entry
        if entry.status ~= "accepted" then report.shown = report.shown + 1 end
    else
        report.suppressed = report.suppressed + 1
    end
end

--- Parse pasted waypoint text into trip stops.
-- A line whose comma pair reads two ways (see coordinatePair) is imported only
-- with a reading chosen for it. Without one the whole import stops, the way it
-- stops for an unreadable line, and the report lists the line with both
-- readings so the player can choose.
-- @param text string Pasted block, at most 8192 characters
-- @param choices table|nil Reading per ambiguous line, "decimal" or "pair",
--   keyed by the `key` of that line's report entry
-- @return table|nil Accepted stops, or nil when none could be read
-- @return string|nil Failure message when no stop was accepted
-- @return table Import report: `accepted` count and one `entries` row per line
function MR:ParseWaypoints(text, choices)
    local report = { accepted = 0, entries = {}, shown = 0, suppressed = 0 }
    if type(text) ~= "string" or #text > 8192 then return nil, QR.L["MULTI_INVALID"], report end
    if type(choices) ~= "table" then choices = {} end
    local stops, pending = {}, 0
    local lines, physicalLines = importLines(text)
    -- The same unit as the warnings. Counting list entries made the summary say
    -- "2 of 3" while a warning named line 4 of that same paste.
    report.total = physicalLines
    for key, entry in ipairs(lines) do
        local line, number = entry.text, entry.line
        local body = line:match("^%s*/way%s+(.-)%s*$")
        if not body then
            -- A heading, a note or prose between waypoints. Skipped with a
            -- warning rather than invalidating the whole paste.
            addEntry(report, { line = number, text = line, status = "skipped", reason = "NOT_A_WAYPOINT" })
        else
            local mapToken, x, y, label, failure, candidates = parseWayBody(body)
            local mapID, mapFailure
            if not failure or candidates then mapID, mapFailure = resolveMap(mapToken) end
            local chosen = candidates and not mapFailure and candidates[choices[key]]
            if chosen then
                x, y, label, failure = chosen.x, chosen.y, chosen.label, nil
            end
            failure = mapFailure or failure
            local readings
            if failure == "COMMA_CHOICE" then
                readings = {}
                for reading, candidate in pairs(candidates) do
                    local option = { mapID = mapID, x = candidate.x / 100, y = candidate.y / 100, title = candidate.label }
                    if option.title == "" then option.title = nil end
                    if validStop(option) then readings[reading] = option end
                end
                if not (readings.decimal and readings.pair) then failure = "BAD_COORDS" end
            end
            if failure == "COMMA_CHOICE" then
                -- Both readings stay in the report and the parse goes on, so
                -- one pass lists every line that needs a choice. The import
                -- itself stops after the loop.
                pending = pending + 1
                addEntry(report, { line = number, text = line, status = "ambiguous", key = key,
                    candidates = readings }, true)
                if #stops + pending > self.MAX_STOPS then return nil, QR.L["MULTI_LIMIT"], report end
            elseif failure then
                -- A /way line that cannot be read is an error, not a note:
                -- the import stops so no silent gap reaches the trip.
                addEntry(report, { line = number, text = line, status = "invalid",
                    reason = failure, token = mapToken }, true)
                return nil, QR.L["MULTI_INVALID"], report
            else
                local stop = { mapID = mapID, x = x / 100, y = y / 100, title = label }
                if not validStop(stop) then
                    addEntry(report, { line = number, text = line, status = "invalid", reason = "BAD_COORDS" }, true)
                    return nil, QR.L["MULTI_INVALID"], report
                end
                if stop.title == "" then stop.title = nil end
                stops[#stops + 1] = stop
                report.accepted = report.accepted + 1
                addEntry(report, { line = number, text = line, status = "accepted", stop = stop })
                if #stops + pending > self.MAX_STOPS then return nil, QR.L["MULTI_LIMIT"], report end
            end
        end
    end
    -- A line still waiting for its reading stops the import: taking the rest
    -- without it would start a trip with a silent gap, and Start replaces the
    -- trip, so the missing stop could not be added afterwards.
    if pending > 0 then return nil, QR.L["MULTI_IMPORT_CHOOSE"], report end
    if #stops == 0 then return nil, QR.L["MULTI_INVALID"], report end
    return stops, nil, report
end

--- Report whether any input line was skipped or rejected.
-- @param report table Third return value of ParseWaypoints
-- @return boolean True when at least one line needs the player's attention
function MR:ImportHasWarnings(report)
    if type(report) ~= "table" or type(report.entries) ~= "table" then return false end
    for _, entry in ipairs(report.entries) do
        if entry.status ~= "accepted" then return true end
    end
    return false
end

-- A coordinate as the player wrote it: 50.57, not 50.5700 or 50.570000001.
local function percent(value)
    return (gsub(gsub(format("%.4f", value * 100), "0+$", ""), "%.$", ""))
end

--- Render one reading of an ambiguous line: its two coordinates and its label.
-- @param stop table A candidate from an "ambiguous" report entry
-- @param coordinatesOnly boolean|nil Leave the label out, for a button
-- @return string For example `50, 57 "56 Treasure"`
function MR:FormatReading(stop, coordinatesOnly)
    if type(stop) ~= "table" then return "?" end
    local text = percent(stop.x) .. ", " .. percent(stop.y)
    if stop.title and not coordinatesOnly then text = text .. ' "' .. display(stop.title:sub(1, 40)) .. '"' end
    return text
end

--- The first line of a report that still waits for the player's reading.
-- @param report table Third return value of ParseWaypoints
-- @return table|nil The report entry, with `key`, `line` and `candidates`
function MR:PendingCommaChoice(report)
    if type(report) ~= "table" or type(report.entries) ~= "table" then return nil end
    for _, entry in ipairs(report.entries) do
        if entry.status == "ambiguous" then return entry end
    end
    return nil
end

--- Render an import report as the status text shown beside the paste box.
-- @param report table Third return value of ParseWaypoints
-- @return string|nil Summary plus one line per skipped or rejected input line
function MR:FormatImportReport(report)
    if type(report) ~= "table" or type(report.entries) ~= "table" then return nil end
    local total = #report.entries
    if total == 0 then return nil end
    -- While a line waits for its reading nothing has been imported, so
    -- "Imported 1 of 2 lines." above "nothing is imported" would contradict it.
    local waiting = MR:PendingCommaChoice(report) ~= nil
    local parts = {}
    if not waiting then
        parts[1] = format(QR.L["MULTI_IMPORT_SUMMARY"], report.accepted or 0, report.total or total)
    end
    for _, entry in ipairs(report.entries) do
        if entry.status == "skipped" then
            parts[#parts + 1] = format(QR.L["MULTI_IMPORT_SKIPPED"], entry.line, display(entry.text:sub(1, 60)))
        elseif entry.status == "ambiguous" and type(entry.candidates) == "table" then
            parts[#parts + 1] = format(QR.L["MULTI_IMPORT_COMMA_CHOICE"], entry.line,
                MR:FormatReading(entry.candidates.decimal), MR:FormatReading(entry.candidates.pair))
        elseif entry.status == "invalid" then
            local key = "MULTI_IMPORT_" .. tostring(entry.reason)
            if entry.reason == "UNKNOWN_MAP" or entry.reason == "AMBIGUOUS_MAP" then
                parts[#parts + 1] = format(QR.L[key], entry.line, display(tostring(entry.token)))
            else
                parts[#parts + 1] = format(QR.L[key], entry.line)
            end
        end
    end
    if (report.suppressed or 0) > 0 then
        parts[#parts + 1] = format(QR.L["MULTI_IMPORT_MORE"], report.suppressed)
    end
    if #parts == 1 then return parts[1] end
    return concat(parts, "\n")
end

function MR:CollectTomTomWaypoints()
    if not (TomTom and type(TomTom.waypoints) == "table") then return nil, QR.L["MULTI_NO_TOMTOM"] end
    local stops, inspected = {}, 0
    -- TomTom's active waypoint registry is mapID -> key -> {mapID, x, y, title}.
    -- Read only: never remove or change the player's TomTom collection.
    for _, mapStops in pairs(TomTom.waypoints) do
        if type(mapStops) == "table" then
            for _, waypoint in pairs(mapStops) do
                inspected = inspected + 1
                if inspected > 2000 then return nil, QR.L["MULTI_LIMIT"] end
                if type(waypoint) == "table" and waypoint.from ~= "QuickRoute"
                    and not (type(waypoint.title) == "string" and waypoint.title:match("^QR: ")) then
                    local stop = { mapID = waypoint[1], x = waypoint[2], y = waypoint[3], title = waypoint.title }
                    if validStop(stop) then
                        stops[#stops + 1] = stop
                        if #stops > self.MAX_STOPS then return nil, QR.L["MULTI_LIMIT"] end
                    end
                end
            end
        end
    end
    if #stops == 0 then return nil, QR.L["MULTI_NO_TOMTOM"] end
    sort(stops, function(a, b)
        if a.mapID ~= b.mapID then return a.mapID < b.mapID end
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return title(a) < title(b)
    end)
    return stops
end

function MR:Start(stops, fastestNext)
    if type(stops) ~= "table" or #stops == 0 or #stops > self.MAX_STOPS then
        return false, QR.L["MULTI_LIMIT"]
    end
    local copy = {}
    for _, stop in ipairs(stops) do
        if not validStop(stop) then return false, QR.L["MULTI_INVALID"] end
        copy[#copy + 1] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    if QR.ServiceRouter and QR.ServiceRouter.CancelCurrencyRouting then
        QR.ServiceRouter:CancelCurrencyRouting()
    end
    self:Clear()
    self.stops, self.fastestNext = copy, fastestNext ~= false
    self.total = #copy
    self:Save()
    self.closes = QR.MainFrame and QR.MainFrame.closeCount
    self:SelectNext()
    return true
end

function MR:DisplayRoute(stop, result)
    local waypoint = { mapID = stop.mapID, x = stop.x, y = stop.y, title = title(stop) }
    if QR.db then QR.db.lastDestination = waypoint end
    -- The leg is chosen across frames. A route window the player closed after
    -- starting the trip or confirming a stop stays closed; the leg is saved and
    -- locked, so the next open routes to it.
    if QR.MainFrame and QR.MainFrame:ClosedSince(self.closes) then
        if QR.db then QR.db.destinationLocked = true end
        return
    end
    result.waypoint, result.waypointSource = waypoint, "map_click"
    if QR.UI then
        QR.UI._pendingPOIRoute = result
        QR.UI:Show()
    end
end

local function playerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, point = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return end
        local x, y = position:GetXY()
        local stop = { mapID = mapID, x = x, y = y }
        if validStop(stop) then return stop end
    end)
    return ok and point or nil
end

function MR:OptimizeTour(restarts)
    local origin = playerPosition()
    if not origin then return self:SelectNext(true) end
    self.generation = self.generation + 1
    local generation, count = self.generation, #self.stops
    self.busy, self.currentIndex = true, nil
    local calculator = QR.PathCalculator
    if calculator.CreateRouteContext then
        local ok, context = pcall(calculator.CreateRouteContext, calculator, { excludeCooldowns = true })
        if ok and context then calculator = context end
    end
    local matrix, from, destination, done = {}, 0, 1, 0
    local points = { [0] = origin }
    for i, stop in ipairs(self.stops) do points[i] = stop end
    local function finish(order, cost, method)
        if self.generation ~= generation then return end
        local current = playerPosition()
        if not current or current.mapID ~= origin.mapID or math.abs(current.x-origin.x) > 0.005 or math.abs(current.y-origin.y) > 0.005 then
            if current and (restarts or 0) < 1 then return self:OptimizeTour(1) end
            self.planCost, self.planMethod = nil, "live-next"
            return self:SelectNext(true)
        end
        if order then
            local sorted = {}
            for i, index in ipairs(order) do sorted[i] = self.stops[index] end
            self.stops, self.planCost, self.planMethod = sorted, cost, method
            self:Save()
            self:SelectNext(true, true)
        else
            -- A cooldown-free matrix may be disconnected even though the
            -- current character can teleport out. Retain every destination and
            -- identify the live next-leg fallback instead of claiming a tour.
            self.planCost, self.planMethod = nil, "live-next"
            self:SelectNext(true)
        end
    end
    local function solve()
        local worker = create(function()
            return QR.TourPlanner:Solve(matrix, count, function() yield() end)
        end)
        local function advance()
            if self.generation ~= generation then return end
            local ok, order, cost, method = resume(worker)
            if not ok then finish(nil); return end
            if status(worker) == "dead" then finish(order, cost, method)
            else C_Timer.After(0, advance) end
        end
        advance()
    end
    local function calculateOne()
        if self.generation ~= generation then return end
        if from > count then solve(); return end
        matrix[from] = matrix[from] or {}
        if from ~= destination then
            local a, b = points[from], points[destination]
            local ok, result = pcall(calculator.CalculatePathFrom, calculator,
                a.mapID, a.x, a.y, b.mapID, b.x, b.y, { excludeCooldowns = true })
            matrix[from][destination] = ok and result and finite(result.totalTime)
                and result.totalTime >= 0 and result.totalTime or huge
            done = done + 1
            self.message = format(QR.L["MULTI_MATRIX_PROGRESS"], done, count*count)
            self:UpdateStatus()
        end
        destination = destination + 1
        if destination > count then from, destination = from + 1, 1 end
        C_Timer.After(0, calculateOne)
    end
    C_Timer.After(0, calculateOne)
end

function MR:SelectNext(skipOptimization, ordered)
    if #self.stops == 0 then return end
    if self.fastestNext and not skipOptimization and QR.PathCalculator.CalculatePathFrom then
        return self:OptimizeTour()
    end
    self.generation = self.generation + 1
    local generation = self.generation
    self.busy, self.currentIndex = true, nil
    self.message = QR.L["CALCULATING"]
    self:UpdateStatus()
    local index, bestIndex, bestResult, bestCost = 1, nil, nil, huge
    local count = self.fastestNext and not ordered and #self.stops or math.min(1, #self.stops)
    local origin, restarts = count > 1 and playerPosition() or nil, 0
    local function calculateOne()
        if self.generation ~= generation then return end
        if count > 1 then
            local current = playerPosition()
            local changed = current and origin and (current.mapID ~= origin.mapID
                or math.abs(current.x - origin.x) > 0.001 or math.abs(current.y - origin.y) > 0.001)
            if not current or not origin or (changed and restarts >= 2) then
                self.busy, self.currentIndex = false, nil
                self.message = QR.L[changed and "MULTI_POSITION_CHANGED" or "DESTINATION_UNAVAILABLE"]
                self:UpdateStatus()
                return
            end
            if changed then
                -- Compare every candidate from the same origin. Refreshing
                -- only the previous winner can retain the wrong destination.
                origin, restarts = current, restarts + 1
                index, bestIndex, bestResult, bestCost = 1, nil, nil, huge
            end
        end
        if index > count then
            -- Selection spans frames; refresh the winning leg from the current
            -- player/cooldown state before presenting an executable route.
            if bestIndex then
                local stop = self.stops[bestIndex]
                local ok, result = pcall(QR.PathCalculator.CalculatePath, QR.PathCalculator, stop.mapID, stop.x, stop.y)
                if ok and result and finite(result.totalTime) and result.totalTime >= 0 then
                    bestResult = result
                else
                    bestIndex = nil
                end
            end
            self.busy, self.currentIndex = false, bestIndex
            if bestIndex then
                self.message = format(QR.L["MULTI_PROGRESS"], self.completed + 1, self.total, title(self.stops[bestIndex]))
                self:DisplayRoute(self.stops[bestIndex], bestResult)
            else
                self.message = QR.L["NO_PATH_FOUND"]
            end
            self:UpdateStatus()
            return
        end
        local stop = self.stops[index]
        local ok, result = pcall(QR.PathCalculator.CalculatePath, QR.PathCalculator, stop.mapID, stop.x, stop.y)
        if ok and result and finite(result.totalTime) and result.totalTime >= 0 and result.totalTime < bestCost then
            bestIndex, bestResult, bestCost = index, result, result.totalTime
        end
        index = index + 1
        C_Timer.After(0, calculateOne)
    end
    -- One destination per frame keeps long lists from monopolizing a UI frame.
    C_Timer.After(0, calculateOne)
end

function MR:Next()
    if self.busy then return false end
    if self.currentIndex then
        remove(self.stops, self.currentIndex)
        self.completed = self.completed + 1
        self.currentIndex = nil
    end
    self:Save()
    self.closes = QR.MainFrame and QR.MainFrame.closeCount
    if #self.stops == 0 then
        self.message = QR.L["MULTI_COMPLETE"]
        self:UpdateStatus()
    else
        self:SelectNext()
    end
    return true
end

function MR:Clear()
    -- Every way a trip is cleared or replaced passes here -- the Clear
    -- button, /qrmulti clear, /qrmulti tomtom, Start -- so an offered reading
    -- for a paste that is no longer being imported goes with the trip.
    -- Finishing the last stop (Next) does not come here, and keeps the
    -- reading: the paste it belongs to is still in the box. The
    -- import itself withdraws or offers before it calls Start, so no reading
    -- is pending when Start reaches here from the paste.
    if self.withdrawCommaChoice then self.withdrawCommaChoice() end
    self.generation = self.generation + 1
    self.stops, self.completed, self.total = {}, 0, 0
    self.currentIndex, self.busy = nil, false
    self.planCost, self.planMethod = nil, nil
    self:Save()
    self.message = QR.L["MULTI_EMPTY"]
    self:UpdateStatus()
end

function MR:CancelSelection()
    self.generation = self.generation + 1
    self.busy = false
end

function MR:Save()
    local guid = UnitGUID and UnitGUID("player")
    if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" or not QR.db then return end
    QR.db.multiRouteTrips = type(QR.db.multiRouteTrips) == "table" and QR.db.multiRouteTrips or {}
    if #self.stops == 0 then QR.db.multiRouteTrips[guid] = nil; return end
    local stops = {}
    for i, stop in ipairs(self.stops) do
        stops[i] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    QR.db.multiRouteTrips[guid] = { stops = stops, completed = self.completed, optimize = self.fastestNext }
end

function MR:Initialize()
    local guid = UnitGUID and UnitGUID("player")
    if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return end
    local trips = QR.db and QR.db.multiRouteTrips
    local saved = type(trips) == "table" and guid and trips[guid]
    if type(saved) ~= "table" or type(saved.stops) ~= "table" or #saved.stops < 1 or #saved.stops > self.MAX_STOPS then return end
    local copy = {}
    for _, stop in ipairs(saved.stops) do
        if not validStop(stop) then trips[guid] = nil; return end
        copy[#copy+1] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    local completed = saved.completed
    if not finite(completed) or completed < 0 or completed > self.MAX_STOPS or completed % 1 ~= 0 then completed = 0 end
    self.stops, self.completed, self.total = copy, completed, completed + #copy
    self.fastestNext, self.message = saved.optimize ~= false, QR.L["MULTI_RESUME"]
    self.currentIndex, self.busy = nil, false
end

function MR:UpdateStatus()
    local message = self.message or QR.L["MULTI_EMPTY"]
    if self.planCost and not self.busy then
        message = message .. "\n" .. format(QR.L["MULTI_TOUR_ESTIMATE"],
            QR.CooldownTracker:FormatTime(self.planCost), QR.L[self.planMethod == "exact" and "MULTI_EXACT" or "MULTI_HEURISTIC"])
    elseif self.planMethod == "live-next" and not self.busy then
        message = message .. "\n" .. QR.L["MULTI_LIVE_FALLBACK"]
    end
    if self.statusLabel then self.statusLabel:SetText(message) end
    if self.itinerary then
        local lines = {}
        for i, stop in ipairs(self.stops) do
            local marker = self.currentIndex == i and "> " or ""
            lines[i] = format("%s%d. %s", marker, self.completed + i, title(stop))
        end
        self.itinerary:SetText(#lines > 0 and concat(lines, "\n\n") or QR.L["MULTI_EMPTY"])
        local height = math.max(214, self.itinerary:GetStringHeight() + 12)
        self.itinerary:SetHeight(height)
        self.itineraryBody:SetHeight(height)
    end
end

function MR:Show()
    if InCombatLockdown() then QR:Print(QR.L["CANNOT_USE_IN_COMBAT"]); return end
    if not self.frame then
        local L = QR.L
        local frame = QR.CreateStandardWindow({ name = "QuickRouteMultiRouteFrame", title = L["MULTI_TITLE"], width = 580, height = 684 })
        self.frame = frame
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetWidth(548)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["MULTI_HINT"])
        local inputSurface = frame:CreateTexture(nil, "BACKGROUND")
        inputSurface:SetPoint("TOPLEFT", 12, -92)
        inputSurface:SetSize(546, 144)
        inputSurface:SetColorTexture(0, 0, 0, 0.25)
        local scroll = CreateFrame("ScrollFrame", "QuickRouteMultiRouteScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -100)
        scroll:SetSize(526, 130)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        if edit.SetJustifyV then edit:SetJustifyV("TOP") end
        if edit.SetTextInsets then edit:SetTextInsets(6, 6, 6, 6) end
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(520)
        edit:SetHeight(130)
        edit:SetMaxLetters(8192)
        edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        scroll:SetScrollChild(edit)
        QR.SkinScrollBar(scroll)
        self.editBox = edit
        if #self.stops > 0 then
            local lines = {}
            for i, stop in ipairs(self.stops) do
                lines[i] = format("/way #%d %.2f %.2f %s", stop.mapID, stop.x*100, stop.y*100, stop.title or "")
            end
            edit:SetText(concat(lines, "\n"))
        end
        local mode = QR.CreateModernCheckbox(frame, 20)
        mode:SetPoint("TOPLEFT", 16, -240)
        mode:SetChecked(self.fastestNext ~= false)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", mode, "RIGHT", 8, 0)
        label:SetSize(510, 32)
        label:SetJustifyH("LEFT")
        label:SetText(L["MULTI_FASTEST_NEXT"])
        local itineraryTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itineraryTitle:SetPoint("TOPLEFT", 16, -282)
        itineraryTitle:SetText(L["MULTI_ITINERARY"])
        local itineraryScroll = CreateFrame("ScrollFrame", "QuickRouteMultiItinerary", frame, "UIPanelScrollFrameTemplate")
        itineraryScroll:SetPoint("TOPLEFT", 16, -306)
        itineraryScroll:SetSize(526, 214)
        local itineraryBody = CreateFrame("Frame", nil, itineraryScroll)
        itineraryBody:SetSize(520, 214)
        local itinerary = itineraryBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        itinerary:SetPoint("TOPLEFT")
        itinerary:SetWidth(520)
        itinerary:SetJustifyH("LEFT")
        itinerary:SetJustifyV("TOP")
        itineraryScroll:SetScrollChild(itineraryBody)
        QR.SkinScrollBar(itineraryScroll)
        self.itinerary = itinerary
        itineraryBody:SetScript("OnSizeChanged", function() itinerary:SetWidth(itineraryBody:GetWidth()) end)
        self.itineraryBody = itineraryBody
        local function button(text, x, callback, y, width)
            local btn = QR.CreateModernButton(frame, width or 132, 26)
            btn:SetPoint("BOTTOMLEFT", x, y or 80)
            btn:SetText(text)
            btn:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                if InCombatLockdown() then return end
                callback()
            end)
            return btn
        end
        -- A line whose comma pair reads two ways gets one button per reading.
        -- The choice belongs to the paste it was made for: a changed paste
        -- starts with no choices, so an old answer never reads a new line.
        local choices, choicesFor = {}, nil
        local offer
        local function start(stops, err, report)
            -- Only when the choice is the one thing left. Offered under another
            -- failure -- too many lines, an unreadable line -- a click could
            -- not import anything, and fixing that failure means editing the
            -- paste, which drops the choice again.
            offer(err == L["MULTI_IMPORT_CHOOSE"] and report or nil)
            local preview = self:FormatImportReport(report)
            if stops then
                edit:ClearFocus()
                self:Start(stops, mode:GetChecked())
                -- Warnings survive the successful start: a skipped heading is
                -- still something the player has to be able to see.
                if preview and self:ImportHasWarnings(report) then
                    self.message = preview
                    self:UpdateStatus()
                end
            else
                self.message = preview and (err .. "\n" .. preview) or err
                self:UpdateStatus()
            end
        end
        local function importPaste()
            local text = edit:GetText()
            if choicesFor ~= text then choices, choicesFor = {}, text end
            start(self:ParseWaypoints(text, choices))
        end
        local withdraw
        local function choose(reading)
            local pending = self.pendingCommaChoice
            -- A button standing for a paste that has changed since is
            -- withdrawn rather than obeyed: importing on its click would start
            -- a trip from text the player never confirmed.
            if not (pending and pending.text == edit:GetText() and choicesFor == pending.text) then
                withdraw()
                return
            end
            choices[pending.key] = reading
            importPaste()
        end
        self.commaDecimalButton = button("", 16, function() choose("decimal") end, 118, 269)
        self.commaPairButton = button("", 295, function() choose("pair") end, 118, 269)
        withdraw = function()
            self.pendingCommaChoice = nil
            self.commaDecimalButton:Hide()
            self.commaPairButton:Hide()
        end
        -- For MR:Clear, which the slash commands reach without the window.
        self.withdrawCommaChoice = withdraw
        withdraw()
        offer = function(report)
            local entry = self:PendingCommaChoice(report)
            if not entry then withdraw(); return end
            self.pendingCommaChoice = { key = entry.key, text = edit:GetText() }
            self.commaDecimalButton:SetText(format(L["MULTI_COMMA_USE"], entry.line,
                self:FormatReading(entry.candidates.decimal, true)))
            self.commaPairButton:SetText(format(L["MULTI_COMMA_USE"], entry.line,
                self:FormatReading(entry.candidates.pair, true)))
            self.commaDecimalButton:Show()
            self.commaPairButton:Show()
        end
        -- Editing the paste withdraws a choice offered for the old text.
        edit:SetScript("OnTextChanged", function(_, userInput)
            if userInput then withdraw() end
        end)
        self.startButton = button(L["MULTI_START"], 16, importPaste)
        button(L["MULTI_TOMTOM"], 154, function() start(self:CollectTomTomWaypoints()) end)
        button(L["MULTI_NEXT"], 292, function() self:Next() end)
        self.clearButton = button(L["MULTI_CLEAR"], 430, function() self:Clear() end)
        self.statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.statusLabel:SetPoint("BOTTOMLEFT", 16, 14)
        self.statusLabel:SetSize(548, 54)
        self.statusLabel:SetJustifyH("LEFT")
    end
    QR.FitWindowScale(self.frame, QR.db and QR.db.windowScale or 1)
    self:UpdateStatus()
    self.frame:Show()
end

_G.SLASH_QRMULTI1 = "/qrmulti"
SlashCmdList["QRMULTI"] = function(message)
    local command = type(message) == "string" and message:match("^%s*(.-)%s*$") or ""
    if command == "next" then MR:Next()
    elseif command == "clear" then MR:Clear()
    elseif command == "tomtom" then
        local stops, err = MR:CollectTomTomWaypoints()
        if stops then MR:Start(stops, true) else QR:Print(err) end
    else MR:Show() end
end
