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
    -- The recorder's own state is module-level and outlives a test. Without
    -- this, one test's last sampled position is the next test's departure
    -- point, and a guard asserting that nothing was recorded passes or fails
    -- on what ran before it.
    QR.ZoneSurvey:ForgetArrivalState()
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
    --
    -- No fallback to the whole output: if the header is ever renamed, falling
    -- back would silently restore the ambiguity this narrowing exists to close.
    -- Better to fail here and be told.
    local out = QR.ZoneSurvey:Render()
    local records = out:match("^(.-)### Observed crossings")
    t:assertNotNil(records, "the output has a records section to look at")
    if not records then return end
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

-------------------------------------------------------------------------------
-- The shape of what comes back from disk
--
-- Checked once on load rather than guarded at every read. A `from` field
-- holding a string survived every downstream guard, because RecordArrival
-- returns before its own check when there is no previous map yet -- which is
-- exactly the state after a login. The first /qrsurvey then died in pairs().
-------------------------------------------------------------------------------

T:run("ZoneSurvey: a malformed store is cleaned when it is loaded", function(t)
    resetState()
    QR.db.zoneSurvey = {
        [77]  = { name = "Felwood", visits = 1, from = "corrupt" },
        [63]  = { name = "Ashenvale", visits = 1,
                  from = { [84] = "also corrupt", [62] = { walked = "3", loaded = 1 } } },
        ["x"] = { name = "not a map id" },
        [99]  = "not a record",
    }
    QR.ZoneSurvey:Initialize()

    local store = QR.db.zoneSurvey
    t:assertNil(store["x"], "a non-numeric map key is dropped")
    t:assertNil(store[99], "a record that is not a table is dropped")
    t:assertNil(store[77].from, "a from field that is not a table is dropped")
    t:assertNotNil(store[63].from, "a well-formed from field is kept")
    if not store[63].from then return end
    t:assertNil(store[63].from[84], "a crossing entry that is not a table is dropped")
    t:assertNotNil(store[63].from[62], "and the good one beside it survives")
    if not store[63].from[62] then return end
    t:assertEqual(3, store[63].from[62].walked, "with its counters made numeric")
end)

T:run("ZoneSurvey: rendering a store loaded from disk does not throw", function(t)
    resetState()
    -- The exact shape that killed /qrsurvey: corrupt, and never revisited, so
    -- no capture ever reaches it.
    QR.db.zoneSurvey = { [77] = { name = "Felwood", visits = 1, from = "corrupt" } }
    QR.ZoneSurvey:Initialize()
    QR.ZoneSurvey:ForgetArrivalState()

    local ok = pcall(function() return QR.ZoneSurvey:Render() end)
    t:assertTrue(ok, "/qrsurvey renders a store that came back malformed")
end)

T:run("ZoneSurvey: a malformed record is not carried forward by a capture", function(t)
    resetState()
    QR.db.zoneSurvey = { [77] = { name = "Felwood", visits = 1, from = "corrupt" } }
    QR.ZoneSurvey:ForgetArrivalState()

    -- No Initialize here: a record can be reached before the load pass has
    -- touched it, so the copy has to check the shape too.
    MockWoW.config.currentMapID = 77
    QR.ZoneSurvey:Capture()

    t:assertNil(QR.db.zoneSurvey[77].from,
        "the capture drops it rather than copying it into the new record")
end)

-------------------------------------------------------------------------------
-- Doorway endpoints
--
-- The half no exported table can supply: where a portal stands and where it
-- lands. SpellTargetPosition is server-side, so the only way to see a
-- destination is to walk through and look.
-------------------------------------------------------------------------------

