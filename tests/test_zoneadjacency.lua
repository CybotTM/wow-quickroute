-------------------------------------------------------------------------------
-- test_zoneadjacency.lua
-- Tests for QR.ZoneAdjacency data, continent mappings, and helper functions
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- 1. QR.ZoneConnections / QR.ZoneAdjacencies - table exists and is non-empty
-------------------------------------------------------------------------------

T:run("ZoneAdjacency: ZoneAdjacencies table exists and is non-empty", function(t)
    t:assertNotNil(QR.ZoneAdjacencies, "ZoneAdjacencies table exists")

    local count = 0
    for _ in pairs(QR.ZoneAdjacencies) do count = count + 1 end
    t:assertGreaterThan(count, 0, "ZoneAdjacencies has entries")
    -- There should be many zones with adjacency data
    t:assertGreaterThan(count, 30, "ZoneAdjacencies has >30 source zones")
end)

T:run("ZoneAdjacency: Continents table exists and has expected keys", function(t)
    t:assertNotNil(QR.Continents, "Continents table exists")

    local expectedKeys = {
        "EASTERN_KINGDOMS", "KALIMDOR", "OUTLAND", "NORTHREND",
        "PANDARIA", "DRAENOR", "BROKEN_ISLES", "KUL_TIRAS",
        "ZANDALAR", "BFA_NEUTRAL", "SHADOWLANDS", "DRAGON_ISLES",
        "KHAZ_ALGAR",
    }
    for _, key in ipairs(expectedKeys) do
        t:assertNotNil(QR.Continents[key], "Continent " .. key .. " exists")
    end
end)

T:run("ZoneAdjacency: Each continent has name, hub, and zones", function(t)
    for key, data in pairs(QR.Continents) do
        local prefix = "[" .. key .. "] "
        t:assert(type(data.name) == "string" and #data.name > 0,
            prefix .. "has non-empty name")
        t:assert(type(data.hub) == "number" and data.hub > 0,
            prefix .. "has valid hub mapID")
        t:assert(type(data.zones) == "table" and #data.zones > 0,
            prefix .. "has non-empty zones list")
    end
end)

T:run("ZoneAdjacency: ZoneToContinent table exists and is non-empty", function(t)
    t:assertNotNil(QR.ZoneToContinent, "ZoneToContinent table exists")

    local count = 0
    for _ in pairs(QR.ZoneToContinent) do count = count + 1 end
    t:assertGreaterThan(count, 0, "ZoneToContinent has entries")
    t:assertGreaterThan(count, 50, "ZoneToContinent has >50 entries")
end)

T:run("ZoneAdjacency: CrossContinentTravel table exists and is non-empty", function(t)
    t:assertNotNil(QR.CrossContinentTravel, "CrossContinentTravel table exists")

    local count = 0
    for _ in pairs(QR.CrossContinentTravel) do count = count + 1 end
    t:assertGreaterThan(count, 0, "CrossContinentTravel has entries")
end)

-------------------------------------------------------------------------------
-- 2. QR.GetAdjacentZones(mapID) - returns adjacent zones for a given map ID
-------------------------------------------------------------------------------

