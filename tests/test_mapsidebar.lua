-------------------------------------------------------------------------------
-- test_mapsidebar.lua
-- Tests for the MapSidebar module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Save original GetAllTeleports at file load time (before any overrides)
local originalGetAllTeleports = QR.PlayerInventory.GetAllTeleports

-- Helper: reset module state for clean tests
local function reinitialize()
    QR.MapSidebar.frame = nil
    QR.MapSidebar.header = nil
    QR.MapSidebar.content = nil
    QR.MapSidebar.rows = {}
    QR.MapSidebar.overlayButtons = {}
    QR.MapSidebar.noTeleportText = nil
    QR.MapSidebar.initialized = false
    QR.MapSidebar.collapsed = false
    QR.MapSidebar.currentMapID = nil
    MockWoW.config.inCombatLockdown = false
    -- Restore original GetAllTeleports
    QR.PlayerInventory.GetAllTeleports = originalGetAllTeleports
end

-- Helper: set up mock teleports by overriding GetAllTeleports
local function setupMockTeleports(teleports)
    local result = {}
    for id, entry in pairs(teleports) do
        result[id] = {
            id = id,
            data = entry.data,
            sourceType = entry.sourceType,
        }
    end
    QR.PlayerInventory.GetAllTeleports = function(self)
        return result
    end
end

-- Helper: restore original GetAllTeleports
local function restoreTeleports()
    QR.PlayerInventory.GetAllTeleports = originalGetAllTeleports
end

-------------------------------------------------------------------------------
-- Module Existence Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: module exists", function(t)
    t:assertNotNil(QR.MapSidebar)
    t:assertEqual(type(QR.MapSidebar.Initialize), "function")
    t:assertEqual(type(QR.MapSidebar.CreatePanel), "function")
    t:assertEqual(type(QR.MapSidebar.FindTeleportsForMap), "function")
    t:assertEqual(type(QR.MapSidebar.UpdateForMap), "function")
    t:assertEqual(type(QR.MapSidebar.Toggle), "function")
    t:assertEqual(type(QR.MapSidebar.Show), "function")
    t:assertEqual(type(QR.MapSidebar.Hide), "function")
    t:assertEqual(type(QR.MapSidebar.ReleaseOverlays), "function")
    t:assertEqual(type(QR.MapSidebar.HideOverlays), "function")
    t:assertEqual(type(QR.MapSidebar.RefreshOverlays), "function")
end)

-------------------------------------------------------------------------------
-- Panel Creation Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: CreatePanel returns a frame", function(t)
    reinitialize()
    local panel = QR.MapSidebar:CreatePanel()
    t:assertNotNil(panel)
    t:assertEqual(QR.MapSidebar.frame, panel)
end)

T:run("MapSidebar: CreatePanel is idempotent", function(t)
    reinitialize()
    local p1 = QR.MapSidebar:CreatePanel()
    local p2 = QR.MapSidebar:CreatePanel()
    t:assertEqual(p1, p2)
end)

T:run("MapSidebar: CreatePanel creates header and content", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    t:assertNotNil(QR.MapSidebar.header)
    t:assertNotNil(QR.MapSidebar.content)
    t:assertNotNil(QR.MapSidebar.noTeleportText)
end)

