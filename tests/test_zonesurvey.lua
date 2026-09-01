-------------------------------------------------------------------------------
-- test_zonesurvey.lua
-- Tests for QR.ZoneSurvey — the zone-change recorder that answers questions the
-- exported client tables cannot: which map the client puts the player on, and
-- whether the addon's own tables know it.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local function resetState()
    MockWoW:Reset()
    QR.db = QR.db or {}
    QR.db.zoneSurveyEnabled = true
    QR.db.zoneSurvey = {}
end

T:run("ZoneSurvey: records the map the client reports", function(t)
    resetState()
    MockWoW.config.currentMapID = 63

    local mapID = QR.ZoneSurvey:Capture()
    t:assertEqual(63, mapID, "the capture reports which map it stored")

    local record = QR.db.zoneSurvey[63]
    t:assertNotNil(record, "a record exists for map 63")
    if not record then return end
    t:assertEqual(1, record.visits, "first visit")
    t:assertNotNil(record.seen, "carries a timestamp")
end)

T:run("ZoneSurvey: a revisit updates rather than appends", function(t)
    resetState()
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:Capture()

    t:assertEqual(1, QR.ZoneSurvey:Count(),
        "one record per map, however often it is visited")
    t:assertEqual(3, QR.db.zoneSurvey[63].visits, "and the visit count grows")
end)

T:run("ZoneSurvey: separate maps get separate records", function(t)
    resetState()
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 84
    QR.ZoneSurvey:Capture()

    t:assertEqual(2, QR.ZoneSurvey:Count(), "two maps, two records")
    t:assertNotNil(QR.db.zoneSurvey[84], "the second map is there")
end)

T:run("ZoneSurvey: records what the addon knows about the map", function(t)
    resetState()
    -- Ashenvale: the addon has a flight master for each faction here, and the
    -- verification output claiming otherwise is what prompted this recorder.
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[63]
    t:assertNotNil(record, "the map was recorded")
    if not record then return end
    t:assertNotNil(record.flightPoint,
        "a zone with a flight master records it")
    t:assertNotNil(record.adjacent,
        "and how many neighbours the addon believes it has")
end)

T:run("ZoneSurvey: switched off, it records nothing", function(t)
    resetState()
    QR.db.zoneSurveyEnabled = false
    MockWoW.config.currentMapID = 63

    t:assertNil(QR.ZoneSurvey:Capture(), "no capture while off")
    t:assertEqual(0, QR.ZoneSurvey:Count(), "and nothing stored")
end)

T:run("ZoneSurvey: Clear empties the store", function(t)
    resetState()
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    t:assertEqual(1, QR.ZoneSurvey:Count(), "one record before")
    QR.ZoneSurvey:Clear()
    t:assertEqual(0, QR.ZoneSurvey:Count(), "none after")
end)

T:run("ZoneSurvey: Render lists every record", function(t)
    resetState()
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 84
    QR.ZoneSurvey:Capture()

    -- Only the records section. The crossings table below it also has rows
    -- beginning "| 63 |", so matching the whole output passed even with the
    -- records table entirely missing -- verified by removing it.
    local out = QR.ZoneSurvey:Render()
    local records = out:match("^(.-)### Observed crossings") or out
    t:assertNotNil(records:match("| 63 |"), "map 63 appears as a record row")
    t:assertNotNil(records:match("| 84 |"), "map 84 appears as a record row")
end)

-------------------------------------------------------------------------------
-- Observed crossings
--
-- Zone boxes are rectangles and overlap across a whole continent, so geometry
-- cannot say which zones border each other: measured against the current
-- tables it claims 148 pairs that are not neighbours, Durotar to Mulgore among
-- them. A player crossing from one zone into the next can, provided a walk is
-- told apart from a portal.
-------------------------------------------------------------------------------

T:run("ZoneSurvey: a crossing without a loading screen is recorded as walked", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[77]
    t:assertNotNil(record and record.from and record.from[63],
        "the arrival is recorded on the destination")
    if not (record and record.from and record.from[63]) then return end
    t:assertEqual(1, record.from[63].walked, "counted as walked")
    t:assertEqual(0, record.from[63].loaded, "and not as a portal")
end)

T:run("ZoneSurvey: a crossing after a loading screen is not counted as walked", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:NoteLoadingScreen()
    MockWoW.config.currentMapID = 84
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[84]
    if not (record and record.from and record.from[63]) then
        t:assertTrue(false, "the arrival should still be recorded")
        return
    end
    t:assertEqual(0, record.from[63].walked,
        "a portal says nothing about two zones bordering each other")
    t:assertEqual(1, record.from[63].loaded, "and is counted on its own")
end)

T:run("ZoneSurvey: staying in one zone records no crossing", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[63]
    t:assertNil(record and record.from, "no arrival from itself")
end)

T:run("ZoneSurvey: crossings survive a revisit rebuilding the record", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()
    -- Back and forth. The record for 77 is rebuilt on the second arrival, and
    -- the crossings are the part that has to accumulate rather than reset.
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[77]
    t:assertNotNil(record and record.from and record.from[63],
        "the crossing is on record at all")
    if not (record and record.from and record.from[63]) then return end
    t:assertEqual(2, record.from[63].walked, "both crossings counted")
end)

