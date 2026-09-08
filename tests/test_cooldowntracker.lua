-------------------------------------------------------------------------------
-- test_cooldowntracker.lua
-- Tests for QR.CooldownTracker module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.itemCooldowns = {}
    MockWoW.config.spellCooldowns = {}
end

-------------------------------------------------------------------------------
-- 1. FormatTime
-------------------------------------------------------------------------------

T:run("FormatTime: 0 seconds returns Ready", function(t)
    t:assertEqual(QR.L["STATUS_READY"], QR.CooldownTracker:FormatTime(0))
end)

T:run("FormatTime: negative returns Ready", function(t)
    t:assertEqual(QR.L["STATUS_READY"], QR.CooldownTracker:FormatTime(-5))
end)

T:run("FormatTime: nil returns Ready", function(t)
    t:assertEqual(QR.L["STATUS_READY"], QR.CooldownTracker:FormatTime(nil))
end)

T:run("FormatTime: seconds only", function(t)
    t:assertEqual("30s", QR.CooldownTracker:FormatTime(30))
    t:assertEqual("1s", QR.CooldownTracker:FormatTime(1))
    t:assertEqual("59s", QR.CooldownTracker:FormatTime(59))
end)

T:run("FormatTime: minutes and seconds", function(t)
    t:assertEqual("1m 0s", QR.CooldownTracker:FormatTime(60))
    t:assertEqual("5m 0s", QR.CooldownTracker:FormatTime(300))
    t:assertEqual("2m 30s", QR.CooldownTracker:FormatTime(150))
    t:assertEqual("59m 59s", QR.CooldownTracker:FormatTime(3599))
end)

T:run("FormatTime: hours and minutes", function(t)
    t:assertEqual("1h 0m", QR.CooldownTracker:FormatTime(3600))
    t:assertEqual("1h 30m", QR.CooldownTracker:FormatTime(5400))
    t:assertEqual("2h 0m", QR.CooldownTracker:FormatTime(7200))
    t:assertEqual("24h 0m", QR.CooldownTracker:FormatTime(86400))
end)

T:run("FormatTime: fractional seconds are floored", function(t)
    t:assertEqual("30s", QR.CooldownTracker:FormatTime(30.9))
    t:assertEqual("1m 0s", QR.CooldownTracker:FormatTime(60.5))
end)

-------------------------------------------------------------------------------
-- 2. GetItemCooldown
-------------------------------------------------------------------------------

T:run("GetItemCooldown: item with no cooldown returns ready", function(t)
    resetState()
    local result = QR.CooldownTracker:GetItemCooldown(12345)
    t:assertTrue(result.ready, "Item with no cooldown is ready")
    t:assertEqual(0, result.remaining, "Remaining is 0")
end)

T:run("GetItemCooldown: item on cooldown returns not ready", function(t)
    resetState()
    -- Set item 12345 with 30s cooldown started 10s ago
    MockWoW.config.baseTime = 1000010
    MockWoW.config.itemCooldowns[12345] = { start = 1000000, duration = 30, enable = 1 }
    local result = QR.CooldownTracker:GetItemCooldown(12345)
    t:assertFalse(result.ready, "Item on cooldown is not ready")
    t:assertGreaterThan(result.remaining, 0, "Remaining > 0")
end)

T:run("GetItemCooldown: expired cooldown returns ready", function(t)
    resetState()
    -- Cooldown started 60s ago, duration 30s -> expired
    MockWoW.config.baseTime = 1000060
    MockWoW.config.itemCooldowns[12345] = { start = 1000000, duration = 30, enable = 1 }
    local result = QR.CooldownTracker:GetItemCooldown(12345)
    t:assertTrue(result.ready, "Expired cooldown is ready")
    t:assertEqual(0, result.remaining, "Remaining is 0 for expired")
end)

-------------------------------------------------------------------------------
-- 3. GetSpellCooldown
-------------------------------------------------------------------------------

T:run("GetSpellCooldown: spell with no cooldown returns ready", function(t)
    resetState()
    local result = QR.CooldownTracker:GetSpellCooldown(54321)
    t:assertTrue(result.ready, "Spell with no cooldown is ready")
    t:assertEqual(0, result.remaining, "Remaining is 0")
end)

T:run("GetSpellCooldown: spell on cooldown returns not ready", function(t)
    resetState()
    MockWoW.config.baseTime = 1000010
    MockWoW.config.spellCooldowns[54321] = { start = 1000000, duration = 60, enable = 1 }
    local result = QR.CooldownTracker:GetSpellCooldown(54321)
    t:assertFalse(result.ready, "Spell on cooldown is not ready")
    t:assertGreaterThan(result.remaining, 0, "Remaining > 0")
end)

-------------------------------------------------------------------------------
-- 4. GetToyCooldown
-------------------------------------------------------------------------------

T:run("GetToyCooldown: delegates to GetItemCooldown", function(t)
    resetState()
    local result = QR.CooldownTracker:GetToyCooldown(140192)
    t:assertTrue(result.ready, "Toy with no cooldown is ready")
end)

