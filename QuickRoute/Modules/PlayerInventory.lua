-- PlayerInventory.lua
-- Scans and tracks the player's available teleport items, toys, and spells
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local table_insert = table.insert
local CreateFrame = CreateFrame

-- Constants
local DEBOUNCE_DELAY = 0.5

-------------------------------------------------------------------------------
-- PlayerInventory Module
-------------------------------------------------------------------------------
QR.PlayerInventory = {
    teleportItems = {},  -- Items from bags/equipped
    toys = {},           -- Toys from toy box
    spells = {},         -- Known teleport spells
    pendingScan = false, -- Debounce flag for event-triggered scans
}

local PlayerInventory = QR.PlayerInventory

-- Cache for GetAllTeleports() result (invalidated by ScanAll)
local allTeleportsCache = nil

-- Equipment slot constants
local EQUIP_SLOTS = {
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TABARD,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
}

-------------------------------------------------------------------------------
-- Scanning Methods
-------------------------------------------------------------------------------

--- Scan all bags for teleport items
-- Helper functions for container API compatibility
local function SafeGetContainerNumSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID)
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bagID)
    end
    return 0
end

local function SafeGetContainerItemID(bagID, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bagID, slot)
    elseif GetContainerItemID then
        return GetContainerItemID(bagID, slot)
    end
    return nil
end

local function SafeGetContainerItemInfo(bagID, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slot)
    elseif GetContainerItemInfo then
        -- Old API returns individual values, not a table
        local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID = GetContainerItemInfo(bagID, slot)
        if itemID then
            return {
                itemID = itemID,
                stackCount = itemCount or 1,
                itemLink = itemLink,
            }
        end
    end
    return nil
end

-- Expose container helpers for reuse by other modules (e.g., TeleportPanel)
PlayerInventory.SafeGetContainerNumSlots = SafeGetContainerNumSlots
PlayerInventory.SafeGetContainerItemID = SafeGetContainerItemID

-- Uses C_Container API (with fallback for older clients) to iterate through all bag slots
function PlayerInventory:ScanBags()
    wipe(self.teleportItems)

    -- Scan bags 0 (backpack) through NUM_BAG_SLOTS
    local maxBags = NUM_BAG_SLOTS or 4
    for bagID = 0, maxBags do
        local numSlots = SafeGetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = SafeGetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID then
                local itemID = itemInfo.itemID
                -- Check if this item is in our teleport data
                if QR.TeleportItemsData and QR.TeleportItemsData[itemID] then
                    local data = QR.TeleportItemsData[itemID]
                    -- Skip toys since they're handled separately
                    if data.type ~= QR.TeleportTypes.TOY then
                        self.teleportItems[itemID] = {
                            id = itemID,
                            data = data,
                            bagID = bagID,
                            slot = slot,
                            count = itemInfo.stackCount or 1,
                        }
                    end
                end
            end
        end
    end

    return self.teleportItems
end

--- Scan equipped items for teleport items
-- Checks rings, tabard, and trinkets
function PlayerInventory:ScanEquipped()
    if not GetInventoryItemID then return self.teleportItems end
    for _, slotID in ipairs(EQUIP_SLOTS) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID and QR.TeleportItemsData[itemID] then
            local data = QR.TeleportItemsData[itemID]
            -- Skip toys since they're handled separately
            if data.type ~= QR.TeleportTypes.TOY then
                self.teleportItems[itemID] = {
                    id = itemID,
                    data = data,
                    slotID = slotID,
                    isEquipped = true,
                }
            end
        end
    end

    return self.teleportItems
end

--- Scan toy box for teleport toys
-- Iterates through TeleportItemsData for type==TOY and checks PlayerHasToy
-- Filters by faction
function PlayerInventory:ScanToys()
    if not (C_ToyBox and PlayerHasToy) then return end
    wipe(self.toys)
    local playerFaction = QR.PlayerInfo:GetFaction()

    for itemID, data in pairs(QR.TeleportItemsData) do
        if data.type == QR.TeleportTypes.TOY then
            -- Check faction restriction
            local factionOK = not data.faction or data.faction == "both" or data.faction == playerFaction
            if factionOK and PlayerHasToy(itemID) then
                local isUsable = C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(itemID) or false
                self.toys[itemID] = {
                    id = itemID,
                    data = data,
                    isUsable = isUsable,
                }
            end
        end
    end

    return self.toys
end

