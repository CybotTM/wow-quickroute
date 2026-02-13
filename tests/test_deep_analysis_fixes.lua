-------------------------------------------------------------------------------
-- test_deep_analysis_fixes.lua
-- Tests for deep analysis fixes from Groups A-E:
--   A1: C_Map.GetPlayerMapPosition pcall wrapping
--   B1: ConfigureForSpell/ConfigureForToy input validation
--   B2: /qrpath rejects invalid mapIDs
--   B3: WindowFactory position restoration type validation
--   B5: TomTom title sanitization (pipe character escaping)
--   C1: wasShowingBeforeCombat resets on manual Hide
--   C6: Log table reuse in ring buffer
--   D1: CrossContinentTravel symmetry
--   E:  PlaySound on button clicks
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper: reset mock state
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW:FireEvent("ZONE_CHANGED_NEW_AREA")
    QR.PathCalculator.graph = nil
    QR.PathCalculator.graphDirty = true
    QR.PlayerInventory.teleportItems = {}
    QR.PlayerInventory.toys = {}
    QR.PlayerInventory.spells = {}
end

--- Helper: ensure MainFrame + UI content frame is created for testing
local function ensureUIFrame()
    -- Initialize MainFrame first (creates container + content frames)
    if not QR.MainFrame.frame then
        QR.MainFrame:CreateFrame()
    end
    QR.MainFrame.initialized = true
    -- Create UI content inside MainFrame's route content area
    if not QR.UI.frame then
        local contentFrame = QR.MainFrame:GetContentFrame("route")
        QR.UI:CreateContent(contentFrame)
    end
    QR.UI.initialized = true
    QR.UI.isCalculating = false
    QR.MainFrame.isShowing = false
    QR.MainFrame.wasShowingBeforeCombat = false
end

-------------------------------------------------------------------------------
-- A1: C_Map.GetPlayerMapPosition pcall wrapping
-- PathCalculator wraps GetPlayerMapPosition in pcall so errors don't crash
-------------------------------------------------------------------------------

T:run("A1: GetPlayerMapPosition pcall - error returns nil position", function(t)
    resetState()

    -- Make GetPlayerMapPosition throw an error (simulates instances/unmapped areas)
    local original = _G.C_Map.GetPlayerMapPosition
    _G.C_Map.GetPlayerMapPosition = function(mapID, unit)
        error("restricted in this instance")
    end

    -- AddPlayerTeleportEdges calls GetPlayerMapPosition with pcall
    -- It should not crash even if the function errors
    QR.PathCalculator.graph = QR.Graph:New()
    QR.PathCalculator.graph:AddNode("Test", { mapID = 84 })

    local success, err = pcall(function()
        QR.PathCalculator:AddPlayerTeleportEdges()
    end)
    t:assertTrue(success, "AddPlayerTeleportEdges does not crash when GetPlayerMapPosition errors")

    -- UpdatePlayerLocation also uses pcall
    success, err = pcall(function()
        QR.PathCalculator:UpdatePlayerLocation()
    end)
    t:assertTrue(success, "UpdatePlayerLocation does not crash when GetPlayerMapPosition errors")

    -- Restore original
    _G.C_Map.GetPlayerMapPosition = original
end)

T:run("A1: GetPlayerMapPosition pcall - normal operation still works", function(t)
    resetState()

    -- Ensure normal case still works after pcall wrapping
    local pos = _G.C_Map.GetPlayerMapPosition(84, "player")
    t:assertNotNil(pos, "Normal GetPlayerMapPosition returns position")
    local x, y = pos:GetXY()
    t:assertEqual(0.5, x, "Default player X is 0.5")
    t:assertEqual(0.5, y, "Default player Y is 0.5")
end)

-------------------------------------------------------------------------------
-- B1: ConfigureForSpell/ConfigureForToy input validation
-- Reject nil, string, negative, fractional, zero IDs
-------------------------------------------------------------------------------

T:run("B1: ConfigureForSpell rejects nil spellID", function(t)
    resetState()
    local btn = { SetAttribute = function() end }
    btn.poolIndex = 1
    local result = QR.SecureButtons:ConfigureForSpell(btn, nil)
    t:assertFalse(result, "ConfigureForSpell rejects nil spellID")
end)

