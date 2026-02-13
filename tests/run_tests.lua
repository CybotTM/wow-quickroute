#!/usr/bin/env lua5.1
-------------------------------------------------------------------------------
-- run_tests.lua
-- Test runner for the QuickRoute addon.
--
-- 1. Sets up package paths
-- 2. Loads the WoW API mock
-- 3. Loads addon files in .toc order via addon_loader
-- 4. Discovers and runs test_*.lua files
-- 5. Reports pass/fail counts
-- 6. Exits with code 0 on success, 1 on failure
-------------------------------------------------------------------------------

-- Determine script directory for path setup
local scriptDir
do
    local info = debug.getinfo(1, "S")
    local src = info.source:gsub("^@", "")
    scriptDir = src:match("(.*/)")
    if not scriptDir then
        -- Fallback: assume running from project root
        scriptDir = "tests/"
    end
end

local projectRoot = scriptDir .. "../"

-- Set up package path so require() can find test modules
package.path = scriptDir .. "?.lua;"
    .. scriptDir .. "../?.lua;"
    .. package.path

-------------------------------------------------------------------------------
-- Load and install the mock API
-------------------------------------------------------------------------------

local MockWoW = require("mock_wow_api")
MockWoW:Install()

print("==========================================================")
print("  QuickRoute Test Runner")
print("==========================================================")
print("")

-------------------------------------------------------------------------------
-- Load the addon via the loader
-------------------------------------------------------------------------------

local AddonLoader = require("addon_loader")

print("[RUNNER] Loading addon files...")
local QR = AddonLoader:Load(MockWoW, {
    addonDir = projectRoot .. "QuickRoute/",
    quiet = true,
})

if not AddonLoader:AllFilesLoaded() then
    print("[RUNNER] WARNING: " .. AddonLoader:GetStatus())
else
    print("[RUNNER] " .. AddonLoader:GetStatus())
end

-- Fire initialization events
print("[RUNNER] Firing ADDON_LOADED and PLAYER_LOGIN events...")
AddonLoader:FireAddonLoaded(MockWoW)
AddonLoader:FirePlayerLogin(MockWoW)
print("[RUNNER] Addon initialized.")
print("")

-------------------------------------------------------------------------------
-- Test Framework (minimal, Lua 5.1 compatible)
-------------------------------------------------------------------------------

local TestFramework = {
    totalTests = 0,
    passedTests = 0,
    failedTests = 0,
    failures = {},
    currentSuite = "",
}