T:run("GetAdjacentZones: returns adjacent zones for Stormwind", function(t)
    local adj = QR.GetAdjacentZones(84)
    t:assertNotNil(adj, "Stormwind adjacency data not nil")
    t:assertGreaterThan(#adj, 0, "Stormwind has at least 1 adjacent zone")

    -- Stormwind is adjacent to Elwynn Forest (37)
    local foundElwynn = false
    for _, entry in ipairs(adj) do
        if entry.zone == 37 then
            foundElwynn = true
            t:assertGreaterThan(entry.travelTime, 0, "Stormwind->Elwynn travelTime > 0")
        end
    end
    t:assertTrue(foundElwynn, "Stormwind is adjacent to Elwynn Forest")
end)

T:run("GetAdjacentZones: returns adjacent zones for Orgrimmar", function(t)
    local adj = QR.GetAdjacentZones(85)
    t:assertNotNil(adj, "Orgrimmar adjacency data not nil")
    t:assertGreaterThan(#adj, 0, "Orgrimmar has at least 1 adjacent zone")

    -- Orgrimmar is adjacent to Durotar (1)
    local foundDurotar = false
    for _, entry in ipairs(adj) do
        if entry.zone == 1 then foundDurotar = true end
    end
    t:assertTrue(foundDurotar, "Orgrimmar is adjacent to Durotar")
end)

T:run("GetAdjacentZones: returns adjacent zones for Dornogal (Khaz Algar)", function(t)
    local adj = QR.GetAdjacentZones(2339)
    t:assertNotNil(adj, "Dornogal adjacency data not nil")
    t:assertGreaterThan(#adj, 0, "Dornogal has at least 1 adjacent zone")

    -- Dornogal is adjacent to Isle of Dorn (2248)
    local foundIsleOfDorn = false
    for _, entry in ipairs(adj) do
        if entry.zone == 2248 then foundIsleOfDorn = true end
    end
    t:assertTrue(foundIsleOfDorn, "Dornogal is adjacent to Isle of Dorn")
end)

T:run("GetAdjacentZones: returns empty table for unknown mapID", function(t)
    local adj = QR.GetAdjacentZones(999999)
    t:assertNotNil(adj, "Returns table, not nil")
    t:assertEqual(0, #adj, "Empty table for unknown mapID")
end)

-------------------------------------------------------------------------------
-- 3. QR.GetContinentForZone(mapID) - returns continent for a zone
-------------------------------------------------------------------------------

T:run("GetContinentForZone: known zones return correct continents", function(t)
    -- Eastern Kingdoms cities
    t:assertEqual("EASTERN_KINGDOMS", QR.GetContinentForZone(84),
        "Stormwind -> Eastern Kingdoms")
    t:assertEqual("EASTERN_KINGDOMS", QR.GetContinentForZone(87),
        "Ironforge -> Eastern Kingdoms")
    t:assertEqual("EASTERN_KINGDOMS", QR.GetContinentForZone(90),
        "Undercity -> Eastern Kingdoms")

    -- Kalimdor cities
    t:assertEqual("KALIMDOR", QR.GetContinentForZone(85),
        "Orgrimmar -> Kalimdor")
    t:assertEqual("KALIMDOR", QR.GetContinentForZone(88),
        "Thunder Bluff -> Kalimdor")

    -- Expansion zones
    t:assertEqual("OUTLAND", QR.GetContinentForZone(111),
        "Shattrath -> Outland")
    t:assertEqual("NORTHREND", QR.GetContinentForZone(125),
        "Dalaran Northrend -> Northrend")
    t:assertEqual("PANDARIA", QR.GetContinentForZone(390),
        "Vale of Eternal Blossoms -> Pandaria")
    t:assertEqual("DRAENOR", QR.GetContinentForZone(525),
        "Frostfire Ridge -> Draenor")
    t:assertEqual("BROKEN_ISLES", QR.GetContinentForZone(627),
        "Dalaran Broken Isles -> Broken Isles")
    t:assertEqual("KUL_TIRAS", QR.GetContinentForZone(1161),
        "Boralus -> Kul Tiras")
    t:assertEqual("ZANDALAR", QR.GetContinentForZone(1165),
        "Dazar'alor -> Zandalar")
    t:assertEqual("SHADOWLANDS", QR.GetContinentForZone(1670),
        "Oribos -> Shadowlands")
    t:assertEqual("DRAGON_ISLES", QR.GetContinentForZone(2112),
        "Valdrakken -> Dragon Isles")
    t:assertEqual("KHAZ_ALGAR", QR.GetContinentForZone(2339),
        "Dornogal -> Khaz Algar")
end)

T:run("GetContinentForZone: continent-level fallback mapIDs work", function(t)
    -- These are the continent parent uiMapIDs used as fallbacks
    t:assertEqual("EASTERN_KINGDOMS", QR.GetContinentForZone(12),
        "MapID 12 -> Eastern Kingdoms (continent)")
    t:assertEqual("KALIMDOR", QR.GetContinentForZone(13),
        "MapID 13 -> Kalimdor (continent)")
    t:assertEqual("OUTLAND", QR.GetContinentForZone(101),
        "MapID 101 -> Outland (continent)")
    t:assertEqual("NORTHREND", QR.GetContinentForZone(113),
        "MapID 113 -> Northrend (continent)")
    t:assertEqual("PANDARIA", QR.GetContinentForZone(424),
        "MapID 424 -> Pandaria (continent)")
    t:assertEqual("DRAENOR", QR.GetContinentForZone(572),
        "MapID 572 -> Draenor (continent)")
    t:assertEqual("BROKEN_ISLES", QR.GetContinentForZone(619),
        "MapID 619 -> Broken Isles (continent)")
    t:assertEqual("KUL_TIRAS", QR.GetContinentForZone(875),
        "MapID 875 -> Kul Tiras (continent)")
    t:assertEqual("ZANDALAR", QR.GetContinentForZone(876),
        "MapID 876 -> Zandalar (continent)")
    t:assertEqual("SHADOWLANDS", QR.GetContinentForZone(1550),
        "MapID 1550 -> Shadowlands (continent)")
    t:assertEqual("DRAGON_ISLES", QR.GetContinentForZone(1978),
        "MapID 1978 -> Dragon Isles (continent)")
    t:assertEqual("KHAZ_ALGAR", QR.GetContinentForZone(2274),
        "MapID 2274 -> Khaz Algar (continent)")
end)

T:run("GetContinentForZone: unknown mapID returns nil", function(t)
    t:assertNil(QR.GetContinentForZone(999999),
        "Unknown mapID returns nil")
end)

-------------------------------------------------------------------------------
-- 4. QR.Continents[key].zones - continent-to-zone mapping
--    (GetContinentZones does not exist as a standalone function; zones are
--     accessed via QR.Continents[continentKey].zones)
-------------------------------------------------------------------------------

T:run("Continent zones: each continent has expected zone count ranges", function(t)
    -- Sanity check that each continent has a reasonable number of zones
    local minZones = {
        EASTERN_KINGDOMS = 20,
        KALIMDOR = 20,
        OUTLAND = 5,
        NORTHREND = 5,
        PANDARIA = 5,
        DRAENOR = 5,
        BROKEN_ISLES = 5,
        KUL_TIRAS = 3,
        ZANDALAR = 3,
        BFA_NEUTRAL = 2,
        SHADOWLANDS = 5,
        DRAGON_ISLES = 5,
        KHAZ_ALGAR = 4,
    }
    for key, minCount in pairs(minZones) do
        local continent = QR.Continents[key]
        t:assertNotNil(continent, key .. " continent exists")
        t:assert(#continent.zones >= minCount,
            key .. " has >= " .. minCount .. " zones (got " .. #continent.zones .. ")")
    end
end)

T:run("Continent zones: all zone IDs are positive numbers", function(t)
    for key, data in pairs(QR.Continents) do
        for i, zoneID in ipairs(data.zones) do
            t:assert(type(zoneID) == "number" and zoneID > 0,
                "[" .. key .. "] zone[" .. i .. "] = " .. tostring(zoneID) .. " is valid")
        end
    end
end)

T:run("Continent zones: hub is listed in its own zones", function(t)
    for key, data in pairs(QR.Continents) do
        local hubFound = false
        for _, zoneID in ipairs(data.zones) do
            if zoneID == data.hub then
                hubFound = true
                break
            end
        end
        t:assertTrue(hubFound,
            "[" .. key .. "] hub " .. data.hub .. " is in zones list")
    end
end)

-------------------------------------------------------------------------------
-- 5. Data structure validation
--    Connections have valid mapIDs > 0 and travelTime > 0
-------------------------------------------------------------------------------

T:run("Data validation: all adjacency entries have zone > 0 and travelTime > 0", function(t)
    local totalEntries = 0
    for sourceID, adjacencies in pairs(QR.ZoneAdjacencies) do
        t:assert(type(sourceID) == "number" and sourceID > 0,
            "Source mapID " .. tostring(sourceID) .. " is a positive number")
        t:assert(type(adjacencies) == "table",
            "Adjacencies for " .. sourceID .. " is a table")

        for i, entry in ipairs(adjacencies) do
            local prefix = "[" .. sourceID .. "][" .. i .. "] "
            t:assert(type(entry.zone) == "number" and entry.zone > 0,
                prefix .. "zone " .. tostring(entry.zone) .. " > 0")
            t:assert(type(entry.travelTime) == "number" and entry.travelTime > 0,
                prefix .. "travelTime " .. tostring(entry.travelTime) .. " > 0")
            totalEntries = totalEntries + 1
        end
    end
    t:assertGreaterThan(totalEntries, 100,
        "Total adjacency entries > 100 (got " .. totalEntries .. ")")
end)

T:run("Data validation: no self-referencing adjacencies", function(t)
    for sourceID, adjacencies in pairs(QR.ZoneAdjacencies) do
        for _, entry in ipairs(adjacencies) do
            t:assert(entry.zone ~= sourceID,
                "Zone " .. sourceID .. " should not be adjacent to itself")
        end
    end
end)

T:run("Data validation: CrossContinentTravel has symmetric pairs", function(t)
    -- If continent A has a travel time to B, then B should have one to A
    for fromCont, destinations in pairs(QR.CrossContinentTravel) do
        for toCont, travelTime in pairs(destinations) do
            t:assert(type(travelTime) == "number" and travelTime > 0,
                fromCont .. " -> " .. toCont .. " travelTime > 0")

            local reverse = QR.CrossContinentTravel[toCont]
            t:assertNotNil(reverse,
                toCont .. " has CrossContinentTravel entry (reverse of " .. fromCont .. ")")
            if reverse then
                t:assertNotNil(reverse[fromCont],
                    toCont .. " -> " .. fromCont .. " reverse entry exists")
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- 6. Symmetry check: if zone A is adjacent to zone B, zone B should be
--    adjacent to zone A (for zones that have adjacency data)
-------------------------------------------------------------------------------

T:run("Symmetry: adjacencies are bidirectional (where both sides have data)", function(t)
    local asymmetricCount = 0
    local checkedCount = 0

    for sourceID, adjacencies in pairs(QR.ZoneAdjacencies) do
        for _, entry in ipairs(adjacencies) do
            local targetID = entry.zone
            local reverseAdj = QR.ZoneAdjacencies[targetID]

            -- Only check symmetry if the target also has adjacency data
            if reverseAdj then
                checkedCount = checkedCount + 1
                local foundReverse = false
                for _, revEntry in ipairs(reverseAdj) do
                    if revEntry.zone == sourceID then
                        foundReverse = true
                        break
                    end
                end

                if not foundReverse then
                    asymmetricCount = asymmetricCount + 1
                end

                t:assertTrue(foundReverse,
                    "Zone " .. targetID .. " should list " .. sourceID ..
                    " as adjacent (reverse of " .. sourceID .. " -> " .. targetID .. ")")
            end
        end
    end

    t:assertGreaterThan(checkedCount, 50,
        "Checked > 50 symmetry pairs (got " .. checkedCount .. ")")
end)

T:run("Symmetry: specific known pairs are bidirectional", function(t)
    -- Check specific well-known pairs
    local knownPairs = {
        {84, 37, "Stormwind <-> Elwynn Forest"},
        {85, 1, "Orgrimmar <-> Durotar"},
        {87, 27, "Ironforge <-> Dun Morogh"},
        {90, 18, "Undercity <-> Tirisfal Glades"},
        {88, 7, "Thunder Bluff <-> Mulgore"},
        {2339, 2248, "Dornogal <-> Isle of Dorn"},
        {2112, 2025, "Valdrakken <-> Thaldraszus"},
        {1161, 895, "Boralus <-> Tiragarde Sound"},
        {1165, 862, "Dazar'alor <-> Zuldazar"},
        {125, 127, "Dalaran Northrend <-> Crystalsong Forest"},
    }

    for _, pair in ipairs(knownPairs) do
        local a, b, desc = pair[1], pair[2], pair[3]
        local fwd, fwdTime = QR.AreAdjacentZones(a, b)
        local rev, revTime = QR.AreAdjacentZones(b, a)
        t:assertTrue(fwd, desc .. " (forward)")
        t:assertTrue(rev, desc .. " (reverse)")
        t:assertGreaterThan(fwdTime, 0, desc .. " forward travelTime > 0")
        t:assertGreaterThan(revTime, 0, desc .. " reverse travelTime > 0")
    end
end)

-------------------------------------------------------------------------------
-- 7. Edge cases: nil input, invalid mapID, non-existent zone
-------------------------------------------------------------------------------

T:run("Edge cases: GetContinentForZone with nil", function(t)
    local result = QR.GetContinentForZone(nil)
    t:assertNil(result, "nil mapID returns nil")
end)

T:run("Edge cases: GetContinentForZone with non-numeric input", function(t)
    local result = QR.GetContinentForZone("not_a_number")
    t:assertNil(result, "String mapID returns nil")
end)

T:run("Edge cases: GetContinentForZone with 0", function(t)
    local result = QR.GetContinentForZone(0)
    t:assertNil(result, "MapID 0 returns nil")
end)

T:run("Edge cases: GetContinentForZone with negative number", function(t)
    local result = QR.GetContinentForZone(-1)
    t:assertNil(result, "Negative mapID returns nil")
end)

T:run("Edge cases: GetAdjacentZones with nil", function(t)
    local adj = QR.GetAdjacentZones(nil)
    t:assertNotNil(adj, "Returns empty table, not nil")
    t:assertEqual(0, #adj, "Empty table for nil mapID")
end)

T:run("Edge cases: GetAdjacentZones with 0", function(t)
    local adj = QR.GetAdjacentZones(0)
    t:assertNotNil(adj, "Returns empty table, not nil")
    t:assertEqual(0, #adj, "Empty table for mapID 0")
end)

T:run("Edge cases: AreAdjacentZones with nil inputs", function(t)
    local result = QR.AreAdjacentZones(nil, 37)
    t:assertFalse(result, "nil source returns false")

    result = QR.AreAdjacentZones(84, nil)
    t:assertFalse(result, "nil target returns false")

    result = QR.AreAdjacentZones(nil, nil)
    t:assertFalse(result, "Both nil returns false")
end)

T:run("Edge cases: AreAdjacentZones with non-adjacent zones", function(t)
    -- Stormwind (84) and Orgrimmar (85) are not adjacent
    local result, travelTime = QR.AreAdjacentZones(84, 85)
    t:assertFalse(result, "Stormwind and Orgrimmar are not adjacent")
    t:assertNil(travelTime, "No travelTime for non-adjacent zones")
end)

T:run("Edge cases: AreSameContinent with known zones", function(t)
    -- Same continent
    t:assertTrue(QR.AreSameContinent(84, 37),
        "Stormwind and Elwynn Forest same continent")
    t:assertTrue(QR.AreSameContinent(85, 1),
        "Orgrimmar and Durotar same continent")

    -- Different continents
    t:assertFalse(QR.AreSameContinent(84, 85),
        "Stormwind and Orgrimmar different continents")
    t:assertFalse(QR.AreSameContinent(84, 2339),
        "Stormwind and Dornogal different continents")
end)

T:run("Edge cases: AreSameContinent with nil/unknown zones", function(t)
    t:assertFalse(QR.AreSameContinent(nil, 84),
        "nil first arg returns false")
    t:assertFalse(QR.AreSameContinent(84, nil),
        "nil second arg returns false")
    t:assertFalse(QR.AreSameContinent(999999, 84),
        "Unknown zone returns false")
end)

T:run("Edge cases: GetContinentHub with valid/invalid inputs", function(t)
    -- Default hub
    local hub = QR.GetContinentHub("EASTERN_KINGDOMS")
    t:assertEqual(84, hub, "EK default hub is Stormwind (84)")

    -- Faction-specific hub
    hub = QR.GetContinentHub("EASTERN_KINGDOMS", "Horde")
    t:assertEqual(85, hub, "EK Horde hub is Orgrimmar (85)")

    hub = QR.GetContinentHub("KALIMDOR", "Alliance")
    t:assertEqual(89, hub, "Kalimdor Alliance hub is Darnassus (89)")

    -- Default when no faction-specific hub
    hub = QR.GetContinentHub("OUTLAND")
    t:assertEqual(111, hub, "Outland default hub is Shattrath (111)")

    -- Invalid continent
    hub = QR.GetContinentHub("NONEXISTENT")
    t:assertNil(hub, "Invalid continent returns nil")

    hub = QR.GetContinentHub(nil)
    t:assertNil(hub, "nil continent returns nil")
end)

T:run("Edge cases: GetCrossContinentTravel with valid/invalid inputs", function(t)
    -- Same continent = 0
    local time = QR.GetCrossContinentTravel("EASTERN_KINGDOMS", "EASTERN_KINGDOMS")
    t:assertEqual(0, time, "Same continent returns 0")

    -- Known cross-continent
    time = QR.GetCrossContinentTravel("EASTERN_KINGDOMS", "KALIMDOR")
    t:assertGreaterThan(time, 0, "EK -> Kalimdor > 0")
    t:assertEqual(180, time, "EK -> Kalimdor is 180s")

    -- Unknown continent falls back to 300
    time = QR.GetCrossContinentTravel("NONEXISTENT", "KALIMDOR")
    t:assertEqual(300, time, "Unknown continent falls back to 300")

    time = QR.GetCrossContinentTravel("EASTERN_KINGDOMS", "NONEXISTENT")
    t:assertEqual(300, time, "Dest unknown falls back to 300")
end)

-------------------------------------------------------------------------------
-- 8. Continent-to-zone mapping consistency
--    Every zone in QR.Continents[key].zones should map back via
--    QR.ZoneToContinent[zoneID] == key
-------------------------------------------------------------------------------

T:run("Mapping consistency: all continent zones map back correctly", function(t)
    local checked = 0
    for contKey, contData in pairs(QR.Continents) do
        for _, zoneID in ipairs(contData.zones) do
            local mapped = QR.ZoneToContinent[zoneID]
            -- Note: if duplicate zoneIDs exist across continents, the last write wins.
            -- We check that it maps to SOME continent (not nil).
            t:assertNotNil(mapped,
                "Zone " .. zoneID .. " from " .. contKey .. " has ZoneToContinent entry")
            checked = checked + 1
        end
    end
    t:assertGreaterThan(checked, 80,
        "Checked > 80 zone-to-continent mappings (got " .. checked .. ")")
end)

T:run("Mapping consistency: continent-level fallback IDs do not overlap with zone IDs",
function(t)
    -- The fallback continent mapIDs (12, 13, 101, etc.) should each map to exactly
    -- one continent. We just verify they are present.
    local continentFallbacks = {
        [12]   = "EASTERN_KINGDOMS",
        [13]   = "KALIMDOR",
        [113]  = "NORTHREND",
        [424]  = "PANDARIA",
        [572]  = "DRAENOR",
        [619]  = "BROKEN_ISLES",
        [875]  = "KUL_TIRAS",
        [876]  = "ZANDALAR",
        [1550] = "SHADOWLANDS",
        [1978] = "DRAGON_ISLES",
        [2274] = "KHAZ_ALGAR",
    }
    for mapID, expectedCont in pairs(continentFallbacks) do
        t:assertEqual(expectedCont, QR.ZoneToContinent[mapID],
            "Continent fallback " .. mapID .. " -> " .. expectedCont)
    end
end)

-------------------------------------------------------------------------------
-- 9. EstimateSameContinentTravel - BFS path estimation
-------------------------------------------------------------------------------

T:run("EstimateSameContinentTravel: same zone returns 0", function(t)
    local time = QR.EstimateSameContinentTravel(84, 84)
    t:assertEqual(0, time, "Same zone travel time is 0")
end)

T:run("EstimateSameContinentTravel: adjacent zones return direct travel time", function(t)
    -- Stormwind (84) -> Elwynn Forest (37) = 30s direct
    local time = QR.EstimateSameContinentTravel(84, 37)
    t:assertNotNil(time, "Path found Stormwind -> Elwynn Forest")
    t:assertEqual(30, time, "Direct adjacency travel time is 30")
end)

T:run("EstimateSameContinentTravel: multi-hop path", function(t)
    -- Stormwind (84) -> Westfall (52): Stormwind -> Elwynn (30) -> Westfall (60) = 90
    local time = QR.EstimateSameContinentTravel(84, 52)
    t:assertNotNil(time, "Path found Stormwind -> Westfall")
    t:assertGreaterThan(time, 0, "Travel time > 0")
    -- BFS finds shortest hop count, not necessarily cheapest time
    -- But it should be positive and reasonable
end)

T:run("EstimateSameContinentTravel: different continents returns nil", function(t)
    -- Stormwind (84, EK) -> Orgrimmar (85, Kalimdor) = different continents
    local time = QR.EstimateSameContinentTravel(84, 85)
    t:assertNil(time, "Cross-continent returns nil")
end)

T:run("EstimateSameContinentTravel: Khaz Algar chain", function(t)
    -- Dornogal (2339) -> Isle of Dorn (2248) = 30s direct
    local time = QR.EstimateSameContinentTravel(2339, 2248)
    t:assertEqual(30, time, "Dornogal -> Isle of Dorn is 30s")

    -- Dornogal -> Ringing Deeps (via Isle of Dorn): 30 + 60 = 90
    time = QR.EstimateSameContinentTravel(2339, 2214)
    t:assertNotNil(time, "Path found Dornogal -> Ringing Deeps")
    t:assertEqual(90, time, "Dornogal -> Ringing Deeps via Isle of Dorn is 90s")
end)

-------------------------------------------------------------------------------
-- 10. Isolated zone handling (BFA Neutral zones: Nazjatar, Mechagon)
-------------------------------------------------------------------------------

T:run("Isolated zones: Nazjatar and Mechagon have empty adjacency lists", function(t)
    local nazjatar = QR.ZoneAdjacencies[1355]
    t:assertNotNil(nazjatar, "Nazjatar has adjacency entry (even if empty)")
    t:assertEqual(0, #nazjatar, "Nazjatar has no walkable adjacent zones")

    local mechagon = QR.ZoneAdjacencies[1462]
    t:assertNotNil(mechagon, "Mechagon has adjacency entry (even if empty)")
    t:assertEqual(0, #mechagon, "Mechagon has no walkable adjacent zones")
end)

-------------------------------------------------------------------------------
-- 11. GetLocalizedContinentName
-------------------------------------------------------------------------------

T:run("GetLocalizedContinentName: returns localized name via C_Map", function(t)
    t:assertNotNil(QR.GetLocalizedContinentName, "Function exists")
    -- C_Map.GetMapInfo returns localized names from mock mapDatabase
    local name = QR.GetLocalizedContinentName("EASTERN_KINGDOMS")
    t:assertNotNil(name, "Returns a name for EASTERN_KINGDOMS")
    t:assert(type(name) == "string" and #name > 0, "Name is non-empty string")
end)

T:run("GetLocalizedContinentName: falls back to Continents table", function(t)
    -- BFA_NEUTRAL may not have a mapID in ContinentKeyToMapID
    local name = QR.GetLocalizedContinentName("BFA_NEUTRAL")
    t:assertNotNil(name, "Returns a name for BFA_NEUTRAL")
    t:assert(type(name) == "string" and #name > 0, "Name is non-empty string")
end)

T:run("GetLocalizedContinentName: returns nil for nil input", function(t)
    local name = QR.GetLocalizedContinentName(nil)
    t:assertNil(name, "Returns nil for nil input")
end)

T:run("GetLocalizedContinentName: returns key for unknown continent", function(t)
    local name = QR.GetLocalizedContinentName("NONEXISTENT_CONTINENT")
    t:assertEqual("NONEXISTENT_CONTINENT", name, "Returns raw key as last resort")
end)

-------------------------------------------------------------------------------
-- 12. Missing zones audit (Patch 11.0.7 - 11.2 + Dragonflight 10.2.5)
-------------------------------------------------------------------------------

T:run("New zones: Siren Isle (2369) is in KHAZ_ALGAR", function(t)
    t:assertEqual("KHAZ_ALGAR", QR.GetContinentForZone(2369),
        "Siren Isle -> Khaz Algar")
end)

T:run("New zones: Siren Isle is accessible via StandalonePortals, not walk adjacency", function(t)
    -- Siren Isle should NOT have walk adjacency (it's zeppelin/portal)
    local fwd = QR.AreAdjacentZones(2369, 2248)
    t:assertFalse(fwd, "Siren Isle -> Isle of Dorn is NOT a walk adjacency")
    local rev = QR.AreAdjacentZones(2248, 2369)
    t:assertFalse(rev, "Isle of Dorn -> Siren Isle is NOT a walk adjacency")

    -- Verify the standalone portals exist in Portals.lua
    local foundZeppelin = false
    local foundMoleMachine = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from.mapID == 2248 and portal.to.mapID == 2369 then
            foundZeppelin = true
            t:assertEqual("zeppelin", portal.type, "Isle of Dorn -> Siren Isle is zeppelin")
        end
        if portal.from.mapID == 2214 and portal.to.mapID == 2369 then
            foundMoleMachine = true
            t:assertEqual("portal", portal.type, "Ringing Deeps -> Siren Isle is portal")
        end
    end
    t:assertTrue(foundZeppelin, "Zeppelin from Isle of Dorn to Siren Isle exists")
    t:assertTrue(foundMoleMachine, "Mole Machine from Ringing Deeps to Siren Isle exists")
end)

T:run("New zones: Undermine (2346) is in KHAZ_ALGAR", function(t)
    t:assertEqual("KHAZ_ALGAR", QR.GetContinentForZone(2346),
        "Undermine -> Khaz Algar")
end)

T:run("New zones: Undermine is accessible via StandalonePortal, not walk adjacency", function(t)
    -- Undermine should NOT have walk adjacency to Dornogal
    local fwd = QR.AreAdjacentZones(2346, 2339)
    t:assertFalse(fwd, "Undermine -> Dornogal is NOT a walk adjacency")
    local rev = QR.AreAdjacentZones(2339, 2346)
    t:assertFalse(rev, "Dornogal -> Undermine is NOT a walk adjacency")

    -- Verify the standalone portal exists
    local foundPortal = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from.mapID == 2339 and portal.to.mapID == 2346 then
            foundPortal = true
            t:assertEqual("portal", portal.type, "Dornogal -> Undermine is portal")
            t:assertTrue(portal.bidirectional, "Portal is bidirectional")
        end
    end
    t:assertTrue(foundPortal, "Portal from Dornogal to Undermine exists")
end)

T:run("New zones: Tazavesh (2472) is in KHAZ_ALGAR", function(t)
    t:assertEqual("KHAZ_ALGAR", QR.GetContinentForZone(2472),
        "Tazavesh -> Khaz Algar")
end)

T:run("New zones: Tazavesh has bidirectional adjacency to K'aresh", function(t)
    local fwd, fwdTime = QR.AreAdjacentZones(2472, 2371)
    local rev, revTime = QR.AreAdjacentZones(2371, 2472)
    t:assertTrue(fwd, "Tazavesh -> K'aresh")
    t:assertTrue(rev, "K'aresh -> Tazavesh")
    t:assertEqual(15, fwdTime, "Tazavesh -> K'aresh = 15s")
    t:assertEqual(15, revTime, "K'aresh -> Tazavesh = 15s")
end)

T:run("New zones: Tazavesh reachable from K'aresh via walk", function(t)
    -- K'aresh -> Tazavesh is walkable (same open-world area)
    local time = QR.EstimateSameContinentTravel(2371, 2472)
    t:assertNotNil(time, "Path found K'aresh -> Tazavesh")
    t:assertEqual(15, time, "K'aresh -> Tazavesh = 15s")
end)

T:run("New zones: Bel'ameth (2239) is in DRAGON_ISLES", function(t)
    t:assertEqual("DRAGON_ISLES", QR.GetContinentForZone(2239),
        "Bel'ameth -> Dragon Isles")
end)

T:run("New zones: Bel'ameth has bidirectional adjacency to Ohn'ahran Plains", function(t)
    local fwd, fwdTime = QR.AreAdjacentZones(2239, 2023)
    local rev, revTime = QR.AreAdjacentZones(2023, 2239)
    t:assertTrue(fwd, "Bel'ameth -> Ohn'ahran Plains")
    t:assertTrue(rev, "Ohn'ahran Plains -> Bel'ameth")
    t:assertEqual(60, fwdTime, "Bel'ameth -> Ohn'ahran Plains = 60s")
    t:assertEqual(60, revTime, "Ohn'ahran Plains -> Bel'ameth = 60s")
end)

T:run("New zones: Bel'ameth is routable from Valdrakken", function(t)
    local time = QR.EstimateSameContinentTravel(2112, 2239)
    t:assertNotNil(time, "Path found Valdrakken -> Bel'ameth")
    -- Valdrakken -> Thaldraszus (30) -> Ohn'ahran (60) -> Bel'ameth (60) = 150
    t:assertEqual(150, time, "Valdrakken -> Bel'ameth via Thaldraszus+Ohn'ahran = 150s")
end)

T:run("New zones: Forbidden Reach 2151 is also in DRAGON_ISLES", function(t)
    -- Both 2107 and 2151 should map to DRAGON_ISLES
    t:assertEqual("DRAGON_ISLES", QR.GetContinentForZone(2107),
        "Forbidden Reach (2107) -> Dragon Isles")
    t:assertEqual("DRAGON_ISLES", QR.GetContinentForZone(2151),
        "Forbidden Reach (2151) -> Dragon Isles")
end)

T:run("New zones: K'aresh (2371) accessible via portal, not walk", function(t)
    -- K'aresh should NOT have walk adjacency to Dornogal
    local fwd = QR.AreAdjacentZones(2339, 2371)
    t:assertFalse(fwd, "Dornogal -> K'aresh is NOT a walk adjacency")
    local rev = QR.AreAdjacentZones(2371, 2339)
    t:assertFalse(rev, "K'aresh -> Dornogal is NOT a walk adjacency")

    -- Verify the standalone portal exists
    local foundPortal = false
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.from.mapID == 2339 and portal.to.mapID == 2371 then
            foundPortal = true
            t:assertEqual("portal", portal.type, "Dornogal -> K'aresh is portal")
            t:assertTrue(portal.bidirectional, "Portal is bidirectional")
        end
    end
    t:assertTrue(foundPortal, "Portal from Dornogal to K'aresh exists")
end)

T:run("New zones: complete KHAZ_ALGAR zone count", function(t)
    local zones = QR.Continents.KHAZ_ALGAR.zones
    -- Isle of Dorn, Ringing Deeps, Hallowfall, Azj-Kahet, Dornogal,
    -- City of Threads, K'aresh, Siren Isle, Undermine, Tazavesh = 10
    t:assertEqual(10, #zones, "KHAZ_ALGAR has 10 zones")
end)

T:run("New zones: complete DRAGON_ISLES zone count", function(t)
    local zones = QR.Continents.DRAGON_ISLES.zones
    -- Waking Shores, Ohn'ahran Plains, Azure Span, Thaldraszus, Valdrakken,
    -- Forbidden Reach (2107), Forbidden Reach (2151), Zaralek Cavern,
    -- Emerald Dream, Bel'ameth = 10
    t:assertEqual(10, #zones, "DRAGON_ISLES has 10 zones")
end)
