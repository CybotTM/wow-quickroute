-- SecureButtons.lua
-- Manages secure action buttons for teleportation that work during combat lockdown
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, tostring, type, pcall = pairs, tostring, type, pcall
local string_format = string.format
local table_insert = table.insert
local math_floor = math.floor
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetInventoryItemID = GetInventoryItemID
local EquipItemByName = EquipItemByName

-- Constants
-- 10 UI step buttons + 40 teleport panel rows + 10 margin
local POOL_SIZE = 60

-------------------------------------------------------------------------------
-- SecureButtons Module
-------------------------------------------------------------------------------
QR.SecureButtons = {
    pool = {},
    maxPoolSize = POOL_SIZE,
    initialized = false,
    combatEndCallbacks = {},  -- Registered callbacks for combat end notifications
}

local SecureButtons = QR.SecureButtons

-- Equipment swap state for equippable teleport items
local savedEquipment = {}  -- [slotNum] = itemID that was equipped before swap
local pendingRestore = false

-------------------------------------------------------------------------------
-- Overlay Manager (single OnUpdate replaces per-button OnUpdate handlers)
-------------------------------------------------------------------------------
local activeOverlays = {}   -- { [btn] = { stepFrame, scrollFrame, xOffset, lastX, lastY, anchorLeft } }
local overlayManagerFrame = nil
local overlayThrottle = 0

