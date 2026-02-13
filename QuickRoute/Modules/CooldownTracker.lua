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

-------------------------------------------------------------------------------
-- Cooldown Query Methods
-------------------------------------------------------------------------------

--- Get cooldown info for an item
-- Uses GetItemCooldown (global) as primary, C_Container.GetItemCooldown as fallback
-- @param itemID number The item ID to check
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
function CooldownTracker:GetItemCooldown(itemID)
    local start, duration, enable
    if GetItemCooldown then
        start, duration, enable = GetItemCooldown(itemID)
    elseif C_Container and C_Container.GetItemCooldown then
        start, duration, enable = C_Container.GetItemCooldown(itemID)
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

--- Get cooldown info for a spell
-- Uses C_Spell.GetSpellCooldownDuration (12.0+), C_Spell.GetSpellCooldown (11.0+),
-- or GetSpellCooldown (legacy) to retrieve cooldown state.
-- @param spellID number The spell ID to check
-- @return table {ready=bool, remaining=seconds, start=number, duration=number}
function CooldownTracker:GetSpellCooldown(spellID)
    local start = 0
    local duration = 0
    local remaining = 0
    local ready = true

    -- 12.0+ DurationObject API (secret-value safe)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durationObj and type(durationObj) == "number" and durationObj > 0 then
            remaining = durationObj
            ready = false
        end
        spellCooldownResult.ready = ready
        spellCooldownResult.remaining = remaining
        spellCooldownResult.start = 0
        spellCooldownResult.duration = 0
        return spellCooldownResult
    end

    -- 11.0+ C_Spell.GetSpellCooldown
    if C_Spell and C_Spell.GetSpellCooldown then
        local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
        if cooldownInfo then
            start = cooldownInfo.startTime or 0
            duration = cooldownInfo.duration or 0

            -- Guard against Blizzard "secret" values that can't be compared numerically
            if type(start) ~= "number" then start = 0 end
            if type(duration) ~= "number" then duration = 0 end

            if start > 0 and duration > 0 then
                remaining = (start + duration) - GetTime()
                if remaining < 0 then remaining = 0 end
                ready = remaining <= 0
            end
        end
    elseif GetSpellCooldown then
        -- Legacy fallback (pre-11.0)
        local s, d, e = GetSpellCooldown(spellID)
        if s and s > 0 and d and d > 0 then
            start = s
            duration = d
            remaining = (s + d) - GetTime()
            if remaining < 0 then remaining = 0 end
            ready = remaining <= 0
        end
    end

    spellCooldownResult.ready = ready
    spellCooldownResult.remaining = remaining
    spellCooldownResult.start = start
    spellCooldownResult.duration = duration
    return spellCooldownResult
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
function CooldownTracker:GetCooldown(id, sourceType)
    if sourceType == "spell" then
        return self:GetSpellCooldown(id)
    elseif sourceType == "toy" then
        return self:GetToyCooldown(id)
    else
        -- "item" or "equipped" both use item cooldown
        return self:GetItemCooldown(id)
    end
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