--- Walk through a doorway: stand somewhere on `fromMap`, load, arrive on `toMap`.
--
-- The order here is the one measured in a real session, not the one I assumed
-- when writing this: the sampler is already running again at the DESTINATION
-- by the time PLAYER_ENTERING_WORLD reaches the handler. Of 30 loading-screen
-- crossings recorded that way, 29 had a live position describing the arrival.
-- `samplesFirst` false reproduces the other ordering, which happened once.
local function crossLoaded(fromMap, fromX, fromY, toMap, toX, toY, samplesFirst)
    if samplesFirst == nil then samplesFirst = true end
    MockWoW.config.currentMapID = fromMap
    MockWoW.config.playerX, MockWoW.config.playerY = fromX, fromY
    QR.ZoneSurvey:Capture()
    -- The tick before the player steps into the doorway.
    QR.ZoneSurvey:SamplePosition()

    -- The loading screen, then the destination.
    MockWoW.config.currentMapID = toMap
    MockWoW.config.playerX, MockWoW.config.playerY = toX, toY
    if samplesFirst then
        QR.ZoneSurvey:SamplePosition()
        QR.ZoneSurvey:NoteLoadingScreen()
    else
        QR.ZoneSurvey:NoteLoadingScreen()
        QR.ZoneSurvey:SamplePosition()
    end
    QR.ZoneSurvey:Capture()
end

local function doorways(intoMap, fromMap)
    local record = QR.db.zoneSurvey[intoMap]
    local entry = record and record.from and record.from[fromMap]
    return entry and entry.endpoints or nil
end

local function onlyDoorway(t, intoMap, fromMap)
    local ends = doorways(intoMap, fromMap)
    t:assertNotNil(ends, "the crossing recorded endpoints")
    if not ends then return nil end
    local found, count = nil, 0
    for _, door in pairs(ends) do found = door; count = count + 1 end
    t:assertEqual(1, count, "exactly one doorway on record")
    return found
end

T:run("ZoneSurvey: a portal records where it stands and where it lands", function(t)
    resetState()
    -- Bastion -> Oribos, the shape #40 needs: the destination is known, the
    -- portal's position inside the zone is what is missing.
    crossLoaded(1533, 0.4312, 0.5578, 1670, 0.4483, 0.6466)

    local door = onlyDoorway(t, 1670, 1533)
    if not door then return end
    t:assertEqual(0.4312, door.fromX, "the departure x is where the player stood")
    t:assertEqual(0.5578, door.fromY, "the departure y too")
    t:assertEqual(0.4483, door.toX, "the arrival x is where the player landed")
    t:assertEqual(0.6466, door.toY, "the arrival y too")
    t:assertEqual(1, door.count, "seen once")
end)

T:run("ZoneSurvey: the same portal twice is one doorway, counted", function(t)
    resetState()
    crossLoaded(1533, 0.4312, 0.5578, 1670, 0.4483, 0.6466)
    -- Back and through again, standing a yard or so off the first spot.
    crossLoaded(1533, 0.4315, 0.5581, 1670, 0.4483, 0.6466)

    local door = onlyDoorway(t, 1670, 1533)
    if not door then return end
    t:assertEqual(2, door.count, "one doorway used twice, not two doorways")
end)

T:run("ZoneSurvey: two portals in one zone stay apart", function(t)
    resetState()
    crossLoaded(1533, 0.1000, 0.1000, 1670, 0.4483, 0.6466)
    crossLoaded(1533, 0.9000, 0.9000, 1670, 0.4483, 0.6466)

    local ends = doorways(1670, 1533)
    t:assertNotNil(ends, "endpoints were recorded")
    if not ends then return end
    local count = 0
    for _ in pairs(ends) do count = count + 1 end
    t:assertEqual(2, count, "two departure points, two doorways")
end)

