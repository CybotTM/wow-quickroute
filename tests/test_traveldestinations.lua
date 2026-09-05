local T, QR, MockWoW = ...

local function Copy(value)
    local result = {}
    for key, field in pairs(value or {}) do result[key] = field end
    return result
end

T:run("Travel catalogue: Mole Machine exposes all 31 choices with discovery requirements", function(t)
    local choices = QR.TeleportDestinations:GetDestinations(265225, QR.RacialTeleportSpells[265225])
    t:assertEqual(31, #choices, "all 31 Mole Machine destinations are catalogued")
    local free, locked, foundFirePlume = 0, 0, false
    for _, choice in ipairs(choices) do
        if choice.requirements and choice.requirements.quest then
            locked = locked + 1
            if choice.requirements.quest == 53591 then foundFirePlume = choice.mapID == 78 end
        else
            free = free + 1
        end
        t:assertNotNil(choice.choiceText, "each Mole Machine landing has a user selection label")
    end
    t:assertEqual(3, free, "three initial destinations require no discovery quest")
    t:assertEqual(28, locked, "28 discovered destinations retain individual unlock requirements")
    t:assertTrue(foundFirePlume, "Fire Plume Ridge is gated by its own discovery flag")
end)

T:run("Travel catalogue: faction-dependent garrisons do not share a landing", function(t)
    local choices = QR.TeleportDestinations:GetDestinations(110560, QR.TeleportItemsData[110560])
    t:assertEqual(2, #choices, "garrison offers two independently restricted faction destinations")
    local maps = {}
    for _, choice in ipairs(choices) do maps[choice.requirements.faction] = choice.mapID end
    t:assertEqual(582, maps.Alliance, "Alliance hearthstone lands in Lunarfall")
    t:assertEqual(525, maps.Horde, "Horde hearthstone lands in Frostwall")
end)

T:run("Travel catalogue: random and placeholder wormholes cannot claim exact landing routes", function(t)
    for _, id in ipairs({ 151652, 87215, 112059 }) do
        local choices = QR.TeleportDestinations:GetDestinations(id, QR.TeleportItemsData[id])
        t:assertEqual(0, #choices, "unverified random or zone-centre landing is excluded for " .. id)
    end
    local choices = QR.TeleportDestinations:GetDestinations(48933, QR.TeleportItemsData[48933])
    t:assertEqual(5, #choices, "Northrend includes the fifth normal Icecrown landing")
    t:assertEqual("toy", QR.TeleportItemsData[48933].type, "owned generator is scanned through the toy box")
    t:assertNil(QR.RacialTeleportSpells[255661], "mailbox summon is not advertised as a teleport")
end)

T:run("Travel catalogue: modern items and spell cast times are available", function(t)
    for _, id in ipairs({ 253629, 252607, 279550, 211788 }) do
        t:assertNotNil(QR.TeleportItemsData[id], "new travel item " .. id .. " is catalogued")
        t:assertGreaterThan(#QR.TeleportDestinations:GetDestinations(id, QR.TeleportItemsData[id]), 0,
            "new travel item " .. id .. " has an actual landing")
    end
    t:assertEqual(10, QR.MageTeleports.Alliance[3561].castTime, "Stormwind teleport has a ten-second cast")
    t:assertEqual(13, QR.TravelTime:GetTeleportTime({ type = "spell", class = "MAGE", castTime = 10 }),
        "route estimate includes cast time and loading")
end)

T:run("Travel destinations: Make Camp clears obsolete and other-character coordinates", function(t)
    MockWoW:Reset()
    local oldDB, oldGUID = QR.db, _G.UnitGUID
    local oldPosition = C_Map.GetPlayerMapPosition
    QR.db = {}
    _G.UnitGUID = function() return "Player-Camp-A" end
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.2, 0.7 end } end
    QR.TeleportDestinations:RecordCamp()
    local choices = QR.TeleportDestinations:GetDestinations(312372, QR.RacialTeleportSpells[312372])
    t:assertEqual(1, #choices, "successful Make Camp position becomes routable")
    t:assertEqual(0.2, choices[1] and choices[1].x, "camp uses the actual map position")
    _G.UnitGUID = function() return "Player-Camp-B" end
    t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(312372, QR.RacialTeleportSpells[312372]),
        "another character cannot route to the first character's camp")
    _G.UnitGUID = function() return "Player-Camp-A" end
    C_Map.GetPlayerMapPosition = function() return nil end
    QR.TeleportDestinations:RecordCamp()
    t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(312372, QR.RacialTeleportSpells[312372]),
        "an unavailable replacement position removes the obsolete camp")
    QR.db, _G.UnitGUID, C_Map.GetPlayerMapPosition = oldDB, oldGUID, oldPosition
end)

T:run("Travel destinations: housing requires observed plot coordinates and keeps secure identity", function(t)
    MockWoW:Reset()
    local oldDB, oldHousing, oldNeighborhood = QR.db, _G.C_Housing, _G.C_HousingNeighborhood
    local oldHouses = QR.TeleportDestinations.houses
    QR.db = {}
    _G.C_Housing = {
        GetCurrentNeighborhoodGUID = function() return "Neighborhood-Own" end,
        GetUIMapIDForNeighborhood = function() return 2351 end,
    }
    _G.C_HousingNeighborhood = { GetNeighborhoodMapData = function()
        return { { plotID = 7, mapPosition = { GetXY = function() return 0.31, 0.46 end } } }
    end }
    local house = { neighborhoodGUID = "Neighborhood-Own", houseGUID = "House-Own", plotID = 7, houseName = "Home" }
    QR.TeleportDestinations:SetHouses({ house })
    local data = QR.GeneralTeleportSpells[1233637]
    local choices = QR.TeleportDestinations:GetDestinations(1233637, data)
    t:assertEqual(1, #choices, "an owned house with a real plot position becomes routable")
    t:assertEqual(0.31, choices[1] and choices[1].x, "the exact plot position is used")
    local button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    t:assertTrue(QR.SecureButtons:ConfigureButton(button, 1233637, "spell", choices[1]),
        "housing candidate configures a protected action")
    t:assertEqual("teleporthome", button:GetAttribute("type"), "housing uses Blizzard's native secure action")
    t:assertEqual("House-Own", button:GetAttribute("house-guid"), "selected house GUID reaches the secure action")
    t:assertEqual(7, button:GetAttribute("house-plot-id"), "selected plot reaches the secure action")
    QR.SecureButtons:ConfigureButton(button, 6948, "item")
    t:assertNil(button:GetAttribute("house-guid"), "reused item button has no stale house identity")
    house.plotID = 8
    QR.TeleportDestinations:SetHouses({ house })
    t:assertEqual(0, #QR.TeleportDestinations:GetDestinations(1233637, data),
        "moving to an unobserved plot does not reuse the former plot position")
    QR.db, _G.C_Housing, _G.C_HousingNeighborhood = oldDB, oldHousing, oldNeighborhood
    QR.TeleportDestinations.houses = oldHouses
end)

T:run("Travel inventory: engineer toys and modern spellbook ownership are detected", function(t)
    MockWoW:Reset()
    local savedData = QR.TeleportItemsData[999900]
    local savedToys, savedSpells = Copy(QR.PlayerInventory.toys), Copy(QR.PlayerInventory.spells)
    local oldSpellBook = _G.C_SpellBook
    QR.TeleportItemsData[999900] = { name = "Engineering fixture", type = "engineer" }
    MockWoW.config.ownedToys[999900] = true
    QR.PlayerInventory:ScanToys()
    t:assertNotNil(QR.PlayerInventory.toys[999900], "engineering toy is owned without occupying a bag slot")
    _G.C_SpellBook = { IsSpellKnown = function(id) return id == 312372 end }
    QR.PlayerInventory:ScanSpells()
    t:assertNotNil(QR.PlayerInventory.spells[312372], "modern C_SpellBook ownership is used")
    QR.TeleportItemsData[999900], _G.C_SpellBook = savedData, oldSpellBook
    wipe(QR.PlayerInventory.toys)
    wipe(QR.PlayerInventory.spells)
    for id, value in pairs(savedToys) do QR.PlayerInventory.toys[id] = value end
    for id, value in pairs(savedSpells) do QR.PlayerInventory.spells[id] = value end
end)

T:run("Travel movement: actual capability and speed override area-only flying guesses", function(t)
    MockWoW:Reset()
    local saved = {}
    for _, key in ipairs({ "GetUnitSpeed", "IsFlying", "IsMounted", "IsIndoors", "IsAdvancedFlyableArea", "C_PlayerInfo" }) do
        saved[key] = _G[key]
    end
    local oldMountIDs = C_MountJournal.GetMountIDs
    C_MountJournal.GetMountIDs = function() return {} end
    _G.GetUnitSpeed = function() return 7, 7, 28.7, 4.7 end
    _G.IsFlying, _G.IsMounted, _G.IsIndoors = function() return false end, function() return false end, function() return false end
    MockWoW.config.currentMapID, MockWoW.config.isFlyableArea = 84, true
    QR.TravelTime:ClearMovementCache()
    t:assertEqual(7, QR.TravelTime:GetMovementSpeed(84, true), "flyable area alone does not grant a mount or flying")
    _G.IsFlying = function() return true end
    QR.TravelTime:ClearMovementCache()
    t:assertEqual(28.7, QR.TravelTime:GetMovementSpeed(84, true), "client flight speed is used when actually flying")
    t:assertEqual(7, QR.TravelTime:GetMovementSpeed(87, true), "current flight speed is not projected into a remote map")
    _G.IsAdvancedFlyableArea = function() return true end
    _G.C_PlayerInfo = { GetGlidingInfo = function() return true, true, 82 end }
    QR.TravelTime:ClearMovementCache()
    t:assertEqual(82, QR.TravelTime:GetMovementSpeed(84, true), "active skyriding uses measured forward speed")
    _G.C_PlayerInfo.GetGlidingInfo = function() return true, true, 0 / 0 end
    QR.TravelTime:ClearMovementCache()
    t:assertEqual(28.7, QR.TravelTime:GetMovementSpeed(84, true), "invalid skyriding speed falls back to actual flight capability")
    for _, key in ipairs({ "GetUnitSpeed", "IsFlying", "IsMounted", "IsIndoors", "IsAdvancedFlyableArea", "C_PlayerInfo" }) do
        _G[key] = saved[key]
    end
    C_MountJournal.GetMountIDs = oldMountIDs
    QR.TravelTime:ClearMovementCache()
end)

T:run("Travel inventory: unknown toy usability fails closed and profession changes invalidate cached access", function(t)
    MockWoW:Reset()
    local savedToys = Copy(QR.PlayerInventory.toys)
    local oldUsable, oldInvalidate = C_ToyBox.IsToyUsable, QR.PlayerInfo.InvalidateCache
    local oldPending = QR.PlayerInventory.pendingScan
    MockWoW.config.ownedToys[48933] = true
    C_ToyBox.IsToyUsable = function() error("client information is unavailable") end
    local ok = pcall(function() QR.PlayerInventory:ScanToys() end)
    t:assertTrue(ok, "an unavailable toy API does not abort inventory scanning")
    local toy = QR.PlayerInventory.toys[48933]
    t:assertNotNil(toy, "owned toy remains visible in the inventory")
    t:assertFalse(toy and toy.isUsable, "unknown usability cannot enable a route")
    local invalidations = 0
    QR.PlayerInfo.InvalidateCache = function() invalidations = invalidations + 1 end
    QR.PlayerInventory.pendingScan = true
    local frame = QR.PlayerInventory.eventFrame
    frame:GetScript("OnEvent")(frame, "SKILL_LINES_CHANGED")
    t:assertEqual(1, invalidations, "profession eligibility invalidates even with an inventory rescan pending")
    C_ToyBox.IsToyUsable, QR.PlayerInfo.InvalidateCache = oldUsable, oldInvalidate
    QR.PlayerInventory.pendingScan = oldPending
    wipe(QR.PlayerInventory.toys)
    for id, value in pairs(savedToys) do QR.PlayerInventory.toys[id] = value end
end)

T:run("Travel time: current client cast time overrides the static travel catalogue", function(t)
    local oldItemSpell, oldSpellInfo = C_Item.GetItemSpell, C_Spell.GetSpellInfo
    C_Item.GetItemSpell = function() return "Generator activation", 999901 end
    C_Spell.GetSpellInfo = function() return { castTime = 7000 } end
    t:assertEqual(12, QR.TravelTime:GetEffectiveTime(48933, { type = "toy", castTime = 5 }, false, "toy"),
        "seven-second live item activation plus five-second loading overrides a stale five-second cast")
    C_Item.GetItemSpell, C_Spell.GetSpellInfo = oldItemSpell, oldSpellInfo
end)
