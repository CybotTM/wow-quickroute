-- CooldownTracker.lua
-- Tracks cooldowns for teleport items, toys, and spells
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local math_floor = math.floor
local string_format = string.format
local table_insert = table.insert
local table_sort = table.sort

-- Pre-allocated result tables to avoid per-call garbage (single-threaded, safe to reuse).
-- WARNING: These tables are SHARED across all callers. Do NOT store references to the
-- returned table -- values are only valid until the next GetItemCooldown/GetSpellCooldown
-- call. Copy fields you need to keep: local remaining = cd.remaining
local itemCooldownResult = { ready = true, remaining = 0, start = 0, duration = 0 }
local spellCooldownResult = { ready = true, remaining = 0, start = 0, duration = 0 }

-------------------------------------------------------------------------------
-- CooldownTracker Module
-------------------------------------------------------------------------------
QR.CooldownTracker = {}

local CooldownTracker = QR.CooldownTracker

-- How long a refresh batch may hold remembered cooldowns before it is treated
-- as abandoned. A 25-quest refresh spends about 0.4s spread across frames.
local BATCH_MAX_SECONDS = 2

-------------------------------------------------------------------------------
-- Visible inventory/map views share one event observer and expiry timer.
-------------------------------------------------------------------------------

function CooldownTracker:HasActiveListeners()
    for _, listener in pairs(self.listeners or {}) do
        if listener.isActive() then return true end
    end
    return false
end

--- Refresh only when a known teleport's cooldown state changes. Frequent global
-- cooldown events must not rebuild every inventory row and secure overlay.
function CooldownTracker:RefreshWatchedCooldowns(force)
    if self.notifying or InCombatLockdown() then return end
    if not self:HasActiveListeners() then
        if self.expiryTimer then self.expiryTimer:Cancel() end
        self.expiryTimer, self.expiryDeadline = nil, nil
        return
    end

    local previous, snapshot = self.observedCooldowns, {}
    local changed, nearest = false, nil
    local now = GetTime()
    for id, entry in pairs(QR.PlayerInventory:GetAllTeleports()) do
        local cooldown = self:GetCooldown(id, entry.sourceType)
        -- Copy immediately: GetCooldown returns a shared result table.
        local ready, remaining = cooldown.ready, cooldown.remaining
        local deadline = not ready and remaining > 0 and (now + remaining) or nil
        local key = (entry.sourceType or "item") .. ":" .. id
        -- Rounding avoids refreshes from floating-point noise in remaining time.
        -- Unknown active timing still differs from a confirmed ready spell;
        -- it must refresh the view without scheduling a guessed expiry.
        snapshot[key] = deadline and math_floor(deadline * 10 + 0.5) or (not ready)
        if previous and previous[key] ~= snapshot[key] then changed = true end
        if deadline and (not nearest or deadline < nearest) then nearest = deadline end
    end
    for key in pairs(previous or {}) do
        if snapshot[key] == nil then changed = true end
    end
    self.observedCooldowns = snapshot

    if nearest ~= self.expiryDeadline then
        if self.expiryTimer then self.expiryTimer:Cancel() end
        self.expiryTimer, self.expiryDeadline = nil, nearest
        if nearest then
            self.expiryTimer = C_Timer.NewTimer(math.max(0.05, nearest - now + 0.05), function()
                -- Do not announce readiness if a timer is delivered prematurely.
                if GetTime() < nearest then return end
                self.expiryTimer, self.expiryDeadline = nil, nil
                self:RefreshWatchedCooldowns(false)
            end)
        end
    end

    if changed or force then
        self.notifying = true
        for _, listener in pairs(self.listeners) do
            if listener.isActive() then
                local ok, err = pcall(listener.callback)
                if not ok then QR:Error("Cooldown view refresh: " .. tostring(err)) end
            end
        end
        self.notifying = false
    end
end

--- Called when a view opens or is manually refreshed, to arm the nearest expiry.
function CooldownTracker:WatchActiveCooldowns()
    self:RefreshWatchedCooldowns(false)
end

--- Register one callback per view. No polling and no background inventory scans
-- while all views are hidden; one deferred query handles a burst of events.
function CooldownTracker:RegisterListener(owner, callback, isActive)
    self.listeners = self.listeners or {}
    self.listeners[owner] = { callback = callback, isActive = isActive }
    if self.eventFrame then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
        "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_ENABLED" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if InCombatLockdown() then return end
        if not self:HasActiveListeners() then return end
        if self.refreshTimer then self.refreshTimer:Cancel() end
        self.forceRefresh = self.forceRefresh or event == "PLAYER_REGEN_ENABLED"
        self.refreshTimer = C_Timer.NewTimer(0.15, function()
            self.refreshTimer = nil
            local force = self.forceRefresh
            self.forceRefresh = nil
            self:RefreshWatchedCooldowns(force)
        end)
    end)
    self.eventFrame = frame