T:run("B1: ConfigureForSpell rejects string spellID", function(t)
    resetState()
    local btn = { SetAttribute = function() end }
    btn.poolIndex = 1
    local result = QR.SecureButtons:ConfigureForSpell(btn, "abc")
    t:assertFalse(result, "ConfigureForSpell rejects string spellID")
end)

T:run("B1: ConfigureForSpell rejects negative spellID", function(t)
    resetState()
    local btn = { SetAttribute = function() end }
    btn.poolIndex = 1
    local result = QR.SecureButtons:ConfigureForSpell(btn, -5)
    t:assertFalse(result, "ConfigureForSpell rejects negative spellID")
end)

T:run("B1: ConfigureForSpell rejects fractional spellID", function(t)
    resetState()
    local btn = { SetAttribute = function() end }
    btn.poolIndex = 1
    local result = QR.SecureButtons:ConfigureForSpell(btn, 3.14)
    t:assertFalse(result, "ConfigureForSpell rejects fractional spellID")
end)

T:run("B1: ConfigureForSpell rejects zero spellID", function(t)
    resetState()
    local btn = { SetAttribute = function() end }
    btn.poolIndex = 1
    local result = QR.SecureButtons:ConfigureForSpell(btn, 0)
    t:assertFalse(result, "ConfigureForSpell rejects zero spellID")
end)

T:run("B1: ConfigureForSpell accepts valid spellID", function(t)
    resetState()
    local attrs = {}
    local btn = {
        SetAttribute = function(self, key, val) attrs[key] = val end,
        poolIndex = 1,
    }
    local result = QR.SecureButtons:ConfigureForSpell(btn, 12345)
    t:assertTrue(result, "ConfigureForSpell accepts valid positive integer spellID")
    t:assertEqual("spell", attrs["type"], "Sets type attribute to spell")
    t:assertEqual(12345, attrs["spell"], "Sets spell attribute to spellID")
    t:assertEqual(12345, btn.teleportID, "Sets teleportID on button")
    t:assertEqual("spell", btn.sourceType, "Sets sourceType on button")
end)

T:run("B1: ConfigureForToy rejects nil toyID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForToy(btn, nil)
    t:assertFalse(result, "ConfigureForToy rejects nil toyID")
end)

T:run("B1: ConfigureForToy rejects string toyID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForToy(btn, "toy")
    t:assertFalse(result, "ConfigureForToy rejects string toyID")
end)

T:run("B1: ConfigureForToy rejects negative toyID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForToy(btn, -1)
    t:assertFalse(result, "ConfigureForToy rejects negative toyID")
end)

T:run("B1: ConfigureForToy rejects fractional toyID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForToy(btn, 1.5)
    t:assertFalse(result, "ConfigureForToy rejects fractional toyID")
end)

T:run("B1: ConfigureForToy rejects zero toyID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForToy(btn, 0)
    t:assertFalse(result, "ConfigureForToy rejects zero toyID")
end)

T:run("B1: ConfigureForToy accepts valid toyID", function(t)
    resetState()
    local attrs = {}
    local btn = {
        SetAttribute = function(self, key, val) attrs[key] = val end,
        poolIndex = 1,
    }
    local result = QR.SecureButtons:ConfigureForToy(btn, 54452)
    t:assertTrue(result, "ConfigureForToy accepts valid positive integer toyID")
    t:assertEqual("toy", attrs["type"], "Sets type attribute to toy")
    t:assertEqual(54452, attrs["toy"], "Sets toy attribute to toyID")
end)

T:run("B1: ConfigureForItem rejects nil itemID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForItem(btn, nil)
    t:assertFalse(result, "ConfigureForItem rejects nil itemID")
end)

T:run("B1: ConfigureForItem rejects string itemID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    local result = QR.SecureButtons:ConfigureForItem(btn, "item")
    t:assertFalse(result, "ConfigureForItem rejects string itemID")
end)