T:run("ZoneSurvey: a walk records no doorway", function(t)
    resetState()
    MockWoW.config.currentMapID = 1533
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4, 0.4
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:SamplePosition()
    -- No NoteLoadingScreen: the player walked over the border.
    MockWoW.config.currentMapID = 1536
    QR.ZoneSurvey:Capture()

    local record = QR.db.zoneSurvey[1536]
    t:assertNotNil(record, "the arrival was recorded")
    if not record then return end
    t:assertEqual(1, record.from[1533].walked, "as a walk")
    -- No endpoints assertion here. It would be green whatever the branch does:
    -- departurePosition is written only by NoteLoadingScreen, so on this path
    -- there is nothing for RecordEndpoints to record even when it is called.
    -- Moving the call into the walk branch reddens no test, which is the
    -- evidence that the coupling and not the branch is what protects this.
end)

T:run("ZoneSurvey: the doorway is found whichever side the sampler resumes on", function(t)
    -- The defect a real session exposed. The first version copied the live
    -- position when the arrival event landed and assumed it still described the
    -- departure; 29 of 30 crossings had it describing the arrival instead, and
    -- the map check discarded every one. Looking the departure up by map is
    -- what makes both orderings work.
    resetState()
    crossLoaded(1533, 0.4312, 0.5578, 1670, 0.4483, 0.6466, true)
    local door = onlyDoorway(t, 1670, 1533)
    if door then
        t:assertEqual(0.4312, door.fromX,
            "sampler resumed at the destination first: still the departure point")
    end

    resetState()
    crossLoaded(1525, 0.7100, 0.2200, 1670, 0.4483, 0.6466, false)
    local other = onlyDoorway(t, 1670, 1525)
    if other then
        t:assertEqual(0.7100, other.fromX,
            "event arrived first: same answer")
    end
end)

T:run("ZoneSurvey: a departure never sampled on the map it left is not invented", function(t)
    resetState()
    -- The failure this guards: if the sampler runs during or after the loading
    -- screen, the "departure" is the arrival position, and the record would
    -- claim the portal stands where the player landed.
    MockWoW.config.currentMapID = 1533
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4312, 0.5578
    QR.ZoneSurvey:Capture()
    -- No sample is ever taken on 1533: the survey was switched on mid-flight,
    -- or the crossing happened inside one sample interval.
    MockWoW.config.currentMapID = 1670
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4483, 0.6466
    QR.ZoneSurvey:SamplePosition()
    QR.ZoneSurvey:NoteLoadingScreen()
    QR.ZoneSurvey:Capture()

    t:assertNil(doorways(1670, 1533),
        "with no position ever seen on the departure map, nothing is recorded")
end)

T:run("ZoneSurvey: switching off forgets the sampled position", function(t)
    resetState()
    MockWoW.config.currentMapID = 1533
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4312, 0.5578
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:SamplePosition()
    QR.ZoneSurvey:ForgetArrivalState()

    QR.ZoneSurvey:NoteLoadingScreen()
    MockWoW.config.currentMapID = 1670
    MockWoW.config.playerX, MockWoW.config.playerY = 0.4483, 0.6466
    QR.ZoneSurvey:Capture()

    t:assertNil(doorways(1670, 1533),
        "nothing sampled while the survey was off becomes a doorway")
end)

T:run("ZoneSurvey: the doorway list is capped per map pair", function(t)
    resetState()
    for i = 1, 10 do
        crossLoaded(1533, i / 20, i / 20, 1670, 0.4483, 0.6466)
    end

    local ends = doorways(1670, 1533)
    t:assertNotNil(ends, "endpoints were recorded")
    if not ends then return end
    local count = 0
    for _ in pairs(ends) do count = count + 1 end
    t:assertTrue(count <= 6,
        "the list is bounded (got " .. tostring(count) .. ")")
end)

T:run("ZoneSurvey: doorways appear in the report", function(t)
    resetState()
    crossLoaded(1533, 0.4312, 0.5578, 1670, 0.4483, 0.6466)

    local report = QR.ZoneSurvey:Render()
    t:assertTrue(report:find("Observed doorways", 1, true) ~= nil,
        "the report has a doorway section")
    t:assertTrue(report:find("0.4312", 1, true) ~= nil,
        "and states where the portal stands")
    t:assertTrue(report:find("0.6466", 1, true) ~= nil,
        "and where it lands")
end)

