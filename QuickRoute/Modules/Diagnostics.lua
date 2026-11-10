-- Diagnostics.lua
-- Records Lua errors and teleport-list rebuilds into SavedVariables.
--
-- Both answer questions that only exist while the game is running and that a
-- screenshot of the error frame answers badly: what exactly threw, and what the
-- teleport panel believed it had at the moment it drew an empty list. Keeping
-- them on disk means a report is "reproduce it once and reload" rather than a
-- transcription.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, pcall, tostring = pairs, ipairs, pcall, tostring
local string_format = string.format
local table_concat, table_remove = table.concat, table.remove
local date = date

QR.Diagnostics = {}
local Diagnostics = QR.Diagnostics

-- Ring buffers. Small, because these live in SavedVariables and are rewritten
-- whole on every logout.
local MAX_ERRORS = 40
local MAX_REFRESHES = 60

local function push(list, entry, cap)
    list[#list + 1] = entry
    while #list > cap do
        table_remove(list, 1)
    end
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- Record one Lua error.
-- @param message string The error text the handler was given
-- @param stack string|nil The stack, captured by the caller. It has to be
--   taken in the error handler itself: read from in here it describes this
--   function and the pcall wrapping it, not where the error came from.
function Diagnostics:RecordError(message, stack)
    if not QR.db then return end
    self:Trace("lua-error", tostring(message), { stack = stack }, "ERROR")
    QR.db.errors = QR.db.errors or {}
    local text = tostring(message)
    -- Collapse a repeat rather than filling the buffer with one error.
    local last = QR.db.errors[#QR.db.errors]
    if last and last.message == text then
        last.count = (last.count or 1) + 1
        last.seen = date("%Y-%m-%d %H:%M:%S")
        return
    end
    push(QR.db.errors, {
        message = text,
        stack = stack,
        seen = date("%Y-%m-%d %H:%M:%S"),
        count = 1,
    }, MAX_ERRORS)
end

--- Record the outcome of one teleport-list rebuild.
-- The panel keeps its filtered result on itself, so this reads the counts after
-- the fact rather than reaching into RefreshList.
function Diagnostics:RecordRefresh()
    if not QR.db then return end
    QR.db.refreshes = QR.db.refreshes or {}
    local panel = QR.TeleportPanel
    local inv = QR.PlayerInventory
    push(QR.db.refreshes, {
        shown = panel and panel.sortedTeleports and #panel.sortedTeleports or 0,
        filter = (panel and panel.availabilityFilter)
            or (QR.db and QR.db.availabilityFilter) or "all",
        invItems = inv and Count(inv.teleportItems) or -1,
        invToys = inv and Count(inv.toys) or -1,
        invSpells = inv and Count(inv.spells) or -1,
        loading = (_G.LoadingScreenEnabled ~= nil) and tostring(_G.LoadingScreenEnabled) or nil,
        combat = InCombatLockdown and InCombatLockdown() or false,
        seen = date("%H:%M:%S"),
    }, MAX_REFRESHES)
end

function Diagnostics:Clear()
    if not QR.db then return end
    QR.db.errors = {}
    QR.db.refreshes = {}
    if QR.db.trace ~= nil then QR.db.trace = nil end
end

-------------------------------------------------------------------------------
-- Diagnostic trace
--
-- Opt-in (setting `diagnosticTrace`, default off). While on, every QR:Log line
-- and a set of structured entries -- window opens and closes with their
-- caller, waypoint triggers with the tracking state at that moment, quest/NPC
-- and travel events, asynchronous route calculations -- go into
-- QuickRouteDB.trace, a ring buffer that survives /reload and logout.
-- scripts/export_trace.py turns it into JSONL.
--
-- The buffer is written in place: `e` is indexed 1..cap, `first` is the oldest
-- entry and `n` the count. Shifting a list on every insert, as push() above
-- does, would move 20000 entries per line.
-------------------------------------------------------------------------------

Diagnostics.TRACE_VERSION = 1
Diagnostics.TRACE_CAP = 20000
-- A second bound, on the estimated serialized size, so a run of long entries
-- cannot grow the SavedVariables file past this however few entries it has.
Diagnostics.TRACE_MAX_BYTES = 6 * 1024 * 1024
-- QUEST_LOG_UPDATE and QUEST_POI_UPDATE fire in bursts; one entry per event
-- per this many seconds, and the next one let through says how many it hid.
Diagnostics.TRACE_THROTTLE_SECONDS = 2

local TRACE_MSG_MAX = 200
-- A waypoint entry carries up to 24 fields (tracking state, trigger, TomTom's
-- callback arguments); the cap leaves room above that.
local TRACE_FIELD_KEYS_MAX = 32
Diagnostics.TRACE_FIELD_KEYS_MAX = TRACE_FIELD_KEYS_MAX
local TRACE_FIELD_STR_MAX = 160
local TRACE_STACK_MAX = 400

local TRACE_EVENTS = {
    "QUEST_DETAIL", "QUEST_ACCEPTED", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_FINISHED", "QUEST_TURNED_IN", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE",
    "GOSSIP_SHOW", "GOSSIP_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED",
}
Diagnostics.TRACE_EVENTS = TRACE_EVENTS

local THROTTLED_EVENTS = { QUEST_LOG_UPDATE = true, QUEST_POI_UPDATE = true }

-- Events whose dialog belongs to an NPC: the NPC's name and ID are read for them.
local NPC_EVENTS = {
    QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
    GOSSIP_SHOW = true, MERCHANT_SHOW = true, TAXIMAP_OPENED = true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
}

local function Truncate(s, max)
    s = tostring(s)
    if #s > max then return s:sub(1, max) end
    return s
end

local function Round(n, places)
    local m = 10 ^ places
    return math.floor(n * m + 0.5) / m
end

--- Copy the scalar fields of a table, bounded in key count and string length.
local function SanitizeFields(fields)
    if type(fields) ~= "table" then return nil end
    local out, count = {}, 0
    for k, v in pairs(fields) do
        if count >= TRACE_FIELD_KEYS_MAX then
            out._truncated = true
            break
        end
        local tk, tv = type(k), type(v)
        if tk == "string" or tk == "number" then
            if tv == "string" then
                out[k] = Truncate(v, k == "stack" and TRACE_STACK_MAX or TRACE_FIELD_STR_MAX)
                count = count + 1
            elseif tv == "number" then
                if v == v and v ~= math.huge and v ~= -math.huge then
                    out[k] = v
                    count = count + 1
                end
            elseif tv == "boolean" then
                out[k] = v
                count = count + 1
            end
        end
    end
    if count == 0 and not out._truncated then return nil end
    return out
end

--- Rough serialized size of a value: the line WoW writes for it, plus the
-- key. Only used to bound the buffer; the measured size is in AGENTS.md.
local function ValueSize(v)
    local t = type(v)
    if t == "string" then return #v + 4 end
    if t == "table" then
        local size = 4
        for k, item in pairs(v) do
            size = size + #tostring(k) + 10 + ValueSize(item)
        end
        return size
    end
    return 20
end
Diagnostics.TraceEntrySize = ValueSize

local function NewStore(cap)
    return { v = Diagnostics.TRACE_VERSION, cap = cap, first = 1, n = 0, bytes = 0, dropped = 0, e = {} }
end

local function ValidStore(s)
    return type(s) == "table" and s.v == Diagnostics.TRACE_VERSION and type(s.e) == "table"
        and type(s.cap) == "number" and s.cap >= 1
        and type(s.first) == "number" and s.first >= 1 and s.first <= s.cap
        and type(s.n) == "number" and s.n >= 0 and s.n <= s.cap
end

local function StoreEntries(s)
    local list = {}
    for i = 0, s.n - 1 do
        local entry = s.e[((s.first - 1 + i) % s.cap) + 1]
        if type(entry) == "table" then list[#list + 1] = entry end
    end
    return list
end

--- The trace store, created or repaired as needed. Only called while tracing,
-- so a player who never turns the setting on never gets a `trace` key.
function Diagnostics:GetTraceStore()
    local s = QR.db.trace
    if not ValidStore(s) then
        s = NewStore(self.TRACE_CAP)
        QR.db.trace = s
    elseif s.cap ~= self.TRACE_CAP then
        -- The cap changed between versions: keep the newest entries in order.
        local old = StoreEntries(s)
        local fresh = NewStore(self.TRACE_CAP)
        fresh.dropped = (tonumber(s.dropped) or 0) + math.max(0, #old - self.TRACE_CAP)
        fresh.client = s.client
        for i = math.max(1, #old - self.TRACE_CAP + 1), #old do
            fresh.e[fresh.n + 1] = old[i]
            fresh.n = fresh.n + 1
            fresh.bytes = fresh.bytes + ValueSize(old[i])
        end
        s = fresh
        QR.db.trace = s
    end
    if type(s.bytes) ~= "number" then
        s.bytes = 0
        for _, entry in ipairs(StoreEntries(s)) do s.bytes = s.bytes + ValueSize(entry) end
    end
    return s
end

local function Push(s, entry)
    local size = ValueSize(entry)
    while s.n > 0 and (s.n >= s.cap or s.bytes + size > Diagnostics.TRACE_MAX_BYTES) do
        local old = s.e[s.first]
        s.e[s.first] = nil
        s.bytes = s.bytes - (old and ValueSize(old) or 0)
        s.first = (s.first % s.cap) + 1
        s.n = s.n - 1
        s.dropped = (tonumber(s.dropped) or 0) + 1
    end
    s.e[((s.first - 1 + s.n) % s.cap) + 1] = entry
    s.n = s.n + 1
    s.bytes = s.bytes + size
    -- Entries written since this login or /reload: what a reload would save.
    Diagnostics.unsavedTrace = (Diagnostics.unsavedTrace or 0) + 1
end

--- Trace entries in chronological order (empty when there are none).
function Diagnostics:GetTraceEntries()
    if not (QR.db and ValidStore(QR.db.trace)) then return {} end
    return StoreEntries(QR.db.trace)
end

function Diagnostics:IsTracing()
    return QR.db ~= nil and QR.db.diagnosticTrace == true
end

local function PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local x, y
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
        end
    end
    return mapID, x, y
end

local function OnTaxi()
    return (UnitOnTaxi and UnitOnTaxi("player")) and true or false
end

local function MakeEntry(level, category, message, fields)
    local entry = {
        t = time and time() or nil,
        g = GetTime and Round(GetTime(), 3) or nil,
        l = level,
        c = category,
        m = Truncate(message or "", TRACE_MSG_MAX),
        f = SanitizeFields(fields),
    }
    local ok, mapID, x, y = pcall(PlayerPosition)
    if ok and mapID then
        entry.map = mapID
        if type(x) == "number" and type(y) == "number" then
            entry.x, entry.y = Round(x, 4), Round(y, 4)
        end
    end
    if InCombatLockdown and InCombatLockdown() then entry.cb = true end
    return entry
end

local function TraceUnsafe(self, category, message, fields, level)
    local store = self:GetTraceStore()
    -- Taxi state has no event of its own on every client, so each entry
    -- compares it with the last one and records the transition first.
    local taxi = OnTaxi()
    if self._lastTaxi ~= nil and taxi ~= self._lastTaxi then
        Push(store, MakeEntry("INFO", "taxi", taxi and "taxi started" or "taxi ended",
            { onTaxi = taxi }))
    end
    self._lastTaxi = taxi
    Push(store, MakeEntry(level or "INFO", category or "misc", message, fields))
end

--- Add one entry to the trace when the setting is on; a no-op otherwise.
-- Never calls QR:Log, so QR:Log can forward here without recursion.
-- @param category string e.g. "window", "waypoint", "event", "route", "log"
-- @param message string Short prose, truncated to 200 characters
-- @param fields table|nil Scalar fields, at most 32, strings to 160 characters
-- @param level string|nil "INFO" (default), "WARN", "ERROR", "DEBUG"
function Diagnostics:Trace(category, message, fields, level)
    if not self:IsTracing() or self._inTrace then return end
    self._inTrace = true
    local ok, err = pcall(TraceUnsafe, self, category, message, fields, level)
    self._inTrace = false
    if not ok then self.lastTraceError = tostring(err) end
end

local function TrimStack(stack)
    if type(stack) ~= "string" then return nil end
    stack = stack:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%s*\n%s*", " | "):gsub(" | $", "")
    return Truncate(stack, TRACE_STACK_MAX)
end
Diagnostics.TrimStack = TrimStack

--- Trace a window action with its reason and the Lua stack that led to it.
-- @param action string "show", "hide", "toggle", "switch", "onhide"
-- @param tab string|nil Requested tab
-- @param reason string|nil Who asked; nil is stored as "unspecified"
-- @param extra table|nil More fields
function Diagnostics:TraceWindow(action, tab, reason, extra)
    if not self:IsTracing() then return end
    local mf = QR.MainFrame
    local fields = {
        action = action,
        tab = tab,
        reason = reason or "unspecified",
        wasShowing = mf and mf.isShowing or false,
        activeTab = mf and mf.activeTab,
        closeCount = mf and mf.closeCount,
        -- From TraceWindow outwards; the frames after the MainFrame method
        -- name the caller.
        stack = TrimStack(debugstack and debugstack(2, 7, 0) or nil),
    }
    for k, v in pairs(extra or {}) do fields[k] = v end
    self:Trace("window", action .. " " .. tostring(tab or "-") .. " (" .. fields.reason .. ")", fields)
end

--- Client identification, kept in the store and in each session entry so the
-- exporter can tell a retail trace from a Forever one.
function Diagnostics:ClientInfo()
    local version, build, _, interface
    if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
    return {
        flavor = QR.IsForever and "forever" or "retail",
        project = WOW_PROJECT_ID,
        interface = interface,
        build = build,
        clientVersion = version,
        addonVersion = QR.version,
    }
end

local function NpcFields(fields)
    if UnitName then
        local name = UnitName("npc")
        if name then fields.npc = name end
    end
    if UnitGUID then
        local guid = UnitGUID("npc")
        if type(guid) == "string" then
            local npcID = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
            if npcID then fields.npcID = tonumber(npcID) end
        end
    end
end

function Diagnostics:OnTraceEvent(event, ...)
    if not self:IsTracing() then return end
    local now = GetTime and GetTime() or 0
    local fields = {}
    if THROTTLED_EVENTS[event] then
        self._throttle = self._throttle or {}
        local slot = self._throttle[event]
        if not slot then
            slot = { last = nil, dropped = 0 }
            self._throttle[event] = slot
        end
        if slot.last and now - slot.last < self.TRACE_THROTTLE_SECONDS then
            slot.dropped = slot.dropped + 1
            return
        end
        if slot.dropped > 0 then fields.dropped = slot.dropped end
        slot.last, slot.dropped = now, 0
    end
    for i = 1, math.min(select("#", ...), 4) do
        local v = select(i, ...)
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then
            fields["a" .. i] = v
        elseif v ~= nil then
            fields["a" .. i] = tv
        end
    end
    if NPC_EVENTS[event] then pcall(NpcFields, fields) end
    if event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        if GetQuestID then
            local ok, questID = pcall(GetQuestID)
            if ok and questID and questID ~= 0 then fields.questID = questID end
        end
    end
    if event == "SUPER_TRACKING_CHANGED" and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok then fields.superQuestID = questID end
    end
    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if GetZoneText then fields.zone = GetZoneText() end
        if GetSubZoneText then fields.subzone = GetSubZoneText() end
    end
    self:Trace("event", event, fields)
end

--- Register or unregister the trace events to match the setting.
-- RegisterEvent raises on an event the client does not know, and the two
-- clients do not know the same ones, so each registration is guarded and the
-- names that failed are recorded in the session entry.
function Diagnostics:ApplyTraceSetting()
    if not CreateFrame then return end
    if not self.traceFrame then
        self.traceFrame = CreateFrame("Frame")
        self.traceFrame:SetScript("OnEvent", function(_, event, ...)
            local ok, err = pcall(Diagnostics.OnTraceEvent, Diagnostics, event, ...)
            if not ok then Diagnostics.lastTraceError = tostring(err) end
        end)
    end
    local frame = self.traceFrame
    frame:UnregisterAllEvents()
    self.traceEventsRegistered = false
    if not self:IsTracing() then return end

    local failed = {}
    for _, event in ipairs(TRACE_EVENTS) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then failed[#failed + 1] = event end
    end
    self.traceEventsRegistered = true
    self._lastTaxi = nil
    self._throttle = {}

    local store = self:GetTraceStore()
    local client = self:ClientInfo()
    store.client = client
    local fields = {}
    for k, v in pairs(client) do fields[k] = v end
    fields.unregistered = #failed > 0 and table_concat(failed, ",") or nil
    fields.cap = self.TRACE_CAP
    self:Trace("session", "trace started", fields)
end

function Diagnostics:Render()
    local lines = { "## QuickRoute Diagnostics", "" }
    local errors = (QR.db and QR.db.errors) or {}
    lines[#lines + 1] = string_format("### Errors (%d)", #errors)
    lines[#lines + 1] = ""
    for _, e in ipairs(errors) do
        lines[#lines + 1] = string_format("- `%s` x%d — %s",
            tostring(e.message), e.count or 1, tostring(e.seen))
    end
    if #errors == 0 then lines[#lines + 1] = "  (none)" end

    local refreshes = (QR.db and QR.db.refreshes) or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = string_format("### Teleport list rebuilds (%d)", #refreshes)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| time | shown | filter | items | toys | spells | combat |"
    lines[#lines + 1] = "|---|---|---|---|---|---|---|"
    for _, r in ipairs(refreshes) do
        lines[#lines + 1] = string_format("| %s | %d | %s | %d | %d | %d | %s |",
            tostring(r.seen), r.shown or 0, tostring(r.filter),
            r.invItems or -1, r.invToys or -1, r.invSpells or -1,
            tostring(r.combat))
    end

    local trace = self:GetTraceEntries()
    lines[#lines + 1] = ""
    lines[#lines + 1] = string_format("### Diagnostic trace: %s, %d entries",
        self:IsTracing() and "on" or "off", #trace)
    return table_concat(lines, "\n")
end

function Diagnostics:Initialize()
    if QR.db then
        QR.db.errors = QR.db.errors or {}
        QR.db.refreshes = QR.db.refreshes or {}
    end

    -- Chain rather than replace: whatever was handling errors keeps handling
    -- them, including the default frame the player sees.
    if seterrorhandler and geterrorhandler and not self.errorHandlerInstalled then
        local previous = geterrorhandler()
        seterrorhandler(function(err)
            -- Captured here, where the erroring frames are still on the stack.
            local stack = debugstack and debugstack(2, 12, 0) or nil
            pcall(function() Diagnostics:RecordError(err, stack) end)
            if previous then return previous(err) end
        end)
        self.errorHandlerInstalled = true
    end

    -- A post-hook, so a rebuild is recorded even when it is the one that ends
    -- up drawing nothing.
    if hooksecurefunc and QR.TeleportPanel and not self.refreshHookInstalled then
        hooksecurefunc(QR.TeleportPanel, "RefreshList", function()
            pcall(function() Diagnostics:RecordRefresh() end)
        end)
        self.refreshHookInstalled = true
    end

    self:ApplyTraceSetting()
    self.Reminder:Initialize()

    QR:Debug("Diagnostics initialized")
end

-------------------------------------------------------------------------------
-- Save reminder
--
-- WoW writes SavedVariables only on /reload or logout, so a crash or a
-- disconnect loses whatever the diagnostic trace and the zone survey recorded
-- since. While either is on and something is unsaved, a small window offers a
-- reload every `saveReminderMinutes`, never at a moment where a reload would
-- cost the player something (combat, a taxi, a loading screen, an instance or
-- encounter, a secure button QuickRoute still has to release). A reminder that
-- falls due at such a moment waits for the next check: every
-- REMINDER_CHECK_SECONDS, and at once when combat ends, a loading screen
-- finishes or the player regains control.
-------------------------------------------------------------------------------

local Reminder = {
    sinceLast = 0,       -- seconds since login, the last reminder or its close
    checkElapsed = 0,
    due = false,         -- due, but the last check found an unsafe moment
    loading = false,
}
Diagnostics.Reminder = Reminder
Diagnostics.REMINDER_CHECK_SECONDS = 5
local REMINDER_WIDTH = 400
local REMINDER_PAD = 12
local REMINDER_BAR_HEIGHT = 6

--- Whether reminders apply now: the setting is on and something records.
function Reminder:Active()
    local db = QR.db
    if not db or db.saveReminder == false then return false end
    return db.diagnosticTrace == true or db.zoneSurveyEnabled == true
end

function Reminder:IntervalSeconds()
    return ((QR.db and tonumber(QR.db.saveReminderMinutes)) or 20) * 60
end

function Reminder:TimeoutSeconds()
    return (QR.db and tonumber(QR.db.saveReminderTimeout)) or 30
end

--- Unsaved counts of the recorders that are on.
-- @return number total, number traceEntries, number surveyCaptures, number surveyCrossings
function Reminder:Unsaved()
    local db = QR.db or {}
    local trace = db.diagnosticTrace == true and (Diagnostics.unsavedTrace or 0) or 0
    local survey = QR.ZoneSurvey
    local captures, crossings = 0, 0
    if db.zoneSurveyEnabled == true and survey then
        captures = survey.unsavedCaptures or 0
        crossings = survey.unsavedCrossings or 0
    end
    return trace + captures, trace, captures, crossings
end

--- Fill level of the trace buffer: the higher of entries/cap and bytes/byte cap.
-- @return number percent (0-100), number n, number bytes
function Reminder:TraceFill()
    local store = QR.db and QR.db.trace
    if not ValidStore(store) then return 0, 0, 0 end
    local byEntries = store.n / Diagnostics.TRACE_CAP
    local byBytes = (tonumber(store.bytes) or 0) / Diagnostics.TRACE_MAX_BYTES
    local fill = math.min(1, math.max(byEntries, byBytes))
    return math.floor(fill * 100 + 0.5), store.n, tonumber(store.bytes) or 0
end

--- Whether a reload now would cost the player nothing.
-- @return boolean safe, string|nil the reason it is not
function Reminder:IsSafeMoment()
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false, "combat" end
    if UnitOnTaxi then
        local ok, onTaxi = pcall(UnitOnTaxi, "player")
        -- A state the client will not tell is treated as a taxi: wait.
        if not ok or (issecretvalue and issecretvalue(onTaxi)) or onTaxi then return false, "taxi" end
    end
    if self.loading then return false, "loading" end
    if IsInInstance then
        local ok, inInstance = pcall(IsInInstance)
        if not ok or inInstance then return false, "instance" end
    end
    if IsEncounterInProgress and IsEncounterInProgress() then return false, "encounter" end
    local secure = QR.SecureButtons
    if secure and secure.pendingReleases and #secure.pendingReleases > 0 then
        return false, "secure-pending"
    end
    return true, nil
end

local function SetLine(fs, text, color)
    fs:SetText(text or "")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

--- Build the window once; the text is filled in by Populate on every show.
function Reminder:CreatePopup()
    if self.popup then return self.popup end
    local L = QR.L
    local frame = QR.CreateStandardWindow({
        name = "QuickRouteSaveReminder",
        title = L["SAVE_REMINDER_TITLE"],
        width = REMINDER_WIDTH,
        height = 200,
        defaultPoint = "TOP",
        defaultY = -120,
        onClose = function() Reminder:Close("close") end,
        -- ESC hides the window without the close button: the interval counts
        -- from that close too. (Combat hides it as well; OnCombatEnter marks
        -- it owed again after the hide.)
        onHide = function() Reminder.sinceLast = 0 end,
    })
    local inner = REMINDER_WIDTH - 2 * REMINDER_PAD
    frame.lines = {}
    for _, key in ipairs({ "active", "why", "unsaved", "fill", "fillDetail", "fullNote", "survey" }) do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWidth(inner)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        frame.lines[key] = fs
    end
    local barBg = frame:CreateTexture(nil, "ARTWORK")
    barBg:SetColorTexture(0.2, 0.2, 0.22, 1)
    barBg:SetSize(inner, REMINDER_BAR_HEIGHT)
    local bar = frame:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(QR.Colors.BRAND_R, QR.Colors.BRAND_G, QR.Colors.BRAND_B, QR.Colors.BRAND_A)
    bar:SetHeight(REMINDER_BAR_HEIGHT)
    frame.barBg, frame.bar = barBg, bar

    local reload = QR.CreateModernButton(frame, 130, 22)
    reload:SetText(L["SAVE_REMINDER_RELOAD"])
    reload:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Reminder:OnReloadClick()
    end)
    local close = QR.CreateModernButton(frame, 100, 22)
    close:SetText(L["SAVE_REMINDER_CLOSE"])
    close:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        Reminder:Close("close")
    end)
    frame.reloadButton, frame.dismissButton = reload, close

    -- Hovering or dragging is interaction: the timeout waits for it.
    if frame.HookScript then
        frame:HookScript("OnEnter", function() frame.hovered = true end)
        frame:HookScript("OnLeave", function() frame.hovered = false end)
    end
    frame:SetScript("OnUpdate", function(self, elapsed)
        if self.hovered or (self.IsMouseOver and self:IsMouseOver()) then return end
        self.shownFor = (self.shownFor or 0) + elapsed
        if self.shownFor >= Reminder:TimeoutSeconds() then
            Reminder:Close("timeout")
        end
    end)
    self.popup = frame
    return frame
end

--- Fill the window with the current counts and size it to its text.
function Reminder:Populate()
    local frame = self:CreatePopup()
    local L = QR.L
    local db = QR.db or {}
    local names = {}
    if db.diagnosticTrace == true then names[#names + 1] = L["SAVE_REMINDER_TRACE_NAME"] end
    if db.zoneSurveyEnabled == true then names[#names + 1] = L["SAVE_REMINDER_SURVEY_NAME"] end
    local total, _, _, crossings = self:Unsaved()
    local lines = frame.lines
    frame.titleText:SetText(L["SAVE_REMINDER_TITLE"])
    SetLine(lines.active, string_format(L["SAVE_REMINDER_ACTIVE"], table_concat(names, " + ")))
    SetLine(lines.why, L["SAVE_REMINDER_WHY"], { 0.8, 0.8, 0.8 })
    SetLine(lines.unsaved, string_format(L["SAVE_REMINDER_UNSAVED"], total), { 1, 0.82, 0 })

    local showTrace = db.diagnosticTrace == true
    local percent, n, bytes = self:TraceFill()
    SetLine(lines.fill, showTrace and string_format(L["SAVE_REMINDER_TRACE_FILL"], percent) or "")
    SetLine(lines.fillDetail, showTrace and string_format(L["SAVE_REMINDER_TRACE_FILL_DETAIL"],
        n, Diagnostics.TRACE_CAP, math.floor(bytes / 1024 + 0.5),
        math.floor(Diagnostics.TRACE_MAX_BYTES / 1024 + 0.5)) or "", { 0.8, 0.8, 0.8 })
    SetLine(lines.fullNote, showTrace and L["SAVE_REMINDER_TRACE_FULL_NOTE"] or "", { 0.8, 0.8, 0.8 })
    SetLine(lines.survey, db.zoneSurveyEnabled == true
        and string_format(L["SAVE_REMINDER_SURVEY_NEW"], crossings) or "")

    -- Stack the lines from the top; empty ones take no room.
    local inner = REMINDER_WIDTH - 2 * REMINDER_PAD
    local y = -36
    local order = { "active", "why", "unsaved", "fill", "bar", "fillDetail", "fullNote", "survey" }
    for _, key in ipairs(order) do
        if key == "bar" then
            frame.barBg:ClearAllPoints()
            frame.bar:ClearAllPoints()
            frame.barBg:SetShown(showTrace)
            frame.bar:SetShown(showTrace)
            if showTrace then
                frame.barBg:SetPoint("TOPLEFT", frame, "TOPLEFT", REMINDER_PAD, y)
                frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", REMINDER_PAD, y)
                frame.barWidth = math.max(1, inner * percent / 100)
                frame.bar:SetWidth(frame.barWidth)
                y = y - REMINDER_BAR_HEIGHT - 4
            end
        else
            local fs = lines[key]
            fs:ClearAllPoints()
            local text = fs:GetText() or ""
            fs:SetShown(text ~= "")
            if text ~= "" then
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", REMINDER_PAD, y)
                y = y - (fs:GetStringHeight() or 12) - 4
            end
        end
    end
    -- Buttons sized to their label, so a long translation is not cut.
    local reload, close = frame.reloadButton, frame.dismissButton
    for _, button in ipairs({ reload, close }) do
        local label = button.GetFontString and button:GetFontString()
        local width = label and label.GetStringWidth and label:GetStringWidth() or 0
        button:SetWidth(math.max(100, width + 24))
    end
    y = y - 6
    reload:ClearAllPoints()
    reload:SetPoint("TOPLEFT", frame, "TOPLEFT", REMINDER_PAD, y)
    close:ClearAllPoints()
    close:SetPoint("LEFT", reload, "RIGHT", 8, 0)
    frame:SetHeight(-y + 22 + REMINDER_PAD)
    return frame
end

function Reminder:ShowPopup()
    local frame = self:Populate()
    frame.shownFor = 0
    frame.hovered = false
    frame:Show()
    local _, trace, captures, crossings = self:Unsaved()
    Diagnostics:Trace("reminder", "save reminder shown",
        { trace = trace, captures = captures, crossings = crossings })
end

--- Close or time out: the next reminder comes a full interval later.
function Reminder:Close(reason)
    if self.popup then self.popup:Hide() end
    self.sinceLast = 0
    self.due = false
    Diagnostics:Trace("reminder", "save reminder " .. tostring(reason))
end

--- The reload button. A hardware click, so the reload is allowed; combat is
-- checked again because the window may have stayed open into a fight.
function Reminder:OnReloadClick()
    if (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        QR:Print(QR.L["SAVE_REMINDER_IN_COMBAT"])
        return false
    end
    local reload = (C_UI and C_UI.Reload) or ReloadUI
    if not reload then return false end
    Diagnostics:Trace("reminder", "save reminder: reload")
    reload()
    return true
end

--- Show the reminder if it is due, something is unsaved and the moment is safe.
-- @return boolean shown, string|nil why not
function Reminder:Check()
    if not self:Active() then return false, "inactive" end
    if self.popup and self.popup:IsShown() then return false, "shown" end
    if not self.due and self.sinceLast < self:IntervalSeconds() then return false, "not-due" end
    if self:Unsaved() <= 0 then return false, "nothing-unsaved" end
    local safe, why = self:IsSafeMoment()
    if not safe then
        self.due = true
        return false, why
    end
    self.due = false
    self.sinceLast = 0
    self:ShowPopup()
    return true
end

function Reminder:OnTick(elapsed)
    if not self:Active() then return end
    self.sinceLast = self.sinceLast + elapsed
    self.checkElapsed = self.checkElapsed + elapsed
    if self.checkElapsed < Diagnostics.REMINDER_CHECK_SECONDS then return end
    self.checkElapsed = 0
    self:Check()
end

function Reminder:Initialize()
    if self.ticker or not CreateFrame then return end
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed) Reminder:OnTick(elapsed) end)
    for _, event in ipairs({ "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
        "PLAYER_CONTROL_GAINED", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(ticker.RegisterEvent, ticker, event)
    end
    ticker:SetScript("OnEvent", function(_, event)
        if event == "LOADING_SCREEN_ENABLED" then
            Reminder.loading = true
            return
        end
        if event == "LOADING_SCREEN_DISABLED" then Reminder.loading = false end
        if Reminder.due then Reminder:Check() end
    end)
    self.ticker = ticker
    if QR.RegisterCombatCallback then
        QR:RegisterCombatCallback(function() Reminder:OnCombatEnter() end,
            function() Reminder:OnCombatLeave() end)
    end
end

--- Never on screen in a fight; owed again once it ends.
function Reminder:OnCombatEnter()
    if self.popup and self.popup:IsShown() then
        self.popup:Hide()
        self.due = true
    end
end

function Reminder:OnCombatLeave()
    if self.due then self:Check() end
end

SLASH_QRDIAG1 = "/qrdiag"
SlashCmdList["QRDIAG"] = function(msg)
    local cmd = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "clear" then
        Diagnostics:Clear()
        QR:Print("Diagnostics cleared.")
        return
    end
    local report = Diagnostics:Render()
    QR:Print(string_format("Diagnostics: %d error(s), %d rebuild(s).",
        #((QR.db and QR.db.errors) or {}), #((QR.db and QR.db.refreshes) or {})))
    if QR.UI and QR.UI.CopyDebugToClipboard then
        QR.UI:CopyDebugToClipboard()
        if QR.UI.copyFrame and QR.UI.copyFrame.editBox then
            QR.UI.copyFrame.editBox:SetText(report)
            QR.UI.copyFrame.editBox:HighlightText()
        end
    end
end