-------------------------------------------------------------------------------
-- 5. GetCooldown dispatch
-------------------------------------------------------------------------------

T:run("GetCooldown: dispatches by sourceType", function(t)
    resetState()
    -- Set up different cooldowns for spell vs item
    MockWoW.config.baseTime = 1000010
    MockWoW.config.spellCooldowns[100] = { start = 1000000, duration = 60, enable = 1 }

    local spellResult = QR.CooldownTracker:GetCooldown(100, "spell")
    t:assertFalse(spellResult.ready, "Spell dispatch works")

    local itemResult = QR.CooldownTracker:GetCooldown(200, "item")
    t:assertTrue(itemResult.ready, "Item dispatch works")

    local toyResult = QR.CooldownTracker:GetCooldown(300, "toy")
    t:assertTrue(toyResult.ready, "Toy dispatch works")

    local equippedResult = QR.CooldownTracker:GetCooldown(400, "equipped")
    t:assertTrue(equippedResult.ready, "Equipped dispatch works")
end)

-------------------------------------------------------------------------------
-- 6. IsReady
-------------------------------------------------------------------------------

T:run("IsReady: returns true when off cooldown", function(t)
    resetState()
    t:assertTrue(QR.CooldownTracker:IsReady(12345, "item"), "Ready when no cooldown")
end)

T:run("IsReady: returns false when on cooldown", function(t)
    resetState()
    MockWoW.config.baseTime = 1000010
    MockWoW.config.itemCooldowns[12345] = { start = 1000000, duration = 30, enable = 1 }
    t:assertFalse(QR.CooldownTracker:IsReady(12345, "item"), "Not ready when on cooldown")
end)

-------------------------------------------------------------------------------
-- 7. GetTimeUntilReady
-------------------------------------------------------------------------------

T:run("GetTimeUntilReady: returns 0 when ready", function(t)
    resetState()
    t:assertEqual(0, QR.CooldownTracker:GetTimeUntilReady(12345, "item"), "0 when ready")
end)

T:run("GetTimeUntilReady: returns remaining seconds when on cooldown", function(t)
    resetState()
    MockWoW.config.baseTime = 1000010
    MockWoW.config.itemCooldowns[12345] = { start = 1000000, duration = 30, enable = 1 }
    local remaining = QR.CooldownTracker:GetTimeUntilReady(12345, "item")
    t:assertGreaterThan(remaining, 0, "Remaining > 0")
end)

-------------------------------------------------------------------------------
-- 3.5: Bulk Operations - GetAllCooldowns and GetReadyTeleports
-------------------------------------------------------------------------------

T:run("GetAllCooldowns: returns cooldown info for all player teleports", function(t)
    resetState()
    -- Give the player some teleport items
    MockWoW.config.knownSpells = { [53140] = true }  -- Teleport: Dalaran
    MockWoW.config.ownedToys = { [140192] = true }   -- Dalaran Hearthstone
    QR.PlayerInventory:ScanAll()

    -- Set one spell on cooldown
    MockWoW.config.baseTime = 1000010
    MockWoW.config.spellCooldowns[53140] = { start = 1000000, duration = 60, enable = 1 }

    local allCooldowns = QR.CooldownTracker:GetAllCooldowns()

    -- Should have entries for both the spell and toy
    t:assertNotNil(allCooldowns, "GetAllCooldowns returns a table")

    -- Count entries
    local count = 0
    for _ in pairs(allCooldowns) do count = count + 1 end
    t:assertGreaterThan(count, 0, "GetAllCooldowns returns at least one entry")

    -- The spell should not be ready
    if allCooldowns[53140] then
        t:assertFalse(allCooldowns[53140].cooldown.ready,
            "Spell 53140 on cooldown shows not ready")
        t:assertGreaterThan(allCooldowns[53140].cooldown.remaining, 0,
            "Spell 53140 has remaining cooldown time")
        t:assertEqual("spell", allCooldowns[53140].sourceType,
            "Spell 53140 has correct sourceType")
    end

    -- The toy should be ready (no cooldown set)
    if allCooldowns[140192] then
        t:assertTrue(allCooldowns[140192].cooldown.ready,
            "Toy 140192 with no cooldown shows ready")
        t:assertEqual("toy", allCooldowns[140192].sourceType,
            "Toy 140192 has correct sourceType")
    end
end)

T:run("GetReadyTeleports: only returns teleports that are off cooldown", function(t)
    resetState()
    -- Give the player a spell and a toy
    MockWoW.config.knownSpells = { [53140] = true }  -- Teleport: Dalaran
    MockWoW.config.ownedToys = { [140192] = true }   -- Dalaran Hearthstone
    QR.PlayerInventory:ScanAll()

    -- Put spell on cooldown, leave toy off cooldown
    MockWoW.config.baseTime = 1000010
    MockWoW.config.spellCooldowns[53140] = { start = 1000000, duration = 60, enable = 1 }

    local ready = QR.CooldownTracker:GetReadyTeleports()

    -- The on-cooldown spell should NOT be in ready list
    t:assertNil(ready[53140], "Spell on cooldown excluded from ready list")

    -- The toy should be in ready list
    t:assertNotNil(ready[140192], "Toy off cooldown included in ready list")
    if ready[140192] then
        t:assertTrue(ready[140192].cooldown.ready, "Ready teleport has ready=true")
    end
end)