T:run("ZoneSurvey: a malformed doorway is cleaned on load", function(t)
    resetState()
    QR.db.zoneSurvey = {
        [1670] = { visits = 1, from = { [1533] = { walked = 0, loaded = 1, endpoints = {
            ["86:111"] = { fromX = 0.4312, fromY = 0.5578, toX = 0.4483, toY = 0.6466, count = "2" },
            ["bad"] = { fromX = "not a number", fromY = 0.5, toX = 0.5, toY = 0.5, count = 1 },
            -- The far end too: a doorway is two points, and a check that only
            -- looks at the near one leaves the renderer a string to print.
            ["bad-far"] = { fromX = 0.5, fromY = 0.5, toX = "not a number", toY = 0.5, count = 1 },
            ["worse"] = "not a table",
        } } } },
    }
    QR.ZoneSurvey:Initialize()

    local ends = doorways(1670, 1533)
    t:assertNotNil(ends, "the good doorway survived")
    if not ends then return end
    t:assertNil(ends["bad"], "a non-numeric departure coordinate is dropped")
    t:assertNil(ends["bad-far"], "and a non-numeric arrival coordinate too")
    t:assertNil(ends["worse"], "a non-table entry is dropped")
    t:assertNotNil(ends["86:111:89:129"], "legacy departure keys migrate to both endpoint buckets")
    if ends["86:111:89:129"] then
        t:assertEqual(2, ends["86:111:89:129"].count, "and a string count becomes a number")
    end

    local ok = pcall(function() return QR.ZoneSurvey:Render() end)
    t:assertTrue(ok, "and the report renders")
end)

-------------------------------------------------------------------------------
-- Loading order, corrupt values, and bounded saved state
-------------------------------------------------------------------------------

local function driveSurvey(event)
    local frame = QR.ZoneSurvey.frame
    frame:GetScript("OnEvent")(frame, event)
end