--- Scan known spells for teleport spells
-- Checks class spells and mage teleports using IsSpellKnown
function PlayerInventory:ScanSpells()
    if not IsSpellKnown then return self.spells end
    wipe(self.spells)

    -- Get player info for filtering (cached)
    local playerClass = QR.PlayerInfo:GetClass()
    local playerFaction = QR.PlayerInfo:GetFaction()

    -- Check class-specific teleport spells
    for spellID, data in pairs(QR.ClassTeleportSpells) do
        if data.class == playerClass then
            if IsSpellKnown(spellID) then
                self.spells[spellID] = {
                    id = spellID,
                    data = data,
                    isClass = true,
                }
            end
        end
    end

    -- Check mage teleports if player is a mage
    if playerClass == "MAGE" then
        -- Check faction-specific mage teleports
        local factionTeleports = QR.MageTeleports[playerFaction]
        if factionTeleports then
            for spellID, data in pairs(factionTeleports) do
                if IsSpellKnown(spellID) then
                    self.spells[spellID] = {
                        id = spellID,
                        data = data,
                        isMageTeleport = true,
                    }
                end
            end
        end

        -- Check shared/neutral mage teleports
        for spellID, data in pairs(QR.MageTeleports.Shared) do
            if not self.spells[spellID] and IsSpellKnown(spellID) then
                self.spells[spellID] = {
                    id = spellID,
                    data = data,
                    isMageTeleport = true,
                }
            end
        end
    end

    -- Check racial teleport spells
    if QR.RacialTeleportSpells then
        for spellID, data in pairs(QR.RacialTeleportSpells) do
            if IsSpellKnown(spellID) then
                self.spells[spellID] = {
                    id = spellID,
                    data = data,
                    isRacial = true,
                }
            end
        end
    end

    return self.spells
end

--- Scan all sources for teleport options
-- Calls all scan methods and returns combined results
-- @return table Table with items, toys, and spells keys
function PlayerInventory:ScanAll()
    allTeleportsCache = nil

    -- Debug: check if data is loaded
    if QR.debugMode then
        local dataCount = 0
        if QR.TeleportItemsData then
            for _ in pairs(QR.TeleportItemsData) do dataCount = dataCount + 1 end
        end
        QR:Debug(string_format("ScanAll - TeleportItemsData has %d entries", dataCount))

        local classSpellCount = 0
        if QR.ClassTeleportSpells then
            for _ in pairs(QR.ClassTeleportSpells) do classSpellCount = classSpellCount + 1 end
        end
        QR:Debug(string_format("ScanAll - ClassTeleportSpells has %d entries", classSpellCount))
    end

    self:ScanBags()
    self:ScanEquipped()
    self:ScanToys()
    self:ScanSpells()

    if QR.debugMode then
        local itemCount, toyCount, spellCount = 0, 0, 0
        for _ in pairs(self.teleportItems) do itemCount = itemCount + 1 end
        for _ in pairs(self.toys) do toyCount = toyCount + 1 end
        for _ in pairs(self.spells) do spellCount = spellCount + 1 end
        QR:Debug(string_format("Found %d items, %d toys, %d spells", itemCount, toyCount, spellCount))
    end

    return {
        items = self.teleportItems,
        toys = self.toys,
        spells = self.spells,
    }
end

-------------------------------------------------------------------------------
-- Query Methods
-------------------------------------------------------------------------------

--- Force rescan command
SLASH_QRSCAN1 = "/qrscan"
SlashCmdList["QRSCAN"] = function(msg)
    print("|cFF00FF00QuickRoute|r: Rescanning teleports...")
    local oldDebug = QR.debugMode
    QR.debugMode = true  -- Temporarily enable debug

    local success, err = pcall(function()
        QR.PlayerInventory:ScanAll()

        local all = QR.PlayerInventory:GetAllTeleports()
        local count = 0
        for id, entry in pairs(all) do
            count = count + 1
            local dataInfo = "NO DATA"
            if entry.data then
                dataInfo = string_format("name=%s, dest=%s, mapID=%s",
                    tostring(entry.data.name),
                    tostring(entry.data.destination),
                    tostring(entry.data.mapID))
            end
            print(string_format("  [%d] %s: %s", id, entry.sourceType or "?", dataInfo))
        end
        print(string_format("|cFF00FF00QuickRoute|r: Total %d teleports found", count))
    end)

    QR.debugMode = oldDebug  -- Always restore
    if not success then
        print("|cFFFF0000QuickRoute ERROR:|r " .. tostring(err))
    end
end

