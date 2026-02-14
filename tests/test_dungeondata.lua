-------------------------------------------------------------------------------
-- test_dungeondata.lua
-- Tests for QR.DungeonData module (runtime scanner, merger, lookup API)
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper: reset DungeonData state between tests
-------------------------------------------------------------------------------
local function resetDungeonData()
    local DD = QR.DungeonData
    DD.instances = {}
    DD.byZone = {}
    DD.byTier = {}
    DD.tierNames = {}
    DD.numTiers = 0
    DD.scanned = false
    DD.entrancesScanned = false
end

-------------------------------------------------------------------------------
-- 1. Module Structure
-------------------------------------------------------------------------------

T:run("DungeonData: module exists", function(t)
    t:assertNotNil(QR.DungeonData, "QR.DungeonData exists")
end)

T:run("DungeonData: has expected methods", function(t)
    local DD = QR.DungeonData
    t:assertNotNil(DD.ScanInstances, "ScanInstances exists")
    t:assertNotNil(DD.ScanEntrances, "ScanEntrances exists")
    t:assertNotNil(DD.MergeStaticFallback, "MergeStaticFallback exists")
    t:assertNotNil(DD.GetInstance, "GetInstance exists")
    t:assertNotNil(DD.GetInstancesForZone, "GetInstancesForZone exists")
    t:assertNotNil(DD.GetTierName, "GetTierName exists")
    t:assertNotNil(DD.GetAllTiers, "GetAllTiers exists")
    t:assertNotNil(DD.Search, "Search exists")
    t:assertNotNil(DD.Initialize, "Initialize exists")
end)

T:run("DungeonData: has expected data fields", function(t)
    local DD = QR.DungeonData
    t:assertNotNil(DD.instances, "instances table exists")
    t:assertNotNil(DD.byZone, "byZone table exists")
    t:assertNotNil(DD.byTier, "byTier table exists")
    t:assertNotNil(DD.tierNames, "tierNames table exists")
    t:assert(type(DD.numTiers) == "number", "numTiers is a number")
    t:assert(type(DD.scanned) == "boolean", "scanned is a boolean")
    t:assert(type(DD.entrancesScanned) == "boolean", "entrancesScanned is a boolean")
end)

-------------------------------------------------------------------------------
-- 2. ScanInstances
-------------------------------------------------------------------------------

T:run("DungeonData: ScanInstances populates tiers", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    t:assertTrue(DD.scanned, "scanned flag set after ScanInstances")
    t:assertGreaterThan(DD.numTiers, 0, "numTiers > 0 after scan")
    -- Mock has 2 tiers
    t:assertEqual(2, DD.numTiers, "numTiers = 2 (from mock data)")
end)

T:run("DungeonData: ScanInstances populates tierNames", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    t:assertEqual("Classic", DD.tierNames[1], "Tier 1 = Classic")
    t:assertEqual("The War Within", DD.tierNames[2], "Tier 2 = The War Within")
end)

T:run("DungeonData: ScanInstances populates instances from mock EJ data", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    local instanceCount = 0
    for _ in pairs(DD.instances) do instanceCount = instanceCount + 1 end
    -- Mock: 1 dungeon + 1 raid (Classic) + 2 dungeons + 1 raid (TWW) = 5
    t:assertEqual(5, instanceCount, "5 instances scanned from mock data")
end)

T:run("DungeonData: Ragefire Chasm (226) is a dungeon in tier 1", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    local rfc = DD.instances[226]
    t:assertNotNil(rfc, "RFC (226) exists")
    t:assertEqual("Ragefire Chasm", rfc.name, "RFC name correct")
    t:assertFalse(rfc.isRaid, "RFC is not a raid")
    t:assertEqual(1, rfc.tier, "RFC is in tier 1")
    t:assertEqual("Classic", rfc.tierName, "RFC tier name is Classic")
end)

T:run("DungeonData: Molten Core (741) is a raid", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    local mc = DD.instances[741]
    t:assertNotNil(mc, "Molten Core (741) exists")
    t:assertEqual("Molten Core", mc.name, "MC name correct")
    t:assertTrue(mc.isRaid, "MC is a raid")
    t:assertEqual(1, mc.tier, "MC is in tier 1")
end)