T:run("GetReadyTeleports: returns all when nothing is on cooldown", function(t)
    resetState()
    MockWoW.config.knownSpells = { [53140] = true }
    MockWoW.config.ownedToys = { [140192] = true }
    QR.PlayerInventory:ScanAll()

    -- No cooldowns set
    MockWoW.config.spellCooldowns = {}
    MockWoW.config.itemCooldowns = {}

    local ready = QR.CooldownTracker:GetReadyTeleports()

    -- Both should be ready
    local readyCount = 0
    for _ in pairs(ready) do readyCount = readyCount + 1 end
    t:assertGreaterThan(readyCount, 0, "At least one ready teleport when no cooldowns")
end)

T:run("GetReadyTeleports: returns empty table when all on cooldown", function(t)
    resetState()
    -- Only give a single spell
    MockWoW.config.knownSpells = { [53140] = true }
    MockWoW.config.ownedToys = {}
    QR.PlayerInventory:ScanAll()

    -- Put it on a long cooldown
    MockWoW.config.baseTime = 1000010
    MockWoW.config.spellCooldowns[53140] = { start = 1000000, duration = 600, enable = 1 }

    local ready = QR.CooldownTracker:GetReadyTeleports()

    -- The spell should not be in the ready list
    t:assertNil(ready[53140], "Spell on cooldown not in ready list")
end)

-------------------------------------------------------------------------------
-- Batch memo
-------------------------------------------------------------------------------

--- Count the queries that reach the client, not the wrapper the memo sits in.
local function withCountedQueries(body)
    local CT = QR.CooldownTracker
    local realSpell, realItem = CT.GetSpellCooldown, CT.GetItemCooldown
    local queries = 0
    CT.GetSpellCooldown = function(self, ...) queries = queries + 1; return realSpell(self, ...) end
    CT.GetItemCooldown = function(self, ...) queries = queries + 1; return realItem(self, ...) end
    local ok, err = pcall(body, function() return queries end, function() queries = 0 end)
    CT.GetSpellCooldown, CT.GetItemCooldown = realSpell, realItem
    CT:EndBatch()
    if not ok then error(err, 0) end
end

T:run("Cooldown batch: one client query serves the whole batch", function(t)
    withCountedQueries(function(count, reset)
        local CT = QR.CooldownTracker
        CT:EndBatch()
        reset()
        for _ = 1, 5 do CT:GetCooldown(3561, "spell") end
        t:assertEqual(5, count(), "outside a batch every ask reaches the client")

        CT:BeginBatch()
        reset()
        for _ = 1, 5 do CT:GetCooldown(3561, "spell") end
        t:assertEqual(1, count(), "inside a batch the first answer serves the rest")
        CT:EndBatch()
    end)
end)

T:run("Cooldown batch: the memo does not outlive the batch", function(t)
    withCountedQueries(function(count, reset)
        local CT = QR.CooldownTracker
        CT:BeginBatch()
        CT:GetCooldown(3561, "spell")
        CT:EndBatch()
        reset()
        CT:GetCooldown(3561, "spell")
        t:assertEqual(1, count(), "after the batch the client is asked again")

        -- A batch abandoned half way must not answer later callers from memory:
        -- cooldowns are live state and the panels read them between refreshes.
        CT:BeginBatch()
        CT:GetCooldown(3561, "spell")
        CT:BeginBatch() -- a fresh refresh starts without the previous one ending
        reset()
        CT:GetCooldown(3561, "spell")
        t:assertEqual(1, count(), "reopening a batch starts from an empty memo")
        CT:EndBatch()
    end)
end)

T:run("Cooldown batch: entries are copies, not the shared result table", function(t)
    withCountedQueries(function()
        local CT = QR.CooldownTracker
        local savedCooldowns = MockWoW.config.spellCooldowns
        local savedTime = MockWoW.config.baseTime
        MockWoW.config.baseTime = 1000010
        MockWoW.config.spellCooldowns = {
            [3561] = nil,                                          -- ready
            [53140] = { start = 1000000, duration = 600, enable = 1 }, -- on cooldown
        }

        -- Every spell query returns ONE module-level table that the next query
        -- overwrites, so a memo of references would hand the second spell's
        -- answer back for the first id.
        CT:BeginBatch()
        local ready = CT:GetCooldown(3561, "spell")
        local onCooldown = CT:GetCooldown(53140, "spell")
        t:assertTrue(onCooldown.remaining > 0, "the second spell reads as on cooldown")
        t:assertEqual(0, ready.remaining, "and the first entry still describes the first spell")
        t:assertTrue(ready ~= onCooldown, "the two ids do not share one table")
        CT:EndBatch()

        MockWoW.config.spellCooldowns = savedCooldowns
        MockWoW.config.baseTime = savedTime
    end)
end)