--- Assert that a condition is true
-- @param condition boolean The condition to check
-- @param message string Description of what is being tested
function TestFramework:assert(condition, message)
    self.totalTests = self.totalTests + 1
    local label = self.currentSuite .. ": " .. (message or "unnamed assertion")
    if condition then
        self.passedTests = self.passedTests + 1
    else
        self.failedTests = self.failedTests + 1
        self.failures[#self.failures + 1] = label
        print("    FAIL: " .. label)
    end
end

--- Assert two values are equal
-- @param expected any The expected value
-- @param actual any The actual value
-- @param message string Description
function TestFramework:assertEqual(expected, actual, message)
    local msg = (message or "assertEqual") ..
        " (expected: " .. tostring(expected) .. ", got: " .. tostring(actual) .. ")"
    self:assert(expected == actual, msg)
end

--- Assert a value is not nil
-- @param value any The value to check
-- @param message string Description
function TestFramework:assertNotNil(value, message)
    self:assert(value ~= nil, (message or "assertNotNil") .. " (got nil)")
end

--- Assert a value is nil
-- @param value any The value to check
-- @param message string Description
function TestFramework:assertNil(value, message)
    self:assert(value == nil, (message or "assertNil") .. " (got: " .. tostring(value) .. ")")
end

--- Assert a value is true
-- @param value any The value to check
-- @param message string Description
function TestFramework:assertTrue(value, message)
    self:assert(value == true, (message or "assertTrue") .. " (got: " .. tostring(value) .. ")")
end

--- Assert a value is false
-- @param value any The value to check
-- @param message string Description
function TestFramework:assertFalse(value, message)
    self:assert(value == false, (message or "assertFalse") .. " (got: " .. tostring(value) .. ")")
end

--- Assert a number is greater than another
-- @param a number The value that should be greater
-- @param b number The value to compare against
-- @param message string Description
function TestFramework:assertGreaterThan(a, b, message)
    local msg = (message or "assertGreaterThan") ..
        " (expected " .. tostring(a) .. " > " .. tostring(b) .. ")"
    self:assert(type(a) == "number" and type(b) == "number" and a > b, msg)
end

--- Assert a table has a certain number of elements (using pairs count)
-- @param tbl table The table to check
-- @param count number Expected count
-- @param message string Description
function TestFramework:assertTableCount(tbl, count, message)
    local actual = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do actual = actual + 1 end
    end
    local msg = (message or "assertTableCount") ..
        " (expected " .. tostring(count) .. ", got " .. tostring(actual) .. ")"
    self:assert(actual == count, msg)
end

--- Run a test function, catching errors
-- @param name string Test name
-- @param testFunc function The test function
function TestFramework:run(name, testFunc)
    self.currentSuite = name
    local ok, err = pcall(testFunc, self, QR, MockWoW)
    if not ok then
        self.totalTests = self.totalTests + 1
        self.failedTests = self.failedTests + 1
        local label = name .. ": ERROR - " .. tostring(err)
        self.failures[#self.failures + 1] = label
        print("    ERROR: " .. label)
    end
end

--- Print final report and return exit code
-- @return number 0 for success, 1 for failure
function TestFramework:report()
    print("")
    print("==========================================================")
    print(string.format("  Results: %d passed, %d failed, %d total",
        self.passedTests, self.failedTests, self.totalTests))
    print("==========================================================")

    if #self.failures > 0 then
        print("")
        print("  Failed tests:")
        for i, msg in ipairs(self.failures) do
            print("    " .. i .. ". " .. msg)
        end
    end

    print("")
    return self.failedTests == 0 and 0 or 1
end

-- Export for test files
_G.TestFramework = TestFramework
_G.MockWoW = MockWoW
_G.QR = QR

-------------------------------------------------------------------------------
-- Discover and run test files
-------------------------------------------------------------------------------

-- Use io.popen to find test files (portable across POSIX systems)
local testFiles = {}
local handle = io.popen("ls " .. scriptDir .. "test_*.lua 2>/dev/null")
if handle then
    for line in handle:lines() do
        testFiles[#testFiles + 1] = line
    end
    handle:close()
end

if #testFiles == 0 then
    print("[RUNNER] No test_*.lua files found in " .. scriptDir)
    print("[RUNNER] Running built-in smoke tests instead...")
    print("")

    -- Built-in smoke tests to verify the framework works
    print("-- Smoke Tests --")

    TestFramework:run("Smoke: MockWoW installed", function(t)
        t:assertNotNil(CreateFrame, "CreateFrame exists")
        t:assertNotNil(C_Map, "C_Map exists")
        t:assertNotNil(C_Map.GetBestMapForUnit, "C_Map.GetBestMapForUnit exists")
        t:assertNotNil(UnitFactionGroup, "UnitFactionGroup exists")
        t:assertNotNil(InCombatLockdown, "InCombatLockdown exists")
        t:assertNotNil(wipe, "wipe exists")
        t:assertNotNil(GetItemInfo, "GetItemInfo exists")
        t:assertNotNil(IsSpellKnown, "IsSpellKnown exists")
        t:assertNotNil(PlayerHasToy, "PlayerHasToy exists")
        t:assertNotNil(C_Timer.After, "C_Timer.After exists")
    end)

    TestFramework:run("Smoke: Player info works", function(t)
        local faction = UnitFactionGroup("player")
        t:assertEqual("Alliance", faction, "Default faction is Alliance")

        local className, classToken = UnitClass("player")
        t:assertEqual("MAGE", classToken, "Default class is MAGE")

        local mapID = C_Map.GetBestMapForUnit("player")
        t:assertEqual(84, mapID, "Default map is Stormwind (84)")
    end)

    TestFramework:run("Smoke: Map database works", function(t)
        local info = C_Map.GetMapInfo(84)
        t:assertNotNil(info, "Stormwind map info exists")
        t:assertEqual("Stormwind City", info.name, "Stormwind name correct")

        info = C_Map.GetMapInfo(85)
        t:assertNotNil(info, "Orgrimmar map info exists")
        t:assertEqual("Orgrimmar", info.name, "Orgrimmar name correct")

        info = C_Map.GetMapInfo(2339)
        t:assertNotNil(info, "Dornogal map info exists")
        t:assertEqual("Dornogal", info.name, "Dornogal name correct")

        info = C_Map.GetMapInfo(2112)
        t:assertNotNil(info, "Valdrakken map info exists")
        t:assertEqual("Valdrakken", info.name, "Valdrakken name correct")
    end)

    TestFramework:run("Smoke: CreateFrame works", function(t)
        local frame = CreateFrame("Frame")
        t:assertNotNil(frame, "Frame created")
        frame:SetSize(100, 50)
        t:assertEqual(100, frame:GetWidth(), "Width set correctly")
        t:assertEqual(50, frame:GetHeight(), "Height set correctly")

        frame:Show()
        t:assertTrue(frame:IsShown(), "Frame is shown after Show()")

        frame:Hide()
        t:assertFalse(frame:IsShown(), "Frame is hidden after Hide()")
    end)

    TestFramework:run("Smoke: Event system works", function(t)
        local received = {}
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("TEST_EVENT")
        frame:SetScript("OnEvent", function(self, event, arg1)
            received[#received + 1] = { event = event, arg1 = arg1 }
        end)

        MockWoW:FireEvent("TEST_EVENT", "hello")
        t:assertEqual(1, #received, "Event received once")
        t:assertEqual("TEST_EVENT", received[1].event, "Event name correct")
        t:assertEqual("hello", received[1].arg1, "Event arg correct")
    end)

    TestFramework:run("Smoke: Addon namespace loaded", function(t)
        t:assertNotNil(QR, "QR namespace exists")
        t:assertNotNil(QR.Graph, "QR.Graph loaded")
        t:assertNotNil(QR.PathCalculator, "QR.PathCalculator loaded")
        t:assertNotNil(QR.TravelTime, "QR.TravelTime loaded")
        t:assertNotNil(QR.PlayerInventory, "QR.PlayerInventory loaded")
        t:assertNotNil(QR.CooldownTracker, "QR.CooldownTracker loaded")
        t:assertNotNil(QR.WaypointIntegration, "QR.WaypointIntegration loaded")
        t:assertNotNil(QR.TeleportItemsData, "QR.TeleportItemsData loaded")
        t:assertNotNil(QR.PortalHubs, "QR.PortalHubs loaded")
        t:assertNotNil(QR.Continents, "QR.Continents loaded")
        t:assertNotNil(QR.ZoneToContinent, "QR.ZoneToContinent loaded")
        t:assertNotNil(QR.ZoneAdjacencies, "QR.ZoneAdjacencies loaded")
        t:assertNotNil(QR.L, "QR.L (localization) loaded")
        t:assertNotNil(QR.SecureButtons, "QR.SecureButtons loaded")
        t:assertNotNil(QR.UI, "QR.UI loaded")
        t:assertNotNil(QR.TeleportPanel, "QR.TeleportPanel loaded")
    end)

    TestFramework:run("Smoke: Graph can be created and used", function(t)
        local g = QR.Graph:New()
        t:assertNotNil(g, "Graph created")

        t:assertTrue(g:AddNode("A", { mapID = 1 }), "Node A added")
        t:assertTrue(g:AddNode("B", { mapID = 2 }), "Node B added")
        t:assertTrue(g:AddNode("C", { mapID = 3 }), "Node C added")

        t:assertTrue(g:AddEdge("A", "B", 10, "walk"), "Edge A->B added")
        t:assertTrue(g:AddEdge("B", "C", 5, "walk"), "Edge B->C added")

        local path, cost, edges = g:FindShortestPath("A", "C")
        t:assertNotNil(path, "Path found A->C")
        t:assertEqual(15, cost, "Path cost is 15")
        t:assertEqual(3, #path, "Path has 3 nodes")
        t:assertEqual("A", path[1], "Path starts at A")
        t:assertEqual("B", path[2], "Path goes through B")
        t:assertEqual("C", path[3], "Path ends at C")
    end)

    TestFramework:run("Smoke: TravelTime calculations work", function(t)
        t:assertNotNil(QR.TravelTime.EstimateWalkingTime, "EstimateWalkingTime exists")

        local time = QR.TravelTime:EstimateWalkingTime(0, 0, 1, 0, false)
        t:assertNotNil(time, "Walking time calculated")
        t:assertGreaterThan(time, 0, "Walking time > 0")

        local flyTime = QR.TravelTime:EstimateWalkingTime(0, 0, 1, 0, true)
        t:assertNotNil(flyTime, "Flying time calculated")
        t:assertGreaterThan(time, flyTime, "Flying is faster than walking")
    end)

    TestFramework:run("Smoke: ZoneAdjacency data loaded", function(t)
        t:assertNotNil(QR.GetContinentForZone, "GetContinentForZone exists")

        local cont = QR.GetContinentForZone(84)
        t:assertEqual("EASTERN_KINGDOMS", cont, "Stormwind is in Eastern Kingdoms")

        cont = QR.GetContinentForZone(85)
        t:assertEqual("KALIMDOR", cont, "Orgrimmar is in Kalimdor")

        cont = QR.GetContinentForZone(2339)
        t:assertEqual("KHAZ_ALGAR", cont, "Dornogal is in Khaz Algar")

        local adj = QR.GetAdjacentZones(84)
        t:assertNotNil(adj, "Stormwind has adjacency data")
        t:assertGreaterThan(#adj, 0, "Stormwind has adjacent zones")
    end)

    TestFramework:run("Smoke: CooldownTracker FormatTime works", function(t)
        t:assertEqual("Ready", QR.CooldownTracker:FormatTime(0), "0 seconds = Ready")
        t:assertEqual("30s", QR.CooldownTracker:FormatTime(30), "30 seconds")
        t:assertEqual("5m 0s", QR.CooldownTracker:FormatTime(300), "300 seconds = 5m")
        t:assertEqual("1h 30m", QR.CooldownTracker:FormatTime(5400), "5400 seconds = 1h 30m")
    end)

    TestFramework:run("Smoke: Localization metatable fallback", function(t)
        t:assertNotNil(QR.L, "Localization table exists")
        -- Existing key should return value
        t:assertEqual("QuickRoute", QR.L["ADDON_TITLE"], "Known key returns value")
        -- Unknown key should return the key itself (metatable __index)
        t:assertEqual("NONEXISTENT_KEY", QR.L["NONEXISTENT_KEY"], "Unknown key returns key name")
    end)

    TestFramework:run("Smoke: BuildGraph succeeds", function(t)
        -- Make sure we have some spells known so teleports show up
        MockWoW.config.knownSpells = {}
        MockWoW.config.ownedToys = {}
        MockWoW.config.bagItems = {}

        local graph = QR.PathCalculator:BuildGraph()
        t:assertNotNil(graph, "Graph was built")

        -- Count nodes
        local nodeCount = 0
        for _ in pairs(graph.nodes) do nodeCount = nodeCount + 1 end
        t:assertGreaterThan(nodeCount, 0, "Graph has nodes")

        -- Count edges
        local edgeCount = 0
        for _, edges in pairs(graph.edges) do
            for _ in pairs(edges) do edgeCount = edgeCount + 1 end
        end
        t:assertGreaterThan(edgeCount, 0, "Graph has edges")
    end)

else
    -- Run discovered test files
    for _, testFile in ipairs(testFiles) do
        local basename = testFile:match("([^/]+)$")
        print("-- Running: " .. basename .. " --")

        local chunk, loadErr = loadfile(testFile)
        if not chunk then
            print("    ERROR loading " .. basename .. ": " .. tostring(loadErr))
            TestFramework.totalTests = TestFramework.totalTests + 1
            TestFramework.failedTests = TestFramework.failedTests + 1
            TestFramework.failures[#TestFramework.failures + 1] = "Failed to load: " .. basename
        else
            local ok, runErr = pcall(chunk, TestFramework, QR, MockWoW)
            if not ok then
                print("    ERROR running " .. basename .. ": " .. tostring(runErr))
                TestFramework.totalTests = TestFramework.totalTests + 1
                TestFramework.failedTests = TestFramework.failedTests + 1
                TestFramework.failures[#TestFramework.failures + 1] =
                    "Failed to execute: " .. basename .. " - " .. tostring(runErr)
            end
        end
        print("")
    end
end

-------------------------------------------------------------------------------
-- Report and exit
-------------------------------------------------------------------------------

local exitCode = TestFramework:report()
os.exit(exitCode)
