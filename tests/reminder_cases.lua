-------------------------------------------------------------------------------
-- reminder_cases.lua
-- The save-reminder cases, shared by test_save_reminder.lua (retail) and
-- test_forever_save_reminder.lua (QR_TEST_FLAVOR=forever). Not named
-- test_*.lua, so the runner does not pick it up on its own.
-------------------------------------------------------------------------------

local T, QR, MockWoW, flavor = ...
local D = QR.Diagnostics
local R = D.Reminder
local ZS = QR.ZoneSurvey
local DC = QR.DataCollection
local prefix = "Save reminder (" .. flavor .. "): "

local DB_KEYS = { "saveReminder", "saveReminderMinutes", "saveReminderTimeout",
    "diagnosticTrace", "zoneSurveyEnabled", "zoneSurveyChoice", "trace", "dataCollection" }
local CFG_KEYS = { "inCombatLockdown", "onTaxi", "inInstance", "instanceType" }

--- Run a case with every piece of state it touches saved and put back.
-- Starts from: reminders on, 20 minutes, 30 s, trace on, survey and
-- observations off, nothing unsaved, a fresh interval, no combat, not on a taxi, outdoors.
local function withReminder(fn)
    local saved = { db = {}, cfg = {} }
    for _, k in ipairs(DB_KEYS) do saved.db[k] = QR.db[k] end
    for _, k in ipairs(CFG_KEYS) do saved.cfg[k] = MockWoW.config[k] end
    saved.unsavedTrace = D.unsavedTrace
    saved.captures, saved.crossings = ZS.unsavedCaptures, ZS.unsavedCrossings
    saved.observations = DC.unsavedCount
    saved.reloadUI, saved.cui = _G.ReloadUI, _G.C_UI
    saved.affecting, saved.encounter = _G.UnitAffectingCombat, _G.IsEncounterInProgress
    saved.pending = QR.SecureButtons and QR.SecureButtons.pendingReleases
    saved.mapID = MockWoW.config.currentMapID
    saved.survey = QR.db.zoneSurvey
    saved.state = { R.sinceLast, R.checkElapsed, R.due, R.loading }

    QR.db.saveReminder = true
    QR.db.saveReminderMinutes = 20
    QR.db.saveReminderTimeout = 30
    QR.db.diagnosticTrace = true
    QR.db.zoneSurveyEnabled = false
    QR.db.dataCollection = false
    D.unsavedTrace = 0
    ZS.unsavedCaptures, ZS.unsavedCrossings = 0, 0
    DC.unsavedCount = 0
    R.sinceLast, R.checkElapsed, R.due, R.loading = 0, 0, false, false
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.onTaxi = false
    MockWoW.config.inInstance = false
    if R.popup then R.popup:Hide() end

    local ok, err = pcall(fn)

    if R.popup then R.popup:Hide() end
    for _, k in ipairs(DB_KEYS) do QR.db[k] = saved.db[k] end
    -- Trace events and the ticker back to what the restored settings say.
    D:ApplyTraceSetting()
    QR.db.trace = saved.db.trace
    for _, k in ipairs(CFG_KEYS) do MockWoW.config[k] = saved.cfg[k] end
    D.unsavedTrace = saved.unsavedTrace
    ZS.unsavedCaptures, ZS.unsavedCrossings = saved.captures, saved.crossings
    DC.unsavedCount = saved.observations
    _G.ReloadUI, _G.C_UI = saved.reloadUI, saved.cui
    _G.UnitAffectingCombat, _G.IsEncounterInProgress = saved.affecting, saved.encounter
    if QR.SecureButtons then QR.SecureButtons.pendingReleases = saved.pending end
    MockWoW.config.currentMapID = saved.mapID
    QR.db.zoneSurvey = saved.survey
    ZS:ForgetArrivalState()
    R.sinceLast, R.checkElapsed, R.due, R.loading = saved.state[1], saved.state[2], saved.state[3], saved.state[4]
    if not ok then error(err, 0) end
end

--- Advance the reminder's clock the way the client does: OnUpdate per step.
local function tick(seconds)
    local onUpdate = R.ticker:GetScript("OnUpdate")
    local step = D.REMINDER_CHECK_SECONDS
    local done = 0
    while done < seconds do
        onUpdate(R.ticker, step)
        done = done + step
    end
