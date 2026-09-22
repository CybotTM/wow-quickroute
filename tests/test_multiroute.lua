local T, QR = ...

T:run("MultiRoute: paste accepts percent coordinates, labels and both map syntaxes", function(t)
    local stops = QR.MultiRoute:ParseWaypoints("/way 84 1 100 First\n/way #85 50.5 0 Second")
    t:assertEqual(2, #stops, "two pasted destinations")
    t:assertEqual(0.01, stops[1].x, "one means one percent, not normalized one")
    t:assertEqual(1, stops[1].y, "100 percent reaches map edge")
    t:assertEqual(85, stops[2].mapID, "hash map ID parsed")
    t:assertEqual("Second", stops[2].title, "label preserved")
end)

T:run("MultiRoute: invalid or excessive lists fail atomically", function(t)
    for _, text in ipairs({"/way 84 -1 50", "/way 84 50 101", "/run dangerous()", "/way 84 20 30\n/way nowhere", string.rep("x", 8193)}) do
        local stops, err = QR.MultiRoute:ParseWaypoints(text)
        t:assertNil(stops, "invalid input yields no partial list")
        t:assertNotNil(err, "invalid input explains failure")
    end
    local stops = QR.MultiRoute:ParseWaypoints(string.rep("/way 84 50 50\n", 21))
    t:assertNil(stops, "21 destinations exceed bounded work")
end)

-- The pasted section of a community profession guide. This exact shape is what
-- the parser rejected before: comma-separated pairs under a heading, with a
-- note between the waypoints and a semicolon inside one label.
local GUIDE_PASTE = table.concat({
    "Midnight profession treasures - Eversong",
    "/way #2393 50.57, 56.62 Ore vein",
    "Next one is inside the cave, upper floor",
    "/way #2393 41.20, 62.80 Cave; upper floor",
}, "\n")

T:run("MultiRoute: community guide paste imports with per-line warnings", function(t)
    local stops, err, report = QR.MultiRoute:ParseWaypoints(GUIDE_PASTE)
    t:assertNil(err, "guide paste is accepted")
    t:assertEqual(2, #stops, "both comma-separated waypoints imported")
    t:assertEqual(2393, stops[1].mapID, "map ID read from the hash form")
    t:assertTrue(math.abs(stops[1].x - 0.5057) < 1e-9, "comma-separated x is 50.57 percent, got " .. stops[1].x)
    t:assertTrue(math.abs(stops[1].y - 0.5662) < 1e-9, "comma-separated y is 56.62 percent, got " .. stops[1].y)
    t:assertEqual("Cave; upper floor", stops[2].title, "semicolon inside a label is kept")
    t:assertEqual(2, report.accepted, "report counts the accepted lines")
    t:assertEqual(4, #report.entries, "report holds one row per input line")
    t:assertTrue(QR.MultiRoute:ImportHasWarnings(report), "the two prose lines are reported")
    local text = QR.MultiRoute:FormatImportReport(report)
    t:assertNotNil(text:find("Midnight profession treasures", 1, true), "skipped heading named in the preview")
end)

T:run("MultiRoute: decimal commas are one pair, not four numbers", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50,57 56,62 Vein")
    t:assertNil(err, "decimal-comma coordinates are accepted")
    t:assertEqual(1, #stops, "one stop from one line")
    t:assertTrue(math.abs(stops[1].x - 0.5057) < 1e-9, "50,57 reads as 50.57 percent, got " .. stops[1].x)
    t:assertTrue(math.abs(stops[1].y - 0.5662) < 1e-9, "56,62 reads as 56.62 percent, got " .. stops[1].y)
    t:assertEqual("Vein", stops[1].title, "label after a decimal-comma pair survives")
end)

T:run("MultiRoute: a coordinate token is read whole, or the line is refused", function(t)
    -- Reading only part of a number and keeping the rest as the label accepted
    -- the line and moved the destination, which is worse than refusing it: both
    -- values stayed inside the valid range, so nothing downstream noticed.
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50 56,62 Treasure")
    t:assertNil(err, "an integer paired with a decimal-comma value is accepted")
    t:assertTrue(math.abs(stops[1].x - 0.50) < 1e-9, "50 reads as 50 percent, got " .. stops[1].x)
    t:assertTrue(math.abs(stops[1].y - 0.5662) < 1e-9, "56,62 reads as 56.62 percent, got " .. stops[1].y)
    t:assertEqual("Treasure", stops[1].title, "the label holds no part of a coordinate")

    -- A comma on the first value and a plain number after it reads two ways;
    -- the player chooses. See "a compact comma pair before a number offers
    -- both readings" below.

    -- A point on one value and a comma on the other explain the line two ways,
    -- and neither order may be picked for the player. Refusing only one of the
    -- two orders moved the destination on the other.
    for _, line in ipairs({ "/way #2393 50,57 56.62 Treasure", "/way #2393 50.57 56,62 Treasure" }) do
        local none, noneErr, report = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(none, "no stop from: " .. line)
        t:assertNotNil(noneErr, "the failure is explained for: " .. line)
        t:assertEqual("AMBIGUOUS_COORDS", report.entries[1].reason, "named as ambiguous: " .. line)
    end

    stops, err = QR.MultiRoute:ParseWaypoints("/way #84 50, 57 Bank")
    t:assertNil(err, "the comma-separated pair is still accepted")
    t:assertTrue(math.abs(stops[1].x - 0.50) < 1e-9, "50 reads as 50 percent, got " .. stops[1].x)
    t:assertTrue(math.abs(stops[1].y - 0.57) < 1e-9, "57 reads as 57 percent, got " .. stops[1].y)
    t:assertEqual("Bank", stops[1].title, "the label after a separated pair survives")
end)

local function near(value, expected)
    return type(value) == "number" and math.abs(value - expected) < 1e-9
end

-- "50,57 56 Treasure" is the pair 50.57 and 56 with the label "Treasure", or
-- the pair 50 and 57 with the label "56 Treasure". Both are complete and in
-- range, so the parser may not pick one: a player writing decimal commas got
-- the wrong point with no warning when it did.
T:run("MultiRoute: a compact comma pair before a number offers both readings", function(t)
    local lines = {
        { "/way #2393 50,57 56 Treasure", 0.5057, 0.56, "Treasure", 0.50, 0.57, "56 Treasure" },
        { "/way #2393 45,32 3 rares here", 0.4532, 0.03, "rares here", 0.45, 0.32, "3 rares here" },
        -- Without a map token the line reaches the same pair.
        { "/way 50,57 56 Treasure", 0.5057, 0.56, "Treasure", 0.50, 0.57, "56 Treasure" },
        -- The map form without the hash.
        { "/way 84 50,57 56", 0.5057, 0.56, nil, 0.50, 0.57, "56" },
    }
    for _, case in ipairs(lines) do
        local line = case[1]
        local stops, err, report = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(stops, "no stop before a choice from: " .. line .. ", got " .. tostring(stops and #stops))
        t:assertNotNil(err, "the pending choice is explained for: " .. line)
        local entry = report.entries[1]
        t:assertEqual("ambiguous", entry and entry.status, "the line is listed as ambiguous: " .. line)
        local choices = entry and entry.candidates
        t:assertNotNil(choices, "both readings travel with the entry: " .. line)
        if choices then
            local decimal, pair = choices.decimal, choices.pair
            t:assertTrue(decimal and near(decimal.x, case[2]) and near(decimal.y, case[3]),
                "decimal reading of " .. line .. " is " .. case[2] .. ", " .. case[3] .. ", got "
                .. tostring(decimal and decimal.x) .. ", " .. tostring(decimal and decimal.y))
            t:assertEqual(case[4], decimal and decimal.title, "decimal reading label of " .. line)
            t:assertTrue(pair and near(pair.x, case[5]) and near(pair.y, case[6]),
                "pair reading of " .. line .. " is " .. case[5] .. ", " .. case[6] .. ", got "
                .. tostring(pair and pair.x) .. ", " .. tostring(pair and pair.y))
            t:assertEqual(case[7], pair and pair.title, "pair reading label of " .. line)
        end
    end
end)

T:run("MultiRoute: the preview names both readings of an ambiguous line", function(t)
    local _, _, report = QR.MultiRoute:ParseWaypoints("/way #84 10 20 First\n/way #2393 50,57 56 Treasure")
    local text = QR.MultiRoute:FormatImportReport(report) or ""
    t:assertNotNil(text:find("50.57, 56", 1, true), "decimal reading shown, preview: " .. text)
    t:assertNotNil(text:find("50, 57", 1, true), "pair reading shown, preview: " .. text)
    t:assertNotNil(text:find("56 Treasure", 1, true), "pair reading's label shown, preview: " .. text)
    t:assertNotNil(text:find("Line 2", 1, true), "the line the player counts is named, preview: " .. text)
end)

T:run("MultiRoute: choosing the decimal reading imports 50.57 and 56", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50,57 56 Treasure", { [1] = "decimal" })
    t:assertNil(err, "the chosen line is accepted, got " .. tostring(err))
    local stop = stops and stops[1]
    t:assertTrue(stop and near(stop.x, 0.5057), "x is 50.57, got " .. tostring(stop and stop.x))
    t:assertTrue(stop and near(stop.y, 0.56), "y is 56, got " .. tostring(stop and stop.y))
    t:assertEqual("Treasure", stop and stop.title, "the label is the text after 56")
end)

-- On the code before the choice existed this test is green as well: the parser
-- ignored the second argument and always took this reading.
T:run("MultiRoute: choosing the pair reading imports 50 and 57 with the number in the label", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50,57 56 Treasure", { [1] = "pair" })
    t:assertNil(err, "the chosen line is accepted, got " .. tostring(err))
    local stop = stops and stops[1]
    t:assertTrue(stop and near(stop.x, 0.50), "x is 50, got " .. tostring(stop and stop.x))
    t:assertTrue(stop and near(stop.y, 0.57), "y is 57, got " .. tostring(stop and stop.y))
    t:assertEqual("56 Treasure", stop and stop.title, "the label keeps its number")
end)

T:run("MultiRoute: without a choice nothing is imported, not even the clear lines", function(t)
    local paste = "/way #84 10 20 First\n/way #2393 50,57 56 Treasure\n/way #84 30 40 Last"
    local stops, err, report = QR.MultiRoute:ParseWaypoints(paste)
    t:assertNil(stops, "no partial trip, got " .. tostring(stops and #stops) .. " stops")
    t:assertNotNil(err, "the import says why it stopped")
    local pending = {}
    for _, entry in ipairs(report.entries) do
        if entry.status == "ambiguous" then pending[#pending + 1] = entry.line end
    end
    t:assertEqual(1, #pending, "exactly one line waits for a choice, got " .. #pending)
    t:assertEqual(2, pending[1], "and it is line 2, got " .. tostring(pending[1]))
    -- A choice for one line resolves only that line.
    local two = "/way #2393 50,57 56 A\n/way #2393 45,32 3 B"
    stops = QR.MultiRoute:ParseWaypoints(two, { [1] = "decimal" })
    t:assertNil(stops, "the second line still waits, got " .. tostring(stops and #stops))
    stops = QR.MultiRoute:ParseWaypoints(two, { [1] = "decimal", [2] = "pair" })
    t:assertEqual(2, stops and #stops, "both lines chosen, got " .. tostring(stops and #stops))
    t:assertTrue(stops and near(stops[1].x, 0.5057), "line 1 took the decimal reading, got " .. tostring(stops and stops[1].x))
    t:assertTrue(stops and near(stops[2].x, 0.45), "line 2 took the pair reading, got " .. tostring(stops and stops[2].x))
    t:assertEqual("3 B", stops and stops[2].title, "line 2 label keeps its number")
end)

T:run("MultiRoute: a comma pair with only one valid reading is not offered as a choice", function(t)
    -- 150 is no coordinate, so only the pair reading exists and it is read
    -- as before.
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50,57 150 Label")
    t:assertNil(err, "accepted, got " .. tostring(err))
    t:assertTrue(stops and near(stops[1].x, 0.50) and near(stops[1].y, 0.57),
        "read as 50 and 57, got " .. tostring(stops and stops[1].x) .. ", " .. tostring(stops and stops[1].y))
    t:assertEqual("150 Label", stops and stops[1].title, "the number stays in the label")
    -- 570 is no coordinate, so the pair reading does not exist. The line is
    -- refused as it was before, not turned into a choice.
    local none, noneErr, report = QR.MultiRoute:ParseWaypoints("/way #2393 50,570 56 Treasure")
    t:assertNil(none, "no stop, got " .. tostring(none and #none))
    t:assertNotNil(noneErr, "the line is reported")
    t:assertEqual("BAD_COORDS", report.entries[1].reason, "refused as before, got " .. tostring(report.entries[1].reason))
end)

T:run("MultiRoute: the trip window asks for the reading and imports the one chosen", function(t)
    local mr = QR.MultiRoute
    local combat, start, message = InCombatLockdown, mr.Start, mr.message
    _G.InCombatLockdown = function() return false end
    local started
    mr.Start = function(_, stops) started = stops; return true end
    mr:Show()
    local previous = mr.editBox:GetText()
    mr.editBox:SetText("/way #2393 50,57 56 Treasure")
    t:assertNotNil(mr.startButton, "the start button is reachable")
    t:assertNotNil(mr.commaDecimalButton, "the decimal choice button exists")
    if mr.startButton and mr.commaDecimalButton and mr.commaPairButton then
        t:assertFalse(mr.commaDecimalButton:IsShown(), "no choice is offered before an ambiguous paste")
        mr.startButton:GetScript("OnClick")()
        t:assertNil(started, "nothing started before the choice, got " .. tostring(started and #started))
        t:assertTrue(mr.commaDecimalButton:IsShown(), "decimal choice offered")
        t:assertTrue(mr.commaPairButton:IsShown(), "pair choice offered")
        mr.commaDecimalButton:GetScript("OnClick")()
        local stop = started and started[1]
        t:assertTrue(stop and near(stop.x, 0.5057) and near(stop.y, 0.56),
            "the decimal reading was imported, got " .. tostring(stop and stop.x) .. ", " .. tostring(stop and stop.y))
        t:assertFalse(mr.commaDecimalButton:IsShown(), "the choice is withdrawn after the import")
        -- A different paste does not inherit the choice made for the old one.
        started = nil
        mr.editBox:SetText("/way #2393 45,32 3 rares here")
        mr.startButton:GetScript("OnClick")()
        t:assertNil(started, "a new ambiguous paste waits again, got " .. tostring(started and #started))
        mr.commaPairButton:GetScript("OnClick")()
        stop = started and started[1]
        t:assertTrue(stop and near(stop.x, 0.45) and near(stop.y, 0.32),
            "the pair reading was imported, got " .. tostring(stop and stop.x) .. ", " .. tostring(stop and stop.y))
    end
    mr.editBox:SetText(previous or "")
    mr.Start, mr.message = start, message
    if mr.commaDecimalButton then mr.commaDecimalButton:Hide(); mr.commaPairButton:Hide() end
    if mr.frame then mr.frame:Hide() end
    _G.InCombatLockdown = combat
end)

T:run("MultiRoute: punctuation after a coordinate belongs to the line, not to the number", function(t)
    -- A guide writing "60, near the tree" means the coordinate 60. Reading the
    -- comma as part of the number failed the pair, and the line was then read
    -- again as map-plus-one-coordinate: the map id became x, the current map
    -- became the destination, and both numbers stayed in range.
    local forms = {
        ["/way 84 50 60, near the tree"] = "near the tree",
        -- A dot or comma ending the number is dropped; any other character
        -- stays with the label, as the released parser left it.
        ["/way 84 50 60: Bank"] = ": Bank",
        ["/way 84 50 60- Bank"] = "- Bank",
        ["/way 84 50. 60 Label"] = "Label",
    }
    for line, label in pairs(forms) do
        local stops, err = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(err, "accepted: " .. line)
        t:assertEqual(84, stops and stops[1].mapID, "the leading number stays the map in: " .. line)
        t:assertTrue(stops and math.abs(stops[1].x - 0.50) < 1e-9, "x is 50 in: " .. line)
        t:assertTrue(stops and math.abs(stops[1].y - 0.60) < 1e-9, "y is 60 in: " .. line)
        t:assertEqual(label, stops and stops[1].title, "the label keeps its words in: " .. line)
    end
end)

T:run("MultiRoute: a label starting with a dot is not a third number", function(t)
    -- The map form is two numbers after a leading one. A dot with no digit
    -- behind it starts a label, so "/way 45 60 .Bank" is the pair 45 and 60
    -- on the current map, as the released parser read it.
    local stops, err = QR.MultiRoute:ParseWaypoints("/way 45 60 .Bank")
    t:assertNil(err, "the line is accepted")
    t:assertTrue(stops and math.abs(stops[1].x - 0.45) < 1e-9, "x is 45, got " .. tostring(stops and stops[1].x))
    t:assertTrue(stops and math.abs(stops[1].y - 0.60) < 1e-9, "y is 60, got " .. tostring(stops and stops[1].y))
end)

T:run("MultiRoute: a map line whose pair cannot be read is refused, not re-paired", function(t)
    -- Two numbers follow the map id, so the line is the map form. The pair is
    -- unreadable, and the answer is a refusal rather than a destination on
    -- whichever map the player happens to be standing on.
    local stops, err, report = QR.MultiRoute:ParseWaypoints("/way 84 50 .5 Label")
    t:assertNil(stops, "no stop from an unreadable pair")
    t:assertNotNil(err, "the line is reported")
    t:assertEqual("BAD_COORDS", report.entries[1].reason, "and named as an unreadable pair")
    -- A decimal mark with a digit behind it, straight after a value that has
    -- no fraction yet, means the reader stopped in the middle of a number.
    -- Reading 60 and keeping ".5 Label" as the label would be the partial read
    -- this parser exists to refuse.
    -- The second line is the one that could fall through: a comma separates
    -- its pair, so the comma-separated shape would read it as 50.5 and 60 and
    -- drop the cut fraction into the label.
    for _, line in ipairs({ "/way 84 50 60..5 Label", "/way #2393 50.5, 60..5 Treasure" }) do
        local none, noneErr, noneReport = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(none, "no stop from: " .. line)
        t:assertNotNil(noneErr, "the failure is explained for: " .. line)
        t:assertEqual("BAD_COORDS", noneReport.entries[1].reason, "named as an unreadable pair: " .. line)
    end
end)

T:run("MultiRoute: two numbers with no map use the current map", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way 50 60 Bank")
    t:assertNil(err, "the two-number form is accepted")
    t:assertEqual(QR.TravelTime:GetCurrentMapID(), stops[1].mapID, "the stop lands on the current map")
    t:assertTrue(math.abs(stops[1].x - 0.50) < 1e-9, "x is 50, got " .. stops[1].x)
    t:assertTrue(math.abs(stops[1].y - 0.60) < 1e-9, "y is 60, got " .. stops[1].y)
end)

T:run("MultiRoute: a pair that was read is kept or refused, never re-read", function(t)
    -- Both values were read, and something glued to the second one is not a
    -- label the first reading accepts. Handing the line to the comma-separated
    -- shape took the comma inside "50,57" as the separator and imported
    -- (50, 57) -- the pair the line does not name.
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #2393 50,57 56,62-2 Treasure")
    t:assertNil(err, "the line is accepted")
    t:assertTrue(stops and math.abs(stops[1].x - 0.5057) < 1e-9, "x is 50.57, got " .. tostring(stops and stops[1].x))
    t:assertTrue(stops and math.abs(stops[1].y - 0.5662) < 1e-9, "y is 56.62, got " .. tostring(stops and stops[1].y))
    -- A value that already carries its fraction cannot be continued, so the
    -- mark behind it starts the label.
    stops, err = QR.MultiRoute:ParseWaypoints("/way 84 50.25 60.75,3 chests")
    t:assertNil(err, "a mark after a finished fraction is not a cut number")
    t:assertTrue(stops and math.abs(stops[1].y - 0.6075) < 1e-9, "y is 60.75, got " .. tostring(stops and stops[1].y))
    -- Punctuation other than a dot or comma stays in the label, and a digit
    -- behind it is the label's, not the number's.
    for _, line in ipairs({ "/way 84 50 60-5 Label", "/way 84 50 60#2", "/way 84 50 60(2)" }) do
        local accepted, failure = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(failure, "accepted: " .. line)
        t:assertTrue(accepted and math.abs(accepted[1].y - 0.60) < 1e-9, "y is 60 in: " .. line)
    end
end)

T:run("MultiRoute: a label may sit straight against the second coordinate", function(t)
    -- A guide that writes no space before its note still names one place. The
    -- number is whole either way, so there is nothing to refuse -- only a digit
    -- behind the value, or a decimal mark with a digit behind it, means the
    -- reader stopped in the middle of a number.
    local forms = { "/way 84 50 60Bank", "/way 84 50 60,near the tree", "/way 84 50 60:Bank" }
    for _, line in ipairs(forms) do
        local stops, err = QR.MultiRoute:ParseWaypoints(line)
        t:assertNil(err, "accepted: " .. line)
        t:assertEqual(84, stops and stops[1].mapID, "the leading number stays the map in: " .. line)
        t:assertTrue(stops and math.abs(stops[1].y - 0.60) < 1e-9, "y is 60 in: " .. line)
    end
end)

T:run("MultiRoute: an ambiguous pair with no map token is named, not retried as a zone", function(t)
    -- Without the map token the line reaches the pair directly. Letting an
    -- ambiguous pair fall through to the zone-name shape reported it as an
    -- unreadable pair instead, which tells the player to check the wrong
    -- thing.
    local stops, err, report = QR.MultiRoute:ParseWaypoints("/way 50,57 56.62 Treasure")
    t:assertNil(stops, "no stop from a line that names two places")
    t:assertNotNil(err, "the line is reported")
    t:assertEqual("AMBIGUOUS_COORDS", report.entries[1].reason, "and named as ambiguous, not as bad coordinates")
end)

T:run("MultiRoute: zone name resolves, unknown and ambiguous names are reported", function(t)
    QR.MultiRoute:ResetZoneNameIndex()
    local stops, err = QR.MultiRoute:ParseWaypoints("/way Stormwind City 49.65 87.25 Bank")
    t:assertNil(err, "a known zone name is accepted")
    t:assertEqual(84, stops[1].mapID, "Stormwind City resolves to map 84")
    local none, noneErr, report = QR.MultiRoute:ParseWaypoints("/way Nowhereland 10 20")
    t:assertNil(none, "an unknown zone name yields no stops")
    t:assertNotNil(noneErr, "an unknown zone name explains the failure")
    t:assertEqual("UNKNOWN_MAP", report.entries[1].reason, "reason names the unresolved map token")
    QR.MultiRoute:ResetZoneNameIndex()
end)

T:run("MultiRoute: a pair without a map uses the current map", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way 49.65 87.25 Bank")
    t:assertNil(err, "the TomTom current-map form is accepted")
    t:assertEqual(1, #stops, "one stop from the current-map form")
    t:assertEqual(QR.TravelTime:GetCurrentMapID(), stops[1].mapID, "stop lands on the current map")
end)

T:run("MultiRoute: imports all active TomTom maps excluding addon navigation pins", function(t)
    local saved = TomTom
    TomTom = { waypoints = {
        [84] = { a = {84, 0.2, 0.3, title = "First"}, b = {84, 0.4, 0.5, title = "QR: Walk", from = "QuickRoute"} },
        [85] = { c = {85, 0.6, 0.7, title = "Second"} },
    } }
    local stops = QR.MultiRoute:CollectTomTomWaypoints()
    t:assertEqual(2, #stops, "both maps imported without generated navigation pin")
    TomTom = saved
end)

T:run("MultiRoute: disconnected tour falls back to current fastest leg and replans after completion", function(t)
    local mr = QR.MultiRoute
    local calc, show, db = QR.PathCalculator.CalculatePath, mr.DisplayRoute, QR.db
    local from, context = QR.PathCalculator.CalculatePathFrom, QR.PathCalculator.CreateRouteContext
    QR.PathCalculator.CreateRouteContext = nil
    QR.PathCalculator.CalculatePathFrom = function() return nil end
    local costs = { [84] = 80, [85] = 10, [86] = 25 }
    QR.db = {}
    QR.PathCalculator.CalculatePath = function(_, mapID)
        return { totalTime = costs[mapID], steps = {} }
    end
    local shown
    mr.DisplayRoute = function(_, stop) shown = stop.mapID end
    mr:Start({{mapID=84,x=0.5,y=0.5}, {mapID=85,x=0.5,y=0.5}, {mapID=86,x=0.5,y=0.5}}, true)
    t:assertEqual(85, shown, "first destination has lowest route time")
    costs[84], costs[86] = 5, 90
    mr:Next()
    t:assertEqual(84, shown, "second choice uses new costs after travel")
    t:assertEqual(1, mr.completed, "only completed stop is removed")
    t:assertEqual(2, #mr.stops, "remaining destinations retained")
    mr:Clear()
    QR.PathCalculator.CalculatePath, mr.DisplayRoute, QR.db = calc, show, db
    QR.PathCalculator.CalculatePathFrom, QR.PathCalculator.CreateRouteContext = from, context
end)

T:run("MultiRoute: unreachable destinations stay pending and preserve-order mode does not skip", function(t)
    local mr = QR.MultiRoute
    local calc, show = QR.PathCalculator.CalculatePath, mr.DisplayRoute
    QR.PathCalculator.CalculatePath = function(_, mapID)
        if mapID == 85 then return {totalTime=5,steps={}} end
    end
    mr.DisplayRoute = function() end
    mr:Start({{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, false)
    t:assertNil(mr.currentIndex, "unreachable first stop is not bypassed in input order")
    t:assertEqual(2, #mr.stops, "unreachable stop is never discarded")
    mr:Clear()
    QR.PathCalculator.CalculatePath, mr.DisplayRoute = calc, show
end)

T:run("MultiRoute: cancel invalidates asynchronous work", function(t)
    local mr = QR.MultiRoute
    local after, calc, show = C_Timer.After, QR.PathCalculator.CalculatePath, mr.DisplayRoute
    local callbacks, shown = {}, 0
    C_Timer.After = function(_, callback) callbacks[#callbacks+1] = callback end
    QR.PathCalculator.CalculatePath = function() return {totalTime=5,steps={}} end
    mr.DisplayRoute = function() shown = shown+1 end
    mr:Start({{mapID=84,x=0.5,y=0.5}}, true)
    mr:Clear()
    for _, callback in ipairs(callbacks) do callback() end
    t:assertEqual(0, shown, "cancelled calculation cannot overwrite current route")
    C_Timer.After, QR.PathCalculator.CalculatePath, mr.DisplayRoute = after, calc, show
end)

T:run("MultiRoute: trip window exposes paste controls and reuses its frame", function(t)
    local mr = QR.MultiRoute
    local combat = InCombatLockdown
    _G.InCombatLockdown = function() return false end
    local ok, err = pcall(mr.Show, mr)
    t:assertTrue(ok, "trip window opens: " .. tostring(err))
    t:assertNotNil(mr.editBox, "multiline paste editor is available")
    local frame = mr.frame
    mr:Show()
    t:assertEqual(frame, mr.frame, "reopening reuses the window")
    if frame then frame:Hide() end
    _G.InCombatLockdown = combat
end)

T:run("MultiRoute: complete-tour order uses isolated origin costs and live executable leg", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local from, calc, show, db = pc.CalculatePathFrom, pc.CalculatePath, mr.DisplayRoute, QR.db
    local createContext = pc.CreateRouteContext
    local getMap, getPosition = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition
    C_Map.GetBestMapForUnit = function() return 84 end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return 0.5,0.5 end} end
    QR.db = {}
    local matrix = {[84]={[85]=1,[86]=2,[87]=4},[85]={[86]=100,[87]=100},[86]={[85]=1,[87]=1},[87]={[85]=1,[86]=1}}
    local calls, contexts, liveDestination, shown = 0, 0
    pc.CalculatePathFrom = function() error("Tour must reuse its context") end
    pc.CreateRouteContext = function(_, options)
        contexts = contexts + 1
        t:assertTrue(options.excludeCooldowns, "tour matrix excludes consumable teleport assumptions")
        return {CalculatePathFrom=function(_, a, _, _, b)
            calls = calls + 1
            return {totalTime=matrix[a][b],steps={}}
        end}
    end
    pc.CalculatePath = function(_, mapID)
        liveDestination = mapID
        return {totalTime=0.75,steps={{type="teleport"}}}
    end
    mr.DisplayRoute = function(_, stop, result) shown = {stop=stop,result=result} end
    mr:Start({{mapID=85,x=0.5,y=0.5},{mapID=86,x=0.5,y=0.5},{mapID=87,x=0.5,y=0.5}}, true)
    t:assertEqual(9, calls, "three-stop tour compares nine directed legs")
    t:assertEqual(1, contexts, "all directed comparisons reuse one isolated graph")
    t:assertEqual(86, shown.stop.mapID, "whole-tour optimum starts at second-nearest destination")
    t:assertEqual(86, liveDestination, "displayed leg recalculated from actual player state")
    t:assertEqual(0.75, shown.result.totalTime, "live teleport time replaces reusable estimate")
    t:assertEqual(4, mr.planCost, "separate whole-tour estimate preserved")
    t:assertEqual(85, mr.stops[3].mapID, "expensive outgoing destination placed last")
    mr:Clear()
    pc.CalculatePathFrom, pc.CalculatePath, mr.DisplayRoute, QR.db = from, calc, show, db
    pc.CreateRouteContext = createContext
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = getMap, getPosition
end)

T:run("MultiRoute: saved trips restore per character without executing navigation", function(t)
    local mr, guid, db = QR.MultiRoute, UnitGUID, QR.db
    UnitGUID = function() return "Player-trip-test" end
    QR.db = { multiRouteTrips = {
        ["Player-trip-test"]={stops={{mapID=84,x=0.5,y=0.6,title="Saved"}},completed=2,optimize=true},
        ["Player-other"]={stops={{mapID=85,x=0.2,y=0.3}},completed=0},
    } }
    mr:Initialize()
    t:assertEqual(84, mr.stops[1].mapID, "restores only current character's trip")
    t:assertEqual(2, mr.completed, "retains completed count")
    t:assertFalse(mr.busy, "login does not launch unattended routing")
    t:assertNil(mr.currentIndex, "resume does not mark an unvisited stop completed")
    mr:Clear()
    t:assertNotNil(QR.db.multiRouteTrips["Player-other"], "clearing trip preserves another character")
    QR.db.multiRouteTrips["Player-trip-test"]={stops={{mapID=84,x=math.huge,y=0.6}}}
    mr:Initialize()
    t:assertEqual(0, #mr.stops, "invalid saved coordinate cannot restore a route")
    t:assertNil(QR.db.multiRouteTrips["Player-trip-test"], "invalid record removed")
    UnitGUID, QR.db = guid, db
end)

T:run("MultiRoute: moving during live-next fallback restarts every candidate", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local saved = {after=C_Timer.After, calc=pc.CalculatePath, show=mr.DisplayRoute,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition, db=QR.db}
    local pending, origin, shown, calls = {}, 84, nil, 0
    QR.db = {}
    C_Map.GetBestMapForUnit = function() return origin end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return 0.5,0.5 end} end
    C_Timer.After = function(_, callback) pending[#pending+1] = callback end
    pc.CalculatePath = function(_, mapID)
        calls = calls + 1
        return {totalTime=mapID == origin and 5 or 95,steps={}}
    end
    mr.DisplayRoute = function(_, stop) shown = stop.mapID end
    local ok, err = pcall(function()
        mr.stops, mr.total, mr.fastestNext = {{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, 2, true
        mr:SelectNext(true)
        pending[1]()
        origin = 85
        local index = 2
        while pending[index] do pending[index](); index = index + 1 end
        t:assertEqual(85, shown, "Movement recomputes ranking and selects new origin's closest stop")
        t:assertEqual(4, calls, "Old first candidate discarded, two candidates compared, winning leg refreshed")
        t:assertEqual(2, #mr.stops, "Movement never discards an unvisited destination")
    end)
    mr:Clear()
    C_Timer.After, pc.CalculatePath, mr.DisplayRoute = saved.after, saved.calc, saved.show
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, QR.db = saved.map, saved.position, saved.db
    if not ok then error(err) end
end)

T:run("MultiRoute: repeated movement stops bounded selection without publishing a stale leg", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local saved = {after=C_Timer.After, calc=pc.CalculatePath, show=mr.DisplayRoute,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition, db=QR.db}
    local pending, x, published, calls = {}, 0.3, 0, 0
    QR.db = {}
    C_Map.GetBestMapForUnit = function() return 84 end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return x,0.5 end} end
    C_Timer.After = function(_, callback) pending[#pending+1] = callback end
    pc.CalculatePath = function() calls = calls + 1; return {totalTime=5,steps={}} end
    mr.DisplayRoute = function() published = published + 1 end
    local ok, err = pcall(function()
        mr.stops, mr.total, mr.fastestNext = {{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, 2, true
        mr:SelectNext(true)
        for index=1,10 do
            if not pending[index] then break end
            x = x + 0.02
            pending[index]()
        end
        t:assertEqual(0, published, "No stale winner is displayed during sustained movement")
        t:assertEqual(2, calls, "Only two restart calculations are allowed")
        t:assertFalse(mr.busy, "Aborted selection releases busy state")
        t:assertEqual(QR.L["MULTI_POSITION_CHANGED"], mr.message, "Status explains how to retry")
        t:assertEqual(2, #mr.stops, "Pending stops survive a bounded abort")
    end)
    mr:Clear()
    C_Timer.After, pc.CalculatePath, mr.DisplayRoute = saved.after, saved.calc, saved.show
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, QR.db = saved.map, saved.position, saved.db
    if not ok then error(err) end
end)

T:run("MultiRoute: pasted text cannot put a live link or colour code in the status label", function(t)
    local paste = "|cFFFF0000|Hitem:6948|h[Hearthstone]|h|r\n/way #84 50 60 X"
    local stops, err, report = QR.MultiRoute:ParseWaypoints(paste)
    t:assertNil(err, "the waypoint line is still imported")
    t:assertEqual(1, #stops, "one stop from the paste")
    local text = QR.MultiRoute:FormatImportReport(report)
    t:assertNil(text:find("|c", 1, true) and not text:find("||c", 1, true) or nil,
        "no unescaped colour code reaches the label")
    t:assertNotNil(text:find("||Hitem", 1, true), "the link escape is doubled, got: " .. text)
    local _, _, tokenReport = QR.MultiRoute:ParseWaypoints("/way |cFF00FF00Nowhere|r 50 60")
    local tokenText = QR.MultiRoute:FormatImportReport(tokenReport)
    t:assertNotNil(tokenText:find("||cFF00FF00", 1, true), "an unresolved map token is escaped too")
end)

T:run("MultiRoute: the preview is bounded however long the paste is", function(t)
    local paste = string.rep("just a note\n", 400) .. "/way #84 50 60 X"
    local stops, err, report = QR.MultiRoute:ParseWaypoints(paste)
    t:assertNil(err, "the one waypoint is still imported")
    t:assertEqual(1, #stops, "one stop")
    t:assertEqual(401, report.total, "the report counts every input line")
    t:assertTrue(#report.entries <= 41, "the rows are capped, got " .. #report.entries)
    local text = QR.MultiRoute:FormatImportReport(report)
    t:assertTrue(#text < 4000, "the status text stays readable, got " .. #text .. " bytes")
    t:assertNotNil(text:find("not shown", 1, true), "the suppressed rows are counted in the text")
end)

T:run("MultiRoute: a semicolon only splits before a real /way command", function(t)
    local stops, err = QR.MultiRoute:ParseWaypoints("/way #84 50 60 Cave; /wayside inn")
    t:assertNil(err, "the line is accepted")
    t:assertEqual(1, #stops, "one stop, not a split")
    t:assertEqual("Cave; /wayside inn", stops[1].title, "the label keeps the whole text, got " .. tostring(stops[1].title))
end)

T:run("MultiRoute: a warning names the line the player counts", function(t)
    local paste = "/way #84 50 60 A\n\n\nthis is prose\n/way #84 10 20 B"
    local stops, err, report = QR.MultiRoute:ParseWaypoints(paste)
    t:assertNil(err, "the two waypoints are imported")
    t:assertEqual(2, #stops, "two stops")
    local skipped
    for _, entry in ipairs(report.entries) do
        if entry.status == "skipped" then skipped = entry end
    end
    t:assertNotNil(skipped, "the prose line is reported")
    t:assertEqual(4, skipped.line, "the blank lines are counted, got line " .. tostring(skipped.line))
end)

T:run("MultiRoute: the summary and the warnings count the same lines", function(t)
    local _, err, report = QR.MultiRoute:ParseWaypoints("/way #84 50 60 A\n\n\nthis is prose\n/way #84 10 20 B")
    t:assertNil(err, "the paste is accepted")
    t:assertEqual(5, report.total, "the summary counts physical lines, got " .. report.total)
    local skipped
    for _, entry in ipairs(report.entries) do
        if entry.status == "skipped" then skipped = entry end
    end
    t:assertTrue(skipped.line <= report.total,
        "a warning cannot name a line past the total: line " .. skipped.line .. " of " .. report.total)
    local _, _, split = QR.MultiRoute:ParseWaypoints("/way #84 50 60 A; /way #84 10 20 B")
    t:assertEqual(1, split.total, "one pasted line stays one line however it splits, got " .. split.total)
end)

T:run("MultiRoute: a leading semicolon produces no warning about a line nobody wrote", function(t)
    local stops, err, report = QR.MultiRoute:ParseWaypoints(";/way #84 50 60 A")
    t:assertNil(err, "the waypoint is imported")
    t:assertEqual(1, #stops, "one stop")
    t:assertFalse(QR.MultiRoute:ImportHasWarnings(report),
        "nothing is reported for the empty fragment before the semicolon")
end)

T:run("MultiRoute: a carriage return ends a line too", function(t)
    for _, paste in ipairs({ "/way #84 50 60 A\r/way #84 10 20 B", "/way #84 50 60 A\r\n/way #84 10 20 B" }) do
        local stops, err = QR.MultiRoute:ParseWaypoints(paste)
        t:assertNil(err, "the paste is accepted")
        t:assertEqual(2, #stops, "both waypoints are read, got " .. #stops)
        t:assertEqual("A", stops[1].title, "the first label does not swallow the second line")
    end
end)

T:run("MultiRoute: the suppressed count names only rows the preview withheld", function(t)
    local paste = string.rep("note\n", 30) .. string.rep("/way #84 50 60 A\n", 15)
    local stops, err, report = QR.MultiRoute:ParseWaypoints(paste)
    t:assertNil(err, "the waypoints are imported")
    t:assertEqual(15, #stops, "all fifteen stops")
    t:assertEqual(0, report.suppressed,
        "thirty warnings fit in the budget, so nothing was withheld, got " .. report.suppressed)
    local text = QR.MultiRoute:FormatImportReport(report)
    t:assertNil(text:find("not shown", 1, true), "and the label does not claim otherwise")
end)

T:run("MultiRoute: a trailing newline does not add a line nobody wrote", function(t)
    local _, err, report = QR.MultiRoute:ParseWaypoints("/way #84 50 60 A\nnote\n")
    t:assertNil(err, "the paste is accepted")
    t:assertEqual(2, report.total, "two pasted lines are two lines, got " .. report.total)
    local _, _, without = QR.MultiRoute:ParseWaypoints("/way #84 50 60 A\nnote")
    t:assertEqual(2, without.total, "with or without the terminator, got " .. without.total)
    local _, _, blank = QR.MultiRoute:ParseWaypoints("/way #84 50 60 A\n\nnote\n")
    t:assertEqual(3, blank.total, "an interior blank line still counts, got " .. blank.total)
end)

T:run("MultiRoute: a large line-feed paste is read in one scan", function(t)
    -- The splitter used a "\r\n?" pattern that never matches in a paste with no
    -- carriage return, so it rescanned to the end of the text once per line.
    local clock = _G.debugprofilestop
    if type(clock) ~= "function" then
        t:assert(true, "no profiler in this environment; the shape is covered by the other assertions")
        return
    end
    local lf = string.rep("x\n", 4000)
    local crlf = string.rep("x\r\n", 2600)
    local started = clock()
    QR.MultiRoute:ParseWaypoints(lf)
    local lfCost = clock() - started
    started = clock()
    QR.MultiRoute:ParseWaypoints(crlf)
    local crlfCost = clock() - started
    -- CRLF is the control: that shape always matched on the first character and
    -- was never slow. A line-feed paste must not cost a multiple of it.
    t:assertTrue(lfCost < crlfCost * 4 + 5,
        "a line-feed paste costs about what a CRLF paste costs: " .. lfCost .. " vs " .. crlfCost)
end)
