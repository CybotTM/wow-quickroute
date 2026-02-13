-------------------------------------------------------------------------------
-- test_playerinventory.lua
-- Tests for QR.PlayerInventory module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    wipe(QR.PlayerInventory.teleportItems)
    wipe(QR.PlayerInventory.toys)
    wipe(QR.PlayerInventory.spells)
    -- Clear PlayerInfo cache so faction/class changes take effect
    if QR.PlayerInfo and QR.PlayerInfo.InvalidateCache then
        QR.PlayerInfo:InvalidateCache()
    end
end

--- Find a known teleport item ID from TeleportItemsData for testing
local function findTestItemID(itemType)
    for id, data in pairs(QR.TeleportItemsData or {}) do
        if data.type == itemType then
            return id, data
        end
    end
    return nil, nil
end

--- Find a known toy from TeleportItemsData
local function findTestToyID(faction)
    for id, data in pairs(QR.TeleportItemsData or {}) do
        if data.type == QR.TeleportTypes.TOY then
            if not faction or not data.faction or data.faction == "both" or data.faction == faction then
                return id, data
            end
        end
    end
    return nil, nil
end

--- Find a known spell from ClassTeleportSpells for a class
local function findTestSpellID(className)
    for id, data in pairs(QR.ClassTeleportSpells or {}) do
        if data.class == className then
            return id, data
        end
    end
    return nil, nil
end

-------------------------------------------------------------------------------
-- 1. ScanBags
-------------------------------------------------------------------------------

T:run("ScanBags: finds teleport items in bags", function(t)
    resetState()

    -- Find a real item from the data
    local itemID, itemData = findTestItemID(QR.TeleportTypes.ITEM)
    if not itemID then
        -- Skip test if no ITEM type exists
        t:assertTrue(true, "No ITEM type in data, skipping")
        return
    end

    -- Place item in bag 0, slot 1
    MockWoW.config.bagItems[itemID] = { bagID = 0, slot = 1, count = 1 }

    QR.PlayerInventory:ScanBags()

    t:assertNotNil(QR.PlayerInventory.teleportItems[itemID], "Item found in bags")
end)

T:run("ScanBags: empty bags returns empty table", function(t)
    resetState()
    MockWoW.config.bagItems = {}

    QR.PlayerInventory:ScanBags()

    local count = 0
    for _ in pairs(QR.PlayerInventory.teleportItems) do count = count + 1 end
    t:assertEqual(0, count, "No items found in empty bags")
end)

T:run("ScanBags: skips toys (handled separately)", function(t)
    resetState()

    local toyID = findTestToyID()
    if not toyID then
        t:assertTrue(true, "No TOY type in data, skipping")
        return
    end

    -- Place toy in bag
    MockWoW.config.bagItems[toyID] = { bagID = 0, slot = 1, count = 1 }

    QR.PlayerInventory:ScanBags()

    t:assertNil(QR.PlayerInventory.teleportItems[toyID], "Toy skipped in bag scan")
end)

-------------------------------------------------------------------------------
-- 2. ScanToys
-------------------------------------------------------------------------------

T:run("ScanToys: finds owned toys", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"

    local toyID = findTestToyID("Alliance")
    if not toyID then
        t:assertTrue(true, "No Alliance TOY in data, skipping")
        return
    end

    MockWoW.config.ownedToys[toyID] = true

    QR.PlayerInventory:ScanToys()

    t:assertNotNil(QR.PlayerInventory.toys[toyID], "Toy found when owned")
end)

T:run("ScanToys: skips unowned toys", function(t)
    resetState()

    local toyID = findTestToyID()
    if not toyID then
        t:assertTrue(true, "No TOY in data, skipping")
        return
    end

    -- Don't put it in ownedToys
    QR.PlayerInventory:ScanToys()

    t:assertNil(QR.PlayerInventory.toys[toyID], "Unowned toy not found")
end)

T:run("ScanToys: filters by faction", function(t)
    resetState()

    -- Find a Horde-only toy
    local hordeToyID = nil
    for id, data in pairs(QR.TeleportItemsData or {}) do
        if data.type == QR.TeleportTypes.TOY and data.faction == "Horde" then
            hordeToyID = id
            break
        end
    end

    if not hordeToyID then
        t:assertTrue(true, "No Horde-only TOY in data, skipping")
        return
    end

    -- Player is Alliance, toy is Horde-only
    MockWoW.config.playerFaction = "Alliance"
    MockWoW.config.ownedToys[hordeToyID] = true

    QR.PlayerInventory:ScanToys()

    t:assertNil(QR.PlayerInventory.toys[hordeToyID], "Horde toy filtered for Alliance player")
end)

-------------------------------------------------------------------------------
-- 3. ScanSpells
-------------------------------------------------------------------------------

T:run("ScanSpells: finds known class spells", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"

    local spellID = findTestSpellID("MAGE")
    if not spellID then
        t:assertTrue(true, "No MAGE spell in ClassTeleportSpells, skipping")
        return
    end

    MockWoW.config.knownSpells[spellID] = true

    QR.PlayerInventory:ScanSpells()

    t:assertNotNil(QR.PlayerInventory.spells[spellID], "Known mage spell found")
end)

T:run("ScanSpells: skips unknown spells", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"

    local spellID = findTestSpellID("MAGE")
    if not spellID then
        t:assertTrue(true, "No MAGE spell, skipping")
        return
    end

    -- Don't add to knownSpells
    QR.PlayerInventory:ScanSpells()

    t:assertNil(QR.PlayerInventory.spells[spellID], "Unknown spell not found")
end)