end

local function shown()
    return R.popup ~= nil and R.popup:IsShown() == true
end

local MINUTES_20 = 20 * 60

T:run(prefix .. "defaults", function(t)
    t:assertTrue(QR.db.saveReminder, "reminders default on")
    t:assertEqual(20, QR.db.saveReminderMinutes, "every 20 minutes")
    t:assertEqual(30, QR.db.saveReminderTimeout, "closing after 30 s")
end)

T:run(prefix .. "shown only when something is unsaved", function(t)
    withReminder(function()
        tick(MINUTES_20 + 10)
        t:assertFalse(shown(), "nothing unsaved: no reminder after the interval")
        D.unsavedTrace = 42
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertTrue(shown(), "unsaved entries: the due reminder appears at the next check")
        t:assertTrue(R.popup.lines.unsaved:GetText():find("42", 1, true) ~= nil,
            "and names the count (" .. tostring(R.popup.lines.unsaved:GetText()) .. ")")
    end)
end)

T:run(prefix .. "not before the interval", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20 - 10)
        t:assertFalse(shown(), "10 s before the interval: nothing")
        tick(10)
        t:assertTrue(shown(), "at the interval: shown")
    end)
end)

T:run(prefix .. "waits out combat and appears after it", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        MockWoW.config.inCombatLockdown = true
        tick(MINUTES_20 + 60)
        t:assertFalse(shown(), "not in combat")
        t:assertTrue(R.due, "but it is owed")
        MockWoW.config.inCombatLockdown = false
        R:OnCombatLeave()   -- what the leave-combat callback calls
        t:assertTrue(shown(), "shown when the fight ends")
    end)
end)

T:run(prefix .. "hidden when combat starts, back after it", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20)
        t:assertTrue(shown(), "shown")
        MockWoW.config.inCombatLockdown = true
        R:OnCombatEnter()
        t:assertFalse(shown(), "hidden in the fight")
        MockWoW.config.inCombatLockdown = false
        R:OnCombatLeave()
        t:assertTrue(shown(), "back after it")
    end)
end)

T:run(prefix .. "never on a taxi, in an instance or a loading screen", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        MockWoW.config.onTaxi = true
        tick(MINUTES_20)
        t:assertFalse(shown(), "not on a taxi")
        MockWoW.config.onTaxi = false
        MockWoW.config.inInstance = true
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertFalse(shown(), "not in an instance")
        MockWoW.config.inInstance = false
        R.loading = true
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertFalse(shown(), "not in a loading screen")
        R.loading = false
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertTrue(shown(), "at the next safe check")
    end)
end)

T:run(prefix .. "closes itself after the timeout", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20)
        local onUpdate = R.popup:GetScript("OnUpdate")
        onUpdate(R.popup, 29)
        t:assertTrue(shown(), "still there after 29 s")
        onUpdate(R.popup, 1)
        t:assertFalse(shown(), "gone after 30 s")
        t:assertEqual(0, R.sinceLast, "and the interval starts again")
    end)
end)

T:run(prefix .. "the timeout waits while the pointer is on it", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20)
        R.popup.hovered = true
        R.popup:GetScript("OnUpdate")(R.popup, 60)
        t:assertTrue(shown(), "still there")
        R.popup.hovered = false
    end)
end)

T:run(prefix .. "Close restarts the interval", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20)
        t:assertTrue(shown(), "shown")
        -- The window stays up a while before it is closed: the interval counts
        -- from the close, not from when it appeared.
        tick(25)
        R.popup.dismissButton:GetScript("OnClick")(R.popup.dismissButton)
        t:assertFalse(shown(), "closed")
        tick(MINUTES_20 - 10)
        t:assertFalse(shown(), "not again before a full interval")
        tick(10)
        t:assertTrue(shown(), "again after it")
    end)
end)