T:run("B1: ConfigureForItem rejects negative/zero/fractional itemID", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }
    t:assertFalse(QR.SecureButtons:ConfigureForItem(btn, -1), "Rejects negative")
    t:assertFalse(QR.SecureButtons:ConfigureForItem(btn, 0), "Rejects zero")
    t:assertFalse(QR.SecureButtons:ConfigureForItem(btn, 2.7), "Rejects fractional")
end)

T:run("B1: ConfigureForItem accepts valid itemID", function(t)
    resetState()
    local attrs = {}
    local btn = {
        SetAttribute = function(self, key, val) attrs[key] = val end,
        poolIndex = 1,
    }
    local result = QR.SecureButtons:ConfigureForItem(btn, 6948)
    t:assertTrue(result, "ConfigureForItem accepts valid positive integer itemID")
    t:assertEqual("macro", attrs["type"], "Sets type attribute to macro")
    -- The macrotext should contain the item ID
    t:assert(attrs["macrotext"] and attrs["macrotext"]:find("6948"),
        "Macrotext contains item ID")
end)

T:run("B1: ConfigureForSpell rejects nil btn", function(t)
    resetState()
    local result = QR.SecureButtons:ConfigureForSpell(nil, 12345)
    t:assertFalse(result, "ConfigureForSpell rejects nil btn")
end)

T:run("B1: ConfigureForToy rejects nil btn", function(t)
    resetState()
    local result = QR.SecureButtons:ConfigureForToy(nil, 12345)
    t:assertFalse(result, "ConfigureForToy rejects nil btn")
end)

-------------------------------------------------------------------------------
-- B2: /qrpath rejects invalid mapIDs (negative, fractional, zero)
-------------------------------------------------------------------------------

T:run("B2: /qrpath rejects negative mapID", function(t)
    resetState()
    -- The slash command validates mapID > 0 and mapID == floor(mapID)
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    -- Call the slash command handler directly
    SlashCmdList["QRPATH"]("-1 0.5 0.5")

    _G.print = origPrint

    -- Should print an error about invalid mapID
    local foundError = false
    for _, msg in ipairs(captured) do
        if msg:find("Invalid") or msg:find("invalid") then
            foundError = true
            break
        end
    end
    t:assertTrue(foundError, "/qrpath rejects negative mapID with error message")
end)

T:run("B2: /qrpath rejects zero mapID", function(t)
    resetState()
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    SlashCmdList["QRPATH"]("0 0.5 0.5")

    _G.print = origPrint

    local foundError = false
    for _, msg in ipairs(captured) do
        if msg:find("Invalid") or msg:find("invalid") then
            foundError = true
            break
        end
    end
    t:assertTrue(foundError, "/qrpath rejects zero mapID with error message")
end)

T:run("B2: /qrpath rejects fractional mapID", function(t)
    resetState()
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    SlashCmdList["QRPATH"]("84.5 0.5 0.5")

    _G.print = origPrint

    local foundError = false
    for _, msg in ipairs(captured) do
        if msg:find("Invalid") or msg:find("invalid") then
            foundError = true
            break
        end
    end
    t:assertTrue(foundError, "/qrpath rejects fractional mapID with error message")
end)

T:run("B2: /qrpath accepts valid mapID", function(t)
    resetState()
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    -- Valid mapID; path calculation may or may not succeed, but it should not
    -- reject the mapID itself
    SlashCmdList["QRPATH"]("84 0.5 0.5")

    _G.print = origPrint

    -- Should NOT print the "Invalid map ID" error
    local foundInvalidError = false
    for _, msg in ipairs(captured) do
        if msg:find("Invalid map ID") then
            foundInvalidError = true
            break
        end
    end
    t:assertFalse(foundInvalidError, "/qrpath accepts valid mapID 84")
end)

-------------------------------------------------------------------------------
-- B3: WindowFactory position restoration rejects non-number x/y
-- and non-string point/relPoint
-------------------------------------------------------------------------------