T:run("ScanSpells: skips other class spells", function(t)
    resetState()
    MockWoW.config.playerClass = "WARRIOR"

    local spellID = findTestSpellID("MAGE")
    if not spellID then
        t:assertTrue(true, "No MAGE spell, skipping")
        return
    end

    MockWoW.config.knownSpells[spellID] = true

    QR.PlayerInventory:ScanSpells()

    t:assertNil(QR.PlayerInventory.spells[spellID], "Mage spell not found for Warrior")
end)

T:run("ScanSpells: mage gets faction-specific teleports", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerFaction = "Alliance"

    -- Find an Alliance mage teleport
    local allianceSpellID = nil
    if QR.MageTeleports and QR.MageTeleports.Alliance then
        for id, _ in pairs(QR.MageTeleports.Alliance) do
            allianceSpellID = id
            break
        end
    end

    if not allianceSpellID then
        t:assertTrue(true, "No Alliance mage teleport, skipping")
        return
    end

    MockWoW.config.knownSpells[allianceSpellID] = true

    QR.PlayerInventory:ScanSpells()

    t:assertNotNil(QR.PlayerInventory.spells[allianceSpellID], "Alliance mage teleport found")
end)

-------------------------------------------------------------------------------
-- 4. HasTeleport
-------------------------------------------------------------------------------

T:run("HasTeleport: returns true for owned items", function(t)
    resetState()
    QR.PlayerInventory.teleportItems[12345] = { id = 12345 }
    t:assertTrue(QR.PlayerInventory:HasTeleport(12345), "Has item teleport")
end)

T:run("HasTeleport: returns true for owned toys", function(t)
    resetState()
    QR.PlayerInventory.toys[67890] = { id = 67890 }
    t:assertTrue(QR.PlayerInventory:HasTeleport(67890), "Has toy teleport")
end)

T:run("HasTeleport: returns true for known spells", function(t)
    resetState()
    QR.PlayerInventory.spells[11111] = { id = 11111 }
    t:assertTrue(QR.PlayerInventory:HasTeleport(11111), "Has spell teleport")
end)

T:run("HasTeleport: returns false for missing teleport", function(t)
    resetState()
    t:assertFalse(QR.PlayerInventory:HasTeleport(99999), "Missing teleport")
end)

-------------------------------------------------------------------------------
-- 5. GetAllTeleports
-------------------------------------------------------------------------------

T:run("GetAllTeleports: merges items, toys, and spells", function(t)
    resetState()
    QR.PlayerInventory.teleportItems[1] = { id = 1, data = { name = "Item1" } }
    QR.PlayerInventory.toys[2] = { id = 2, data = { name = "Toy1" } }
    QR.PlayerInventory.spells[3] = { id = 3, data = { name = "Spell1" } }

    -- Force cache invalidation by calling ScanAll (which sets cache to nil)
    -- or directly invalidate - ScanAll wipes tables, so just trigger a fresh get
    QR.PlayerInventory:ScanAll()
    -- Re-set after scan wipes
    QR.PlayerInventory.teleportItems[1] = { id = 1, data = { name = "Item1" } }
    QR.PlayerInventory.toys[2] = { id = 2, data = { name = "Toy1" } }
    QR.PlayerInventory.spells[3] = { id = 3, data = { name = "Spell1" } }

    -- ScanAll invalidated the cache, so next GetAllTeleports builds fresh
    local all = QR.PlayerInventory:GetAllTeleports()

    t:assertNotNil(all[1], "Item present in merged result")
    t:assertNotNil(all[2], "Toy present in merged result")
    t:assertNotNil(all[3], "Spell present in merged result")
    t:assertEqual("item", all[1].sourceType, "Item has sourceType item")
    t:assertEqual("toy", all[2].sourceType, "Toy has sourceType toy")
    t:assertEqual("spell", all[3].sourceType, "Spell has sourceType spell")
end)

T:run("GetAllTeleports: equipped items have sourceType equipped", function(t)
    resetState()
    -- Invalidate cache
    QR.PlayerInventory:ScanAll()
    -- Set after scan
    QR.PlayerInventory.teleportItems[1] = { id = 1, data = { name = "Ring" }, isEquipped = true, slotID = 11 }

    local all = QR.PlayerInventory:GetAllTeleports()

    t:assertNotNil(all[1], "Equipped item present")
    t:assertEqual("equipped", all[1].sourceType, "Equipped item has sourceType equipped")
end)

-------------------------------------------------------------------------------
-- 6. GetTeleportCount
-------------------------------------------------------------------------------

T:run("GetTeleportCount: counts all teleports", function(t)
    resetState()
    QR.PlayerInventory.teleportItems[1] = { id = 1 }
    QR.PlayerInventory.teleportItems[2] = { id = 2 }
    QR.PlayerInventory.toys[3] = { id = 3 }
    QR.PlayerInventory.spells[4] = { id = 4 }

    t:assertEqual(4, QR.PlayerInventory:GetTeleportCount(), "Count is 4")
end)

T:run("GetTeleportCount: returns 0 when empty", function(t)
    resetState()
    t:assertEqual(0, QR.PlayerInventory:GetTeleportCount(), "Count is 0")
end)

-------------------------------------------------------------------------------
-- 7. ScanAll
-------------------------------------------------------------------------------

T:run("ScanAll: returns combined result", function(t)
    resetState()

    local result = QR.PlayerInventory:ScanAll()

    t:assertNotNil(result, "ScanAll returns result")
    t:assertNotNil(result.items, "Result has items key")
    t:assertNotNil(result.toys, "Result has toys key")
    t:assertNotNil(result.spells, "Result has spells key")
end)