T:run(prefix .. "Reload calls the reload function, not in combat", function(t)
    withReminder(function()
        local calls = 0
        _G.C_UI = nil
        _G.ReloadUI = function() calls = calls + 1 end
        D.unsavedTrace = 5
        tick(MINUTES_20)
        local click = R.popup.reloadButton:GetScript("OnClick")
        MockWoW.config.inCombatLockdown = true
        click(R.popup.reloadButton)
        t:assertEqual(0, calls, "no reload in combat")
        MockWoW.config.inCombatLockdown = false
        click(R.popup.reloadButton)
        t:assertEqual(1, calls, "ReloadUI out of combat")
        local modern = 0
        _G.C_UI = { Reload = function() modern = modern + 1 end }
        click(R.popup.reloadButton)
        t:assertEqual(1, modern, "C_UI.Reload where the client has it")
        t:assertEqual(1, calls, "and then not ReloadUI")
        _G.C_UI, _G.ReloadUI = nil, nil
        t:assertFalse(R:OnReloadClick(), "neither: nothing happens")
    end)
end)

T:run(prefix .. "the setting turns it off", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        QR.db.saveReminder = false
        tick(MINUTES_20 * 2)
        t:assertFalse(shown(), "off: never shown")
        QR.db.saveReminder = true
        QR.db.diagnosticTrace = false
        QR.db.zoneSurveyEnabled = false
        QR.db.dataCollection = false
        DC.unsavedCount = 5
        tick(MINUTES_20 * 2)
        t:assertFalse(shown(), "nothing recording: never shown")
    end)
end)

T:run(prefix .. "names what records and the fill level", function(t)
    withReminder(function()
        QR.db.zoneSurveyEnabled = true
        D.unsavedTrace = 7
        ZS.unsavedCaptures, ZS.unsavedCrossings = 3, 2
        -- The log ring counts too: 3 of the 6 MiB both rings may hold.
        local total = D.TRACE_MAX_BYTES + D.TRACE_LOG_MAX_BYTES
        QR.db.trace = { v = D.TRACE_VERSION, cap = D.TRACE_CAP, first = 1, n = 5000, bytes = total / 2 - 1024 * 1024,
            e = {}, log = { cap = D.TRACE_LOG_CAP, first = 1, n = 1000, bytes = 1024 * 1024, e = {} } }
        tick(MINUTES_20)
        local lines = R.popup.lines
        local L = QR.L
        t:assertTrue(lines.active:GetText():find(L["SAVE_REMINDER_TRACE_NAME"], 1, true) ~= nil, "names the trace")
        t:assertTrue(lines.active:GetText():find(L["SAVE_REMINDER_SURVEY_NAME"], 1, true) ~= nil, "names the survey")
        t:assertTrue(lines.unsaved:GetText():find("10", 1, true) ~= nil, "7 trace + 3 survey entries unsaved")
        -- 6000 of 25000 entries = 24 %, 3 of 6 MiB = 50 %: the higher one.
        t:assertEqual(string.format(L["SAVE_REMINDER_TRACE_FILL"], 50), lines.fill:GetText(), "fill is the higher share")
        t:assertTrue(lines.survey:GetText():find("2", 1, true) ~= nil, "two new crossings")
        t:assertEqual(math.floor(376 * 0.5), math.floor(R.popup.barWidth), "the bar is half full")
    end)
end)

T:run(prefix .. "names the observations and counts their unsaved writes", function(t)
    withReminder(function()
        QR.db.diagnosticTrace = false
        QR.db.dataCollection = true
        DC.unsavedCount = 6
        tick(MINUTES_20)
        t:assertTrue(shown(), "observations alone make the reminder apply")
        local lines = R.popup.lines
        local L = QR.L
        t:assertEqual(string.format(L["SAVE_REMINDER_ACTIVE"], L["SAVE_REMINDER_OBSERVATIONS_NAME"]),
            lines.active:GetText(), "names only the observations")
        t:assertEqual(string.format(L["SAVE_REMINDER_UNSAVED"], 6), lines.unsaved:GetText(), "six unsaved writes")
        t:assertEqual(string.format(L["SAVE_REMINDER_OBSERVATIONS_NEW"], 6), lines.observations:GetText(),
            "and its own line")
        t:assertTrue(lines.observations:IsShown(), "which is shown")
        t:assertFalse(lines.survey:IsShown(), "the survey line is not, the survey is off")
        local total, trace, captures, crossings, observations = R:Unsaved()
        t:assertEqual(6, total, "total includes the observations")
        t:assertEqual(0, trace + captures + crossings, "the other counts are untouched")
        t:assertEqual(6, observations, "fifth value is the observations")
    end)
end)