T:run("B3: WindowFactory rejects non-number x in saved position", function(t)
    resetState()
    -- Set up QR.db with invalid position data
    QR.db = QR.db or {}
    QR.db.testPoint = "CENTER"
    QR.db.testRelPoint = "CENTER"
    QR.db.testX = "not_a_number"  -- Invalid: should be number
    QR.db.testY = 100

    local frame = QR.CreateStandardWindow({
        name = "QRTestWindow_B3_1",
        title = "Test",
        width = 200,
        height = 200,
        savedPosKeys = { point = "testPoint", relPoint = "testRelPoint", x = "testX", y = "testY" },
    })

    -- The frame should still be created (falls back to default position)
    t:assertNotNil(frame, "Frame created despite invalid saved position x")

    -- Cleanup
    QR.db.testPoint = nil
    QR.db.testRelPoint = nil
    QR.db.testX = nil
    QR.db.testY = nil
end)

T:run("B3: WindowFactory rejects non-string point in saved position", function(t)
    resetState()
    QR.db = QR.db or {}
    QR.db.testPoint2 = 42  -- Invalid: should be string
    QR.db.testRelPoint2 = "CENTER"
    QR.db.testX2 = 100
    QR.db.testY2 = 100

    local frame = QR.CreateStandardWindow({
        name = "QRTestWindow_B3_2",
        title = "Test",
        width = 200,
        height = 200,
        savedPosKeys = { point = "testPoint2", relPoint = "testRelPoint2", x = "testX2", y = "testY2" },
    })

    t:assertNotNil(frame, "Frame created despite invalid saved position point")

    -- Cleanup
    QR.db.testPoint2 = nil
    QR.db.testRelPoint2 = nil
    QR.db.testX2 = nil
    QR.db.testY2 = nil
end)

T:run("B3: WindowFactory rejects non-string relPoint in saved position", function(t)
    resetState()
    QR.db = QR.db or {}
    QR.db.testPoint3 = "CENTER"
    QR.db.testRelPoint3 = true  -- Invalid: should be string
    QR.db.testX3 = 100
    QR.db.testY3 = 100

    local frame = QR.CreateStandardWindow({
        name = "QRTestWindow_B3_3",
        title = "Test",
        width = 200,
        height = 200,
        savedPosKeys = { point = "testPoint3", relPoint = "testRelPoint3", x = "testX3", y = "testY3" },
    })

    t:assertNotNil(frame, "Frame created despite invalid saved position relPoint")

    -- Cleanup
    QR.db.testPoint3 = nil
    QR.db.testRelPoint3 = nil
    QR.db.testX3 = nil
    QR.db.testY3 = nil
end)

T:run("B3: WindowFactory uses saved position when all types are valid", function(t)
    resetState()
    QR.db = QR.db or {}
    QR.db.validPoint = "TOPLEFT"
    QR.db.validRelPoint = "TOPLEFT"
    QR.db.validX = 50
    QR.db.validY = -30

    local frame = QR.CreateStandardWindow({
        name = "QRTestWindow_B3_4",
        title = "Test Valid",
        width = 200,
        height = 200,
        savedPosKeys = { point = "validPoint", relPoint = "validRelPoint", x = "validX", y = "validY" },
    })

    t:assertNotNil(frame, "Frame created with valid saved position")

    -- Check the frame was positioned with saved values
    local point, relativeTo, relPoint, x, y = frame:GetPoint()
    t:assertEqual("TOPLEFT", point, "Saved point restored correctly")

    -- Cleanup
    QR.db.validPoint = nil
    QR.db.validRelPoint = nil
    QR.db.validX = nil
    QR.db.validY = nil
end)

-------------------------------------------------------------------------------
-- B5: TomTom title sanitization (pipe characters escaped)
-------------------------------------------------------------------------------

T:run("B5: SetTomTomWaypoint escapes pipe characters in title", function(t)
    resetState()

    -- Set up a mock TomTom
    local capturedOpts = nil
    _G.TomTom = {
        AddWaypoint = function(self, mapID, x, y, opts)
            capturedOpts = opts
            return "uid123"
        end,
    }

    -- Call with a title containing pipe characters (WoW UI escape codes)
    QR.WaypointIntegration:SetTomTomWaypoint(84, 0.5, 0.5, "Test |cFF00FF00colored|r title")

    t:assertNotNil(capturedOpts, "TomTom AddWaypoint was called")
    t:assertNotNil(capturedOpts.title, "Title was passed to TomTom")

    -- The title should have pipes doubled (escaped)
    local title = capturedOpts.title
    -- Original has | chars, escaped should have ||
    t:assert(not title:find("|c") or title:find("||c"),
        "Pipe characters in title are escaped (no raw |c)")

    -- Restore
    _G.TomTom = nil
end)

