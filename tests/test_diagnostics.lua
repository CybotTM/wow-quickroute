-------------------------------------------------------------------------------
-- test_diagnostics.lua
-- Tests for QR.Diagnostics — the on-disk recorder for Lua errors and teleport
-- list rebuilds. It exists so a bug report is "reproduce it and reload" rather
-- than a transcription of the error frame.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local function resetState()
    MockWoW:Reset()
    QR.db = QR.db or {}
    QR.db.errors = {}
    QR.db.refreshes = {}
end

T:run("Diagnostics: records an error with a timestamp", function(t)
    resetState()
    QR.Diagnostics:RecordError("attempt to index a nil value")

    t:assertEqual(1, #QR.db.errors, "one error recorded")
    local e = QR.db.errors[1]
    if not e then return end
    t:assertEqual("attempt to index a nil value", e.message, "the message is kept verbatim")
    t:assertNotNil(e.seen, "with a timestamp")
    t:assertEqual(1, e.count, "seen once")
end)

T:run("Diagnostics: a repeated error collapses instead of filling the buffer", function(t)
    resetState()
    for _ = 1, 5 do
        QR.Diagnostics:RecordError("same thing again")
    end

    t:assertEqual(1, #QR.db.errors, "still one entry")
    t:assertEqual(5, QR.db.errors[1].count, "counted five times")
end)

T:run("Diagnostics: different errors are kept apart", function(t)
    resetState()
    QR.Diagnostics:RecordError("first")
    QR.Diagnostics:RecordError("second")

    t:assertEqual(2, #QR.db.errors, "two entries")
    t:assertEqual("first", QR.db.errors[1].message, "in order")
    t:assertEqual("second", QR.db.errors[2].message, "in order")
end)

T:run("Diagnostics: the error buffer is bounded", function(t)
    resetState()
    for i = 1, 120 do
        QR.Diagnostics:RecordError("error number " .. i)
    end

    -- Bounded, and it is the OLD ones that go: an unbounded table here would be
    -- rewritten whole into SavedVariables on every logout.
    t:assertTrue(#QR.db.errors <= 40, "capped (" .. #QR.db.errors .. ")")
    t:assertEqual("error number 120", QR.db.errors[#QR.db.errors].message,
        "the newest survives")
end)

T:run("Diagnostics: a rebuild records what the panel had to show", function(t)
    resetState()
    QR.TeleportPanel.sortedTeleports = { {}, {}, {} }
    QR.db.availabilityFilter = "usable"
    QR.PlayerInventory.teleportItems = { [1] = {}, [2] = {} }
    QR.PlayerInventory.toys = { [3] = {} }
    QR.PlayerInventory.spells = {}

    QR.Diagnostics:RecordRefresh()

    t:assertEqual(1, #QR.db.refreshes, "one rebuild recorded")
    local r = QR.db.refreshes[1]
    if not r then return end
    t:assertEqual(3, r.shown, "how many entries the list drew")
    t:assertEqual(2, r.invItems, "and what the inventory held at that moment")
    t:assertEqual(1, r.invToys, "toys counted")
    t:assertEqual(0, r.invSpells, "spells counted")
end)

T:run("Diagnostics: an empty list next to a full inventory is visible in the record", function(t)
    resetState()
    -- The shape being hunted: the panel drew nothing while the player owned
    -- plenty. Without both numbers side by side there is no way to tell that
    -- from the player genuinely owning nothing.
    QR.TeleportPanel.sortedTeleports = {}
    QR.PlayerInventory.teleportItems = { [1] = {}, [2] = {}, [3] = {} }
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}

    QR.Diagnostics:RecordRefresh()
    local r = QR.db.refreshes[1]
    if not r then return end
    t:assertEqual(0, r.shown, "nothing drawn")
    t:assertEqual(3, r.invItems, "while three items were owned")
end)

T:run("Diagnostics: Clear empties both buffers", function(t)
    resetState()
    QR.Diagnostics:RecordError("boom")
    QR.Diagnostics:RecordRefresh()
    QR.Diagnostics:Clear()

    t:assertEqual(0, #QR.db.errors, "errors gone")
    t:assertEqual(0, #QR.db.refreshes, "rebuilds gone")
end)

T:run("Diagnostics: Render reports both sections", function(t)
    resetState()
    QR.Diagnostics:RecordError("a nil value")
    QR.Diagnostics:RecordRefresh()

    local out = QR.Diagnostics:Render()
    t:assertNotNil(out:match("a nil value"), "the error text appears")
    t:assertNotNil(out:match("Teleport list rebuilds"), "the rebuild table appears")
end)

T:run("Diagnostics: the RefreshList hook is actually wired", function(t)
    resetState()
    -- Every other test here calls RecordRefresh directly, which proves the
    -- recorder and nothing about whether anything ever calls it. This drives
    -- the real path.
    -- No re-initialise: the addon installed the hook at load, and installing a
    -- second one would record every rebuild twice and hide whether the first
    -- exists at all.
    QR.db.refreshes = {}

    if not (QR.TeleportPanel and QR.TeleportPanel.RefreshList) then
        t:assertTrue(false, "TeleportPanel:RefreshList exists to be hooked")
        return
    end
    -- RefreshList returns early without a frame, which is enough: the hook runs
    -- after the call either way, and that is the wiring under test.
    QR.TeleportPanel:RefreshList()

    t:assertEqual(1, #QR.db.refreshes,
        "a rebuild reaches the recorder without anyone calling it by hand")
end)