T:run(prefix .. "observations count only while their switch is on", function(t)
    withReminder(function()
        DC.unsavedCount = 6
        D.unsavedTrace = 1
        t:assertEqual(1, (R:Unsaved()), "observations off: their writes are not counted")
        QR.db.dataCollection = true
        t:assertEqual(7, (R:Unsaved()), "on: counted")
        tick(MINUTES_20)
        t:assertTrue(R.popup.lines.active:GetText():find(QR.L["SAVE_REMINDER_TRACE_NAME"], 1, true) ~= nil,
            "the trace is named")
        t:assertTrue(R.popup.lines.active:GetText():find(QR.L["SAVE_REMINDER_OBSERVATIONS_NAME"], 1, true) ~= nil,
            "and the observations beside it")
    end)
end)

-- The mock measures 7 px per byte. That fits Latin scripts; Cyrillic, Hangul
-- and Han take 2-3 bytes per character there, so the mock cannot tell whether
-- they fit and those locales are left to the wrapping the frame does.
T:run(prefix .. "German and the other Latin-script texts fit the window", function(t)
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)") or "tests/"
    local chunk = loadfile(scriptDir .. "../QuickRoute/Localization.lua")
    t:assertNotNil(chunk, "Localization.lua loads")
    local savedLocale = MockWoW.config.locale
    withReminder(function()
        QR.db.zoneSurveyEnabled = true
        QR.db.trace = { v = D.TRACE_VERSION, cap = D.TRACE_CAP, first = 1, n = D.TRACE_CAP,
            bytes = D.TRACE_MAX_BYTES, e = {} }
        D.unsavedTrace = 999999
        ZS.unsavedCaptures, ZS.unsavedCrossings = 0, 999999
        for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ptBR", "itIT" }) do
            MockWoW.config.locale = locale
            chunk("QuickRoute", QR)
            R:Populate()
            local frame = R.popup
            local inner = 376
            for key, fs in pairs(frame.lines) do
                if key ~= "why" then
                    t:assert(fs:GetStringWidth() <= inner, locale .. " " .. key .. " on one line ("
                        .. fs:GetStringWidth() .. " px of " .. inner .. "): " .. tostring(fs:GetText()))
                end
            end
            t:assert(frame.lines.why:GetStringHeight() <= 36, locale .. " explanation in at most 3 lines ("
                .. frame.lines.why:GetStringHeight() .. " px)")
            local buttons = frame.reloadButton:GetWidth() + 8 + frame.dismissButton:GetWidth()
            t:assert(buttons <= inner, locale .. " buttons side by side (" .. buttons .. " px)")
            t:assert(frame.titleText:GetStringWidth() <= 400 - 40, locale .. " title clear of the close button ("
                .. frame.titleText:GetStringWidth() .. " px)")
            t:assert(frame:GetHeight() <= 240, locale .. " window stays compact (" .. frame:GetHeight() .. " px)")
        end
        -- All three recorders on: one more line, and the list of names may
        -- wrap once. Every other line still fits on one. The window measures
        -- 250 px in each of these locales; one line more than that fails.
        QR.db.dataCollection = true
        DC.unsavedCount = 999999
        for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ptBR", "itIT" }) do
            MockWoW.config.locale = locale
            chunk("QuickRoute", QR)
            R:Populate()
            local frame = R.popup
            local inner = 376
            t:assertTrue(frame.lines.observations:IsShown(), locale .. " shows the observations line")
            for key, fs in pairs(frame.lines) do
                if key ~= "why" and key ~= "active" then
                    t:assert(fs:GetStringWidth() <= inner, locale .. " " .. key .. " on one line with three recorders ("
                        .. fs:GetStringWidth() .. " px of " .. inner .. "): " .. tostring(fs:GetText()))
                end
            end
            t:assert(frame.lines.active:GetStringHeight() <= 24, locale .. " names in at most 2 lines ("
                .. frame.lines.active:GetStringHeight() .. " px): " .. tostring(frame.lines.active:GetText()))
            t:assert(frame:GetHeight() <= 256, locale .. " window with three recorders stays compact ("
                .. frame:GetHeight() .. " px)")
        end
    end)
    MockWoW.config.locale = "enUS"
    chunk("QuickRoute", QR)
    MockWoW.config.locale = savedLocale
    if R.popup then R:Populate() end