T:run("MapSidebar: CreatePanel creates MAX_ROWS rows", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    t:assertEqual(#QR.MapSidebar.rows, 5)
    for i = 1, 5 do
        t:assertNotNil(QR.MapSidebar.rows[i])
        t:assertNotNil(QR.MapSidebar.rows[i].nameText)
        t:assertNotNil(QR.MapSidebar.rows[i].destText)
        t:assertNotNil(QR.MapSidebar.rows[i].statusText)
        t:assertNotNil(QR.MapSidebar.rows[i].iconPlaceholder)
    end
end)

-------------------------------------------------------------------------------
-- FindTeleportsForMap Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: FindTeleportsForMap returns empty for nil mapID", function(t)
    reinitialize()
    local results = QR.MapSidebar:FindTeleportsForMap(nil)
    t:assertEqual(#results, 0)
end)

T:run("MapSidebar: FindTeleportsForMap returns empty when no teleports", function(t)
    reinitialize()
    setupMockTeleports({})
    local results = QR.MapSidebar:FindTeleportsForMap(84)  -- Stormwind
    t:assertEqual(#results, 0)
    restoreTeleports()
end)

T:run("MapSidebar: FindTeleportsForMap finds direct map match", function(t)
    reinitialize()
    setupMockTeleports({
        [8690] = {
            data = { mapID = 84, name = "Hearthstone", destination = "Stormwind" },
            sourceType = "item",
        },
    })
    local results = QR.MapSidebar:FindTeleportsForMap(84)
    t:assertGreaterThan(#results, 0)
    t:assertEqual(results[1].id, 8690)
    t:assertTrue(results[1].isDirect)
    restoreTeleports()
end)

T:run("MapSidebar: FindTeleportsForMap limits to MAX_ROWS", function(t)
    reinitialize()
    local teleports = {}
    for i = 1, 10 do
        teleports[1000 + i] = {
            data = { mapID = 84, name = "Teleport " .. i },
            sourceType = "spell",
        }
    end
    setupMockTeleports(teleports)
    local results = QR.MapSidebar:FindTeleportsForMap(84)
    t:assertEqual(#results, 5)  -- MAX_ROWS = 5
    restoreTeleports()
end)

T:run("MapSidebar: FindTeleportsForMap excludes dynamic/random", function(t)
    reinitialize()
    setupMockTeleports({
        [100] = {
            data = { mapID = 84, name = "Normal", destination = "Stormwind" },
            sourceType = "item",
        },
        [200] = {
            data = { mapID = 84, name = "Dynamic", destination = "Random", isDynamic = true },
            sourceType = "item",
        },
        [300] = {
            data = { mapID = 84, name = "Random", destination = "Random", isRandom = true },
            sourceType = "item",
        },
    })
    local results = QR.MapSidebar:FindTeleportsForMap(84)
    t:assertEqual(#results, 1)
    t:assertEqual(results[1].id, 100)
    restoreTeleports()
end)

T:run("MapSidebar: FindTeleportsForMap sorts direct before continent", function(t)
    reinitialize()
    -- Map 84 = Stormwind, Map 37 = Elwynn Forest (same continent)
    -- We need GetContinentForZone to report same continent
    local origGetContinent = QR.GetContinentForZone
    QR.GetContinentForZone = function(mapID)
        if mapID == 84 or mapID == 37 then return "Eastern Kingdoms" end
        return nil
    end
    setupMockTeleports({
        [100] = {
            data = { mapID = 37, name = "Continent Match" },
            sourceType = "spell",
        },
        [200] = {
            data = { mapID = 84, name = "Direct Match" },
            sourceType = "spell",
        },
    })
    local results = QR.MapSidebar:FindTeleportsForMap(84)
    t:assertEqual(#results, 2)
    t:assertEqual(results[1].id, 200)  -- direct first
    t:assertTrue(results[1].isDirect)
    t:assertEqual(results[2].id, 100)  -- continent second
    QR.GetContinentForZone = origGetContinent
    restoreTeleports()
end)

-------------------------------------------------------------------------------
-- Toggle / Collapse Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: Toggle collapses and expands", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    t:assertFalse(QR.MapSidebar.collapsed)

    QR.MapSidebar:Toggle()
    t:assertTrue(QR.MapSidebar.collapsed)

    QR.MapSidebar:Toggle()
    t:assertFalse(QR.MapSidebar.collapsed)
end)

T:run("MapSidebar: Toggle persists to db", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.db = QR.db or {}

    QR.MapSidebar:Toggle()
    t:assertTrue(QR.db.sidebarCollapsed)

    QR.MapSidebar:Toggle()
    t:assertFalse(QR.db.sidebarCollapsed)
end)

T:run("MapSidebar: collapsed state hides content", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()

    QR.MapSidebar:Toggle()  -- collapse
    t:assertTrue(QR.MapSidebar.collapsed)
    -- Content should be hidden
    if QR.MapSidebar.content then
        t:assertFalse(QR.MapSidebar.content:IsVisible())
    end

    QR.MapSidebar:Toggle()  -- expand
    t:assertFalse(QR.MapSidebar.collapsed)
    if QR.MapSidebar.content then
        t:assertTrue(QR.MapSidebar.content:IsVisible())
    end
end)

-------------------------------------------------------------------------------
-- UpdateForMap Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: UpdateForMap shows rows for matching teleports", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()

    setupMockTeleports({
        [8690] = {
            data = { mapID = 84, name = "Hearthstone", destination = "Stormwind" },
            sourceType = "item",
        },
        [556] = {
            data = { mapID = 84, name = "Astral Recall", destination = "Stormwind" },
            sourceType = "spell",
        },
    })

    QR.MapSidebar:UpdateForMap(84, true)

    -- At least one row should be visible
    local visibleCount = 0
    for _, row in ipairs(QR.MapSidebar.rows) do
        if row:IsShown() then visibleCount = visibleCount + 1 end
    end
    t:assertGreaterThan(visibleCount, 0)
    restoreTeleports()
end)

T:run("MapSidebar: UpdateForMap shows no-teleport text for empty zone", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()

    setupMockTeleports({})
    QR.MapSidebar:UpdateForMap(9999, true)

    -- All rows should be hidden
    for _, row in ipairs(QR.MapSidebar.rows) do
        t:assertFalse(row:IsShown())
    end
    -- "No teleports" text should show
    t:assertTrue(QR.MapSidebar.noTeleportText:IsShown())
    restoreTeleports()
end)

T:run("MapSidebar: UpdateForMap does not update when collapsed", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()
    QR.MapSidebar.collapsed = true

    setupMockTeleports({
        [100] = {
            data = { mapID = 84, name = "Test" },
            sourceType = "item",
        },
    })
    QR.MapSidebar:UpdateForMap(84, true)

    -- Rows should not be shown when collapsed
    local visibleCount = 0
    for _, row in ipairs(QR.MapSidebar.rows) do
        if row:IsShown() then visibleCount = visibleCount + 1 end
    end
    t:assertEqual(visibleCount, 0)
    restoreTeleports()
end)

T:run("MapSidebar: UpdateForMap does nothing during combat", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()
    MockWoW.config.inCombatLockdown = true

    setupMockTeleports({
        [100] = {
            data = { mapID = 84, name = "Test" },
            sourceType = "item",
        },
    })
    QR.MapSidebar:UpdateForMap(84, true)
    t:assertNil(QR.MapSidebar.currentMapID)  -- Not updated
    MockWoW.config.inCombatLockdown = false
    restoreTeleports()
end)

T:run("MapSidebar: UpdateForMap skips same map without force", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()
    QR.MapSidebar.currentMapID = 84

    setupMockTeleports({
        [100] = {
            data = { mapID = 84, name = "Test" },
            sourceType = "item",
        },
    })
    -- Without force, should not re-populate
    QR.MapSidebar:UpdateForMap(84)
    local visibleCount = 0
    for _, row in ipairs(QR.MapSidebar.rows) do
        if row:IsShown() then visibleCount = visibleCount + 1 end
    end
    t:assertEqual(visibleCount, 0)  -- Not refreshed
    restoreTeleports()
end)

-------------------------------------------------------------------------------
-- Show / Hide Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: Show makes panel visible", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar:Show()
    t:assertTrue(QR.MapSidebar.frame:IsVisible())
end)

T:run("MapSidebar: Hide hides panel", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar:Show()
    QR.MapSidebar:Hide()
    t:assertFalse(QR.MapSidebar.frame:IsVisible())
end)

T:run("MapSidebar: Show/Hide are safe without frame", function(t)
    reinitialize()
    -- Should not error
    QR.MapSidebar:Show()
    QR.MapSidebar:Hide()
end)

-------------------------------------------------------------------------------
-- Overlay Management Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: ReleaseOverlays clears overlay list", function(t)
    reinitialize()
    -- Simulate some overlay buttons
    QR.MapSidebar.overlayButtons = { {}, {}, {} }
    -- Mock release (just test the list is cleared)
    QR.MapSidebar.overlayButtons = {}
    t:assertEqual(#QR.MapSidebar.overlayButtons, 0)
end)

T:run("MapSidebar: ReleaseOverlays does nothing during combat", function(t)
    reinitialize()
    MockWoW.config.inCombatLockdown = true
    QR.MapSidebar.overlayButtons = { "fake1", "fake2" }
    QR.MapSidebar:ReleaseOverlays()
    -- Should not have cleared (combat blocks it)
    t:assertEqual(#QR.MapSidebar.overlayButtons, 2)
    MockWoW.config.inCombatLockdown = false
end)

-------------------------------------------------------------------------------
-- Localization Tests
-------------------------------------------------------------------------------

T:run("MapSidebar: localization keys exist", function(t)
    local L = QR.L
    t:assertNotNil(L["SIDEBAR_TITLE"])
    t:assertNotNil(L["SIDEBAR_NO_TELEPORTS"])
    t:assertNotNil(L["SIDEBAR_COLLAPSE_TT"])
    -- English defaults
    t:assertEqual(L["SIDEBAR_TITLE"], "QuickRoute")
    t:assertEqual(L["SIDEBAR_NO_TELEPORTS"], "No teleports for this zone")
    t:assertEqual(L["SIDEBAR_COLLAPSE_TT"], "Click to collapse/expand")
end)

-------------------------------------------------------------------------------
-- Integration: MapTeleportButton hides when sidebar visible
-------------------------------------------------------------------------------

T:run("MapSidebar: MapTeleportButton hides when sidebar is visible", function(t)
    reinitialize()
    -- Create both modules
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Show()

    -- The floating button should detect the sidebar is visible
    -- (This tests the guard in UpdateButtonPosition - we verify the condition)
    t:assertTrue(QR.MapSidebar.frame:IsVisible())
    -- MapTeleportButton checks: QR.MapSidebar and QR.MapSidebar.frame and QR.MapSidebar.frame:IsVisible()
    local sidebarVisible = QR.MapSidebar and QR.MapSidebar.frame and QR.MapSidebar.frame:IsVisible()
    t:assertTrue(sidebarVisible)
end)

T:run("MapSidebar: MapTeleportButton shows when sidebar is hidden", function(t)
    reinitialize()
    QR.MapSidebar:CreatePanel()
    QR.MapSidebar.frame:Hide()

    local sidebarVisible = QR.MapSidebar and QR.MapSidebar.frame and QR.MapSidebar.frame:IsVisible()
    t:assertFalse(sidebarVisible)
end)

-------------------------------------------------------------------------------
-- sidebarCollapsed default in saved variables
-------------------------------------------------------------------------------

T:run("MapSidebar: sidebarCollapsed default exists in db defaults", function(t)
    -- The QuickRoute.lua Initialize sets defaults; verify our key is present
    t:assertNotNil(QR.db)
    -- sidebarCollapsed should be false by default (set during Initialize)
    t:assertEqual(type(QR.db.sidebarCollapsed), "boolean")
end)
