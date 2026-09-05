local T, QR, MockWoW = ...

T:run("Secure buttons: equippable configuration performs no combat mutations", function(t)
    local combat = MockWoW.config.inCombatLockdown
    MockWoW.config.inCombatLockdown = true
    local mutations = 0
    local btn = {
        SetAttribute = function() mutations = mutations + 1 end,
        SetScript = function() mutations = mutations + 1 end,
    }
    t:assertFalse(QR.SecureButtons:ConfigureForEquippable(btn, 63353, 15),
        "Equipping is refused under combat lockdown")
    t:assertFalse(QR.SecureButtons:ConfigureButton(btn, 63353, "item"),
        "Shared dispatch is refused under combat lockdown")
    t:assertEqual(0, mutations, "Protected attributes and scripts remain untouched")
    MockWoW.config.inCombatLockdown = combat
end)

T:run("Secure buttons: reusing equipment action as spell clears its equipment callback", function(t)
    local combat = MockWoW.config.inCombatLockdown
    MockWoW.config.inCombatLockdown = false
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    t:assertTrue(QR.SecureButtons:ConfigureButton(btn, 63353, "item"), "Cloak configures")
    t:assertNotNil(btn:GetScript("PreClick"), "Cloak has an equipment callback")
    t:assertTrue(QR.SecureButtons:ConfigureButton(btn, 1233637, "spell"), "Housing spell configures")
    t:assertNil(btn:GetScript("PreClick"), "Reused spell never equips the previous cloak")
    t:assertNil(btn.equipSlot, "Equipment slot is cleared on reuse")
    t:assertEqual("", btn:GetAttribute("*type2"), "Right-click cannot inherit teleport action")
    t:assertEqual("", btn:GetAttribute("*type3"), "Middle-click cannot inherit teleport action")
    MockWoW.config.inCombatLockdown = combat
end)

T:run("Secure buttons: IDs and equipment slots must be finite integers", function(t)
    local combat = MockWoW.config.inCombatLockdown
    MockWoW.config.inCombatLockdown = false
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    for _, method in ipairs({ "ConfigureForItem", "ConfigureForToy", "ConfigureForSpell" }) do
        t:assertFalse(QR.SecureButtons[method](QR.SecureButtons, btn, math.huge),
            method .. " rejects infinite IDs")
    end
    t:assertFalse(QR.SecureButtons:ConfigureForEquippable(btn, 63353, 15.5),
        "Fractional inventory slots cannot silently round to another slot")
    MockWoW.config.inCombatLockdown = combat
end)