--- Get all teleports as a flat table with sourceType added
-- Merges items, toys, and spells into a single table
-- @return table Flat table of all available teleports
function PlayerInventory:GetAllTeleports()
    if allTeleportsCache then return allTeleportsCache end

    local all = {}

    -- Add items with sourceType
    for id, entry in pairs(self.teleportItems) do
        local teleport = {
            id = id,
            data = entry.data,
            sourceType = "item",
        }
        if entry.isEquipped then
            teleport.sourceType = "equipped"
            teleport.slotID = entry.slotID
        else
            teleport.bagID = entry.bagID
            teleport.slot = entry.slot
        end
        all[id] = teleport
    end

    -- Add toys with sourceType
    for id, entry in pairs(self.toys) do
        all[id] = {
            id = id,
            data = entry.data,
            sourceType = "toy",
            isUsable = entry.isUsable,
        }
    end

    -- Add spells with sourceType
    for id, entry in pairs(self.spells) do
        all[id] = {
            id = id,
            data = entry.data,
            sourceType = "spell",
            isClass = entry.isClass,
            isMageTeleport = entry.isMageTeleport,
        }
    end

    allTeleportsCache = all
    return all
end

--- Check if the player has a specific teleport
-- @param id number The item/spell ID to check
-- @return boolean True if player has this teleport available
function PlayerInventory:HasTeleport(id)
    if self.teleportItems[id] then
        return true
    end
    if self.toys[id] then
        return true
    end
    if self.spells[id] then
        return true
    end
    return false
end

--- Get the total count of all available teleports
-- @return number Total count of items + toys + spells
function PlayerInventory:GetTeleportCount()
    local count = 0

    for _ in pairs(self.teleportItems) do
        count = count + 1
    end
    for _ in pairs(self.toys) do
        count = count + 1
    end
    for _ in pairs(self.spells) do
        count = count + 1
    end

    return count
end

--- Print a formatted debug list of all teleports
function PlayerInventory:PrintDebug()
    print("|cFF00FF00QuickRoute|r: Player Teleport Inventory")
    print("----------------------------------------")

    local count = 0

    -- Print items
    if next(self.teleportItems) then
        print("|cFFFFFF00Items:|r")
        for id, entry in pairs(self.teleportItems) do
            local location = entry.isEquipped and "equipped" or string_format("bag %d slot %d", entry.bagID, entry.slot)
            print(string_format("  [%d] %s (%s)", id, entry.data.name, location))
            count = count + 1
        end
    end

    -- Print toys
    if next(self.toys) then
        print("|cFFFFFF00Toys:|r")
        for id, entry in pairs(self.toys) do
            local usable = entry.isUsable and "|cFF00FF00usable|r" or "|cFFFF0000not usable|r"
            print(string_format("  [%d] %s (%s)", id, entry.data.name, usable))
            count = count + 1
        end
    end

    -- Print spells
    if next(self.spells) then
        print("|cFFFFFF00Spells:|r")
        for id, entry in pairs(self.spells) do
            local spellType = entry.isMageTeleport and "mage" or "class"
            print(string_format("  [%d] %s (%s)", id, entry.data.name, spellType))
            count = count + 1
        end
    end

    print("----------------------------------------")
    print(string_format("|cFF00FF00Total:|r %d teleport methods available", count))
end

-------------------------------------------------------------------------------
-- Event Handling
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local debounceTimer = nil

-- Events that should trigger a rescan
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("TOYS_UPDATED")
eventFrame:RegisterEvent("SPELLS_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Debounce rapid events with a 0.5 second timer
    if PlayerInventory.pendingScan then
        return
    end

    PlayerInventory.pendingScan = true

    -- Cancel any existing timer
    if debounceTimer then
        debounceTimer:Cancel()
        debounceTimer = nil
    end

    -- Set a new timer
    debounceTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
        PlayerInventory.pendingScan = false

        -- Skip scan if addon not fully initialized yet
        if not QR.db then return end

        -- Perform the scan
        PlayerInventory:ScanAll()

        -- Notify PathCalculator if it exists (defer during combat to avoid expensive graph rebuild)
        if QR.PathCalculator and QR.PathCalculator.OnInventoryChanged then
            if InCombatLockdown() then
                QR.PathCalculator.graphDirty = true
            else
                QR.PathCalculator:OnInventoryChanged()
            end
        end

        if QR.debugMode then
            local count = PlayerInventory:GetTeleportCount()
            QR:Debug(string_format("Inventory updated (%d teleports)", count))
        end
    end)
end)

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

SLASH_QRINV1 = "/qrinv"
SlashCmdList["QRINV"] = function(msg)
    if QR.MainFrame then
        QR.MainFrame:Toggle("teleports")
    else
        PlayerInventory:ScanAll()
        PlayerInventory:PrintDebug()
    end
end