end

-------------------------------------------------------------------------------
-- Cooldown Query Methods
-------------------------------------------------------------------------------

--- Get cooldown info for an item
-- Uses GetItemCooldown (global) as primary, C_Container.GetItemCooldown as fallback
-- @param itemID number The item ID to check
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
function CooldownTracker:GetItemCooldown(itemID)
    local start, duration
    if GetItemCooldown then
        start, duration = GetItemCooldown(itemID)
    elseif C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(itemID)
    end

    local remaining = 0
    local ready = true

    if start and start > 0 and duration and duration > 0 then
        remaining = (start + duration) - GetTime()
        if remaining < 0 then
            remaining = 0
        end
        ready = remaining <= 0
    end

    itemCooldownResult.ready = ready
    itemCooldownResult.remaining = remaining
    itemCooldownResult.start = start or 0
    itemCooldownResult.duration = duration or 0
    return itemCooldownResult
end

--- True when a value can be compared and used in arithmetic.
-- type() reports the real type of a 12.0+ "secret" value, so it is useless as a
-- guard on its own: a secret number passes type(v) == "number" and then raises
-- an immediate Lua error on the first comparison. issecretvalue is the
-- documented probe and is absent before 12.0, where no value is secret.
local function IsUsableNumber(value)
    if type(value) ~= "number" then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return value == value and value > -math.huge and value < math.huge
end

local function SpellCooldownResult(ready, remaining, start, duration)
    spellCooldownResult.ready = ready
    spellCooldownResult.remaining = remaining
    spellCooldownResult.start = start
    spellCooldownResult.duration = duration
    return spellCooldownResult
end

local function CallDurationMethod(object, name)
    local method = object[name]
    if type(method) == "function" then return method(object) end
end

local function ReadDurationNumber(object, name)
    local ok, value = pcall(CallDurationMethod, object, name)
    if ok and IsUsableNumber(value) then return value end
end

local function NumericSpellCooldown(start, duration)
    if not IsUsableNumber(start) or not IsUsableNumber(duration) then return nil end
    local remaining = 0
    if start > 0 and duration > 0 then remaining = math.max(0, start + duration - GetTime()) end
    return SpellCooldownResult(remaining == 0, remaining, start, duration)
end

--- Get cooldown info for a spell
-- Retail duration objects exclude the GCD without guessing from short times.
-- Public numeric metadata remains a fallback on older/restricted clients.
-- @param spellID number The spell ID to check
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
function CooldownTracker:GetSpellCooldown(spellID)
    -- GetRemainingDuration/GetStartTime/GetTotalDuration are documented native
    -- LuaDurationObject methods. Their results can be secret, and method calls
    -- can be restricted: inspect neither without the appropriate public guard.
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, object = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        if ok and not (issecretvalue and issecretvalue(object)) then
            -- A successful query with no active personal duration is ready,
            -- even if the general cooldown table currently describes the GCD.
            if object == nil then return SpellCooldownResult(true, 0, 0, 0) end
            if IsUsableNumber(object) then
                local remaining = math.max(0, object)
                return SpellCooldownResult(remaining == 0, remaining, 0, 0)
            end
            local remaining = ReadDurationNumber(object, "GetRemainingDuration")
            if remaining then
                local start = ReadDurationNumber(object, "GetStartTime") or 0
                local duration = ReadDurationNumber(object, "GetTotalDuration") or 0
                remaining = math.max(0, remaining)
                return SpellCooldownResult(remaining == 0, remaining, start, duration)
            end
        end
    end

    -- Do not infer GCD from duration <= 1.5s or read isOnGCD outside the
    -- documented SPELL_UPDATE_COOLDOWN event context. Short real cooldowns
    -- remain real cooldowns when the GCD-free duration API is unavailable.
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            local result = NumericSpellCooldown(info.startTime, info.duration)
            if result then return result end
        end
    end
    if GetSpellCooldown then
        local ok, start, duration = pcall(GetSpellCooldown, spellID)
        local result = ok and NumericSpellCooldown(start, duration)
        if result then return result end
    end
    -- Unreadable timing is not evidence that a teleport can be used.
    return SpellCooldownResult(false, 0, 0, 0)
end

--- Get cooldown info for a toy
-- Toys use the item cooldown API
-- @param itemID number The toy item ID to check
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
function CooldownTracker:GetToyCooldown(itemID)
    -- Toys use the same cooldown API as items
    return self:GetItemCooldown(itemID)
end