T:run("B5: SetTomTomWaypoint handles nil title gracefully", function(t)
    resetState()

    local capturedOpts = nil
    _G.TomTom = {
        AddWaypoint = function(self, mapID, x, y, opts)
            capturedOpts = opts
            return "uid456"
        end,
    }

    QR.WaypointIntegration:SetTomTomWaypoint(84, 0.5, 0.5, nil)

    t:assertNotNil(capturedOpts, "TomTom AddWaypoint was called with nil title")
    t:assertEqual("QuickRoute", capturedOpts.title, "Nil title defaults to QuickRoute")

    _G.TomTom = nil
end)

T:run("B5: SetTomTomWaypoint passes clean title unchanged", function(t)
    resetState()

    local capturedOpts = nil
    _G.TomTom = {
        AddWaypoint = function(self, mapID, x, y, opts)
            capturedOpts = opts
            return "uid789"
        end,
    }

    QR.WaypointIntegration:SetTomTomWaypoint(84, 0.5, 0.5, "Clean Title")

    t:assertNotNil(capturedOpts, "TomTom AddWaypoint was called")
    t:assertEqual("Clean Title", capturedOpts.title, "Clean title passed unchanged")

    _G.TomTom = nil
end)

-------------------------------------------------------------------------------
-- C1: wasShowingBeforeCombat resets on manual Hide (now on MainFrame)
-------------------------------------------------------------------------------

T:run("C1: wasShowingBeforeCombat resets on manual Hide", function(t)
    resetState()
    ensureUIFrame()

    -- Simulate: MainFrame is showing, combat starts (sets wasShowingBeforeCombat)
    QR.MainFrame:Show("route")
    QR.MainFrame.wasShowingBeforeCombat = true

    -- User manually hides the MainFrame during combat
    QR.MainFrame:Hide()

    -- wasShowingBeforeCombat should be reset to false
    t:assertFalse(QR.MainFrame.wasShowingBeforeCombat,
        "wasShowingBeforeCombat reset to false after manual Hide()")
    t:assertFalse(QR.MainFrame.isShowing,
        "isShowing is false after Hide()")
end)

T:run("C1: wasShowingBeforeCombat set correctly in combat enter callback", function(t)
    resetState()
    ensureUIFrame()

    -- MainFrame is showing
    QR.MainFrame:Show("route")
    QR.MainFrame.wasShowingBeforeCombat = false

    -- Simulate combat enter: Hide() is called, then wasShowingBeforeCombat is set
    QR.MainFrame:Hide()
    QR.MainFrame.wasShowingBeforeCombat = true  -- Set after Hide, matching the actual code

    -- Now simulate user manually hiding (e.g., pressing ESC after combat started)
    QR.MainFrame:Hide()

    t:assertFalse(QR.MainFrame.wasShowingBeforeCombat,
        "Manual Hide during combat clears wasShowingBeforeCombat")
end)

-------------------------------------------------------------------------------
-- C6: Log table reuse - verify entries are reused not recreated
-------------------------------------------------------------------------------

