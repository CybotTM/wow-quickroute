-------------------------------------------------------------------------------
-- survey_choice_cases.lua
-- The zone survey is off unless the player switched it on. Shared by
-- test_survey_choice.lua (retail) and test_forever_survey_choice.lua
-- (QR_TEST_FLAVOR=forever). Not named test_*.lua, so the runner does not pick
-- it up on its own.
-------------------------------------------------------------------------------

local T, QR, MockWoW, flavor = ...
local ZS = QR.ZoneSurvey
local D = QR.Diagnostics
local R = D.Reminder
local prefix = "Zone survey choice (" .. flavor .. "): "

local KEYS = { "zoneSurveyEnabled", "zoneSurveyChoice", "zoneSurvey", "diagnosticTrace", "saveReminder",
    "saveReminderMinutes" }

--- Run a case on a SavedVariables state of its own, then put the suite's back.
local function withSurveyState(state, fn)
    local saved = {}
    for _, k in ipairs(KEYS) do saved[k] = QR.db[k] end
    local savedMap = MockWoW.config.currentMapID
    local savedCombat = MockWoW.config.inCombatLockdown
    local savedReminder = { R.sinceLast, R.checkElapsed, R.due }
    local savedCounts = { D.unsavedTrace, ZS.unsavedCaptures, ZS.unsavedCrossings }
    for _, k in ipairs(KEYS) do QR.db[k] = nil end
    for k, v in pairs(state) do QR.db[k] = v end
    D.unsavedTrace, ZS.unsavedCaptures, ZS.unsavedCrossings = 0, 0, 0
    MockWoW.config.inCombatLockdown = false
    local ok, err = pcall(fn)
    if R.popup then R.popup:Hide() end
    for _, k in ipairs(KEYS) do QR.db[k] = saved[k] end
    -- Initialize again on the suite's own store, so ZoneSurvey's budget
    -- bookkeeping describes it again; the marker keeps the migration from
    -- touching the suite's setting.
    local choice = QR.db.zoneSurveyChoice
    QR.db.zoneSurveyChoice = true
    ZS:Initialize()
    QR.db.zoneSurveyChoice = choice
    MockWoW.config.currentMapID = savedMap
    MockWoW.config.inCombatLockdown = savedCombat
    R.sinceLast, R.checkElapsed, R.due = savedReminder[1], savedReminder[2], savedReminder[3]
    D.unsavedTrace, ZS.unsavedCaptures, ZS.unsavedCrossings = savedCounts[1], savedCounts[2], savedCounts[3]
    ZS:ForgetArrivalState()
    if not ok then error(err, 0) end
end

local function control()
    return QR.SettingsPanel.controls.zoneSurveyEnabled
end

local RECORD = { name = "Somewhere", visits = 4, seen = "2026-11-01 10:00:00" }

T:run(prefix .. "a fresh install has the survey off and records nothing", function(t)
    withSurveyState({}, function()
        ZS:Initialize()   -- what the first login runs
        t:assertFalse(QR.db.zoneSurveyEnabled == true, "off after the first load (got "
            .. tostring(QR.db.zoneSurveyEnabled) .. ")")
        t:assertFalse(control().setting._getValue(), "and the checkbox says so")
        MockWoW.config.currentMapID = 63
        t:assertNil(ZS:Capture(), "a zone change records nothing")
        MockWoW.config.currentMapID = 84
        t:assertNil(ZS:Capture(), "nor the next one")
        t:assertEqual(0, ZS.unsavedCaptures or 0, "nothing unsaved")
    end)
end)

T:run(prefix .. "a fresh install shows no save reminder after zone changes", function(t)
    withSurveyState({ saveReminder = true, saveReminderMinutes = 20 }, function()
        ZS:Initialize()
        D.unsavedTrace, ZS.unsavedCaptures, ZS.unsavedCrossings = 0, 0, 0
        R.sinceLast, R.checkElapsed, R.due = 0, 0, false
        if R.popup then R.popup:Hide() end
        for _, mapID in ipairs({ 63, 84, 63, 84 }) do
            MockWoW.config.currentMapID = mapID
            ZS:Capture()
        end
        local onUpdate = R.ticker:GetScript("OnUpdate")
        for _ = 1, (2 * 20 * 60) / D.REMINDER_CHECK_SECONDS do
            onUpdate(R.ticker, D.REMINDER_CHECK_SECONDS)
        end
        t:assertFalse(R:Active(), "the reminder has nothing to watch")
        t:assertFalse(R.popup ~= nil and R.popup:IsShown() == true, "and does not appear in 40 minutes")
    end)
end)

T:run(prefix .. "the old automatic on is turned off once and the data kept", function(t)
    withSurveyState({ zoneSurveyEnabled = true, zoneSurvey = { [63] = RECORD } }, function()
        ZS:Initialize()   -- first load of this build
        t:assertFalse(QR.db.zoneSurveyEnabled, "an unmarked true is turned off")
        t:assertNil(QR.db.zoneSurveyChoice, "and not recorded as a choice")
        t:assertNotNil(QR.db.zoneSurvey[63], "the recorded map is still there")
        t:assertEqual(4, QR.db.zoneSurvey[63] and QR.db.zoneSurvey[63].visits, "unchanged")
        ZS:SetEnabled(true)   -- the player switches it on afterwards
        ZS:Initialize()       -- the next load
        t:assertTrue(QR.db.zoneSurveyEnabled, "the next load leaves the choice alone")
    end)
end)

T:run(prefix .. "a choice survives reloads", function(t)
    withSurveyState({}, function()
        control().setting._setValue(true)   -- the checkbox
        t:assertTrue(QR.db.zoneSurveyChoice, "the checkbox marks a choice")
        ZS:Initialize()
        t:assertTrue(QR.db.zoneSurveyEnabled, "on stays on after a reload")
        SlashCmdList["QRSURVEY"]("off")
        ZS:Initialize()
        t:assertFalse(QR.db.zoneSurveyEnabled, "off stays off after a reload")
        t:assertTrue(QR.db.zoneSurveyChoice, "and is a choice too")
    end)
end)

T:run(prefix .. "the checkbox and /qrsurvey agree", function(t)
    withSurveyState({}, function()
        local setting = control().setting
        local notified = 0
        setting.NotifyUpdate = function() notified = notified + 1 end
        SlashCmdList["QRSURVEY"]("on")
        t:assertTrue(setting._getValue(), "/qrsurvey on: the checkbox reads on")
        t:assertEqual(1, notified, "and an open panel is told")
        setting._setValue(false)
        t:assertFalse(QR.db.zoneSurveyEnabled, "the checkbox switches it off")
        t:assertEqual(1, notified, "without telling the panel about its own change")
        MockWoW.config.currentMapID = 63
        t:assertNil(ZS:Capture(), "and nothing is recorded")
        SlashCmdList["QRSURVEY"]("on")
        t:assertTrue(setting._getValue(), "on again from the chat")
        setting.NotifyUpdate = nil
    end)
end)