--- Single OnUpdate handler that iterates all tracked overlays and updates positions.
-- Replaces per-button OnUpdate scripts with one centralized loop.
local function UpdateAllOverlays(self, elapsed)
    overlayThrottle = overlayThrottle + elapsed
    if overlayThrottle < 0.1 then return end
    overlayThrottle = 0

    -- Cannot hide/move secure frames during combat lockdown
    if InCombatLockdown() then return end

    for btn, info in pairs(activeOverlays) do
        local sf = info.stepFrame
        if not sf or not sf:IsVisible() then
            btn:Hide()
        else
            local clipped = false
            -- Check if within scroll frame visible area
            local scroll = info.scrollFrame
            if scroll then
                local scrollTop = scroll:GetTop()
                local scrollBottom = scroll:GetBottom()
                local rowTop = sf:GetTop()
                local rowBottom = sf:GetBottom()
                if scrollTop and scrollBottom and rowTop and rowBottom then
                    if rowBottom > scrollTop or rowTop < scrollBottom then
                        btn:Hide()
                        clipped = true
                    end
                end
            end
            if not clipped then
                local left = sf:GetLeft()
                local right = sf:GetRight()
                local top = sf:GetTop()
                local bottom = sf:GetBottom()
                if left and right and top and bottom then
                    local newX, anchor
                    if info.anchorLeft then
                        newX = left + info.xOffset
                        anchor = "LEFT"
                    else
                        newX = right + info.xOffset
                        anchor = "RIGHT"
                    end
                    local newY
                    if info.yFromTop then
                        newY = top - info.yFromTop
                    else
                        newY = (top + bottom) / 2
                    end
                    if info.lastX ~= newX or info.lastY ~= newY then
                        info.lastX = newX
                        info.lastY = newY
                        btn:ClearAllPoints()
                        btn:SetPoint(anchor, UIParent, "BOTTOMLEFT", newX, newY)
                    end
                    if not btn:IsShown() then
                        btn:Show()
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the secure button pool
-- Must be called outside of combat lockdown
-- Will retry automatically if called during combat
function SecureButtons:Initialize()
    if self.initialized then
        return
    end

    if InCombatLockdown() then
        -- Retry when combat ends via event instead of polling timer
        local waitFrame = CreateFrame("Frame")
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(frame)
            frame:UnregisterAllEvents()
            SecureButtons:Initialize()
        end)
        return
    end

    -- Pre-create button pool outside of combat
    for i = 1, self.maxPoolSize do
        local btn = CreateFrame("Button", "QRSecBtn" .. i, UIParent, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyDown", "AnyUp")
        btn:SetSize(22, 22)
        btn:Hide()
        if btn.SetUsingParentLevel then btn:SetUsingParentLevel(true) end
        btn.inUse = false
        btn.poolIndex = i
        table_insert(self.pool, btn)
    end

    self.initialized = true

    -- Register combat events during initialization (idempotent)
    self:RegisterCombatEvents()

    QR:Debug("SecureButtons initialized with " .. self.maxPoolSize .. " buttons")
end

-------------------------------------------------------------------------------
-- Pool Management
-------------------------------------------------------------------------------

--- Get an available button from the pool
-- @return Button|nil A button from the pool, or nil if all are in use
function SecureButtons:GetButton()
    if not self.initialized then
        QR:Debug("SecureButtons not initialized")
        return nil
    end

    -- Defense-in-depth: callers should check before calling, but guard here too
    if InCombatLockdown() then
        return nil
    end

    for _, btn in ipairs(self.pool) do
        if not btn.inUse then
            btn.inUse = true
            return btn
        end
    end

    -- Always log a warning when pool is exhausted (not just in debug mode)
    QR:Warn("SecureButtons pool exhausted (" .. self.maxPoolSize .. " buttons in use)")
    return nil
end

--- Release a button back to the pool
-- Will defer release if called during combat lockdown
-- @param btn Button The button to release
function SecureButtons:ReleaseButton(btn)
    if not btn then
        return
    end

    -- Verify button belongs to our pool (defense against stale/foreign frames)
    if not btn.poolIndex or btn.poolIndex < 1 or btn.poolIndex > self.maxPoolSize then
        return
    end

    if InCombatLockdown() then
        -- Queue release for after combat
        if not self.pendingReleases then
            self.pendingReleases = {}
        end
        table_insert(self.pendingReleases, btn)
        return
    end

    btn:Hide()
    -- Remove from centralized overlay tracking
    activeOverlays[btn] = nil
    -- Hide manager frame when no overlays remain
    if overlayManagerFrame and not next(activeOverlays) then
        overlayManagerFrame:Hide()
    end
    btn:SetScript("OnUpdate", nil)
    btn:SetScript("PreClick", nil)
    btn:SetScript("PostClick", nil)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn._qrStepFrame = nil
    btn._qrScrollFrame = nil
    btn._lastX = nil
    btn._lastY = nil
    btn._elapsed = nil
    btn:ClearAllPoints()
    btn:SetParent(UIParent)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("toy", nil)
    btn:SetAttribute("item", nil)
    btn.inUse = false
    btn.teleportID = nil
    btn.sourceType = nil
    btn.equipSlot = nil
    -- Reset visual state for icon-as-button reuse
    if btn.iconTexture then
        btn.iconTexture:Hide()
    end
    if btn.text then
        btn.text:Hide()
    end
    btn:SetAlpha(1.0)
    btn:SetNormalTexture("")
    btn:SetHighlightTexture("")
    btn:SetPushedTexture("")
    btn.styled = false
end

--- Release all pending buttons (call after combat ends)
function SecureButtons:ReleasePendingButtons()
    if InCombatLockdown() then
        return
    end

    if self.pendingReleases then
        for _, btn in ipairs(self.pendingReleases) do
            self:ReleaseButton(btn)
        end
        self.pendingReleases = nil
    end
end

--- Get the number of buttons currently in use
-- @return number Count of buttons in use
function SecureButtons:GetInUseCount()
    local count = 0
    for _, btn in ipairs(self.pool) do
        if btn.inUse then
            count = count + 1
        end
    end
    return count
end

-------------------------------------------------------------------------------
-- Button Configuration
-------------------------------------------------------------------------------

--- Configure a button to use an item
-- Uses macro approach for items with charges: /use item:itemID
-- @param btn Button The button to configure
-- @param itemID number The item ID to use
-- @return boolean True if configuration succeeded, false if in combat lockdown
function SecureButtons:ConfigureForItem(btn, itemID)
    if InCombatLockdown() then
        return false
    end

    if not btn or not itemID then
        return false
    end

    -- Validate itemID is a positive integer to prevent macro injection
    if type(itemID) ~= "number" or itemID ~= math_floor(itemID) or itemID <= 0 then
        return false
    end

    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "/use item:" .. itemID)
    btn.teleportID = itemID
    btn.sourceType = "item"
    return true
end

--- Configure a button to cast a spell
-- @param btn Button The button to configure
-- @param spellID number The spell ID to cast
-- @return boolean True if configuration succeeded, false if in combat lockdown
function SecureButtons:ConfigureForSpell(btn, spellID)
    if InCombatLockdown() then
        return false
    end

    if not btn or not spellID then
        return false
    end

    -- Validate spellID is a positive integer
    if type(spellID) ~= "number" or spellID ~= math_floor(spellID) or spellID <= 0 then
        return false
    end

    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", spellID)
    btn.teleportID = spellID
    btn.sourceType = "spell"
    return true
