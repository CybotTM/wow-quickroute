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

T:run("ScanSpells: learned alternate Shattrath variant becomes a routing option", function(t)
    resetState()
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    QR.PlayerInventory:ScanAll()
    t:assertNil(QR.PlayerInventory.spells[35715], "Unlearned Shattrath spell 35715 is unavailable")

    MockWoW.config.knownSpells[35715] = true
    QR.PlayerInventory:ScanAll()
    local teleport = QR.PlayerInventory:GetAllTeleports()[35715]
    t:assertNotNil(teleport, "Learned spell 35715 is included in routing inventory")
    t:assertEqual("spell", teleport and teleport.sourceType, "Shattrath variant is activated as a spell")
    t:assertNil(QR.PlayerInventory.spells[33690], "Learning 35715 does not claim the other variant is learned")

    local graph = QR.Graph:New()
    QR.PathCalculator.AddPlayerTeleportEdges({ graph = graph })
    -- The generated Mapzeroth supplement adds this ID at addon load; checking
    -- only TeleportItems would miss the spell and its sourced graph node.
    local edge = graph:GetEdge("Player Location", "Travel:SHATTRATH_OUTLANDS")
    t:assertEqual(35715, edge and edge.data.teleportID, "Shattrath route uses the learned alternate spell ID")
    local destination = graph.nodes["Travel:SHATTRATH_OUTLANDS"]
    t:assertEqual(111, destination and destination.mapID, "Alternate spell routes to sourced Shattrath map 111")
    t:assertEqual(0.5497, destination and destination.x, "Alternate spell retains sourced Shattrath landing X")
    t:assertEqual(0.4023, destination and destination.y, "Alternate spell retains sourced Shattrath landing Y")
    local existing = QR.TeleportDestinations:GetDestinations(33690, QR.MageTeleports.Shared[33690])[1]
    t:assertEqual(existing and existing.mapID, destination and destination.mapID,
        "Both spell variants resolve to Shattrath's map")

    MockWoW.config.playerFaction = "Alliance"
    MockWoW.config.knownSpells[35715] = nil
    MockWoW.config.knownSpells[33690] = true
    QR.PlayerInfo:InvalidateCache()
    QR.PlayerInventory:ScanAll()
    t:assertNil(QR.PlayerInventory.spells[35715], "Learning only 33690 does not expose spell 35715")
    t:assertNotNil(QR.PlayerInventory.spells[33690], "The original learned Shattrath spell remains available")

    MockWoW.config.playerFaction = "Horde"
    MockWoW.config.playerClass = "WARRIOR"
    MockWoW.config.knownSpells[35715] = true
    QR.PlayerInfo:InvalidateCache()
    QR.PlayerInventory:ScanAll()
    t:assertNil(QR.PlayerInventory.spells[35715], "Shattrath variant is excluded for non-mages")
    resetState()
    QR.PlayerInventory:ScanAll()
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

-------------------------------------------------------------------------------
-- Equipped teleport items
--
-- A worn item is not in the bags, so it is only found if ScanEquipped looks at
-- its slot. The slot list used to be hand-written -- rings, tabard, trinkets --
-- while TeleportItemsData declared eleven items in three further slots: the six
-- guild cloaks and Mountebank's Colorful Cloak on the back, three pairs of
-- slippers on the feet, and the Blessed Medallion of Karabor on the neck. While
-- worn, none of them was owned, so the panel drew a plain icon instead of a
-- button and clicking it did nothing.
-------------------------------------------------------------------------------

T:run("PlayerInventory: an equipped teleport item is found in every slot the data uses", function(t)
    local slots = {}
    for id, data in pairs(QR.TeleportItemsData or {}) do
        if data.equipSlot and data.type ~= QR.TeleportTypes.TOY and not slots[data.equipSlot] then
            slots[data.equipSlot] = id
        end
    end

    local ordered = {}
    for slot in pairs(slots) do ordered[#ordered + 1] = slot end
    table.sort(ordered)
    t:assertGreaterThan(#ordered, 1, "the data declares more than one equip slot")

    local missed = {}
    for _, slot in ipairs(ordered) do
        local itemID = slots[slot]
        resetState()
        MockWoW.config.equippedItems[slot] = itemID
        QR.PlayerInventory:ScanEquipped()
        if not QR.PlayerInventory:HasTeleport(itemID) then
            missed[#missed + 1] = string.format("slot %d (item %d, %s)",
                slot, itemID, QR.TeleportItemsData[itemID].name or "?")
        end
    end
    t:assertEqual(0, #missed,
        "every declared equip slot is scanned; missed: " .. table.concat(missed, ", "))
end)

T:run("PlayerInventory: a worn guild cloak is owned", function(t)
    resetState()
    -- Shroud of Cooperation, Horde. Back slot, which the old list omitted.
    MockWoW.config.equippedItems[15] = 63353
    QR.PlayerInventory:ScanEquipped()
    t:assertTrue(QR.PlayerInventory:HasTeleport(63353),
        "a cloak worn in slot 15 counts as owned")
end)

T:run("PlayerInventory: a ring declared for finger 1 is found on finger 2", function(t)
    resetState()
    -- Signet of the Kirin Tor declares INVSLOT_FINGER1, but a ring can be worn
    -- in either finger, so both slots have to be scanned.
    MockWoW.config.equippedItems[12] = 40585
    QR.PlayerInventory:ScanEquipped()
    t:assertTrue(QR.PlayerInventory:HasTeleport(40585),
        "the paired finger slot is scanned too")
end)

-------------------------------------------------------------------------------
-- A scan the container API cannot answer
--
-- The empty teleport list, reported from the client: use a teleport, and the
-- list is empty until the window is closed and reopened. The bag event the
-- teleport fires schedules a rescan, the teleport is followed by a loading
-- screen, and the rescan lands inside it. The container API answers 0 slots
-- there -- indistinguishable, to the caller, from bags that are simply empty --
-- and ScanBags wiped on that answer. With the panel's availability filter on
-- "usable" the list then draws nothing at all.
-------------------------------------------------------------------------------

T:run("PlayerInventory: a scan the container API cannot answer keeps the last one", function(t)
    resetState()
    MockWoW.config.bagItems = {
        [6948]  = { bagID = 0, slot = 1, count = 1 },
        [63352] = { bagID = 0, slot = 2, count = 1 },
    }
    QR.PlayerInventory:ScanAll()
    local before = 0
    for _ in pairs(QR.PlayerInventory.teleportItems) do before = before + 1 end
    t:assertEqual(2, before, "two items to begin with")

    -- Every bag reports no slots, which is what the API does while it has no
    -- answer. A character always has a backpack, so this cannot be real.
    local realNumSlots = C_Container.GetContainerNumSlots
    C_Container.GetContainerNumSlots = function() return 0 end
    QR.PlayerInventory:ScanAll()
    local during = 0
    for _ in pairs(QR.PlayerInventory.teleportItems) do during = during + 1 end
    C_Container.GetContainerNumSlots = realNumSlots

    t:assertEqual(2, during,
        "the previous scan survives instead of being wiped to nothing")
end)

T:run("PlayerInventory: bags that answer and hold nothing do write an empty result", function(t)
    resetState()
    MockWoW.config.bagItems = { [6948] = { bagID = 0, slot = 1, count = 1 } }
    QR.PlayerInventory:ScanAll()
    t:assertTrue(QR.PlayerInventory:HasTeleport(6948), "the item is there first")

    -- Sold, dropped, or used up. The bags report their slots, so zero is a real
    -- answer and has to be written -- the guard above must not swallow it.
    MockWoW.config.bagItems = {}
    QR.PlayerInventory:ScanAll()
    t:assertFalse(QR.PlayerInventory:HasTeleport(6948),
        "a genuine empty result still replaces the previous scan")
end)