end)

T:run(prefix .. "never during an encounter, in unit combat or with a secure button pending", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        local encounter, affecting = true, false
        _G.IsEncounterInProgress = function() return encounter end
        _G.UnitAffectingCombat = function() return affecting end
        tick(MINUTES_20)
        t:assertFalse(shown(), "not during an encounter")
        encounter, affecting = false, true
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertFalse(shown(), "not while the player is in combat by UnitAffectingCombat")
        affecting = false
        QR.SecureButtons.pendingReleases = { {} }
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertFalse(shown(), "not while QuickRoute still has a secure button to release")
        QR.SecureButtons.pendingReleases = nil
        tick(D.REMINDER_CHECK_SECONDS)
        t:assertTrue(shown(), "at the next safe check")
    end)
end)

T:run(prefix .. "closing with ESC restarts the interval too", function(t)
    withReminder(function()
        D.unsavedTrace = 5
        tick(MINUTES_20)
        t:assertTrue(shown(), "shown")
        tick(25)
        R.popup:Hide()   -- what ESC does
        tick(MINUTES_20 - 10)
        t:assertFalse(shown(), "not again before a full interval")
    end)
end)

T:run(prefix .. "the trace counts what it records", function(t)
    withReminder(function()
        QR.db.trace = nil
        QR:Log("INFO", "one line for the reminder")
        t:assertEqual(1, D.unsavedTrace, "a log line with the trace on is one unsaved entry")
        QR.db.diagnosticTrace = false
        QR:Log("INFO", "a line while off")
        t:assertEqual(1, D.unsavedTrace, "nothing counted while the trace is off")
    end)
end)

T:run(prefix .. "the zone survey counts captures and crossings", function(t)
    withReminder(function()
        QR.db.zoneSurveyEnabled = true
        QR.db.zoneSurvey = {}
        ZS:ForgetArrivalState()
        MockWoW.config.currentMapID = 63
        ZS:Capture()
        MockWoW.config.currentMapID = 84
        ZS:Capture()
        t:assertEqual(2, ZS.unsavedCaptures, "two maps captured")
        t:assertEqual(1, ZS.unsavedCrossings, "one crossing between them")
        local total = R:Unsaved()
        t:assertEqual(2, total, "the reminder counts the captures")
    end)
end)

T:run(prefix .. "the ticker runs only while reminders apply", function(t)
    withReminder(function()
        QR.db.diagnosticTrace = false
        QR.db.zoneSurveyEnabled = false
        D:ApplyTraceSetting()
        t:assertFalse(R.ticker:IsShown(), "trace and survey off: the ticker is hidden")
        QR.db.diagnosticTrace = true
        D:ApplyTraceSetting()   -- what the trace checkbox calls
        t:assertTrue(R.ticker:IsShown(), "trace on: shown")
        QR.db.diagnosticTrace = false
        D:ApplyTraceSetting()
        t:assertFalse(R.ticker:IsShown(), "trace off again: hidden")
        ZS:SetEnabled(true)     -- the survey checkbox or /qrsurvey on
        t:assertTrue(R.ticker:IsShown(), "survey on: shown")
        QR.SettingsPanel.controls.saveReminder.setting._setValue(false)
        t:assertFalse(R.ticker:IsShown(), "reminders switched off: hidden")
        QR.SettingsPanel.controls.saveReminder.setting._setValue(true)
        t:assertTrue(R.ticker:IsShown(), "and on again: shown")
        ZS:SetEnabled(false)
        t:assertFalse(R.ticker:IsShown(), "survey off: hidden")
        QR.SettingsPanel.controls.dataCollection.setting._setValue(true)   -- the observations checkbox
        t:assertTrue(R.ticker:IsShown(), "observations on: shown")
        SlashCmdList["QRDATA"]("off")
        t:assertFalse(R.ticker:IsShown(), "observations off by /qrdata: hidden")
        SlashCmdList["QRDATA"]("on")
        t:assertTrue(R.ticker:IsShown(), "on by /qrdata: shown")
        QR.SettingsPanel.controls.dataCollection.setting._setValue(false)
        t:assertFalse(R.ticker:IsShown(), "unticked: hidden")
    end)
end)