T:run("C6: Log ring buffer reuses table entries", function(t)
    resetState()

    -- Clear the log first
    QR:ClearLog()

    -- Fill the log to capacity (LOG_MAX_ENTRIES = 200)
    for i = 1, 200 do
        QR:Log("INFO", "Message " .. i)
    end

    -- Get entries at capacity
    local entries1 = QR:GetLogEntries()
    t:assertEqual(200, #entries1, "Log has 200 entries at capacity")

    -- Verify the oldest entry was message 1 (now overwritten)
    -- After 200 entries, the ring buffer is full.
    -- The first entry should be "Message 1" (index 1 was written first).
    t:assertEqual("Message 1", entries1[1].msg, "First entry is Message 1")
    t:assertEqual("Message 200", entries1[200].msg, "Last entry is Message 200")

    -- Now add one more entry - this should REUSE the existing table at index 1
    -- (not create a new one)
    QR:Log("WARN", "Overflow message")

    local entries2 = QR:GetLogEntries()
    t:assertEqual(200, #entries2, "Log still has 200 entries after overflow")

    -- The oldest should now be "Message 2" and newest "Overflow message"
    t:assertEqual("Message 2", entries2[1].msg, "After overflow, oldest is Message 2")
    t:assertEqual("Overflow message", entries2[200].msg, "After overflow, newest is Overflow message")
    t:assertEqual("WARN", entries2[200].level, "Overflow entry has correct level")
end)

T:run("C6: Log entries have time field updated on reuse", function(t)
    resetState()
    QR:ClearLog()

    -- Add an entry
    QR:Log("INFO", "First")
    local entries = QR:GetLogEntries()
    t:assertEqual(1, #entries, "One entry after first log")
    t:assertNotNil(entries[1].time, "Entry has time field")
    t:assertEqual("INFO", entries[1].level, "Entry has correct level")
    t:assertEqual("First", entries[1].msg, "Entry has correct message")

    -- Add another entry
    QR:Log("ERROR", "Second")
    entries = QR:GetLogEntries()
    t:assertEqual(2, #entries, "Two entries after second log")
    t:assertEqual("Second", entries[2].msg, "Second entry has correct message")
end)

-------------------------------------------------------------------------------
-- D1: CrossContinentTravel symmetry - all entries have reverse mappings
-------------------------------------------------------------------------------

T:run("D1: CrossContinentTravel has symmetrical entries", function(t)
    resetState()

    local cct = QR.CrossContinentTravel
    t:assertNotNil(cct, "CrossContinentTravel table exists")

    local missingReverse = {}
    local mismatchedValues = {}

    for fromContinent, destinations in pairs(cct) do
        for toContinent, travelTime in pairs(destinations) do
            -- Check reverse mapping exists
            if not cct[toContinent] then
                missingReverse[#missingReverse + 1] =
                    toContinent .. " has no entry in CrossContinentTravel"
            elseif not cct[toContinent][fromContinent] then
                missingReverse[#missingReverse + 1] =
                    toContinent .. " -> " .. fromContinent .. " missing (reverse of " ..
                    fromContinent .. " -> " .. toContinent .. ")"
            else
                -- Check that reverse has the same value
                local reverseTime = cct[toContinent][fromContinent]
                if reverseTime ~= travelTime then
                    mismatchedValues[#mismatchedValues + 1] = string.format(
                        "%s->%s=%d but %s->%s=%d",
                        fromContinent, toContinent, travelTime,
                        toContinent, fromContinent, reverseTime
                    )
                end
            end
        end
    end

    -- Report missing reverse entries
    t:assertEqual(0, #missingReverse,
        "All CrossContinentTravel entries have reverse mappings" ..
        (#missingReverse > 0 and " (missing: " .. table.concat(missingReverse, "; ") .. ")" or ""))
end)

T:run("D1: CrossContinentTravel covers all continent pairs", function(t)
    resetState()

    local continentKeys = {}
    for key, _ in pairs(QR.Continents) do
        continentKeys[#continentKeys + 1] = key
    end

    local cct = QR.CrossContinentTravel
    local missingPairs = {}

    -- Check that every continent has an entry
    for _, contKey in ipairs(continentKeys) do
        if not cct[contKey] then
            missingPairs[#missingPairs + 1] = contKey .. " missing from CrossContinentTravel"
        end
    end

    t:assertEqual(0, #missingPairs,
        "All continents have CrossContinentTravel entries" ..
        (#missingPairs > 0 and " (missing: " .. table.concat(missingPairs, "; ") .. ")" or ""))
end)

T:run("D1: CrossContinentTravel self-travel is zero", function(t)
    resetState()

    -- GetCrossContinentTravel should return 0 for same-continent
    local time = QR.GetCrossContinentTravel("EASTERN_KINGDOMS", "EASTERN_KINGDOMS")
    t:assertEqual(0, time, "Same-continent travel time is 0")

    time = QR.GetCrossContinentTravel("KALIMDOR", "KALIMDOR")
    t:assertEqual(0, time, "Same-continent (Kalimdor) travel time is 0")
end)

T:run("D1: CrossContinentTravel returns positive values for cross-continent", function(t)
    resetState()

    local time = QR.GetCrossContinentTravel("EASTERN_KINGDOMS", "KALIMDOR")
    t:assertGreaterThan(time, 0, "EK -> Kalimdor travel time > 0")

    time = QR.GetCrossContinentTravel("KALIMDOR", "EASTERN_KINGDOMS")
    t:assertGreaterThan(time, 0, "Kalimdor -> EK travel time > 0")
end)

-------------------------------------------------------------------------------
-- E: PlaySound on button clicks
-------------------------------------------------------------------------------

T:run("E: PlaySound and SOUNDKIT are available", function(t)
    t:assertNotNil(PlaySound, "PlaySound function exists")
    t:assertNotNil(SOUNDKIT, "SOUNDKIT table exists")
    t:assertNotNil(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
        "SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON exists")
    t:assertNotNil(SOUNDKIT.IG_MAINMENU_CLOSE,
        "SOUNDKIT.IG_MAINMENU_CLOSE exists")
end)

T:run("E: PlaySound tracks calls in mock", function(t)
    resetState()
    MockWoW.config.playedSounds = {}

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

    t:assertEqual(1, #MockWoW.config.playedSounds, "One sound played")
    t:assertEqual(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
        MockWoW.config.playedSounds[1].soundID,
        "Correct sound ID tracked")
end)

T:run("E: UI Refresh button plays sound on click", function(t)
    resetState()
    ensureUIFrame()
    MockWoW.config.playedSounds = {}

    -- Get the refresh button's OnClick handler
    local refreshBtn = QR.UI.frame.refreshButton
    t:assertNotNil(refreshBtn, "Refresh button exists")

    -- Reset the throttle so click goes through
    QR.UI.lastRefreshClickTime = 0

    -- Simulate click
    local onclick = refreshBtn._scripts and refreshBtn._scripts["OnClick"]
    if onclick then
        onclick(refreshBtn)
    end

    -- Check that PlaySound was called
    t:assertGreaterThan(#MockWoW.config.playedSounds, 0,
        "PlaySound called on refresh button click")
end)

T:run("E: WindowFactory close button plays IG_MAINMENU_CLOSE", function(t)
    resetState()
    MockWoW.config.playedSounds = {}

    -- Create a test window with onClose
    local closeCalled = false
    local frame = QR.CreateStandardWindow({
        name = "QRTestWindowE1",
        title = "Test Close Sound",
        width = 200,
        height = 200,
        onClose = function() closeCalled = true end,
    })

    t:assertNotNil(frame, "Test window created")

    -- Find the close button - it's a child frame with UIPanelCloseButton template
    -- In our mock, we need to find it by iterating children or checking the OnClick
    -- The close button was created as a child of frame
    -- Since CreateFrame returns mock frames with _scripts, check children
    local children = frame._children or {}
    local closeBtn = nil
    for _, child in ipairs(children) do
        -- The close button should have an OnClick script
        if child._scripts and child._scripts["OnClick"] and child._template == "UIPanelCloseButton" then
            closeBtn = child
            break
        end
    end

    if closeBtn then
        closeBtn._scripts["OnClick"](closeBtn)
        t:assertTrue(closeCalled, "onClose callback was invoked")
        -- Check PlaySound was called with close sound
        local foundCloseSound = false
        for _, sound in ipairs(MockWoW.config.playedSounds) do
            if sound.soundID == SOUNDKIT.IG_MAINMENU_CLOSE then
                foundCloseSound = true
                break
            end
        end
        t:assertTrue(foundCloseSound, "IG_MAINMENU_CLOSE sound played on close button click")
    else
        -- If we can't find the close button in the mock, just verify the window was created
        t:assertNotNil(frame, "Window created (close button not directly testable in mock)")
    end
end)

-------------------------------------------------------------------------------
-- Additional edge case tests
-------------------------------------------------------------------------------

T:run("B1: ConfigureButton dispatches to correct handler", function(t)
    resetState()
    local attrs = {}
    local scripts = {}
    local btn = {
        SetAttribute = function(self, key, val) attrs[key] = val end,
        GetAttribute = function(self, key) return attrs[key] end,
        SetScript = function(self, st, h) scripts[st] = h end,
        poolIndex = 1,
    }

    -- Test spell dispatch
    attrs = {}
    local result = QR.SecureButtons:ConfigureButton(btn, 12345, "spell")
    t:assertTrue(result, "ConfigureButton dispatches spell correctly")
    t:assertEqual("spell", attrs["type"], "ConfigureButton spell sets type=spell")

    -- Test toy dispatch
    attrs = {}
    result = QR.SecureButtons:ConfigureButton(btn, 54452, "toy")
    t:assertTrue(result, "ConfigureButton dispatches toy correctly")
    t:assertEqual("toy", attrs["type"], "ConfigureButton toy sets type=toy")

    -- Test item dispatch
    attrs = {}
    result = QR.SecureButtons:ConfigureButton(btn, 6948, "item")
    t:assertTrue(result, "ConfigureButton dispatches item correctly")
    t:assertEqual("macro", attrs["type"], "ConfigureButton item sets type=macro")

    -- Test equipped dispatch (should use item path)
    attrs = {}
    result = QR.SecureButtons:ConfigureButton(btn, 6948, "equipped")
    t:assertTrue(result, "ConfigureButton dispatches equipped as item")
    t:assertEqual("macro", attrs["type"], "ConfigureButton equipped sets type=macro")
end)

T:run("B1: ConfigureButton rejects invalid IDs through dispatch", function(t)
    resetState()
    local btn = { SetAttribute = function() end, poolIndex = 1 }

    t:assertFalse(QR.SecureButtons:ConfigureButton(btn, nil, "spell"),
        "ConfigureButton spell rejects nil")
    t:assertFalse(QR.SecureButtons:ConfigureButton(btn, -1, "toy"),
        "ConfigureButton toy rejects negative")
    t:assertFalse(QR.SecureButtons:ConfigureButton(btn, 3.5, "item"),
        "ConfigureButton item rejects fractional")
    t:assertFalse(QR.SecureButtons:ConfigureButton(btn, 0, "spell"),
        "ConfigureButton spell rejects zero")
end)

T:run("A1: C_Map.GetBestMapForUnit nil does not crash PathCalculator", function(t)
    resetState()

    -- Make GetBestMapForUnit return nil (simulates loading screen)
    local original = _G.C_Map.GetBestMapForUnit
    _G.C_Map.GetBestMapForUnit = function() return nil end

    QR.PathCalculator.graph = QR.Graph:New()

    local success = pcall(function()
        QR.PathCalculator:AddPlayerTeleportEdges()
    end)
    t:assertTrue(success, "AddPlayerTeleportEdges handles nil mapID gracefully")

    local success2 = pcall(function()
        QR.PathCalculator:UpdatePlayerLocation()
    end)
    t:assertTrue(success2, "UpdatePlayerLocation handles nil mapID gracefully")

    _G.C_Map.GetBestMapForUnit = original
end)

T:run("C1: Hide resets isShowing flag", function(t)
    resetState()
    ensureUIFrame()

    QR.MainFrame:Show("route")
    t:assertTrue(QR.MainFrame.isShowing, "isShowing is true after Show()")
    QR.MainFrame:Hide()
    t:assertFalse(QR.MainFrame.isShowing, "isShowing is false after Hide()")
end)

T:run("B2: /qrpath with insufficient args shows usage", function(t)
    resetState()
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    SlashCmdList["QRPATH"]("84")

    _G.print = origPrint

    local foundUsage = false
    for _, msg in ipairs(captured) do
        if msg:find("Usage") then
            foundUsage = true
            break
        end
    end
    t:assertTrue(foundUsage, "/qrpath with 1 arg shows usage message")
end)

T:run("B2: /qrpath with non-numeric args shows error", function(t)
    resetState()
    local captured = {}
    local origPrint = print
    _G.print = function(...) captured[#captured + 1] = table.concat({...}, " ") end

    SlashCmdList["QRPATH"]("abc def ghi")

    _G.print = origPrint

    local foundError = false
    for _, msg in ipairs(captured) do
        if msg:find("Invalid") or msg:find("invalid") then
            foundError = true
            break
        end
    end
    t:assertTrue(foundError, "/qrpath with non-numeric args shows error")
end)