T:run("Secure buttons: visibility driver hides in combat without showing released pool entries", function(t)
    local combat, originalDriver = MockWoW.config.inCombatLockdown, RegisterStateDriver
    MockWoW.config.inCombatLockdown = false
    local calls = {}
    RegisterStateDriver = function(frame, state, values)
        calls[#calls + 1] = { frame = frame, state = state, values = values }
    end
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    QR.SecureButtons:ConfigureButton(btn, 6948, "item")
    QR.SecureButtons:ConfigureButton(btn, 140192, "toy")
    RegisterStateDriver = originalDriver
    MockWoW.config.inCombatLockdown = combat
    t:assertEqual(1, #calls, "Reusing a button does not duplicate state drivers")
    t:assertEqual(btn, calls[1] and calls[1].frame, "Driver is attached to the protected action button")
    t:assertEqual("visibility", calls[1] and calls[1].state, "Uses Blizzard's protected visibility handler")
    t:assertEqual("[combat] hide", calls[1] and calls[1].values,
        "Driver never forces hidden pool entries visible outside combat")
end)

T:run("Secure buttons: equipment restore respects a subsequent manual equipment change", function(t)
    local combat = MockWoW.config.inCombatLockdown
    local originalItem, originalEquip = MockWoW.config.equippedItems[15], C_Item.EquipItemByName
    MockWoW.config.inCombatLockdown = false
    local restored = {}
    C_Item.EquipItemByName = function(itemID, slot) restored[#restored + 1] = { itemID, slot } end
    -- MockWoW:Reset drops event-frame registrations. Capture this lifecycle
    -- callback directly so the regression does not depend on test-file order.
    local register, registered = QR.RegisterCombatCallback, QR.SecureButtons.equipmentRestoreRegistered
    local restoreEquipment
    QR.RegisterCombatCallback = function(_, _, leave) restoreEquipment = leave end
    QR.SecureButtons.equipmentRestoreRegistered = false
    QR.SecureButtons:RegisterEquipmentRestoreCallback()
    QR.RegisterCombatCallback = register
    QR.SecureButtons.equipmentRestoreRegistered = registered
    restoreEquipment()
    restored = {}
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    QR.SecureButtons:ConfigureForEquippable(btn, 63353, 15)
    MockWoW.config.equippedItems[15] = 1001
    btn:GetScript("PreClick")(btn, "LeftButton", false)
    MockWoW.config.equippedItems[15] = 2002 -- Player chooses another cloak.
    restoreEquipment()
    t:assertEqual(0, #restored, "Crossing a zone does not undo the player's later equipment change")

    MockWoW.config.equippedItems[15] = 1001
    btn:GetScript("PreClick")(btn, "LeftButton", false)
    MockWoW.config.equippedItems[15] = 63353
    restoreEquipment()
    t:assertEqual(1, #restored, "The teleport cloak itself is restored")
    t:assertEqual(1001, restored[1] and restored[1][1], "Restores the original item")
    t:assertEqual(15, restored[1] and restored[1][2], "Restores the original equipment slot")
    C_Item.EquipItemByName = originalEquip
    MockWoW.config.equippedItems[15] = originalItem
    MockWoW.config.inCombatLockdown = combat
end)

T:run("Route progress: same-zone teleport remains actionable before the final walk", function(t)
    local mapID = MockWoW.config.currentMapID
    MockWoW.config.currentMapID = 84
    t:assertEqual(1, QR.UI:GetCurrentStepIndex({
        { type = "teleport", fromMapID = 84, destMapID = 84 },
        { type = "walk", fromMapID = 84, destMapID = 84 },
    }), "Sharing the destination zone does not mark its teleport completed")
    MockWoW.config.currentMapID = mapID
end)

T:run("Quest shortcuts: walking-first routes never advertise a later teleport", function(t)
    local qtb = QR.QuestTeleportButtons
    local combat, watches = MockWoW.config.inCombatLockdown, MockWoW.config.questWatches
    local waypoint, calculate, teleports = QR.WaypointIntegration.GetQuestWaypoint,
        QR.PathCalculator.CalculatePath, QR.PlayerInventory.GetAllTeleports
    local getCooldown = QR.CooldownTracker.GetCooldown
    local ready, calculations = true, 0
    QR.CooldownTracker.GetCooldown = function() return { ready = ready, remaining = ready and 0 or 60 } end
    MockWoW.config.inCombatLockdown = false
    qtb:Initialize()
    local enabled = qtb.enabled
    qtb.enabled = true
    MockWoW.config.questWatches = { 123 }
    QR.WaypointIntegration.GetQuestWaypoint = function()
        return { mapID = 84, x = 0.8, y = 0.2, title = "Quest objective" }
    end
    QR.PlayerInventory.GetAllTeleports = function()
        return { [3561] = { sourceType = "spell", data = { mapID = 84 } } }
    end
    QR.PathCalculator.CalculatePath = function()
        calculations = calculations + 1
        return { steps = {
            { type = "walk", fromMapID = 84, destMapID = 84 },
            { type = "teleport", teleportID = 3561, sourceType = "spell" },
        } }
    end
    qtb:InvalidateCache()
    qtb:RefreshButtons()
    t:assertNil(qtb.activeButtons[123], "A same-map teleport does not override the planner's first walk")

    QR.PathCalculator.CalculatePath = function()
        calculations = calculations + 1
        return { steps = { { type = "teleport", teleportID = 3561, sourceType = "spell" } } }
    end
    qtb:InvalidateCache()
    qtb:RefreshButtons()
    t:assertNotNil(qtb.activeButtons[123], "The selected first-step teleport has a shortcut")

    local before = calculations
    qtb.eventFrame:GetScript("OnEvent")(qtb.eventFrame, "SPELL_UPDATE_COOLDOWN")
    t:assertEqual(before, calculations, "An unrelated cooldown event does not replan all quest routes")
    ready = false
    qtb.eventFrame:GetScript("OnEvent")(qtb.eventFrame, "SPELL_UPDATE_COOLDOWN")
    t:assertNil(qtb.activeButtons[123], "A teleport that goes on cooldown loses its ready shortcut")
    ready = true
    qtb:InvalidateCache()
    qtb:RefreshButtons()
    MockWoW.config.inCombatLockdown = true
    qtb:SetEnabled(false)
    MockWoW.config.inCombatLockdown = false
    qtb:RefreshButtons()
    t:assertNil(qtb.activeButtons[123], "Disabling in combat releases the button when lockdown ends")
    qtb:ReleaseAllButtons()
    qtb.enabled = enabled
    qtb:InvalidateCache()
    QR.WaypointIntegration.GetQuestWaypoint = waypoint
    QR.PathCalculator.CalculatePath = calculate
    QR.PlayerInventory.GetAllTeleports = teleports
    QR.CooldownTracker.GetCooldown = getCooldown
    MockWoW.config.questWatches = watches
    MockWoW.config.inCombatLockdown = combat
end)