--- Get cooldown info for any teleport type
-- Dispatches to the correct method based on sourceType
-- @param id number The item or spell ID
-- @param sourceType string "item", "toy", "spell", or "equipped"
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
--- Reuse client answers about cooldowns until EndBatch.
-- A refresh computes one route per tracked quest, each on its own frame, and
-- every route prices every teleport it could take: measured at 2300 cooldown
-- queries for 92 distinct teleports in a single refresh of 25 quests. Inside a
-- batch that is the same question asked over and over within a fraction of a
-- second, so the first answer stands for all of them.
--
-- Scoped to a batch rather than to wall time on purpose. This is live state:
-- outside a batch every caller -- the panels, the filters, the readiness check
-- that decides whether a cooldown moved -- reads the client, and a memo with a
-- timer instead of a scope would answer them with its own last word and hide
-- the very change they exist to notice.
-- Opening is idempotent rather than counted: one refresh batch runs at a time,
-- and a batch left open by a cancelled refresh would otherwise go on answering
-- from stale memory. Opening always starts from an empty memo.
function CooldownTracker:BeginBatch()
    self.batchOpen = true
    self.batchStamp = GetTime and GetTime() or 0
    if self.batchMemo then wipe(self.batchMemo) end
end

--- End the batch opened by BeginBatch and drop what it remembered.
-- Safe to call when no batch is open, so a cancelled refresh can call it
-- unconditionally.
function CooldownTracker:EndBatch()
    self.batchOpen = false
    if self.batchMemo then wipe(self.batchMemo) end
end

--- Read the client rather than the memo, without discarding it.
-- For the one caller that has to see live state in the middle of somebody
-- else's batch: the readiness check that decides whether a cooldown moved. It
-- used to end the batch outright, which is correct but throws away the memo of
-- a refresh that is still running -- and SPELL_UPDATE_COOLDOWN fires on every
-- global cooldown, so that was the common case rather than the rare one.
-- @return boolean Whether a batch was open, to hand back to ResumeBatch
function CooldownTracker:SuspendBatch()
    local wasOpen = self.batchOpen or false
    self.batchOpen = false
    return wasOpen
end

--- Reopen a batch suspended by SuspendBatch, with its memo intact.
-- Only sound when the caller established that nothing it cares about moved --
-- otherwise the memo would answer the rest of the batch with the state from
-- before the change. EndBatch is the other exit, and it is the right one
-- whenever readiness did move.
-- @param wasOpen boolean The value SuspendBatch returned
function CooldownTracker:ResumeBatch(wasOpen)
    if wasOpen then self.batchOpen = true end
end

function CooldownTracker:GetCooldown(id, sourceType)
    -- A batch is closed on every path that leaves a refresh, but the tail of
    -- that refresh is not all inside a pcall: an error there would leave one
    -- open, and every panel and filter in the addon reads through here. The
    -- stamp bounds that to BATCH_MAX_SECONDS rather than to the next refresh.
    -- It is a backstop, not the scope -- the scope is the batch.
    if self.batchOpen and self.batchStamp
        and (GetTime and GetTime() or 0) - self.batchStamp > BATCH_MAX_SECONDS then
        self:EndBatch()
    end

    local memo, key
    if self.batchOpen then
        memo = self.batchMemo
        if not memo then memo = {}; self.batchMemo = memo end
        key = (sourceType or "item") .. ":" .. tostring(id)
        local entry = memo[key]
        if entry then return entry end
    end

    local result
    if sourceType == "spell" then
        result = self:GetSpellCooldown(id)
    elseif sourceType == "toy" then
        result = self:GetToyCooldown(id)
    else
        -- "item" or "equipped" both use item cooldown
        result = self:GetItemCooldown(id)
    end

    if not memo then return result end
    -- A copy, never the shared result table the queries above return: those are
    -- overwritten by the next query, so a memo of references would answer every
    -- id with whatever was asked last.
    local entry = {
        ready = result.ready,
        remaining = result.remaining,
        start = result.start,
        duration = result.duration,
    }
    memo[key] = entry
    return entry
end

--- Check if a teleport is ready (off cooldown)
-- @param id number The item or spell ID
-- @param sourceType string "item", "toy", "spell", or "equipped"
-- @return boolean True if ready (cooldown remaining <= 0)
function CooldownTracker:IsReady(id, sourceType)
    local cooldown = self:GetCooldown(id, sourceType)
    return cooldown.ready
end

--- Get seconds until a teleport is ready
-- @param id number The item or spell ID
-- @param sourceType string "item", "toy", "spell", or "equipped"
-- @return number Seconds until ready (0 if already ready)
function CooldownTracker:GetTimeUntilReady(id, sourceType)
    local cooldown = self:GetCooldown(id, sourceType)
    return cooldown.remaining