T:run("ZoneSurvey: loading start freezes the current departure and first arrival", function(t)
    resetState()
    local after, callbacks = C_Timer.After, {}
    C_Timer.After = function(_, callback) callbacks[#callbacks + 1] = callback end
    MockWoW.config.currentMapID = 1533
    MockWoW.config.playerX, MockWoW.config.playerY = .1, .2
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:SamplePosition()
    MockWoW.config.playerX, MockWoW.config.playerY = .31, .42
    driveSurvey("LOADING_SCREEN_ENABLED")
    MockWoW.config.baseTime = MockWoW.config.baseTime + 20
    MockWoW.config.currentMapID = 1670
    MockWoW.config.playerX, MockWoW.config.playerY = .53, .64
    driveSurvey("PLAYER_ENTERING_WORLD")
    MockWoW.config.playerX, MockWoW.config.playerY = .8, .9
    QR.ZoneSurvey:SamplePosition()
    C_Timer.After = after
    for _, callback in ipairs(callbacks) do callback() end
    local door = onlyDoorway(t, 1670, 1533)
    if door then
        t:assertEqual(.31, door.fromX, "departure is read at loading start instead of the old tick")
        t:assertEqual(.53, door.toX, "arrival stays at first observation before post-load movement")
    end
end)

T:run("ZoneSurvey: a stale sample is not a portal coordinate", function(t)
    resetState()
    MockWoW.config.currentMapID = 1533
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:SamplePosition()
    MockWoW.config.baseTime = MockWoW.config.baseTime + 10
    MockWoW.config.currentMapID = 1670
    QR.ZoneSurvey:SamplePosition()
    QR.ZoneSurvey:NoteLoadingScreen()
    QR.ZoneSurvey:Capture()
    t:assertNil(doorways(1670, 1533), "a ten-second-old departure cannot identify a doorway")
end)

T:run("ZoneSurvey: combat clears departure even if the player remains on the same map", function(t)
    resetState()
    MockWoW.config.currentMapID = 1533
    QR.ZoneSurvey:Capture()
    QR.ZoneSurvey:SamplePosition()
    driveSurvey("PLAYER_REGEN_DISABLED")
    MockWoW.config.currentMapID = 1670
    QR.ZoneSurvey:NoteLoadingScreen()
    QR.ZoneSurvey:Capture()
    t:assertNil(QR.db.zoneSurvey[1670].from, "a pre-combat origin is never reused after combat")
end)

T:run("ZoneSurvey: clear invalidates a delayed capture already queued", function(t)
    resetState()
    local after, callback = C_Timer.After
    C_Timer.After = function(_, fn) callback = fn end
    driveSurvey("ZONE_CHANGED_NEW_AREA")
    C_Timer.After = after
    QR.ZoneSurvey:Clear()
    if callback then callback() end
    t:assertEqual(0, QR.ZoneSurvey:Count(), "cleared survey stays empty when an old callback runs")
end)

T:run("ZoneSurvey: two loads before capture never invent a direct crossing", function(t)
    resetState()
    local after, callbacks = C_Timer.After, {}
    C_Timer.After = function(_, fn) callbacks[#callbacks + 1] = fn end
    MockWoW.config.currentMapID = 84
    QR.ZoneSurvey:Capture()
    driveSurvey("LOADING_SCREEN_ENABLED")
    MockWoW.config.currentMapID = 1670
    driveSurvey("PLAYER_ENTERING_WORLD")
    driveSurvey("LOADING_SCREEN_ENABLED")
    MockWoW.config.currentMapID = 1533
    driveSurvey("PLAYER_ENTERING_WORLD")
    C_Timer.After = after
    for _, callback in ipairs(callbacks) do callback() end
    t:assertNil(QR.db.zoneSurvey[1533].from, "a two-leg journey cannot become a direct Stormwind-to-Bastion crossing")
end)

T:run("ZoneSurvey: distinct arrivals at the same origin remain separate", function(t)
    resetState()
    crossLoaded(1533, .43, .55, 1670, .44, .64)
    crossLoaded(1533, .43, .55, 1670, .21, .35)
    t:assertTableCount(doorways(1670, 1533), 2, "both endpoint pairs survive rather than increasing one false doorway count")
end)

T:run("ZoneSurvey: secret and nonfinite positions never become endpoint evidence", function(t)
    resetState()
    local bestMap, position, secret = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, issecretvalue
    C_Map.GetPlayerMapPosition = function() return { x = .123, y = .5 } end
    _G.issecretvalue = function(value) return value == .123 end
    t:assertNil(QR.ZoneSurvey:SamplePosition(), "secret coordinate is rejected before arithmetic")
    C_Map.GetBestMapForUnit = function() return .123 end
    t:assertNil(QR.ZoneSurvey:Capture(), "secret map ID is rejected before indexing")
    C_Map.GetBestMapForUnit = bestMap
    _G.issecretvalue = secret
    for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge, -.01, 1.01 }) do
        C_Map.GetPlayerMapPosition = function() return { x = invalid, y = .5 } end
        t:assertNil(QR.ZoneSurvey:SamplePosition(), "invalid coordinate is rejected: " .. tostring(invalid))
    end
    C_Map.GetPlayerMapPosition = position
end)