T:run("DungeonData: byTier populated correctly", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    t:assertNotNil(DD.byTier[1], "byTier[1] exists")
    t:assertNotNil(DD.byTier[2], "byTier[2] exists")
    -- Tier 1: RFC(226) + MC(741) = 2
    t:assertEqual(2, #DD.byTier[1], "Tier 1 has 2 instances")
    -- Tier 2: Stonevault(1267) + City of Threads(1268) + Nerub-ar Palace(1273) = 3
    t:assertEqual(3, #DD.byTier[2], "Tier 2 has 3 instances")
end)

T:run("DungeonData: TWW instances populated", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()

    local sv = DD.instances[1267]
    t:assertNotNil(sv, "The Stonevault (1267) exists")
    t:assertEqual("The Stonevault", sv.name, "Stonevault name correct")
    t:assertFalse(sv.isRaid, "Stonevault is not a raid")
    t:assertEqual(2, sv.tier, "Stonevault is in tier 2")

    local np = DD.instances[1273]
    t:assertNotNil(np, "Nerub-ar Palace (1273) exists")
    t:assertTrue(np.isRaid, "Nerub-ar Palace is a raid")
end)

-------------------------------------------------------------------------------
-- 3. ScanEntrances
-------------------------------------------------------------------------------

T:run("DungeonData: ScanEntrances populates zoneMapID/x/y from mock data", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    t:assertTrue(DD.entrancesScanned, "entrancesScanned flag set")
end)

T:run("DungeonData: RFC gets zoneMapID=85 from entrance mock", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    local rfc = DD.instances[226]
    t:assertNotNil(rfc, "RFC exists after entrance scan")
    t:assertEqual(85, rfc.zoneMapID, "RFC zoneMapID = 85 (Orgrimmar)")
    t:assertNotNil(rfc.x, "RFC has x coordinate")
    t:assertNotNil(rfc.y, "RFC has y coordinate")
    -- Mock data: position = { x = 0.39, y = 0.50 }
    t:assertEqual(0.39, rfc.x, "RFC x = 0.39")
    t:assertEqual(0.50, rfc.y, "RFC y = 0.50")
end)

T:run("DungeonData: byZone[85] contains RFC", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    t:assertNotNil(DD.byZone[85], "byZone[85] exists")
    local foundRFC = false
    for _, id in ipairs(DD.byZone[85]) do
        if id == 226 then foundRFC = true end
    end
    t:assertTrue(foundRFC, "byZone[85] contains RFC (226)")
end)

T:run("DungeonData: ScanEntrances populates atlas name", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    local rfc = DD.instances[226]
    t:assertNotNil(rfc, "RFC exists")
    t:assertEqual("DungeonEntrance", rfc.atlasName, "RFC atlasName from mock entrance data")
end)

T:run("DungeonData: ScanEntrances handles Isle of Dorn entrances", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    -- Mock has Isle of Dorn (2248) with Stonevault(1267) and City of Threads(1268)
    t:assertNotNil(DD.byZone[2248], "byZone[2248] exists")
    t:assertGreaterThan(#DD.byZone[2248], 0, "Isle of Dorn has dungeon entrances")

    -- Check coordinates from mock
    local sv = DD.instances[1267]
    if sv then
        t:assertEqual(2248, sv.zoneMapID, "Stonevault zoneMapID = 2248")
        t:assertEqual(0.62, sv.x, "Stonevault x = 0.62")
        t:assertEqual(0.31, sv.y, "Stonevault y = 0.31")
    end
end)

-------------------------------------------------------------------------------
-- 4. MergeStaticFallback
-------------------------------------------------------------------------------

T:run("DungeonData: MergeStaticFallback fills instances missing from API", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    -- Count instances before merge
    local beforeCount = 0
    for _ in pairs(DD.instances) do beforeCount = beforeCount + 1 end

    DD:MergeStaticFallback()

    -- After merge, should have more instances (static data has many more)
    local afterCount = 0
    for _ in pairs(DD.instances) do afterCount = afterCount + 1 end

    t:assertGreaterThan(afterCount, beforeCount,
        "More instances after static merge (was " .. beforeCount .. ", now " .. afterCount .. ")")
end)

T:run("DungeonData: MergeStaticFallback fills coordinates for API-discovered instances", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    -- Only scan instances (no entrance scan), so Molten Core has no coordinates
    DD:ScanInstances()

    local mc = DD.instances[741]
    t:assertNotNil(mc, "Molten Core exists from scan")
    t:assertNil(mc.zoneMapID, "MC has no zoneMapID before merge")

    DD:MergeStaticFallback()

    -- Static data has MC in Burning Steppes (25)
    mc = DD.instances[741]
    t:assertNotNil(mc.zoneMapID, "MC has zoneMapID after merge")
    t:assertEqual(25, mc.zoneMapID, "MC zoneMapID = 25 (Burning Steppes)")
    t:assertNotNil(mc.x, "MC has x after merge")
    t:assertNotNil(mc.y, "MC has y after merge")
end)

T:run("DungeonData: MergeStaticFallback populates byZone", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:MergeStaticFallback()

    -- Burning Steppes (25) has many instances in static data
    t:assertNotNil(DD.byZone[25], "byZone[25] exists after merge")
    t:assertGreaterThan(#DD.byZone[25], 0, "Burning Steppes has instances")
end)

T:run("DungeonData: MergeStaticFallback does not overwrite API coordinates", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:ScanInstances()
    DD:ScanEntrances()

    -- RFC got coordinates from entrance scan
    local rfcBefore = DD.instances[226]
    local xBefore = rfcBefore.x
    local yBefore = rfcBefore.y

    DD:MergeStaticFallback()

    -- Coordinates should not be overwritten by static data
    local rfcAfter = DD.instances[226]
    t:assertEqual(xBefore, rfcAfter.x, "RFC x not overwritten by static fallback")
    t:assertEqual(yBefore, rfcAfter.y, "RFC y not overwritten by static fallback")
end)

-------------------------------------------------------------------------------
-- 5. GetInstance
-------------------------------------------------------------------------------

T:run("DungeonData: GetInstance(226) returns correct data", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local rfc = DD:GetInstance(226)
    t:assertNotNil(rfc, "GetInstance(226) returns data")
    t:assertEqual("Ragefire Chasm", rfc.name, "RFC name correct")
    t:assertFalse(rfc.isRaid, "RFC is not a raid")
end)

T:run("DungeonData: GetInstance(99999) returns nil", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local result = DD:GetInstance(99999)
    t:assertNil(result, "GetInstance(99999) returns nil")
end)

T:run("DungeonData: GetInstance(nil) returns nil", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    local result = DD:GetInstance(nil)
    t:assertNil(result, "GetInstance(nil) returns nil")
end)

-------------------------------------------------------------------------------
-- 6. GetInstancesForZone
-------------------------------------------------------------------------------

T:run("DungeonData: GetInstancesForZone(85) returns entries", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:GetInstancesForZone(85)
    t:assertNotNil(results, "GetInstancesForZone(85) returns table")
    t:assertGreaterThan(#results, 0, "Orgrimmar has at least 1 dungeon entrance")

    -- Should include RFC
    local foundRFC = false
    for _, info in ipairs(results) do
        if info.instanceID == 226 then
            foundRFC = true
            t:assertEqual("Ragefire Chasm", info.name, "RFC name in zone results")
        end
    end
    t:assertTrue(foundRFC, "RFC found in zone 85 results")
end)

T:run("DungeonData: GetInstancesForZone returns empty for unknown zone", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:GetInstancesForZone(99999)
    t:assertNotNil(results, "Returns table, not nil")
    t:assertEqual(0, #results, "Empty for unknown zone")
end)

T:run("DungeonData: GetInstancesForZone(nil) returns empty table", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    local results = DD:GetInstancesForZone(nil)
    t:assertNotNil(results, "Returns table, not nil")
    t:assertEqual(0, #results, "Empty for nil zone")
end)

T:run("DungeonData: GetInstancesForZone results include instanceID", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:GetInstancesForZone(85)
    if #results > 0 then
        t:assertNotNil(results[1].instanceID, "Result includes instanceID field")
    end
end)

-------------------------------------------------------------------------------
-- 7. GetTierName
-------------------------------------------------------------------------------

T:run("DungeonData: GetTierName(1) returns Classic", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    t:assertEqual("Classic", DD:GetTierName(1), "Tier 1 = Classic")
end)

T:run("DungeonData: GetTierName(2) returns The War Within", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    t:assertEqual("The War Within", DD:GetTierName(2), "Tier 2 = The War Within")
end)

T:run("DungeonData: GetTierName(99) returns nil", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    t:assertNil(DD:GetTierName(99), "Unknown tier returns nil")
end)

T:run("DungeonData: GetTierName(nil) returns nil", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    t:assertNil(DD:GetTierName(nil), "nil tier returns nil")
end)

-------------------------------------------------------------------------------
-- 8. GetAllTiers
-------------------------------------------------------------------------------

T:run("DungeonData: GetAllTiers returns at least 2 tiers", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local tiers = DD:GetAllTiers()
    t:assertNotNil(tiers, "GetAllTiers returns table")
    t:assertGreaterThan(#tiers, 1, "At least 2 tiers (got " .. #tiers .. ")")
end)

T:run("DungeonData: GetAllTiers returns tier structure", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local tiers = DD:GetAllTiers()
    for _, tierInfo in ipairs(tiers) do
        t:assertNotNil(tierInfo.tier, "Tier has tier index")
        t:assertNotNil(tierInfo.name, "Tier has name")
        t:assert(type(tierInfo.dungeonCount) == "number", "dungeonCount is number")
        t:assert(type(tierInfo.raidCount) == "number", "raidCount is number")
    end
end)

T:run("DungeonData: GetAllTiers Classic tier has correct counts", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local tiers = DD:GetAllTiers()
    local classic = nil
    for _, tierInfo in ipairs(tiers) do
        if tierInfo.tier == 1 then classic = tierInfo end
    end
    t:assertNotNil(classic, "Classic tier found")
    t:assertEqual("Classic", classic.name, "Classic tier name")
    t:assertEqual(1, classic.dungeonCount, "Classic has 1 dungeon in mock")
    t:assertEqual(1, classic.raidCount, "Classic has 1 raid in mock")
end)

T:run("DungeonData: GetAllTiers TWW tier has correct counts", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local tiers = DD:GetAllTiers()
    local tww = nil
    for _, tierInfo in ipairs(tiers) do
        if tierInfo.tier == 2 then tww = tierInfo end
    end
    t:assertNotNil(tww, "TWW tier found")
    t:assertEqual("The War Within", tww.name, "TWW tier name")
    t:assertEqual(2, tww.dungeonCount, "TWW has 2 dungeons in mock")
    t:assertEqual(1, tww.raidCount, "TWW has 1 raid in mock")
end)

-------------------------------------------------------------------------------
-- 9. Search
-------------------------------------------------------------------------------

T:run("DungeonData: Search('rage') finds Ragefire Chasm", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:Search("rage")
    t:assertNotNil(results, "Search returns table")
    t:assertGreaterThan(#results, 0, "Found results for 'rage'")

    local foundRFC = false
    for _, info in ipairs(results) do
        if info.instanceID == 226 then
            foundRFC = true
            t:assertEqual("Ragefire Chasm", info.name, "RFC name in search results")
        end
    end
    t:assertTrue(foundRFC, "RFC found in search results")
end)

T:run("DungeonData: Search('zzz') returns empty", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:Search("zzz")
    t:assertNotNil(results, "Search returns table")
    t:assertEqual(0, #results, "No results for 'zzz'")
end)

T:run("DungeonData: Search is case-insensitive", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local lower = DD:Search("ragefire")
    local upper = DD:Search("RAGEFIRE")
    local mixed = DD:Search("RageFire")

    t:assertGreaterThan(#lower, 0, "lowercase search finds results")
    t:assertEqual(#lower, #upper, "case-insensitive: lower == upper count")
    t:assertEqual(#lower, #mixed, "case-insensitive: lower == mixed count")
end)

T:run("DungeonData: Search('') returns empty", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:Search("")
    t:assertEqual(0, #results, "Empty query returns empty results")
end)

T:run("DungeonData: Search(nil) returns empty", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:Search(nil)
    t:assertEqual(0, #results, "nil query returns empty results")
end)

T:run("DungeonData: Search results sorted newest expansion first", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    -- Search for something in both tiers: "the" appears in "The Stonevault" (tier 2)
    -- and other instances
    local results = DD:Search("the")
    if #results >= 2 then
        -- Verify descending tier order
        for i = 1, #results - 1 do
            local tierA = results[i].tier or 0
            local tierB = results[i + 1].tier or 0
            if tierA ~= tierB then
                t:assertGreaterThan(tierA, tierB - 1,
                    "Results sorted by tier desc (tier " .. tierA .. " >= " .. tierB .. ")")
            end
        end
    end
end)

T:run("DungeonData: Search results include instanceID", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    local results = DD:Search("rage")
    if #results > 0 then
        t:assertNotNil(results[1].instanceID, "Search results include instanceID")
    end
end)

-------------------------------------------------------------------------------
-- 10. Initialize (integration test)
-------------------------------------------------------------------------------

T:run("DungeonData: Initialize runs all three stages", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:Initialize()

    t:assertTrue(DD.scanned, "scanned flag set")
    t:assertTrue(DD.entrancesScanned, "entrancesScanned flag set")
    t:assertGreaterThan(DD.numTiers, 0, "numTiers > 0")

    -- Should have instances from both API scan and static merge
    local count = 0
    for _ in pairs(DD.instances) do count = count + 1 end
    t:assertGreaterThan(count, 5, "More than 5 instances after full init (got " .. count .. ")")
end)

T:run("DungeonData: Initialize populates byZone for multiple zones", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    DD:Initialize()

    local zoneCount = 0
    for _ in pairs(DD.byZone) do zoneCount = zoneCount + 1 end
    t:assertGreaterThan(zoneCount, 5, "byZone has > 5 zones after init (got " .. zoneCount .. ")")
end)

-------------------------------------------------------------------------------
-- 11. Edge cases
-------------------------------------------------------------------------------

T:run("DungeonData: ScanInstances handles missing EJ API gracefully", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    -- Temporarily remove EJ API
    local origGetNumTiers = EJ_GetNumTiers
    _G.EJ_GetNumTiers = nil

    -- Should not error
    local ok, err = pcall(function() DD:ScanInstances() end)
    t:assertTrue(ok, "ScanInstances does not error without EJ API: " .. tostring(err))
    t:assertFalse(DD.scanned, "scanned stays false without EJ API")

    -- Restore
    _G.EJ_GetNumTiers = origGetNumTiers
end)

T:run("DungeonData: ScanEntrances handles missing C_EncounterJournal gracefully", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    -- Temporarily remove the function
    local orig = C_EncounterJournal.GetDungeonEntrancesForMap
    C_EncounterJournal.GetDungeonEntrancesForMap = nil

    local ok, err = pcall(function() DD:ScanEntrances() end)
    t:assertTrue(ok, "ScanEntrances does not error: " .. tostring(err))
    t:assertFalse(DD.entrancesScanned, "entrancesScanned stays false")

    -- Restore
    C_EncounterJournal.GetDungeonEntrancesForMap = orig
end)

T:run("DungeonData: MergeStaticFallback handles missing static data gracefully", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    local orig = QR.StaticDungeonEntrances
    QR.StaticDungeonEntrances = nil

    local ok, err = pcall(function() DD:MergeStaticFallback() end)
    t:assertTrue(ok, "MergeStaticFallback does not error: " .. tostring(err))

    QR.StaticDungeonEntrances = orig
end)

T:run("DungeonData: No duplicate entries in byZone", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    for zoneMapID, instanceIDs in pairs(DD.byZone) do
        local seen = {}
        for _, id in ipairs(instanceIDs) do
            t:assert(not seen[id],
                "No duplicate instanceID " .. id .. " in byZone[" .. zoneMapID .. "]")
            seen[id] = true
        end
    end
end)

T:run("DungeonData: All instances have a name", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    for id, inst in pairs(DD.instances) do
        t:assertNotNil(inst.name, "Instance " .. id .. " has a name")
        t:assert(type(inst.name) == "string" and #inst.name > 0,
            "Instance " .. id .. " name is non-empty string")
    end
end)

T:run("DungeonData: Static data instances have coordinates", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    -- Pick a few known static-only instances and verify they have coords
    -- The Deadmines (63) in Westfall (52)
    local dm = DD.instances[63]
    if dm then
        t:assertNotNil(dm.x, "Deadmines has x")
        t:assertNotNil(dm.y, "Deadmines has y")
        t:assertNotNil(dm.zoneMapID, "Deadmines has zoneMapID")
    end

    -- The Stockade (238) in Stormwind (84)
    local stock = DD.instances[238]
    if stock then
        t:assertNotNil(stock.x, "Stockade has x")
        t:assertNotNil(stock.y, "Stockade has y")
    end
end)

-------------------------------------------------------------------------------
-- 12. Graph Integration — Dungeon Entrance Nodes
-------------------------------------------------------------------------------

T:run("DungeonData Graph: Ragefire Chasm node exists after BuildGraph", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    -- Force graph rebuild with dungeon data available
    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built")

    local node = graph.nodes["Dungeon: Ragefire Chasm"]
    t:assertNotNil(node, "Dungeon: Ragefire Chasm node exists in graph")
end)

T:run("DungeonData Graph: RFC node has correct mapID and isDungeon", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()

    local node = graph.nodes["Dungeon: Ragefire Chasm"]
    t:assertNotNil(node, "RFC node exists")
    t:assertEqual(85, node.mapID, "RFC node mapID = 85 (Orgrimmar)")
    t:assertTrue(node.isDungeon, "RFC node isDungeon = true")
end)

T:run("DungeonData Graph: RFC node has walking edges to other mapID 85 nodes", function(t)
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    -- Switch to Horde so Orgrimmar (mapID 85) is in the graph as a city node
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()

    -- Orgrimmar (mapID 85) should have a city node and the dungeon node
    -- ConnectSameMapNodes should have connected them
    local rfcNodeName = "Dungeon: Ragefire Chasm"
    local node = graph.nodes[rfcNodeName]
    t:assertNotNil(node, "RFC node exists")

    -- Look for any walking edge from or to the RFC node on mapID 85
    local hasWalkEdge = false
    -- Check outgoing edges from RFC
    if graph.edges[rfcNodeName] then
        for toNode, edge in pairs(graph.edges[rfcNodeName]) do
            local toData = graph.nodes[toNode]
            if toData and toData.mapID == 85 and edge.edgeType == "walk" then
                hasWalkEdge = true
                break
            end
        end
    end
    -- Also check incoming edges (bidirectional walk edges)
    if not hasWalkEdge then
        for fromNode, edges in pairs(graph.edges) do
            if edges[rfcNodeName] then
                local edge = edges[rfcNodeName]
                local fromData = graph.nodes[fromNode]
                if fromData and fromData.mapID == 85 and edge.edgeType == "walk" then
                    hasWalkEdge = true
                    break
                end
            end
        end
    end

    t:assertTrue(hasWalkEdge, "RFC node has walking edge to another node on mapID 85")

    -- Restore faction
    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("DungeonData Graph: dungeon nodes added BEFORE ConnectSameMapNodes", function(t)
    -- Verify that dungeon nodes get connected via walking edges,
    -- which only happens if they are added before ConnectSameMapNodes runs.
    resetDungeonData()
    local DD = QR.DungeonData
    DD:Initialize()

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()

    -- Count dungeon nodes with walking edges
    local dungeonNodesWithEdges = 0
    for nodeName, nodeData in pairs(graph.nodes) do
        if nodeData.isDungeon then
            -- Check if this node has any walk edges
            if graph.edges[nodeName] then
                for _, edge in pairs(graph.edges[nodeName]) do
                    if edge.edgeType == "walk" then
                        dungeonNodesWithEdges = dungeonNodesWithEdges + 1
                        break
                    end
                end
            end
        end
    end

    t:assertGreaterThan(dungeonNodesWithEdges, 0,
        "At least one dungeon node has walking edges (meaning it was connected by ConnectSameMapNodes)")
end)

T:run("DungeonData Graph: no dungeon nodes without DungeonData", function(t)
    -- Temporarily remove DungeonData to verify graceful handling
    local origDD = QR.DungeonData
    QR.DungeonData = nil

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()
    t:assertNotNil(graph, "Graph was built without DungeonData")

    -- Count dungeon nodes — should be zero
    local dungeonCount = 0
    for _, nodeData in pairs(graph.nodes) do
        if nodeData.isDungeon then
            dungeonCount = dungeonCount + 1
        end
    end
    t:assertEqual(0, dungeonCount, "No dungeon nodes without DungeonData")

    -- Restore
    QR.DungeonData = origDD
end)

T:run("DungeonData Graph: skips instances without coordinates", function(t)
    resetDungeonData()
    local DD = QR.DungeonData

    -- Only scan instances (no entrance scan, no static merge) — no coordinates
    DD:ScanInstances()
    -- Mark scanned so AddDungeonNodes will run
    -- instances exist but have no zoneMapID/x/y

    QR.PathCalculator.graphDirty = true
    local graph = QR.PathCalculator:BuildGraph()

    -- Instances without coords should NOT become graph nodes
    local dungeonCount = 0
    for _, nodeData in pairs(graph.nodes) do
        if nodeData.isDungeon then
            dungeonCount = dungeonCount + 1
        end
    end
    t:assertEqual(0, dungeonCount, "No dungeon nodes when instances lack coordinates")
end)