end

-------------------------------------------------------------------------------
-- Time Formatting
-------------------------------------------------------------------------------

--- Format seconds into human-readable time string
-- @param seconds number Time in seconds
-- @return string Formatted time string
function CooldownTracker:FormatTime(seconds)
    if not seconds or seconds <= 0 then
        return QR.L and QR.L["STATUS_READY"] or "Ready"
    end

    seconds = math_floor(seconds)

    if seconds < 60 then
        return string_format("%ds", seconds)
    elseif seconds < 3600 then
        local minutes = math_floor(seconds / 60)
        local secs = seconds % 60
        return string_format("%dm %ds", minutes, secs)
    else
        local hours = math_floor(seconds / 3600)
        local minutes = math_floor((seconds % 3600) / 60)
        return string_format("%dh %dm", hours, minutes)
    end
end

-------------------------------------------------------------------------------
-- Bulk Operations
-------------------------------------------------------------------------------

--- Get cooldown info for all available teleports
-- Calls PlayerInventory:GetAllTeleports() and adds cooldown info
-- @return table All teleports with cooldown info added
function CooldownTracker:GetAllCooldowns()
    local teleports = QR.PlayerInventory:GetAllTeleports()
    local result = {}

    for id, teleport in pairs(teleports) do
        local cd = self:GetCooldown(id, teleport.sourceType)
        -- Copy fields: cd is a reused module-level table, must snapshot values
        result[id] = {
            id = id,
            data = teleport.data,
            sourceType = teleport.sourceType,
            cooldown = {
                ready = cd.ready,
                remaining = cd.remaining,
                start = cd.start,
                duration = cd.duration,
            },
        }
    end

    return result
end

--- Get only teleports that are ready to use
-- @return table Teleports where IsReady is true
function CooldownTracker:GetReadyTeleports()
    local teleports = QR.PlayerInventory:GetAllTeleports()
    local ready = {}

    for id, teleport in pairs(teleports) do
        local cd = self:GetCooldown(id, teleport.sourceType)
        if cd.ready then
            -- Copy fields: cd is a reused module-level table, must snapshot values
            ready[id] = {
                id = id,
                data = teleport.data,
                sourceType = teleport.sourceType,
                cooldown = {
                    ready = cd.ready,
                    remaining = cd.remaining,
                    start = cd.start,
                    duration = cd.duration,
                },
            }
        end
    end

    return ready
end

-------------------------------------------------------------------------------
-- Debug/Display Methods
-------------------------------------------------------------------------------

--- Print formatted status of all teleport cooldowns
-- Uses WoW color codes: green=ready, red=on cooldown
function CooldownTracker:PrintStatus()
    print("|cFF00FF00QuickRoute|r: Teleport Cooldown Status")
    print("----------------------------------------")

    local teleports = QR.PlayerInventory:GetAllTeleports()
    local count = 0
    local readyCount = 0

    -- Sort entries by name for consistent display
    local sorted = {}
    for id, teleport in pairs(teleports) do
        table_insert(sorted, {id = id, teleport = teleport})
    end
    table_sort(sorted, function(a, b)
        return (a.teleport.data.name or "") < (b.teleport.data.name or "")
    end)

    for _, entry in ipairs(sorted) do
        local id = entry.id
        local teleport = entry.teleport
        local cooldown = self:GetCooldown(id, teleport.sourceType)
        local L = QR.L
        local name = teleport.data.name or ((L and L["UNKNOWN"] or "Unknown") .. " [" .. id .. "]")
        local destination = teleport.data.destination or (L and L["UNKNOWN"] or "Unknown")

        local statusColor, statusText
        if cooldown.ready then
            statusColor = "|cFF00FF00"  -- Green
            statusText = L and L["STATUS_READY"] or "Ready"
            readyCount = readyCount + 1
        else
            statusColor = "|cFFFF0000"  -- Red
            statusText = self:FormatTime(cooldown.remaining)
        end

        local typeLabel = string_format("|cFFAAAAAA[%s]|r", teleport.sourceType)
        print(string_format("  %s %s|r -> %s %s%s|r",
            typeLabel,
            name,
            destination,
            statusColor,
            statusText
        ))
        count = count + 1
    end

    print("----------------------------------------")
    print(string_format("|cFF00FF00Ready:|r %d/%d teleports available", readyCount, count))
end

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

SLASH_QRCD1 = "/qrcd"
SlashCmdList["QRCD"] = function(msg)
    -- Ensure inventory is up to date
    QR.PlayerInventory:ScanAll()
    CooldownTracker:PrintStatus()
end