T:run("ZoneSurvey: saved maps origins endpoints and counters are bounded on load", function(t)
    resetState()
    local endpoints, origins, store = {}, {}, {}
    for i = 1, 80 do
        endpoints[i] = { fromX = i / 100, fromY = .1, toX = .2, toY = .3, count = math.huge }
        origins[i] = { walked = -1, loaded = 0 / 0, endpoints = endpoints }
    end
    store[1] = { visits = math.huge, from = origins, extra = { "discard me" } }
    store[-1] = { visits = 1 }
    store[1.5] = { visits = 1 }
    store[math.huge] = { visits = 1 }
    QR.db.zoneSurvey = store
    QR.ZoneSurvey:Initialize()
    t:assertEqual(1, QR.ZoneSurvey:Count(), "invalid map IDs are discarded")
    local saved = QR.db.zoneSurvey[1]
    t:assertEqual(0, saved.visits, "infinite visit count resets")
    t:assertNil(saved.extra, "unknown nested state is not carried forward")
    t:assertTableCount(saved.from, 64, "loaded map has at most 64 origins")
    for _, entry in pairs(saved.from) do
        t:assertEqual(0, entry.walked, "negative count resets")
        t:assertEqual(0, entry.loaded, "NaN count resets")
        t:assertTableCount(entry.endpoints, 6, "loaded origin has at most six endpoint pairs")
    end
    store = {}
    for i = 1, 3100 do store[i] = { visits = 1 } end
    QR.db.zoneSurvey = store
    QR.ZoneSurvey:Initialize()
    t:assertEqual(3000, QR.ZoneSurvey:Count(), "loaded store obeys the same map cap as live recording")
    t:assertTrue(pcall(function() QR.ZoneSurvey:Render() end), "bounded saved state renders")
end)

T:run("ZoneSurvey: bad endpoint coordinates are discarded independently of key types", function(t)
    resetState()
    local endpoints = {
        [1] = { fromX = .3, fromY = .4, toX = .5, toY = .6, count = "4" },
        [false] = { fromX = 0 / 0, fromY = .4, toX = .5, toY = .6 },
        bad = { fromX = .3, fromY = .4, toX = math.huge, toY = .6 },
        outside = { fromX = .3, fromY = .4, toX = .5, toY = 2 },
    }
    QR.db.zoneSurvey = { [84] = { visits = "corrupt", from = { [85] = { endpoints = endpoints } } } }
    QR.ZoneSurvey:Initialize()
    local clean = doorways(84, 85)
    t:assertTableCount(clean, 1, "only the finite in-range endpoint pair survives")
    t:assertEqual(4, clean["60:80:100:120"].count, "arbitrary saved keys are rebuilt from valid coordinates")
    t:assertTrue(pcall(function() QR.ZoneSurvey:Render() end), "mixed saved keys cannot break table sorting")
end)

T:run("ZoneSurvey: initialization reuses the same event frame", function(t)
    resetState()
    local frame = QR.ZoneSurvey.frame
    QR.ZoneSurvey:Initialize()
    t:assertEqual(frame, QR.ZoneSurvey.frame, "reinitializing cannot leak extra samplers or event handlers")
end)