end

--- Configure a button to use a toy
-- @param btn Button The button to configure
-- @param toyID number The toy item ID to use
-- @return boolean True if configuration succeeded, false if in combat lockdown
function SecureButtons:ConfigureForToy(btn, toyID)
    if InCombatLockdown() then
        return false
    end

    if not btn or not toyID then
        return false
    end

    -- Validate toyID is a positive integer
    if type(toyID) ~= "number" or toyID ~= math_floor(toyID) or toyID <= 0 then
        return false
    end

    btn:SetAttribute("type", "toy")
    btn:SetAttribute("toy", toyID)
    btn.teleportID = toyID
    btn.sourceType = "toy"
    return true
end

--- Configure a button to equip and use an equippable teleport item
-- Saves the currently equipped item in that slot, then creates a macro
-- that equips the teleport item and uses the slot
-- @param btn Button The button to configure
-- @param itemID number The item ID to equip and use
-- @param equipSlot number The inventory slot number (e.g. 15=back, 11=finger1)
-- @return boolean True if configuration succeeded
function SecureButtons:ConfigureForEquippable(btn, itemID, equipSlot)
    if not btn or not itemID or not equipSlot then
        return false
    end

    if type(itemID) ~= "number" or itemID ~= math_floor(itemID) or itemID <= 0 then
        return false
    end

    if type(equipSlot) ~= "number" or equipSlot < 1 or equipSlot > 19 then
        return false
    end

    -- Save currently equipped item in this slot (before combat lockdown check in PreClick)
    btn:SetScript("PreClick", function(self, button, down)
        if InCombatLockdown() then return end
        local currentItemID = GetInventoryItemID("player", equipSlot)
        if currentItemID and currentItemID ~= itemID then
            savedEquipment[equipSlot] = currentItemID
            pendingRestore = true
            QR:Debug(string_format("Saved equipment slot %d: item %d", equipSlot, currentItemID))
        end
    end)

    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", string_format("/equip item:%d\n/use %d", itemID, equipSlot))
    btn.teleportID = itemID
    btn.sourceType = "equipped"
    btn.equipSlot = equipSlot
    return true
end

--- Configure a button based on source type
-- Dispatches to the appropriate configuration method
-- @param btn Button The button to configure
-- @param id number The item or spell ID
-- @param sourceType string "spell", "toy", "item", or "equipped"
-- @return boolean True if configuration succeeded
function SecureButtons:ConfigureButton(btn, id, sourceType)
    local ok
    if sourceType == "spell" then
        ok = self:ConfigureForSpell(btn, id)
    elseif sourceType == "toy" then
        ok = self:ConfigureForToy(btn, id)
    elseif sourceType == "item" or sourceType == "equipped" then
        -- Check if the item has an equipSlot (needs equip-swap logic)
        local itemData = QR.TeleportItemsData and QR.TeleportItemsData[id]
        if itemData and itemData.equipSlot then
            ok = self:ConfigureForEquippable(btn, id, itemData.equipSlot)
        else
            ok = self:ConfigureForItem(btn, id)
        end
    else
        ok = self:ConfigureForItem(btn, id)
    end
    -- Add PostClick sound + debug logging
    if ok then
        btn:SetScript("PostClick", function(self, button, down)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            QR:Debug(string_format("SecureButton clicked: %s id=%s type=%s btn=%s down=%s",
                tostring(self.sourceType), tostring(self.teleportID),
                tostring(self:GetAttribute("type")), tostring(button), tostring(down)))
        end)
    end
    return ok
end

-------------------------------------------------------------------------------
-- Combat State Management
-------------------------------------------------------------------------------

--- Check if secure buttons can be modified
-- @return boolean True if not in combat lockdown
function SecureButtons:CanModify()
    return not InCombatLockdown()
end

--- Register a callback to be called when combat ends
-- @param callback function The callback function to register
function SecureButtons:RegisterCombatEndCallback(callback)
    if type(callback) == "function" then
        table_insert(self.combatEndCallbacks, callback)
    end
end