T:run("ZoneSurvey: Clear forgets where the player came from", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:Clear()
    -- Without forgetting, this would record an arrival from a map the store no
    -- longer holds.
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[77]
    t:assertNil(record and record.from, "no crossing invented across a clear")
end)

T:run("ZoneSurvey: a crossing entry missing a counter does not break the capture", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    -- This table comes back from SavedVariables, a file that survives version
    -- changes and hand-editing, so an entry can arrive without its counters.
    QR.db.zoneSurvey[77].from[63] = { walked = 1 }

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:NoteLoadingScreen()
    MockWoW.config.currentMapID = 77
    local ok = pcall(function() return QR.ZoneSurvey:Capture() end)

    t:assertTrue(ok, "the capture survives an entry with a missing counter")
    local entry = QR.db.zoneSurvey[77] and QR.db.zoneSurvey[77].from
        and QR.db.zoneSurvey[77].from[63]
    t:assertNotNil(entry, "the entry survives and is still there")
    if not entry then return end
    t:assertEqual(1, entry.loaded, "the missing counter starts at zero and counts")
    t:assertEqual(1, entry.walked, "and the one that was there is kept")
end)

T:run("ZoneSurvey: switching off and on again invents no crossing", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    -- Somewhere, recorded.
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()

    -- Off. The player then travels -- by portal, several zones -- and none of
    -- it is recorded, so none of it may be remembered either.
    --
    -- Driven through the real event handler, not by calling
    -- ForgetArrivalState here: doing that by hand proves the function and says
    -- nothing about whether anything calls it. Removing the guard from the
    -- handler left this test green until it went through the handler.
    local onEvent = QR.ZoneSurvey.frame and QR.ZoneSurvey.frame:GetScript("OnEvent")
    t:assertNotNil(onEvent, "the survey has an event handler to drive")
    if not onEvent then return end

    QR.db.zoneSurveyEnabled = false
    MockWoW.config.currentMapID = 1670
    onEvent(QR.ZoneSurvey.frame, "PLAYER_ENTERING_WORLD")
    MockWoW.config.currentMapID = 2339
    onEvent(QR.ZoneSurvey.frame, "ZONE_CHANGED_NEW_AREA")

    -- Back on, in a zone far from where the survey was switched off.
    QR.db.zoneSurveyEnabled = true
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[2339]
    t:assertNotNil(record, "the current map is recorded again")
    if not record then return end
    t:assertNil(record.from,
        "and no crossing from the map the survey was switched off in")
end)

T:run("ZoneSurvey: a loading screen while off does not classify a later crossing", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    local onEvent = QR.ZoneSurvey.frame and QR.ZoneSurvey.frame:GetScript("OnEvent")
    t:assertNotNil(onEvent, "the survey has an event handler to drive")
    if not onEvent then return end

    QR.db.zoneSurveyEnabled = false
    onEvent(QR.ZoneSurvey.frame, "PLAYER_ENTERING_WORLD")

    QR.db.zoneSurveyEnabled = true
    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    local entry = QR.db.zoneSurvey[77] and QR.db.zoneSurvey[77].from
        and QR.db.zoneSurvey[77].from[63]
    t:assertNotNil(entry, "the crossing after switching on is recorded")
    if not entry then return end
    t:assertEqual(1, entry.walked,
        "as a walk -- the loading screen belonged to a journey nobody recorded")
    t:assertEqual(0, entry.loaded, "and not as a portal")
end)

T:run("ZoneSurvey: a crossing entry that is not a table at all is replaced", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    -- Hand-edited SavedVariables can hold anything. Guarding only the counters
    -- was half a job: this threw on the first index into the entry.
    QR.db.zoneSurvey[77].from[63] = "corrupt"

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    local ok = pcall(function() return QR.ZoneSurvey:Capture() end)

    t:assertTrue(ok, "the capture survives a non-table entry")
    local entry = QR.db.zoneSurvey[77] and QR.db.zoneSurvey[77].from
        and QR.db.zoneSurvey[77].from[63]
    t:assertNotNil(entry, "and replaces it with a usable one")
    if not entry then return end
    t:assertEqual(1, entry.walked, "counting from zero again")
end)

T:run("ZoneSurvey: a counter that is not a number at all restarts at zero", function(t)
    resetState()
    QR.ZoneSurvey:Clear()

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    -- A numeric string would need no guard -- Lua adds "3" + 1 to 4 by itself,
    -- so a test on that asserts nothing about tonumber. This is the case
    -- tonumber actually buys: a value that cannot be added at all, which
    -- without it throws on the increment.
    QR.db.zoneSurvey[77].from[63] = { walked = "corrupt", loaded = 0 }

    MockWoW.config.currentMapID = 63
    QR.ZoneSurvey:Capture()
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    local entry = QR.db.zoneSurvey[77] and QR.db.zoneSurvey[77].from
        and QR.db.zoneSurvey[77].from[63]
    t:assertNotNil(entry, "the entry is still there")
    if not entry then return end
    t:assertEqual(1, entry.walked, "restarted at zero and counted, rather than throwing")
end)