T:run("ZoneSurvey: an old zone timer cannot consume the next loading transition", function(t)
    resetState()
    local after, callbacks = C_Timer.After, {}
    C_Timer.After = function(_, fn) callbacks[#callbacks + 1] = fn end
    MockWoW.config.currentMapID = 84
    MockWoW.config.playerX, MockWoW.config.playerY = .31, .42
    QR.ZoneSurvey:Capture()
    driveSurvey("ZONE_CHANGED_NEW_AREA")
    driveSurvey("LOADING_SCREEN_ENABLED")
    -- The previously queued zone callback fires during loading.
    callbacks[1]()
    MockWoW.config.currentMapID = 1670
    MockWoW.config.playerX, MockWoW.config.playerY = .53, .64
    driveSurvey("PLAYER_ENTERING_WORLD")
    C_Timer.After = after
    if callbacks[2] then callbacks[2]() end
    local door = onlyDoorway(t, 1670, 84)
    if door then
        t:assertEqual(.31, door.fromX, "pre-load callback cannot clear the frozen departure")
    end
end)

T:run("ZoneSurvey: one destination cannot accumulate unbounded origin maps", function(t)
    resetState()
    for origin = 1, 70 do
        MockWoW.config.currentMapID = origin
        QR.ZoneSurvey:Capture()
        MockWoW.config.currentMapID = 1670
        QR.ZoneSurvey:Capture()
    end
    t:assertTableCount(QR.db.zoneSurvey[1670].from, 64,
        "live origin collection obeys the same bound as loaded state")
end)

T:run("ZoneSurvey: rounded bucket boundaries preserve doorway identity after reload", function(t)
    resetState()
    crossLoaded(1533, .00499, .43499, 1670, .60499, .53499)
    QR.ZoneSurvey:Initialize()
    crossLoaded(1533, .00499, .43499, 1670, .60499, .53499)
    local door = onlyDoorway(t, 1670, 1533)
    if door then
        t:assertEqual(2, door.count, "repeat near a rounding boundary increments the saved doorway")
        t:assertEqual(.005, door.fromX, "stored precision and bucket identity agree")
    end
end)

local function surveyTotals()
    local origins, endpoints = 0, 0
    for _, record in pairs(QR.db.zoneSurvey) do
        for _, entry in pairs(record.from or {}) do
            origins = origins + 1
            for _ in pairs(entry.endpoints or {}) do endpoints = endpoints + 1 end
        end
    end
    return origins, endpoints
end

local function manySurveyPairs(maps, perMap, doors)
    local store = {}
    for map = 1, maps do
        local origins = {}
        for origin = 1, perMap do
            local endpoints = {}
            for door = 1, doors do
                endpoints[door] = { fromX = .1 + door / 100, fromY = .2,
                    toX = .3, toY = .4, count = 1 }
            end
            origins[origin] = { walked = 0, loaded = 1, endpoints = endpoints }
        end
        store[10000 + map] = { visits = 1, from = origins }
    end
    return store
end

T:run("ZoneSurvey: aggregate saved budgets cap many individually modest maps", function(t)
    resetState()
    QR.db.zoneSurvey = manySurveyPairs(300, 16, 3)
    QR.ZoneSurvey:Initialize()
    local origins, endpoints = surveyTotals()
    t:assertEqual(4800, origins, "valid modest origin lists remain within the global origin budget")
    t:assertEqual(6000, endpoints, "global endpoint budget prevents 14400 endpoint tables")
    QR.db.zoneSurvey = manySurveyPairs(260, 24, 1)
    QR.ZoneSurvey:Initialize()
    origins, endpoints = surveyTotals()
    t:assertEqual(6000, origins, "global origin budget prevents 6240 independent arrivals")
    t:assertEqual(6000, endpoints, "each admitted endpoint respects the same global memory budget")
end)

T:run("ZoneSurvey: live global budgets admit only remaining space and reset on clear", function(t)
    resetState()
    QR.db.zoneSurvey = manySurveyPairs(250, 24, 1)
    QR.db.zoneSurvey[10250].from[24] = nil -- 5999 origins and endpoints
    QR.ZoneSurvey:Initialize()
    crossLoaded(1533, .41, .52, 1670, .63, .74)
    -- A repeat remains countable even though no additional table can be added.
    crossLoaded(1533, .41, .52, 1670, .63, .74)
    crossLoaded(1525, .21, .32, 1670, .63, .74)
    local origins, endpoints = surveyTotals()
    t:assertEqual(6000, origins, "live capture consumes only the last global origin slot")
    t:assertEqual(6000, endpoints, "live capture consumes only the last global endpoint slot")
    local door = onlyDoorway(t, 1670, 1533)
    if door then t:assertEqual(2, door.count, "an existing endpoint still increments at global capacity") end
    t:assertNil(doorways(1670, 1525), "another source cannot exceed the global cap")
    QR.ZoneSurvey:Clear()
    crossLoaded(1533, .41, .52, 1670, .63, .74)
    origins, endpoints = surveyTotals()
    t:assertEqual(1, origins, "clear resets global origin bookkeeping")
    t:assertEqual(1, endpoints, "clear resets global endpoint bookkeeping")
end)