--- Register for combat events to handle pending operations.
-- Uses the centralized QR combat manager instead of a per-module frame.
-- Called automatically during Initialize() - idempotent.
function SecureButtons:RegisterCombatEvents()
    if self.combatEventsRegistered then
        return
    end
    self.combatEventsRegistered = true

    QR:RegisterCombatCallback(
        nil,  -- no enter-combat action needed
        function()  -- leave combat
            -- Combat ended, release pending buttons
            SecureButtons:ReleasePendingButtons()
            -- Call all registered combat end callbacks
            for _, callback in ipairs(SecureButtons.combatEndCallbacks) do
                local success, err = pcall(callback)
                if not success then
                    QR:Error("Combat end callback error: " .. tostring(err))
                end
            end
        end
    )
end

-------------------------------------------------------------------------------
-- Overlay Positioning
-------------------------------------------------------------------------------

--- Attach a secure button as an overlay that tracks a target frame's position.
-- The button stays parented to UIParent (required for secure frames in WoW 11.x)
-- and uses a throttled OnUpdate to follow the target frame's screen position.
-- @param btn Button The secure button to attach
-- @param targetFrame Frame The frame to track (e.g. a step row)
-- @param scrollFrame Frame|nil Optional scroll frame for clipping (hide when row scrolls out)
-- @param xOffset number|nil Offset from anchor edge of target (default: -5)
-- @param anchorLeft boolean|nil If true, anchor button's LEFT to target's LEFT + xOffset
-- @param yFromTop number|nil If set, position button center at this offset from target's top edge
function SecureButtons:AttachOverlay(btn, targetFrame, scrollFrame, xOffset, anchorLeft, yFromTop)
    if not btn or not targetFrame then
        return
    end

    xOffset = xOffset or -5

    -- Keep per-button properties for backward compatibility
    btn._qrStepFrame = targetFrame
    btn._qrScrollFrame = scrollFrame or nil

    -- Remove any old per-button OnUpdate (from prior code or external callers)
    btn:SetScript("OnUpdate", nil)

    -- Register in centralized tracking table
    activeOverlays[btn] = {
        stepFrame = targetFrame,
        scrollFrame = scrollFrame or nil,
        xOffset = xOffset,
        anchorLeft = anchorLeft or false,
        yFromTop = yFromTop or nil,
        lastX = nil,
        lastY = nil,
    }

    -- Ensure manager frame exists and is running
    if not overlayManagerFrame then
        overlayManagerFrame = CreateFrame("Frame")
        overlayManagerFrame:SetScript("OnUpdate", UpdateAllOverlays)
    end
    overlayManagerFrame:Show()
end

--- Get the number of overlays currently being tracked by the manager frame.
-- @return number Count of active overlays
function SecureButtons:GetActiveOverlayCount()
    local count = 0
    for _ in pairs(activeOverlays) do count = count + 1 end
    return count
end

-------------------------------------------------------------------------------
-- Equipment Restore After Teleport
-- When equippable teleport items are used, restore the original equipment
-- after a zone change (indicating teleport completed)
-------------------------------------------------------------------------------

--- Restore previously saved equipment after a teleport
local function RestoreEquipment()
    if not pendingRestore then return end
    if InCombatLockdown() then return end

    local restored = false
    for slotNum, savedItemID in pairs(savedEquipment) do
        local currentItemID = GetInventoryItemID("player", slotNum)
        if currentItemID and currentItemID ~= savedItemID then
            -- Teleport item is still equipped, restore the original
            EquipItemByName(savedItemID)
            QR:Debug(string_format("Restoring equipment slot %d: item %d", slotNum, savedItemID))
            restored = true
        end
        savedEquipment[slotNum] = nil
    end
    pendingRestore = false

    if restored then
        QR:Debug("Equipment restored after teleport")
    end
end

-- Register zone change events to trigger equipment restore
local restoreFrame = CreateFrame("Frame")
local restoreTimer = nil
restoreFrame:RegisterEvent("ZONE_CHANGED")
restoreFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
restoreFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
restoreFrame:SetScript("OnEvent", function(self, event)
    -- Delay slightly to ensure the teleport is complete
    -- Use a single timer to prevent multiple queued restores
    if pendingRestore then
        if restoreTimer then
            restoreTimer:Cancel()
        end
        restoreTimer = C_Timer.NewTimer(1, function()
            restoreTimer = nil
            RestoreEquipment()
        end)
    end
end)

-- Also restore when leaving combat (in case teleport happened during combat)
QR:RegisterCombatCallback(nil, function()
    if pendingRestore then
        if restoreTimer then
            restoreTimer:Cancel()
        end
        restoreTimer = C_Timer.NewTimer(0.5, function()
            restoreTimer = nil
            RestoreEquipment()
        end)
    end
end)
