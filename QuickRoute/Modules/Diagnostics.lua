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

    QR:Debug("Diagnostics initialized")
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
