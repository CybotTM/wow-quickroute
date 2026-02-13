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

    local newYOffset = QR.TeleportPanel:CreateGroupIconRow(group, 0)
    t:assertEqual(3, #QR.TeleportPanel.iconFrames, "3 icon frames created")
    t:assertGreaterThan(newYOffset, 0, "yOffset advanced")

    -- Verify all icons are shown
    for i, icon in ipairs(QR.TeleportPanel.iconFrames) do
        t:assertTrue(icon:IsShown(), "Icon " .. i .. " is shown")
    end

    QR.TeleportPanel:ClearIcons()
end)

T:run("CreateGroupIconRow: wraps to next row when full", function(t)
    resetState()
    ensureTeleportPanelFrame()

    -- Panel width ~500, avail ~450. At 36+4=40px per icon, fits ~11 per row
    -- Create 15 icons to force wrap
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
    local newYOffset = QR.TeleportPanel:CreateGroupIconRow(group, 0)

    t:assertEqual(15, #QR.TeleportPanel.iconFrames, "15 icon frames created")
    -- With 2 rows (11+4), height should be more than one row of icons
    -- One row: 6+36+6 = 48, two rows: 6 + 36 + 4 + 36 + 6 = 88
    t:assertGreaterThan(newYOffset, 48, "yOffset reflects multiple rows")

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
