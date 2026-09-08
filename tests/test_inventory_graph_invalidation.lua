local T, QR, MockWoW = ...

local function withInventoryEvents(callback)
    local inv, calculator = QR.PlayerInventory, QR.PathCalculator
    local old = { scan = inv.ScanAll, get = inv.GetAllTeleports, pending = inv.pendingScan,
        changed = calculator.OnInventoryChanged, dirty = calculator.graphDirty,
        timer = C_Timer.NewTimer, db = QR.db, combat = MockWoW.config.inCombatLockdown }
    local data = { name = "Fixture teleport" }
    local current = { [6948] = { data = data, sourceType = "item", bagID = 0, slot = 1 } }
    local nextInventory, queued, scans, notifications = current, nil, 0, 0
    QR.db, inv.pendingScan, MockWoW.config.inCombatLockdown = {}, false, false
    inv.GetAllTeleports = function() return current end
    inv.ScanAll = function() scans = scans + 1; current = nextInventory end
    calculator.OnInventoryChanged = function(self) notifications = notifications + 1; self.graphDirty = true end
    C_Timer.NewTimer = function(_, fn)
        queued = fn
        return { Cancel = function() end }
    end
    local function flush()
        local fn = queued
        queued = nil
        if fn then fn() end
    end
    local fixture = {
        fire = function(event) inv.eventFrame:GetScript("OnEvent")(inv.eventFrame, event) end,
        flush = flush,
        replace = function(value) nextInventory = value end,
        counts = function() return scans, notifications end,
        data = data,
    }
    -- Other files can simulate an outstanding scan without running its timer.
    -- Drain one explicit forced batch so these cases begin with no queued work.
    fixture.fire("SPELLS_CHANGED")
    flush()
    scans, notifications = 0, 0
    calculator.graphDirty = false
    local ok, err = pcall(callback, fixture)
    flush()
    inv.ScanAll, inv.GetAllTeleports, inv.pendingScan = old.scan, old.get, old.pending
    calculator.OnInventoryChanged, calculator.graphDirty = old.changed, old.dirty
    C_Timer.NewTimer, QR.db, MockWoW.config.inCombatLockdown = old.timer, old.db, old.combat
    if not ok then error(err) end
end

T:run("Inventory events: ordinary loot still scans without invalidating identical travel options", function(t)
    withInventoryEvents(function(f)
        f.replace({ [6948] = { data = f.data, sourceType = "item", bagID = 0, slot = 1 } })
        for _ = 1, 3 do f.fire("BAG_UPDATE"); f.flush() end
        local scans, notifications = f.counts()
        t:assertEqual(3, scans, "All three loot batches still scan the inventory")
        t:assertEqual(0, notifications, "Identical teleport options do not rebuild the travel graph")
    end)
end)

T:run("Inventory events: adding and removing teleport items invalidate routes", function(t)
    withInventoryEvents(function(f)
        f.replace({})
        f.fire("BAG_UPDATE"); f.flush()
        local _, removed = f.counts()
        t:assertEqual(1, removed, "Removing the last teleport invalidates its route edge")
        f.replace({ [6948] = { data = f.data, sourceType = "item" } })
        f.fire("BAG_UPDATE"); f.flush()
        local _, added = f.counts()
        t:assertEqual(2, added, "Acquiring a teleport invalidates routes to add the new option")
    end)
end)

T:run("Inventory events: changed source and usability remain routing changes", function(t)
    withInventoryEvents(function(f)
        f.replace({ [6948] = { data = f.data, sourceType = "toy", isUsable = true } })
        f.fire("BAG_UPDATE"); f.flush()
        f.replace({ [6948] = { data = f.data, sourceType = "toy", isUsable = false } })
        f.fire("BAG_UPDATE"); f.flush()
        local _, notifications = f.counts()
        t:assertEqual(2, notifications, "Changed activation source and toy usability each invalidate routes")
    end)
end)

for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "TOYS_UPDATED", "SKILL_LINES_CHANGED" }) do
    T:run("Inventory events: coalesced " .. event .. " still invalidates unchanged teleports", function(t)
        withInventoryEvents(function(f)
            f.fire("BAG_UPDATE")
            f.fire(event)
            f.flush()
            local scans, notifications = f.counts()
            t:assertEqual(1, scans, "Coalesced events use one inventory scan")
            t:assertEqual(1, notifications, "Capability or equipment changes still invalidate routes")
            f.fire("BAG_UPDATE"); f.flush()
            local _, later = f.counts()
            t:assertEqual(1, later, "The forced refresh does not leak into the next ordinary loot batch")
        end)
    end)
end

-- The leave-combat callback normally runs the postponed scan. A reload or a
-- logout mid-fight ends the fight without PLAYER_REGEN_ENABLED reaching this
-- session, and the pending flag that coalesces a fight's events would then
-- suppress every later scan for good.
T:run("Inventory events: a deferred scan is not lost when leaving combat goes unseen", function(t)
    withInventoryEvents(function(f)
        MockWoW.config.inCombatLockdown = true
        f.fire("BAG_UPDATE"); f.flush()
        t:assertEqual(0, (f.counts()), "nothing scanned during the fight")

        -- No PLAYER_REGEN_ENABLED, no callback: just the next inventory event.
        MockWoW.config.inCombatLockdown = false
        f.replace({})
        f.fire("BAG_UPDATE"); f.flush()
        local scans, notifications = f.counts()
        t:assertTrue(scans > 0, "the next event out of combat settles the owed scan")
        t:assertEqual(1, notifications, "and the inventory change is still noticed")
    end)
end)

-- Combat used to scan and merely postpone the rebuild. It now postpones the
-- scan as well: walking every bag slot is itself work the player is not asking
-- for mid-fight, and the events that provoke it -- loot, buffs, cooldowns --
-- arrive constantly while fighting. What must not change is that a real
-- inventory change is not lost, only deferred.
T:run("Inventory events: combat does not scan at all, and the change survives it", function(t)
    withInventoryEvents(function(f)
        MockWoW.config.inCombatLockdown, QR.PathCalculator.graphDirty = true, false
        f.replace({})
        f.fire("BAG_UPDATE"); f.flush()
        local scans, notifications = f.counts()
        t:assertEqual(0, scans, "A fight is not the time to walk every bag slot")
        t:assertFalse(QR.PathCalculator.graphDirty, "and nothing is invalidated mid-fight either")
        t:assertEqual(0, notifications, "Combat never invokes the normal inventory-change callback")
        t:assertTrue(QR.PlayerInventory.scanDeferredByCombat, "the scan is remembered, not dropped")

        -- What the leave-combat callback does once the fight ends.
        MockWoW.config.inCombatLockdown = false
        QR.PlayerInventory:RunDeferredScan()
        scans, notifications = f.counts()
        t:assertEqual(1, scans, "The postponed scan runs exactly once afterwards")
        t:assertEqual(1, notifications, "and the removed teleport invalidates the routes then")
    end)
end)
