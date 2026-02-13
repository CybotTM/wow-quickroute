-------------------------------------------------------------------------------
-- test_logging.lua
-- Tests for QR:Log(), QR:GetLogEntries(), QR:ClearLog() ring buffer
-- (3.1 Ring buffer log wraparound + 3.7 Full init chain integration test)
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- 3.1: Ring Buffer Log Wraparound
-------------------------------------------------------------------------------

T:run("Log ring buffer: basic log and retrieve", function(t)
    QR:ClearLog()

    QR:Log("INFO", "message one")
    QR:Log("WARN", "message two")

    local entries = QR:GetLogEntries()
    t:assertEqual(2, #entries, "Two log entries after two Log calls")
    t:assertEqual("INFO", entries[1].level, "First entry is INFO")
    t:assertEqual("message one", entries[1].msg, "First message correct")
    t:assertEqual("WARN", entries[2].level, "Second entry is WARN")
    t:assertEqual("message two", entries[2].msg, "Second message correct")
end)

T:run("Log ring buffer: ClearLog empties the buffer", function(t)
    QR:ClearLog()
    QR:Log("INFO", "will be cleared")
    QR:ClearLog()

    local entries = QR:GetLogEntries()
    t:assertEqual(0, #entries, "No entries after ClearLog")
end)

T:run("Log ring buffer: wraparound at LOG_MAX_ENTRIES=200 boundary", function(t)
    QR:ClearLog()

    -- Fill the buffer with exactly 200 entries
    for i = 1, 200 do
        QR:Log("INFO", "entry-" .. i)
    end

    local entries = QR:GetLogEntries()
    t:assertEqual(200, #entries, "Buffer holds exactly 200 entries at capacity")
    t:assertEqual("entry-1", entries[1].msg, "Oldest entry is entry-1 (no wraparound yet)")
    t:assertEqual("entry-200", entries[200].msg, "Newest entry is entry-200")

    -- Add one more to trigger wraparound: entry-1 should be evicted
    QR:Log("INFO", "entry-201")

    entries = QR:GetLogEntries()
    t:assertEqual(200, #entries, "Buffer still holds 200 entries after wraparound")
    t:assertEqual("entry-2", entries[1].msg, "Oldest entry is now entry-2 (entry-1 evicted)")
    t:assertEqual("entry-201", entries[200].msg, "Newest entry is entry-201")
end)

T:run("Log ring buffer: multiple wraparounds maintain chronological order", function(t)
    QR:ClearLog()

    -- Write 450 entries (2+ full wraps around a 200-entry buffer)
    for i = 1, 450 do
        QR:Log("DEBUG", "wrap-" .. i)
    end

    local entries = QR:GetLogEntries()
    t:assertEqual(200, #entries, "Buffer capped at 200 after multiple wraps")

    -- Oldest should be entry 251 (450 - 200 + 1)
    t:assertEqual("wrap-251", entries[1].msg, "Oldest entry correct after multi-wrap")
    t:assertEqual("wrap-450", entries[200].msg, "Newest entry correct after multi-wrap")

    -- Verify chronological order is maintained across the wrap boundary
    local inOrder = true
    for i = 1, #entries - 1 do
        local a = tonumber(entries[i].msg:match("wrap%-(%d+)"))
        local b = tonumber(entries[i + 1].msg:match("wrap%-(%d+)"))
        if a >= b then
            inOrder = false
            break
        end
    end
    t:assertTrue(inOrder, "Entries are in strictly increasing chronological order")
end)

T:run("Log ring buffer: Print/Debug/Warn/Error all write to log", function(t)
    QR:ClearLog()

    -- Save and restore debugMode
    local savedDebugMode = QR.debugMode
    QR.debugMode = true

    QR:Print("print msg")
    QR:Debug("debug msg")
    QR:Warn("warn msg")
    QR:Error("error msg")

    QR.debugMode = savedDebugMode

    local entries = QR:GetLogEntries()
    t:assertGreaterThan(#entries, 3, "At least 4 log entries from Print/Debug/Warn/Error")

    -- Check that each level appears
    local levels = {}
    for _, entry in ipairs(entries) do
        levels[entry.level] = true
    end
    t:assertTrue(levels["INFO"] == true, "INFO level present (from Print)")
    t:assertTrue(levels["DEBUG"] == true, "DEBUG level present (from Debug)")
    t:assertTrue(levels["WARN"] == true, "WARN level present (from Warn)")
    t:assertTrue(levels["ERROR"] == true, "ERROR level present (from Error)")
end)

-------------------------------------------------------------------------------
-- 3.7: Full Init Chain Integration Test
-------------------------------------------------------------------------------

T:run("OnPlayerLogin: init chain continues when one module fails", function(t)
    -- Save original module methods
    local origInitGraph = QR.InitializeGraph
    local origScanTeleports = QR.ScanPlayerTeleports
    local origSecureInit = QR.SecureButtons.Initialize
    local origWaypointInit = QR.WaypointIntegration.Initialize
    local origUIInit = QR.UI.Initialize
    local origTPInit = QR.TeleportPanel.Initialize

    -- Track which modules got initialized
    local initialized = {}

    -- Make Graph init throw an error
    QR.InitializeGraph = function()
        error("Simulated Graph init failure")
    end

    -- Track all other modules
    QR.ScanPlayerTeleports = function()
        initialized.PlayerTeleports = true
    end
    QR.SecureButtons.Initialize = function()
        initialized.SecureButtons = true
    end
    QR.WaypointIntegration.Initialize = function()
        initialized.WaypointIntegration = true
    end
    QR.UI.Initialize = function()
        initialized.UI = true
    end
    QR.TeleportPanel.Initialize = function()
        initialized.TeleportPanel = true
    end

    -- Run the init chain (C_Timer.After executes immediately in test env)
    QR:OnPlayerLogin()

    -- Despite Graph failing, all other modules should have been initialized
    t:assertTrue(initialized.PlayerTeleports == true,
        "PlayerTeleports initialized despite Graph failure")
    t:assertTrue(initialized.SecureButtons == true,
        "SecureButtons initialized despite Graph failure")
    t:assertTrue(initialized.WaypointIntegration == true,
        "WaypointIntegration initialized despite Graph failure")
    t:assertTrue(initialized.UI == true,
        "UI initialized despite Graph failure")
    t:assertTrue(initialized.TeleportPanel == true,
        "TeleportPanel initialized despite Graph failure")

    -- Restore
    QR.InitializeGraph = origInitGraph
    QR.ScanPlayerTeleports = origScanTeleports
    QR.SecureButtons.Initialize = origSecureInit
    QR.WaypointIntegration.Initialize = origWaypointInit
    QR.UI.Initialize = origUIInit
    QR.TeleportPanel.Initialize = origTPInit
end)

T:run("OnPlayerLogin: error is logged when a module fails", function(t)
    -- Save originals
    local origInitGraph = QR.InitializeGraph
    local origError = QR.Error
    local origScanTeleports = QR.ScanPlayerTeleports
    local origSecureInit = QR.SecureButtons.Initialize
    local origWaypointInit = QR.WaypointIntegration.Initialize
    local origUIInit = QR.UI.Initialize
    local origTPInit = QR.TeleportPanel.Initialize

    -- Track errors
    local errorMessages = {}
    QR.Error = function(self, msg)
        errorMessages[#errorMessages + 1] = msg
    end

    -- Make Graph init fail
    QR.InitializeGraph = function()
        error("Graph boom")
    end

    -- Stub the rest to no-ops
    QR.ScanPlayerTeleports = function() end
    QR.SecureButtons.Initialize = function() end
    QR.WaypointIntegration.Initialize = function() end
    QR.UI.Initialize = function() end
    QR.TeleportPanel.Initialize = function() end

    QR:OnPlayerLogin()

    -- Should have logged exactly one error for the Graph module
    t:assertGreaterThan(#errorMessages, 0, "At least one error message logged")

    local foundGraphError = false
    for _, msg in ipairs(errorMessages) do
        if msg:find("Graph") then
            foundGraphError = true
        end
    end
    t:assertTrue(foundGraphError, "Error message mentions Graph module")

    -- Restore
    QR.InitializeGraph = origInitGraph
    QR.Error = origError
    QR.ScanPlayerTeleports = origScanTeleports
    QR.SecureButtons.Initialize = origSecureInit
    QR.WaypointIntegration.Initialize = origWaypointInit
    QR.UI.Initialize = origUIInit
    QR.TeleportPanel.Initialize = origTPInit
end)
