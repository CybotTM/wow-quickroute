-------------------------------------------------------------------------------
-- test_teleportpanel.lua
-- Tests for QR.TeleportPanel module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
end

-------------------------------------------------------------------------------
-- 1. CollectAllTeleports
-------------------------------------------------------------------------------

T:run("CollectAllTeleports: returns entries from TeleportItemsData", function(t)
    resetState()
    local teleports = QR.TeleportPanel:CollectAllTeleports()
    t:assertNotNil(teleports, "CollectAllTeleports returns table")
    t:assertGreaterThan(#teleports, 0, "Has teleport entries from data")
end)

T:run("CollectAllTeleports: entries have required fields", function(t)
    resetState()
    local teleports = QR.TeleportPanel:CollectAllTeleports()

    if #teleports > 0 then
        local entry = teleports[1]
        t:assertNotNil(entry.id, "Entry has id")
        t:assertNotNil(entry.data, "Entry has data")
        t:assertNotNil(entry.status, "Entry has status")
        t:assertNotNil(entry.filterCategory, "Entry has filterCategory")
    end
end)

T:run("CollectAllTeleports: no duplicate IDs", function(t)
    resetState()
    local teleports = QR.TeleportPanel:CollectAllTeleports()
    local seen = {}
    local hasDuplicate = false
    for _, entry in ipairs(teleports) do
        if seen[entry.id] then
            hasDuplicate = true
        end
        seen[entry.id] = true
    end
    t:assertFalse(hasDuplicate, "No duplicate IDs in collected teleports")
end)

T:run("CollectAllTeleports: includes class spells", function(t)
    resetState()
    local teleports = QR.TeleportPanel:CollectAllTeleports()

    local hasSpell = false
    for _, entry in ipairs(teleports) do
        if entry.isSpell then
            hasSpell = true
            break
        end
    end
    t:assertTrue(hasSpell, "Collected teleports include spells")
end)

-------------------------------------------------------------------------------
-- 2. SortTeleports
-------------------------------------------------------------------------------

T:run("SortTeleports: ready items come before missing items", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Zeta" }, status = { sortOrder = 4, color = "" }, filterCategory = "Items" },
        { id = 2, data = { name = "Alpha" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
    }

    QR.TeleportPanel:SortTeleports(teleports)

    t:assertEqual(2, teleports[1].id, "Ready item (sortOrder 1) comes first")
    t:assertEqual(1, teleports[2].id, "Missing item (sortOrder 4) comes second")
end)

T:run("SortTeleports: same status sorted by name", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Zeta" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 2, data = { name = "Alpha" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
    }

    QR.TeleportPanel:SortTeleports(teleports)

    t:assertEqual("Alpha", teleports[1].data.name, "Alpha comes before Zeta")
    t:assertEqual("Zeta", teleports[2].data.name, "Zeta comes after Alpha")
end)

-------------------------------------------------------------------------------
-- 3. FilterTeleports
-------------------------------------------------------------------------------

T:run("FilterTeleports: All filter returns all entries", function(t)
    resetState()
    QR.TeleportPanel.currentFilter = "All"

    local teleports = {
        { filterCategory = "Items" },
        { filterCategory = "Toys" },
        { filterCategory = "Spells" },
    }

    local filtered = QR.TeleportPanel:FilterTeleports(teleports)
    t:assertEqual(3, #filtered, "All filter returns all entries")
end)

T:run("FilterTeleports: Items filter returns only items", function(t)
    resetState()
    QR.TeleportPanel.currentFilter = "Items"

    local teleports = {
        { filterCategory = "Items" },
        { filterCategory = "Toys" },
        { filterCategory = "Spells" },
        { filterCategory = "Items" },
    }

    local filtered = QR.TeleportPanel:FilterTeleports(teleports)
    t:assertEqual(2, #filtered, "Items filter returns 2 items")
end)

T:run("FilterTeleports: Toys filter returns only toys", function(t)
    resetState()
    QR.TeleportPanel.currentFilter = "Toys"

    local teleports = {
        { filterCategory = "Items" },
        { filterCategory = "Toys" },
        { filterCategory = "Spells" },
    }

    local filtered = QR.TeleportPanel:FilterTeleports(teleports)
    t:assertEqual(1, #filtered, "Toys filter returns 1 toy")
end)

T:run("FilterTeleports: Spells filter returns only spells", function(t)
    resetState()
    QR.TeleportPanel.currentFilter = "Spells"

    local teleports = {
        { filterCategory = "Items" },
        { filterCategory = "Toys" },
        { filterCategory = "Spells" },
    }

    local filtered = QR.TeleportPanel:FilterTeleports(teleports)
    t:assertEqual(1, #filtered, "Spells filter returns 1 spell")
end)

-------------------------------------------------------------------------------
-- 4. Row pooling
-------------------------------------------------------------------------------

T:run("GetRowFrame: returns a frame", function(t)
    resetState()
    local row = QR.TeleportPanel:GetRowFrame()
    t:assertNotNil(row, "GetRowFrame returns a frame")
end)

-- Regression: the icon lookup fell through to the global GetSpellInfo, removed
-- in 11.0.2, whenever C_Spell.GetSpellInfo returned nothing for an uncached
-- spell. On a 12.x client that is a nil call that aborts the row's icon setup.
T:run("ConfigureRowIcon: uncached spell falls back without calling a removed global", function(t)
    resetState()
    local spellID = 3565
    MockWoW.config.uncachedSpells[spellID] = true
    MockWoW.config.knownSpells[spellID] = true

    t:assertNil(_G.GetSpellInfo, "Global GetSpellInfo does not exist on a 12.x client")

    local row = QR.TeleportPanel:GetRowFrame()
    local entry = {
        id = spellID,
        isSpell = true,
        data = { name = "Uncached Spell", destination = "Somewhere" },
    }

    local ok, err = pcall(function()
        QR.TeleportPanel:ConfigureRowIcon(row, entry)
    end)
    t:assertTrue(ok, "ConfigureRowIcon survives an uncached spell (got: " .. tostring(err) .. ")")

    QR.TeleportPanel:ReleaseRowFrame(row)
end)

T:run("ReleaseRowFrame and reuse: pool recycles frames", function(t)
    resetState()
    -- Drain pool first
    QR.TeleportPanel.rowPool = {}

    local row = QR.TeleportPanel:GetRowFrame()
    t:assertNotNil(row, "Got new frame")

    -- Release it
    QR.TeleportPanel:ReleaseRowFrame(row)
    t:assertEqual(1, #QR.TeleportPanel.rowPool, "Pool has 1 frame after release")

    -- Get again - should reuse
    local row2 = QR.TeleportPanel:GetRowFrame()
    t:assertEqual(0, #QR.TeleportPanel.rowPool, "Pool empty after reuse")
end)

T:run("ReleaseRowFrame: clears row data", function(t)
    resetState()
    QR.TeleportPanel.rowPool = {}

    local row = QR.TeleportPanel:GetRowFrame()
    row.teleportID = 12345
    row.isSpell = true
    row.data = { name = "test" }

    QR.TeleportPanel:ReleaseRowFrame(row)

    t:assertNil(row.teleportID, "teleportID cleared on release")
    t:assertNil(row.isSpell, "isSpell cleared on release")
    t:assertNil(row.data, "data cleared on release")
end)

T:run("ReleaseRowFrame: handles nil gracefully", function(t)
    resetState()
    -- Should not error
    QR.TeleportPanel:ReleaseRowFrame(nil)
    t:assertTrue(true, "No error on nil release")
end)

T:run("ClearRows: releases all rows to pool", function(t)
    resetState()
    QR.TeleportPanel.rowPool = {}

    -- Add some mock rows
    local row1 = QR.TeleportPanel:GetRowFrame()
    local row2 = QR.TeleportPanel:GetRowFrame()
    QR.TeleportPanel.teleportRows = { row1, row2 }

    QR.TeleportPanel:ClearRows()

    t:assertEqual(0, #QR.TeleportPanel.teleportRows, "No rows after clear")
    t:assertEqual(2, #QR.TeleportPanel.rowPool, "2 rows returned to pool")
end)

-------------------------------------------------------------------------------
-- 5. Frame creation (now via CreateContent with MainFrame parent)
-------------------------------------------------------------------------------

T:run("CreateContent: creates frame with required elements", function(t)
    resetState()

    -- Ensure MainFrame exists
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true

    -- Ensure it's not already created for clean test
    local origFrame = QR.TeleportPanel.frame
    QR.TeleportPanel.frame = nil

    local parentFrame = QR.MainFrame:GetContentFrame("teleports")
    local frame = QR.TeleportPanel:CreateContent(parentFrame)

    t:assertNotNil(frame, "Frame created")
    t:assertNotNil(frame.scrollFrame, "Has scroll frame")
    t:assertNotNil(frame.scrollChild, "Has scroll child")
    t:assertNotNil(frame.statusSummary, "Has status summary")
    t:assertNotNil(frame.refreshButton, "Has refresh button")

    -- Restore original
    QR.TeleportPanel.frame = origFrame
end)

T:run("CreateContent: idempotent", function(t)
    resetState()

    -- Ensure MainFrame exists
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true

    local origFrame = QR.TeleportPanel.frame
    QR.TeleportPanel.frame = nil

    local parentFrame = QR.MainFrame:GetContentFrame("teleports")
    local frame1 = QR.TeleportPanel:CreateContent(parentFrame)
    local frame2 = QR.TeleportPanel:CreateContent(parentFrame)

    t:assertTrue(frame1 == frame2, "Same frame returned on second call")

    -- Restore
    QR.TeleportPanel.frame = origFrame
end)

-------------------------------------------------------------------------------
-- 6. Show/Hide/Toggle (delegates to MainFrame)
-------------------------------------------------------------------------------

T:run("Toggle: alternates visibility via MainFrame", function(t)
    resetState()

    -- Ensure MainFrame + TeleportPanel content exist
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true
    if not QR.TeleportPanel.frame then
        local parentFrame = QR.MainFrame:GetContentFrame("teleports")
        QR.TeleportPanel:CreateContent(parentFrame)
    end
    QR.TeleportPanel.initialized = true

    QR.TeleportPanel:Show()
    t:assertTrue(QR.MainFrame.isShowing, "MainFrame showing after TeleportPanel:Show()")
    t:assertEqual("teleports", QR.MainFrame.activeTab, "Active tab is teleports")

    QR.TeleportPanel:Hide()
    t:assertFalse(QR.MainFrame.isShowing, "MainFrame hidden after TeleportPanel:Hide()")
end)

-------------------------------------------------------------------------------
-- 7. GroupTeleportsByDestination
-------------------------------------------------------------------------------

T:run("GroupTeleportsByDestination: produces correct groups", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Item A", destination = "Dalaran" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 2, data = { name = "Item B", destination = "Stormwind" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 3, data = { name = "Item C", destination = "Dalaran" }, status = { sortOrder = 2, color = "" }, filterCategory = "Items" },
        { id = 4, data = { name = "Item D", destination = "Orgrimmar" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual(3, #groups, "3 groups for 3 distinct destinations")

    -- Find Dalaran group
    local dalaranGroup
    for _, g in ipairs(groups) do
        if g.name == "Dalaran" then dalaranGroup = g end
    end
    t:assertNotNil(dalaranGroup, "Dalaran group exists")
    t:assertEqual(2, #dalaranGroup.teleports, "Dalaran has 2 teleports")
end)

T:run("GroupTeleportsByDestination: groups sorted alphabetically", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Z", destination = "Zuldazar" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 2, data = { name = "A", destination = "Ashenvale" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 3, data = { name = "M", destination = "Moonglade" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual("Ashenvale", groups[1].name, "First group alphabetically is Ashenvale")
    t:assertEqual("Moonglade", groups[2].name, "Second group is Moonglade")
    t:assertEqual("Zuldazar", groups[3].name, "Third group is Zuldazar")
end)

T:run("GroupTeleportsByDestination: teleports within groups sorted by status", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Missing Item", destination = "Dalaran" }, status = { sortOrder = 4, color = "" }, filterCategory = "Items" },
        { id = 2, data = { name = "Ready Item", destination = "Dalaran" }, status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 3, data = { name = "On CD Item", destination = "Dalaran" }, status = { sortOrder = 2, color = "" }, filterCategory = "Items" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual(1, #groups, "One group")
    t:assertEqual("Ready Item", groups[1].teleports[1].data.name, "Ready item first in group")
    t:assertEqual("On CD Item", groups[1].teleports[2].data.name, "On CD item second in group")
    t:assertEqual("Missing Item", groups[1].teleports[3].data.name, "Missing item last in group")
end)

T:run("GroupTeleportsByDestination: uses name as fallback destination", function(t)
    resetState()

    local teleports = {
        { id = 1, data = { name = "Some Spell" }, status = { sortOrder = 1, color = "" }, filterCategory = "Spells" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual(1, #groups, "One group")
    t:assertEqual("Some Spell", groups[1].name, "Group name falls back to item name")
end)

T:run("GroupTeleportsByDestination: empty input returns empty", function(t)
    resetState()

    local groups = QR.TeleportPanel:GroupTeleportsByDestination({})
    t:assertEqual(0, #groups, "No groups for empty input")
end)

T:run("groupByDestination toggle: default is false", function(t)
    -- groupByDestination should default to false (flat mode)
    t:assertFalse(QR.TeleportPanel.groupByDestination, "Default grouping mode is false")
end)

-------------------------------------------------------------------------------
-- 8. Header frame pooling
-------------------------------------------------------------------------------

T:run("GetHeaderFrame: returns a frame with expected elements", function(t)
    resetState()
    QR.TeleportPanel.headerPool = {}

    local header = QR.TeleportPanel:GetHeaderFrame()

    t:assertNotNil(header, "GetHeaderFrame returns a frame")
    t:assertNotNil(header.zoneText, "Header has zoneText")
    t:assertNotNil(header.countText, "Header has countText")
    t:assertNotNil(header.bg, "Header has background")
end)

T:run("ReleaseHeaderFrame and reuse: pool recycles headers", function(t)
    resetState()
    QR.TeleportPanel.headerPool = {}

    local header = QR.TeleportPanel:GetHeaderFrame()
    QR.TeleportPanel:ReleaseHeaderFrame(header)
    t:assertEqual(1, #QR.TeleportPanel.headerPool, "Pool has 1 header after release")

    local header2 = QR.TeleportPanel:GetHeaderFrame()
    t:assertEqual(0, #QR.TeleportPanel.headerPool, "Pool empty after reuse")
end)

T:run("ReleaseHeaderFrame: handles nil gracefully", function(t)
    resetState()
    QR.TeleportPanel:ReleaseHeaderFrame(nil)
    t:assertTrue(true, "No error on nil header release")
end)

T:run("ClearHeaders: releases all headers to pool", function(t)
    resetState()
    QR.TeleportPanel.headerPool = {}

    local h1 = QR.TeleportPanel:GetHeaderFrame()
    local h2 = QR.TeleportPanel:GetHeaderFrame()
    QR.TeleportPanel.headerRows = { h1, h2 }

    QR.TeleportPanel:ClearHeaders()

    t:assertEqual(0, #QR.TeleportPanel.headerRows, "No headers after clear")
    t:assertEqual(2, #QR.TeleportPanel.headerPool, "2 headers returned to pool")
end)

-------------------------------------------------------------------------------
-- Hearthstone bind location display
-------------------------------------------------------------------------------

T:run("Hearthstone shows actual bind location from GetBindLocation", function(t)
    resetState()
    MockWoW.config.bindLocation = "Orgrimmar"
    -- Collect all teleports — hearthstone (6948) should be in data
    local teleports = QR.TeleportPanel:CollectAllTeleports()
    local hearthstone = nil
    for _, entry in ipairs(teleports) do
        if entry.id == 6948 then hearthstone = entry; break end
    end
    if hearthstone then
        -- The entry has isDynamic=true and destination="Bound Location"
        t:assertTrue(hearthstone.data.isDynamic, "Hearthstone is dynamic")
        t:assertEqual("Bound Location", hearthstone.data.destination, "Hearthstone destination is Bound Location")
        -- GetBindLocation should be used since isDynamic and destination matches
        t:assertNotNil(GetBindLocation, "GetBindLocation global exists")
        t:assertEqual("Orgrimmar", GetBindLocation(), "GetBindLocation returns configured location")
    end
end)

T:run("GetBindLocation returns configured bind location", function(t)
    resetState()
    MockWoW.config.bindLocation = "Valdrakken"
    t:assertEqual("Valdrakken", GetBindLocation(), "Returns Valdrakken")

    MockWoW.config.bindLocation = ""
    t:assertEqual("", GetBindLocation(), "Returns empty string when not set")
end)

-------------------------------------------------------------------------------
-- 9. CreateTeleportRow rendering
-------------------------------------------------------------------------------

--- Helper: ensure TeleportPanel has frame with scrollChild for row tests
local function ensureTeleportPanelFrame()
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true
    if not QR.TeleportPanel.frame then
        local parentFrame = QR.MainFrame:GetContentFrame("teleports")
        QR.TeleportPanel:CreateContent(parentFrame)
    end
end

T:run("CreateTeleportRow: row has nameText, destText, statusText", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 6948,
        data = { name = "Hearthstone", destination = "Bound Location",
            type = QR.TeleportTypes.HEARTHSTONE, mapID = nil },
        isSpell = false,
        status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
        cooldownRemaining = 0,
        filterCategory = "Items",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)
    t:assertNotNil(row, "Row created")
    t:assertNotNil(row.nameText, "Row has nameText")
    t:assertNotNil(row.destText, "Row has destText")
    t:assertNotNil(row.statusText, "Row has statusText")

    -- Verify text content
    local nameStr = row.nameText:GetText()
    t:assertNotNil(nameStr, "nameText has text")
    t:assertTrue(#nameStr > 0, "nameText not empty")

    local destStr = row.destText:GetText()
    t:assertNotNil(destStr, "destText has text")
    t:assertTrue(#destStr > 0, "destText not empty")

    local statusStr = row.statusText:GetText()
    t:assertNotNil(statusStr, "statusText has text")
    t:assertTrue(#statusStr > 0, "statusText not empty")

    -- Release for cleanup
    QR.TeleportPanel:ReleaseRowFrame(row)
end)

T:run("CreateTeleportRow: name shows localized name with status color", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 6948,
        data = { name = "Hearthstone", destination = "Stormwind",
            type = QR.TeleportTypes.HEARTHSTONE, mapID = 84 },
        isSpell = false,
        status = { sortOrder = 4, color = "|cFFFFFF00", text = "Missing", key = "STATUS_MISSING" },
        filterCategory = "Items",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)

    -- Name should contain the item name (possibly with color codes)
    local nameStr = row.nameText:GetText()
    t:assertNotNil(nameStr, "nameText has text")
    -- Name should include the status color prefix
    t:assertTrue(nameStr:find("|cFFFFFF00") ~= nil or nameStr:find("Hearthstone") ~= nil,
        "Name contains color code or item name")

    QR.TeleportPanel:ReleaseRowFrame(row)
end)

T:run("CreateTeleportRow: destination from mapID", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 140192,
        data = { name = "Dalaran Hearthstone", destination = "Dalaran",
            type = QR.TeleportTypes.TOY, mapID = 627 },
        isSpell = false,
        status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
        filterCategory = "Toys",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)

    local destStr = row.destText:GetText()
    t:assertNotNil(destStr, "destText has text")
    t:assertTrue(#destStr > 0, "destText not empty")

    QR.TeleportPanel:ReleaseRowFrame(row)
end)

T:run("CreateTeleportRow: status shows cooldown time for ON_CD", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 6948,
        data = { name = "Hearthstone", destination = "Stormwind",
            type = QR.TeleportTypes.HEARTHSTONE, mapID = 84 },
        isSpell = false,
        status = { sortOrder = 2, color = "|cFFFF6600", text = "On Cooldown", key = "STATUS_ON_CD" },
        cooldownRemaining = 300,
        filterCategory = "Items",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)

    local statusStr = row.statusText:GetText()
    t:assertNotNil(statusStr, "statusText has text")
    -- Should contain the cooldown time (5:00 for 300s)
    t:assertTrue(#statusStr > 0, "statusText not empty")
    t:assertTrue(statusStr:find("5:00") ~= nil or statusStr:find("On Cooldown") ~= nil,
        "Status shows cooldown info")

    QR.TeleportPanel:ReleaseRowFrame(row)
end)

T:run("CreateTeleportRow: spell entry shows spell name", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 53140,
        data = { name = "Teleport: Dalaran", destination = "Dalaran",
            type = QR.TeleportTypes.SPELL, mapID = 125 },
        isSpell = true,
        status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
        filterCategory = "Spells",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)

    local nameStr = row.nameText:GetText()
    t:assertNotNil(nameStr, "nameText has text for spell")
    t:assertTrue(#nameStr > 0, "nameText not empty for spell")

    QR.TeleportPanel:ReleaseRowFrame(row)
end)

-------------------------------------------------------------------------------
-- 10. Availability filter
-------------------------------------------------------------------------------

T:run("Availability filter usable: only READY entries pass", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local teleports = {
        { id = 1, data = { name = "A" }, status = { sortOrder = 1, color = "", text = "Ready", key = "STATUS_READY" }, filterCategory = "Items" },
        { id = 2, data = { name = "B" }, status = { sortOrder = 2, color = "", text = "On CD", key = "STATUS_ON_CD" }, filterCategory = "Items" },
        { id = 3, data = { name = "C" }, status = { sortOrder = 4, color = "", text = "Missing", key = "STATUS_MISSING" }, filterCategory = "Items" },
        { id = 4, data = { name = "D" }, status = { sortOrder = 5, color = "", text = "N/A", key = "STATUS_NA" }, filterCategory = "Items" },
    }

    -- Simulate usable filter
    local filtered = {}
    for _, entry in ipairs(teleports) do
        if entry.status.sortOrder == 1 then  -- STATUS_READY.sortOrder
            table.insert(filtered, entry)
        end
    end
    t:assertEqual(1, #filtered, "Only 1 READY entry passes usable filter")
    t:assertEqual("A", filtered[1].data.name, "READY entry is A")
end)

T:run("Availability filter obtainable: excludes only N/A entries", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local teleports = {
        { id = 1, data = { name = "A" }, status = { sortOrder = 1, color = "", text = "Ready", key = "STATUS_READY" }, filterCategory = "Items" },
        { id = 2, data = { name = "B" }, status = { sortOrder = 2, color = "", text = "On CD", key = "STATUS_ON_CD" }, filterCategory = "Items" },
        { id = 3, data = { name = "C" }, status = { sortOrder = 4, color = "", text = "Missing", key = "STATUS_MISSING" }, filterCategory = "Items" },
        { id = 4, data = { name = "D" }, status = { sortOrder = 5, color = "", text = "N/A", key = "STATUS_NA" }, filterCategory = "Items" },
    }

    -- Simulate obtainable filter (exclude NA which has sortOrder 5)
    local filtered = {}
    for _, entry in ipairs(teleports) do
        if entry.status.sortOrder ~= 5 then  -- STATUS_NA.sortOrder
            table.insert(filtered, entry)
        end
    end
    t:assertEqual(3, #filtered, "3 entries pass obtainable filter (READY, ON_CD, MISSING)")
end)

-------------------------------------------------------------------------------
-- 11. RefreshList status summary
-------------------------------------------------------------------------------

T:run("RefreshList: updates status summary with counts", function(t)
    resetState()
    ensureTeleportPanelFrame()

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"

    QR.TeleportPanel:RefreshList()

    local summary = QR.TeleportPanel.frame.statusSummary:GetText()
    t:assertNotNil(summary, "Status summary has text after RefreshList")
    t:assertTrue(#summary > 0, "Status summary is not empty")
end)

T:run("RefreshList: clears old rows before adding new ones", function(t)
    resetState()
    ensureTeleportPanelFrame()

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"

    -- First refresh
    QR.TeleportPanel:RefreshList()
    local count1 = #QR.TeleportPanel.teleportRows

    -- Second refresh — should not double the rows
    QR.TeleportPanel:RefreshList()
    local count2 = #QR.TeleportPanel.teleportRows

    t:assertEqual(count1, count2, "Row count same after double refresh (old rows cleared)")
end)

-------------------------------------------------------------------------------
-- 12. Row release cleans up child elements
-------------------------------------------------------------------------------

T:run("ReleaseRowFrame: hides nameText, destText, statusText", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local entry = {
        id = 6948,
        data = { name = "Hearthstone", destination = "Bound Location",
            type = QR.TeleportTypes.HEARTHSTONE, mapID = nil },
        isSpell = false,
        status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
        cooldownRemaining = 0,
        filterCategory = "Items",
    }
    local row = QR.TeleportPanel:CreateTeleportRow(entry, 0)

    -- Verify elements exist and are shown
    t:assertNotNil(row.nameText, "nameText exists before release")
    t:assertNotNil(row.destText, "destText exists before release")
    t:assertNotNil(row.statusText, "statusText exists before release")

    QR.TeleportPanel:ReleaseRowFrame(row)

    -- After release, child elements should be hidden
    t:assertFalse(row.nameText:IsShown(), "nameText hidden after release")
    t:assertFalse(row.destText:IsShown(), "destText hidden after release")
    t:assertFalse(row.statusText:IsShown(), "statusText hidden after release")
end)

-------------------------------------------------------------------------------
-- 13. Grid Icon Rendering (grouped mode)
-------------------------------------------------------------------------------

T:run("GetIconFrame: returns frame with correct size", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local icon = QR.TeleportPanel:GetIconFrame()
    t:assertNotNil(icon, "GetIconFrame returns frame")
    t:assertEqual(36, icon:GetWidth(), "Icon width is 36")
    t:assertNotNil(icon.iconTexture, "Icon has iconTexture")
    t:assertNotNil(icon.border, "Icon has border texture")
    t:assertNotNil(icon.cooldownText, "Icon has cooldownText")

    QR.TeleportPanel:ReleaseIconFrame(icon)
end)

T:run("ReleaseIconFrame: resets and hides frame, grows pool", function(t)
    resetState()
    ensureTeleportPanelFrame()

    -- Reset pool to known state
    QR.TeleportPanel.iconPool = {}

    local icon = QR.TeleportPanel:GetIconFrame()
    t:assertEqual(0, #QR.TeleportPanel.iconPool, "Pool empty after get")

    icon.teleportID = 6948
    icon.isSpell = false
    icon:Show()

    QR.TeleportPanel:ReleaseIconFrame(icon)

    t:assertFalse(icon:IsShown(), "Icon hidden after release")
    t:assertNil(icon.teleportID, "teleportID cleared after release")
    t:assertNil(icon.isSpell, "isSpell cleared after release")
    t:assertEqual(1, #QR.TeleportPanel.iconPool, "Pool grows to 1")
end)

T:run("CreateGroupIconRow: icons laid out in grid", function(t)
    resetState()
    ensureTeleportPanelFrame()

    local group = {
        name = "Stormwind",
        mapID = 84,
        teleports = {
            { id = 6948, data = { name = "Hearthstone", destination = "Stormwind", type = QR.TeleportTypes.HEARTHSTONE },
              isSpell = false, status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
              cooldownRemaining = 0, filterCategory = "Items" },
            { id = 556, data = { name = "Astral Recall", destination = "Stormwind" },
              isSpell = true, status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
              cooldownRemaining = 0, filterCategory = "Spells" },
            { id = 64488, data = { name = "Dark Portal", destination = "Stormwind", type = QR.TeleportTypes.TOY },
              isSpell = false, status = { sortOrder = 2, color = "|cFFFF6600", text = "On CD", key = "STATUS_ON_CD" },
              cooldownRemaining = 120, filterCategory = "Items" },
        },
    }

    -- The grouped view draws a card per destination now; the icons live along
    -- the foot of the card instead of in a full-width grid below a header.
    -- The width is set here rather than taken from whatever the mock frame
    -- happens to report, because it is what the layout is being tested on.
    QR.TeleportPanel.frame:SetWidth(820)
    local newYOffset = QR.TeleportPanel:CreateGroupCards({ group }, 0)
    t:assertEqual(3, #QR.TeleportPanel.iconFrames, "3 icon frames created")
    t:assertGreaterThan(newYOffset, 0, "yOffset advanced")
    t:assertEqual(1, #QR.TeleportPanel.cards, "one card for one group")

    for i, icon in ipairs(QR.TeleportPanel.iconFrames) do
        t:assertTrue(icon:IsShown(), "Icon " .. i .. " is shown")
    end

    QR.TeleportPanel:ClearCards()
    QR.TeleportPanel:ClearIcons()
end)

T:run("CreateGroupCards: a group with more teleports than fit says how many are hidden", function(t)
    resetState()
    ensureTeleportPanelFrame()

    -- A card is narrower than the panel, so 15 teleports cannot all show. The
    -- ones that do not fit are stated on the card rather than dropped silently.
    local teleports = {}
    for i = 1, 15 do
        table.insert(teleports, {
            id = 6948 + i,
            data = { name = "Teleport" .. i, destination = "Dalaran", type = QR.TeleportTypes.HEARTHSTONE },
            isSpell = false,
            status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
            cooldownRemaining = 0,
            filterCategory = "Items",
        })
    end

    local group = { name = "Dalaran", mapID = 125, teleports = teleports }
    QR.TeleportPanel.frame:SetWidth(820)
    local newYOffset = QR.TeleportPanel:CreateGroupCards({ group }, 0)

    local cardWidth = QR.TeleportPanel:CardWidth(QR.TeleportPanel.frame:GetWidth())
    local fit = QR.TeleportPanel:IconsPerCard(cardWidth)
    t:assertTrue(fit < 15, "15 teleports do not all fit on one card (" .. fit .. ")")
    t:assertEqual(fit, #QR.TeleportPanel.iconFrames, "only the ones that fit get a frame")
    t:assertGreaterThan(newYOffset, 0, "yOffset advanced")

    local card = QR.TeleportPanel.cards[1]
    t:assertNotNil(card, "a card was made")
    if card then
        t:assertNotNil(card.contText:GetText():match("%+" .. (15 - fit)),
            "the card says how many are not shown")
    end

    QR.TeleportPanel:ClearCards()
    QR.TeleportPanel:ClearIcons()
end)

T:run("ConfigureGridIcon: missing item is desaturated via RefreshList", function(t)
    resetState()
    ensureTeleportPanelFrame()

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"
    QR.TeleportPanel.groupByDestination = true

    -- RefreshList creates entries with real STATUS references
    QR.TeleportPanel:RefreshList()

    -- Find a missing item in the icon frames (status.sortOrder == 4)
    local foundMissing = false
    for _, icon in ipairs(QR.TeleportPanel.iconFrames) do
        if icon.entry and icon.entry.status and icon.entry.status.sortOrder == 4 then
            t:assertTrue(icon.iconTexture._desaturated, "Missing icon is desaturated")
            t:assertEqual(0.7, icon.iconTexture._alpha, "Missing icon alpha is 0.7 (recognizable but dimmed)")
            -- Border should be hidden for missing items
            if icon.border then
                t:assertFalse(icon.border:IsShown(), "Missing icon border is hidden")
            end
            foundMissing = true
            break
        end
    end
    t:assertTrue(foundMissing, "Found at least one missing item icon")

    QR.TeleportPanel.groupByDestination = false
end)

T:run("ConfigureGridIcon: on-cooldown item is dimmed via RefreshList", function(t)
    resetState()
    ensureTeleportPanelFrame()

    -- Set a hearthstone as owned
    QR.PlayerInventory.teleportItems = { [6948] = true }

    -- Mock GetCooldown to report hearthstone on cooldown
    local origGetCooldown = QR.CooldownTracker.GetCooldown
    QR.CooldownTracker.GetCooldown = function(self, id, sourceType)
        if id == 6948 then
            return { ready = false, remaining = 300, start = 0, duration = 900 }
        end
        return origGetCooldown(self, id, sourceType)
    end

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"
    QR.TeleportPanel.groupByDestination = true

    QR.TeleportPanel:RefreshList()

    -- Find the hearthstone icon by id and verify it's on CD
    local foundOnCD = false
    for _, icon in ipairs(QR.TeleportPanel.iconFrames) do
        if icon.entry and icon.entry.id == 6948 then
            t:assertEqual(2, icon.entry.status.sortOrder, "Hearthstone has ON_CD status")
            -- If a secure button was attached (isOwned=true), alpha is on the button
            if icon.useButton then
                t:assertEqual(0.5, icon.useButton._alpha, "On CD icon button is dimmed")
            else
                -- Static icon path (no SecureButtons available)
                t:assertEqual(0.6, icon.iconTexture._alpha, "On CD icon alpha is 0.6")
                t:assertFalse(icon.iconTexture._desaturated, "On CD icon is NOT desaturated")
            end
            foundOnCD = true
            break
        end
    end
    t:assertTrue(foundOnCD, "Found hearthstone icon")

    -- Restore
    QR.CooldownTracker.GetCooldown = origGetCooldown
    QR.TeleportPanel.groupByDestination = false
end)

T:run("RefreshList grouped mode uses icon grid, not row list", function(t)
    resetState()
    ensureTeleportPanelFrame()

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"
    QR.TeleportPanel.groupByDestination = true

    QR.TeleportPanel:RefreshList()

    -- In grouped mode, teleportRows should be empty (icons used instead)
    t:assertEqual(0, #QR.TeleportPanel.teleportRows, "No teleportRows in grouped mode")
    t:assertGreaterThan(#QR.TeleportPanel.iconFrames, 0, "iconFrames populated in grouped mode")

    -- Restore default
    QR.TeleportPanel.groupByDestination = false
end)

T:run("ClearRows also clears icon frames", function(t)
    resetState()
    ensureTeleportPanelFrame()

    -- Start clean
    QR.TeleportPanel:ClearRows()
    QR.TeleportPanel.iconPool = {}

    -- Populate some icons manually
    local icon1 = QR.TeleportPanel:GetIconFrame()
    local icon2 = QR.TeleportPanel:GetIconFrame()
    table.insert(QR.TeleportPanel.iconFrames, icon1)
    table.insert(QR.TeleportPanel.iconFrames, icon2)

    t:assertEqual(2, #QR.TeleportPanel.iconFrames, "2 icon frames before clear")

    QR.TeleportPanel:ClearRows()

    t:assertEqual(0, #QR.TeleportPanel.iconFrames, "iconFrames empty after ClearRows")
    t:assertEqual(2, #QR.TeleportPanel.iconPool, "Icons returned to pool")
end)

-------------------------------------------------------------------------------
-- 14. GroupTeleportsByDestination mapID adoption
-------------------------------------------------------------------------------

T:run("GroupTeleportsByDestination: adopts mapID from later entries", function(t)
    resetState()

    local teleports = {
        { id = 6948, data = { name = "Hearthstone", destination = "Valdrakken", mapID = nil },
          status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 140192, data = { name = "Dalaran Hearthstone", destination = "Valdrakken", mapID = 2112 },
          status = { sortOrder = 1, color = "" }, filterCategory = "Toys" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual(1, #groups, "One group for Valdrakken")
    t:assertEqual(2112, groups[1].mapID, "Group adopted mapID 2112 from second entry")
end)

T:run("GroupTeleportsByDestination: keeps nil mapID if no entry has one", function(t)
    resetState()

    local teleports = {
        { id = 6948, data = { name = "Hearthstone", destination = "Bound Location", mapID = nil },
          status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
        { id = 64488, data = { name = "The Innkeeper's Daughter", destination = "Bound Location", mapID = nil },
          status = { sortOrder = 1, color = "" }, filterCategory = "Items" },
    }

    local groups = QR.TeleportPanel:GroupTeleportsByDestination(teleports)

    t:assertEqual(1, #groups, "One group")
    t:assertNil(groups[1].mapID, "Group mapID stays nil when no entry has one")
end)

-------------------------------------------------------------------------------
-- 15. ShoppingTooltip suppression
-------------------------------------------------------------------------------

T:run("ShoppingTooltip1 and ShoppingTooltip2 globals exist", function(t)
    resetState()
    t:assertNotNil(ShoppingTooltip1, "ShoppingTooltip1 exists")
    t:assertNotNil(ShoppingTooltip2, "ShoppingTooltip2 exists")
end)

-------------------------------------------------------------------------------
-- 16. Grid icon visual treatment by status
-------------------------------------------------------------------------------

T:run("ConfigureGridIcon: NA item is desaturated with alpha 0.5 and hidden border", function(t)
    resetState()
    ensureTeleportPanelFrame()

    QR.TeleportPanel.currentFilter = "All"
    QR.TeleportPanel.availabilityFilter = "all"
    QR.TeleportPanel.groupByDestination = true

    QR.TeleportPanel:RefreshList()

    -- Find an NA item in the icon frames (status.sortOrder == 5)
    local foundNA = false
    for _, icon in ipairs(QR.TeleportPanel.iconFrames) do
        if icon.entry and icon.entry.status and icon.entry.status.sortOrder == 5 then
            t:assertTrue(icon.iconTexture._desaturated, "NA icon is desaturated")
            t:assertEqual(0.5, icon.iconTexture._alpha, "NA icon alpha is 0.5")
            if icon.border then
                t:assertFalse(icon.border:IsShown(), "NA icon border is hidden")
            end
            foundNA = true
            break
        end
    end
    t:assertTrue(foundNA, "Found at least one NA item icon")

    QR.TeleportPanel.groupByDestination = false
end)

T:run("ReleaseIconFrame: restores border visibility", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.iconPool = {}

    local icon = QR.TeleportPanel:GetIconFrame()
    -- Simulate a missing item that hid the border
    if icon.border then
        icon.border:Hide()
        t:assertFalse(icon.border:IsShown(), "Border hidden before release")
    end

    QR.TeleportPanel:ReleaseIconFrame(icon)

    -- After release, border should be restored to visible
    local reused = QR.TeleportPanel:GetIconFrame()
    if reused.border then
        t:assertTrue(reused.border:IsShown(), "Border shown after pool reuse")
    end

    QR.TeleportPanel:ReleaseIconFrame(reused)
end)

-------------------------------------------------------------------------------
-- Zone-restricted teleports (usableOnMaps)
-------------------------------------------------------------------------------

local function findEntry(teleports, id)
    for _, entry in ipairs(teleports) do
        if entry.id == id then return entry end
    end
    return nil
end

T:run("Zone restriction: Kirin Tor Beacon reads NOT HERE away from Isle of Thunder", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()
    MockWoW.config.ownedToys[95567] = true
    MockWoW.config.currentMapID = 84  -- Stormwind City

    local entry = findEntry(QR.TeleportPanel:CollectAllTeleports(), 95567)
    t:assertNotNil(entry, "The beacon is listed")
    t:assertEqual(entry.status.key, "STATUS_ZONE", "Owned, but the game refuses it here")
end)

T:run("Zone restriction: the beacon counts as owned on a Throne of Thunder floor", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()
    MockWoW.config.ownedToys[95567] = true
    -- A raid floor nested inside Isle of Thunder (uiMap 508 -> 504)
    MockWoW.mapDatabase[508] = { mapID = 508, name = "Throne of Thunder", mapType = 4, parentMapID = 504 }
    MockWoW.config.currentMapID = 508

    local entry = findEntry(QR.TeleportPanel:CollectAllTeleports(), 95567)
    MockWoW.mapDatabase[508] = nil
    t:assertNotNil(entry, "The beacon is listed")
    t:assertTrue(entry.status.key ~= "STATUS_ZONE", "Inside the restriction the zone status does not apply")
    t:assertTrue(entry.status.key ~= "STATUS_MISSING", "The owned toy is not reported missing")
end)

-------------------------------------------------------------------------------
-- Card layout
--
-- The design is explicit that the column count must follow the window width
-- rather than being hard-coded: at the panel minimum of 500 a 254-wide card
-- leaves nothing for an icon, a name and a status. These pin the arithmetic,
-- which is the part of the design that can be checked without seeing it.
-------------------------------------------------------------------------------

T:run("CardsPerRow: the column count follows the window", function(t)
    local TP = QR.TeleportPanel
    t:assertEqual(1, TP:CardsPerRow(500), "one column at the panel minimum")
    t:assertEqual(2, TP:CardsPerRow(540), "two once there is room for two")
    t:assertEqual(3, TP:CardsPerRow(820), "three at the width the design was drawn at")
    t:assertEqual(4, TP:CardsPerRow(1200), "and it keeps going")
end)

T:run("CardsPerRow: never fewer than one, whatever it is given", function(t)
    local TP = QR.TeleportPanel
    t:assertEqual(1, TP:CardsPerRow(0), "zero width")
    t:assertEqual(1, TP:CardsPerRow(-100), "negative width")
    t:assertEqual(1, TP:CardsPerRow(nil), "no width at all")
end)

T:run("CardWidth: cards divide the row without spilling out of it", function(t)
    local TP = QR.TeleportPanel
    for _, panel in ipairs({500, 540, 760, 820, 1200}) do
        local width, perRow = TP:CardWidth(panel)
        -- Every card, plus the gaps between them, plus the padding either side.
        local used = perRow * width + (perRow - 1) * 12 + 16
        t:assertTrue(used <= panel + 0.5,
            string.format("at %d: %d card(s) of %.1f fit in %d (used %.1f)",
                panel, perRow, width, panel, used))
        t:assertTrue(width > 0, "and the card has a width at " .. panel)
    end
end)

T:run("IconsPerCard: the status dot keeps its place", function(t)
    local TP = QR.TeleportPanel
    -- A card at the design's own width takes five icons, which is what the
    -- design says. Fewer than that and the dot would be pushed off the card.
    t:assertEqual(5, TP:IconsPerCard(254), "five at the design's card width")
    t:assertEqual(1, TP:IconsPerCard(0), "never fewer than one")
    t:assertEqual(1, TP:IconsPerCard(nil), "even with no width")
end)

T:run("ClearCards: cards and their icons both go back to the pools", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.frame:SetWidth(820)
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.cards = {}
    QR.TeleportPanel.iconFrames = {}

    local group = {
        name = "Dalaran", mapID = 125,
        teleports = {
            { id = 6948, data = { name = "Hearthstone", destination = "Dalaran" },
              isSpell = false, status = { sortOrder = 1, color = "|cFF00FF00",
              text = "Ready", key = "STATUS_READY" }, cooldownRemaining = 0 },
        },
    }
    QR.TeleportPanel:CreateGroupCards({ group }, 0)
    t:assertEqual(1, #QR.TeleportPanel.cards, "one card on screen")

    QR.TeleportPanel:ClearCards()
    t:assertEqual(0, #QR.TeleportPanel.cards, "none after clearing")
    t:assertEqual(1, #QR.TeleportPanel.cardPool, "and it went back to the pool")

    QR.TeleportPanel:ClearIcons()
end)

T:run("ClearCards: an icon frame reaches the pool exactly once", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.frame:SetWidth(820)
    QR.TeleportPanel.iconPool = {}
    QR.TeleportPanel.iconFrames = {}
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.cards = {}

    local teleports = {}
    for i = 1, 3 do
        teleports[i] = {
            id = 6940 + i,
            data = { name = "T" .. i, destination = "Dalaran" },
            isSpell = false,
            status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" },
            cooldownRemaining = 0,
        }
    end
    QR.TeleportPanel:CreateGroupCards({ { name = "Dalaran", mapID = 125,
        teleports = teleports } }, 0)

    -- Both clearing calls, in the order RefreshList makes them. The card holds
    -- its icons but does not release them; ClearIcons owns that. When both did
    -- it, three icons produced six pool entries and the next GetIconFrame
    -- handed the same frame to two callers.
    QR.TeleportPanel:ClearIcons()
    QR.TeleportPanel:ClearCards()

    t:assertEqual(3, #QR.TeleportPanel.iconPool,
        "three icons built, three in the pool")

    local seen, duplicates = {}, 0
    for _, frame in ipairs(QR.TeleportPanel.iconPool) do
        if seen[frame] then duplicates = duplicates + 1 end
        seen[frame] = true
    end
    t:assertEqual(0, duplicates, "and none of them twice")
end)

T:run("RefreshList: the column headers belong to the list, not the cards", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.frame:SetWidth(820)

    -- Rendered proof this was needed: a screenshot of the card view showed a
    -- stray "Name" and "Status" floating above the first row of cards, left
    -- over from the flat list they label.
    QR.TeleportPanel.groupByDestination = true
    QR.TeleportPanel:RefreshList()
    t:assertFalse(QR.TeleportPanel.frame.nameHeader:IsShown(),
        "no Name column over cards")
    t:assertFalse(QR.TeleportPanel.frame.statusHeader:IsShown(),
        "no Status column over cards")
    t:assertFalse(QR.TeleportPanel.frame.headerSep:IsShown(),
        "and no separator under them")

    QR.TeleportPanel.groupByDestination = false
    QR.TeleportPanel:RefreshList()
    t:assertTrue(QR.TeleportPanel.frame.nameHeader:IsShown(),
        "but they are back over the flat list")
    t:assertTrue(QR.TeleportPanel.frame.statusHeader:IsShown(), "both of them")
    t:assertTrue(QR.TeleportPanel.frame.headerSep:IsShown(), "separator too")

    QR.TeleportPanel:ClearCards()
    QR.TeleportPanel:ClearIcons()
end)

-------------------------------------------------------------------------------
-- K2 picture cards: banner crop, card anatomy, card height
-------------------------------------------------------------------------------

T:run("BannerTexCoords: a 254px card shows the middle band of the icon (xMidYMid slice)", function(t)
    local l, r, top, bottom = QR.TeleportPanel.BannerTexCoords(254, 68, 64)
    t:assertEqual(0, l)
    t:assertEqual(1, r)
    t:assertTrue(math.abs(top - 0.366) < 0.002, "top of the band, got " .. tostring(top))
    t:assertTrue(math.abs(bottom - 0.634) < 0.002, "bottom of the band, got " .. tostring(bottom))
end)

T:run("BannerTexCoords: the band is symmetric and never squashes", function(t)
    local _, _, top, bottom = QR.TeleportPanel.BannerTexCoords(100, 68, 64)
    t:assertTrue(math.abs((1 - bottom) - top) < 1e-9, "centred band")
    t:assertTrue(math.abs((bottom - top) - 0.68) < 1e-9, "the visible fraction is height over width")
end)

T:run("BannerTexCoords: a banner taller than the scaled icon shows the whole icon", function(t)
    local l, r, top, bottom = QR.TeleportPanel.BannerTexCoords(50, 68, 64)
    t:assertEqual(0, top)
    t:assertEqual(1, bottom)
    t:assertEqual(0, l)
    t:assertEqual(1, r)
    local _, _, t2, b2 = QR.TeleportPanel.BannerTexCoords(nil, 68, 64)
    t:assertEqual(0, t2)
    t:assertEqual(1, b2)
end)

T:run("Card: has a picture banner, a scrim, stacked texts and a status dot", function(t)
    resetState()
    QR.TeleportPanel.cardPool = {}
    local card = QR.TeleportPanel:GetCardFrame()
    t:assertNotNil(card.banner, "banner texture")
    t:assertNotNil(card.scrim, "scrim over the banner")
    t:assertNotNil(card.scrim._gradient, "the scrim is a gradient")
    t:assertNotNil(card.nameText, "name")
    t:assertNotNil(card.contText, "continent")
    t:assertNotNil(card.dot, "status dot")
    t:assertNil(card.icon, "no 36px corner icon: the banner is the picture")
end)

T:run("Card: ConfigureCard crops the banner and picks the round dot by status", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.iconFrames = {}
    local group = { name = "Dalaran", mapID = 627, teleports = {
        { id = 140192, isSpell = false, data = { name = "Dalaran Hearthstone", mapID = 627 },
          status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" }, cooldownRemaining = 0 },
    } }
    local card = QR.TeleportPanel:GetCardFrame()
    QR.TeleportPanel:ConfigureCard(card, group, 254)
    local _, _, top, bottom = card.banner:GetTexCoord()
    t:assertTrue(top > 0.3 and bottom < 0.7, "banner shows the middle band")
    t:assertEqual("Interface\\COMMON\\Indicator-Green", card.dot:GetTexture(), "ready -> green dot")
    t:assertNotNil(card.nameText:GetText():find("Dalaran", 1, true), "name in the banner")
end)

T:run("CreateGroupCards: a row is a 124px card plus the gap", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.cards = {}
    QR.TeleportPanel.iconFrames = {}
    local group = { name = "Dalaran", mapID = 627, teleports = {} }
    local newYOffset = QR.TeleportPanel:CreateGroupCards({ group }, 0)
    t:assertEqual(124 + 12, newYOffset, "68px banner + 56px foot, then the 12px gap")
end)

-------------------------------------------------------------------------------
-- Zone banners: the card pictures the destination's map
-------------------------------------------------------------------------------

local function gridTiles(cols, rows)
    local tiles = {}
    for i = 1, cols * rows do tiles[i] = 1000 + i end
    return { cols = cols, rows = rows, tiles = tiles }
end

T:run("ZoneBannerTiles: the middle two tiles of the middle row", function(t)
    resetState()
    MockWoW.config.mapArt[627] = gridTiles(4, 3)     -- a zone map: 1002x668 in 256px tiles
    MockWoW.config.mapArt[2112] = gridTiles(15, 10)  -- a continent map
    local left, right, edge = QR.TeleportPanel.ZoneBannerTiles(627)
    t:assertEqual(1006, left, "row 2 of 3, column 2 of 4")
    t:assertEqual(1007, right, "and its right neighbour")
    t:assertEqual(256, edge, "the tile edge, for the crop")
    left, right = QR.TeleportPanel.ZoneBannerTiles(2112)
    t:assertEqual(1067, left, "row 5 of 10, column 7 of 15")
    t:assertEqual(1068, right, "and its right neighbour")
end)

T:run("ZoneBannerTiles: nothing without a map or without art", function(t)
    resetState()
    t:assertNil(QR.TeleportPanel.ZoneBannerTiles(nil), "no map")
    t:assertNil(QR.TeleportPanel.ZoneBannerTiles(9999), "a map the client has no art for")
end)

T:run("Card: the banner is the destination's map, not the teleport's icon", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.iconFrames = {}
    MockWoW.config.mapArt[627] = gridTiles(4, 3)
    local group = { name = "Dalaran", mapID = 627, teleports = {
        { id = 140192, isSpell = false, data = { name = "Dalaran Hearthstone", mapID = 627 },
          status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" }, cooldownRemaining = 0 },
    } }
    local card = QR.TeleportPanel:GetCardFrame()
    QR.TeleportPanel:ConfigureCard(card, group, 254)
    t:assertEqual(1006, card.tiles[1]:GetTexture(), "left tile of the map")
    t:assertEqual(1007, card.tiles[2]:GetTexture(), "right tile of the map")
    t:assertTrue(card.tiles[1]:IsShown() and card.tiles[2]:IsShown(), "both tiles shown")
    t:assertFalse(card.banner:IsShown(), "the icon banner is not")
    local _, _, top, bottom = card.tiles[1]:GetTexCoord()
    t:assertTrue(top > 0.15 and bottom < 0.85 and top < 0.5, "each tile shows its middle band")
end)

T:run("Card: without map art the icon banner stays", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.iconFrames = {}
    local group = { name = "Random Dungeon", teleports = {
        { id = 6948, isSpell = false, data = { name = "Hearthstone" },
          status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" }, cooldownRemaining = 0 },
    } }
    local card = QR.TeleportPanel:GetCardFrame()
    QR.TeleportPanel:ConfigureCard(card, group, 254)
    t:assertTrue(card.banner:IsShown(), "icon banner shown")
    t:assertFalse(card.tiles[1]:IsShown() or card.tiles[2]:IsShown(), "no map tiles")
end)

T:run("PictureMapFor: a destination's own map first, then the stand-in", function(t)
    resetState()
    local TP = QR.TeleportPanel
    t:assertEqual(627, TP.PictureMapFor({ mapID = 627, destination = "Garrison" }), "own map wins")
    MockWoW.config.playerFaction = "Alliance"; QR.PlayerInfo:InvalidateCache()
    t:assertEqual(582, TP.PictureMapFor({ destination = "Garrison" }), "Lunarfall for the Alliance")
    t:assertEqual(2352, TP.PictureMapFor({ destination = "Homestead" }), "Founder's Point for the Alliance")
    MockWoW.config.playerFaction = "Horde"; QR.PlayerInfo:InvalidateCache()
    t:assertEqual(590, TP.PictureMapFor({ destination = "Garrison Shipyard" }), "Frostwall for the Horde")
    t:assertEqual(2351, TP.PictureMapFor({ destination = "Homestead" }), "Razorwind Shores for the Horde")
    MockWoW.config.playerFaction = "Alliance"; QR.PlayerInfo:InvalidateCache()
    t:assertEqual(2274, TP.PictureMapFor({ destination = "Random Delve" }), "delves are in Khaz Algar")
    t:assertEqual(947, TP.PictureMapFor({ destination = "Random location worldwide" }), "the world")
    t:assertEqual(619, TP.PictureMapFor({ destination = "Random Broken Isles Ley Line" }), "Broken Isles")
    t:assertNil(TP.PictureMapFor({ destination = "Bound Location" }), "no map the client could name")
    t:assertNil(TP.PictureMapFor({ destination = "Camp Location" }), "nor here")
end)

T:run("Card: the garrison is pictured by the faction's garrison map", function(t)
    resetState()
    ensureTeleportPanelFrame()
    QR.TeleportPanel.cardPool = {}
    QR.TeleportPanel.iconFrames = {}
    MockWoW.config.mapArt[582] = gridTiles(4, 3)
    MockWoW.config.playerFaction = "Alliance"; QR.PlayerInfo:InvalidateCache()
    local group = { name = "Garrison", destination = "Garrison", teleports = {
        { id = 110560, isSpell = false, data = { name = "Garrison Hearthstone", destination = "Garrison" },
          status = { sortOrder = 1, color = "|cFF00FF00", text = "Ready", key = "STATUS_READY" }, cooldownRemaining = 0 },
    } }
    local card = QR.TeleportPanel:GetCardFrame()
    QR.TeleportPanel:ConfigureCard(card, group, 254)
    t:assertEqual(1006, card.tiles[1]:GetTexture(), "Lunarfall's middle tile")
    t:assertFalse(card.banner:IsShown(), "no icon banner")
end)

T:run("GroupTeleportsByDestination: a group remembers its English destination", function(t)
    resetState()
    local groups = QR.TeleportPanel:GroupTeleportsByDestination({
        { id = 110560, isSpell = false, data = { name = "Garrison Hearthstone", destination = "Garrison" },
          status = { sortOrder = 1, color = "", text = "", key = "STATUS_READY" }, cooldownRemaining = 0 },
    })
    t:assertEqual("Garrison", groups[1].destination, "the key PictureMapFor looks up")
end)

-------------------------------------------------------------------------------
-- The filter dropdown fits every label its menu can produce
-------------------------------------------------------------------------------

--- Measures like the mock's FontString does: 7 px per byte.
local function fakeProbe()
    local probe = { text = "" }
    function probe:SetText(value) self.text = value or "" end
    function probe:GetStringWidth() return #self.text * 7 end
    return probe
end

T:run("TeleportPanel: filter labels include each filter combined with grouping", function(t)
    local candidates = QR.TeleportPanel.FilterLabelCandidates()
    local seen = {}
    for _, text in ipairs(candidates) do seen[text] = true end

    t:assertTrue(seen["Usable Now, Group by Destination"], "The combined label the dropdown shows")
    t:assertTrue(seen["Show All, Group by Destination"], "Show All combined with grouping")
    t:assertTrue(seen["Obtainable, Group by Destination"], "Obtainable combined with grouping")
end)

T:run("TeleportPanel: the dropdown is wide enough for its longest label", function(t)
    local probe = fakeProbe()
    local candidates = QR.TeleportPanel.FilterLabelCandidates()
    local width = QR.TeleportPanel.FilterDropdownWidth(probe, candidates)

    local widest = 0
    for _, text in ipairs(candidates) do
        if #text * 7 > widest then widest = #text * 7 end
    end

    -- The button draws a chevron beside the text, so the text width alone is
    -- not enough; 24 px is the smallest that leaves room for it.
    t:assertTrue(
        width >= widest + 24,
        "Room for the widest label and the chevron: " .. width .. " for " .. widest
    )
    t:assertTrue(width <= 320, "Stays inside the panel, got " .. width)
end)

T:run("TeleportPanel: a short label still gets a usable dropdown width", function(t)
    local width = QR.TeleportPanel.FilterDropdownWidth(fakeProbe(), { "All" })

    t:assertTrue(width >= 150, "Keeps a minimum width, got " .. width)
end)

T:run("TeleportPanel: measuring leaves no text behind on the probe", function(t)
    local probe = fakeProbe()
    QR.TeleportPanel.FilterDropdownWidth(probe, { "Usable Now, Group by Destination" })

    t:assertEqual(probe.text, "", "Probe cleared after measuring")
end)
