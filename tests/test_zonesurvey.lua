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

    local out = QR.ZoneSurvey:Render()
    t:assertNotNil(out:match("| 63 |"), "map 63 appears as a row")
    t:assertNotNil(out:match("| 84 |"), "map 84 appears as a row")
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
    t:assertNotNil(record and record.from, "the arrival is recorded on the destination")
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
