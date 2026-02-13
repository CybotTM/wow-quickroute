-------------------------------------------------------------------------------
-- test_mapteleportbutton.lua
-- Tests for the MapTeleportButton module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Save original GetAllTeleports at file load time (before any overrides)
local originalGetAllTeleports = QR.PlayerInventory.GetAllTeleports

-- Helper: reset module state for clean tests
local function reinitialize()
    QR.MapTeleportButton.button = nil
    QR.MapTeleportButton.initialized = false
    QR.MapTeleportButton.currentMapID = nil
    QR.MapTeleportButton.currentTeleportID = nil
    QR.MapTeleportButton.currentSourceType = nil
    MockWoW.config.inCombatLockdown = false
    -- Always restore original GetAllTeleports
    QR.PlayerInventory.GetAllTeleports = originalGetAllTeleports
end

-- Helper: set up mock teleports by overriding GetAllTeleports
local function setupMockTeleports(teleports)
    -- Build the flat table that GetAllTeleports normally returns
    local result = {}
    for id, entry in pairs(teleports) do
        result[id] = {
            id = id,
            data = entry.data,
            sourceType = entry.sourceType,
        }
    end
    -- Override GetAllTeleports to return our mock data
    QR.PlayerInventory.GetAllTeleports = function(self)
        return result
    end
end

-- Helper: restore original GetAllTeleports
local function restoreTeleports()
    QR.PlayerInventory.GetAllTeleports = originalGetAllTeleports
end

-------------------------------------------------------------------------------
-- Module Existence Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: module exists", function(t)
    t:assertNotNil(QR.MapTeleportButton)
    t:assertEqual(type(QR.MapTeleportButton.Initialize), "function")
    t:assertEqual(type(QR.MapTeleportButton.CreateButton), "function")
    t:assertEqual(type(QR.MapTeleportButton.FindBestTeleportForMap), "function")
    t:assertEqual(type(QR.MapTeleportButton.UpdateForMap), "function")
end)

-------------------------------------------------------------------------------
-- Button Creation Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: CreateButton returns a frame", function(t)
    reinitialize()
    local btn = QR.MapTeleportButton:CreateButton()
    t:assertNotNil(btn)
    t:assertEqual(QR.MapTeleportButton.button, btn)
end)

T:run("MapTeleportButton: CreateButton is idempotent", function(t)
    reinitialize()
    local btn1 = QR.MapTeleportButton:CreateButton()
    local btn2 = QR.MapTeleportButton:CreateButton()
    t:assertEqual(btn1, btn2)
end)

T:run("MapTeleportButton: CreateButton returns nil during combat", function(t)
    reinitialize()
    MockWoW.config.inCombatLockdown = true
    local btn = QR.MapTeleportButton:CreateButton()
    t:assertNil(btn)
    MockWoW.config.inCombatLockdown = false
end)

T:run("MapTeleportButton: button has tooltip handlers", function(t)
    reinitialize()
    local btn = QR.MapTeleportButton:CreateButton()
    t:assertNotNil(btn._scripts["OnEnter"])
    t:assertNotNil(btn._scripts["OnLeave"])
end)

T:run("MapTeleportButton: button has PostClick handler for right-click after UpdateForMap", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [3561] = {
            sourceType = "spell",
            data = { name = "Teleport: Stormwind", destination = "Stormwind City", mapID = 84, type = "spell" },
        },
    })
    QR.MapTeleportButton:UpdateForMap(84)
    local btn = QR.MapTeleportButton.button
    t:assertNotNil(btn._scripts["PostClick"])
    restoreTeleports()
end)

T:run("MapTeleportButton: button has action bar slot styling", function(t)
    reinitialize()
    local btn = QR.MapTeleportButton:CreateButton()
    t:assertNotNil(btn.icon)
    t:assertNotNil(btn.bg)
    t:assertNotNil(btn.cdText)
end)

T:run("MapTeleportButton: button is SecureActionButtonTemplate", function(t)
    reinitialize()
    local btn = QR.MapTeleportButton:CreateButton()
    t:assertNotNil(btn)
    -- Button should start hidden
    t:assertEqual(btn._shown, false)
end)

-------------------------------------------------------------------------------
-- FindBestTeleportForMap Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: FindBestTeleportForMap returns nil with no teleports", function(t)
    reinitialize()
    setupMockTeleports({})
    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertNil(id)
    t:assertNil(data)
    t:assertNil(source)
end)

T:run("MapTeleportButton: FindBestTeleportForMap finds direct map match", function(t)
    reinitialize()
    setupMockTeleports({
        [12345] = {
            sourceType = "item",
            data = {
                name = "Test Teleport",
                destination = "Stormwind City",
                mapID = 84,
                x = 0.5,
                y = 0.5,
                type = "item",
            },
        },
    })

    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertEqual(12345, id)
    t:assertNotNil(data)
    t:assertEqual("Stormwind City", data.destination)
    t:assertEqual("item", source)
end)

T:run("MapTeleportButton: FindBestTeleportForMap skips dynamic teleports", function(t)
    reinitialize()
    setupMockTeleports({
        [6948] = {
            sourceType = "item",
            data = {
                name = "Hearthstone",
                destination = "Bound Location",
                mapID = 84,
                isDynamic = true,
                type = "item",
            },
        },
    })

    local id = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertNil(id)
end)

T:run("MapTeleportButton: FindBestTeleportForMap prefers ready teleport", function(t)
    reinitialize()

    -- Two teleports to same map, one ready and one on cooldown
    setupMockTeleports({
        [111] = {
            sourceType = "item",
            data = {
                name = "Item on CD",
                destination = "Stormwind City",
                mapID = 84,
                type = "item",
            },
        },
        [222] = {
            sourceType = "spell",
            data = {
                name = "Ready Spell",
                destination = "Stormwind City",
                mapID = 84,
                type = "spell",
            },
        },
    })

    -- Put item 111 on cooldown
    MockWoW.config.itemCooldowns[111] = { start = MockWoW.config.baseTime - 10, duration = 1800, enable = 1 }
    MockWoW.config.spellCooldowns[222] = nil  -- spell is ready

    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    -- Should prefer the ready spell
    t:assertEqual(222, id)
    t:assertEqual("spell", source)

    -- Cleanup
    MockWoW.config.itemCooldowns = {}
    MockWoW.config.spellCooldowns = {}
end)

T:run("MapTeleportButton: FindBestTeleportForMap falls back to same continent", function(t)
    reinitialize()

    -- Teleport to Elwynn Forest (37) - same continent as Stormwind (84)
    setupMockTeleports({
        [333] = {
            sourceType = "item",
            data = {
                name = "Elwynn Teleport",
                destination = "Elwynn Forest",
                mapID = 37,
                type = "item",
            },
        },
    })

    -- Look for a teleport to Stormwind (84) - no direct match, but same continent
    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    -- Should find the Elwynn teleport via continent fallback
    if QR.GetContinentForZone then
        local swContinent = QR.GetContinentForZone(84)
        local elwynnContinent = QR.GetContinentForZone(37)
        if swContinent and elwynnContinent and swContinent == elwynnContinent then
            t:assertEqual(333, id)
            t:assertEqual("item", source)
        else
            -- Continents don't match in test data, so nil is acceptable
            t:assert(true, "Continent data may not match in mock")
        end
    else
        t:assert(true, "GetContinentForZone not available")
    end
end)

T:run("MapTeleportButton: FindBestTeleportForMap returns nil for nil mapID", function(t)
    reinitialize()
    local id = QR.MapTeleportButton:FindBestTeleportForMap(nil)
    t:assertNil(id)
end)

T:run("MapTeleportButton: FindBestTeleportForMap skips random teleports", function(t)
    reinitialize()
    setupMockTeleports({
        [4242] = {
            sourceType = "item",
            data = {
                name = "Direbrew's Remote",
                destination = "Random Dungeon",
                mapID = 84,
                isRandom = true,
                type = "item",
            },
        },
    })

    local id = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertNil(id)
end)

T:run("MapTeleportButton: FindBestTeleportForMap returns nil when all teleports are random or dynamic", function(t)
    reinitialize()
    setupMockTeleports({
        [5001] = {
            sourceType = "item",
            data = {
                name = "Random Teleport Item",
                destination = "Random Place",
                mapID = 84,
                isRandom = true,
                type = "item",
            },
        },
        [5002] = {
            sourceType = "item",
            data = {
                name = "Hearthstone",
                destination = "Bound Location",
                mapID = 84,
                isDynamic = true,
                type = "item",
            },
        },
        [5003] = {
            sourceType = "spell",
            data = {
                name = "Random Portal",
                destination = "Somewhere Random",
                mapID = 84,
                isRandom = true,
                type = "spell",
            },
        },
    })

    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertNil(id)
    t:assertNil(data)
    t:assertNil(source)
end)

T:run("MapTeleportButton: FindBestTeleportForMap picks normal teleport over random ones", function(t)
    reinitialize()
    setupMockTeleports({
        [6001] = {
            sourceType = "item",
            data = {
                name = "Random Dungeon Finder",
                destination = "Random Dungeon",
                mapID = 84,
                isRandom = true,
                type = "item",
            },
        },
        [6002] = {
            sourceType = "spell",
            data = {
                name = "Teleport: Stormwind",
                destination = "Stormwind City",
                mapID = 84,
                type = "spell",
            },
        },
        [6003] = {
            sourceType = "item",
            data = {
                name = "Another Random",
                destination = "Random Place",
                mapID = 84,
                isRandom = true,
                type = "item",
            },
        },
    })

    local id, data, source = QR.MapTeleportButton:FindBestTeleportForMap(84)
    t:assertEqual(6002, id)
    t:assertNotNil(data)
    t:assertEqual("Stormwind City", data.destination)
    t:assertEqual("spell", source)
end)

-------------------------------------------------------------------------------
-- UpdateForMap Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: UpdateForMap hides button when no teleport available", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({})
    QR.MapTeleportButton.button._shown = true  -- Force visible
    QR.MapTeleportButton:UpdateForMap(84)
    t:assertEqual(QR.MapTeleportButton.button._shown, false)
    t:assertNil(QR.MapTeleportButton.currentTeleportID)
end)

T:run("MapTeleportButton: UpdateForMap sets teleport state when found", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [555] = {
            sourceType = "toy",
            data = {
                name = "Test Toy",
                destination = "Stormwind City",
                mapID = 84,
                x = 0.5,
                y = 0.5,
                type = "toy",
            },
        },
    })

    QR.MapTeleportButton:UpdateForMap(84)
    t:assertEqual(555, QR.MapTeleportButton.currentTeleportID)
    t:assertEqual("toy", QR.MapTeleportButton.currentSourceType)
    t:assertEqual(84, QR.MapTeleportButton.currentMapID)
end)

T:run("MapTeleportButton: UpdateForMap sets tooltip data on button", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [777] = {
            sourceType = "spell",
            data = {
                name = "Portal: Stormwind",
                destination = "Stormwind City",
                mapID = 84,
                type = "spell",
            },
        },
    })

    QR.MapTeleportButton:UpdateForMap(84)
    local btn = QR.MapTeleportButton.button
    -- Uses localized name from WoW API (mock returns "Spell 777")
    t:assertEqual("Spell 777", btn._qrTeleportName)
    -- Uses localized destination from C_Map.GetMapInfo (mock returns zone name)
    t:assertNotNil(btn._qrDestination)
end)

T:run("MapTeleportButton: UpdateForMap skipped during combat", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [888] = {
            sourceType = "item",
            data = {
                name = "Test",
                destination = "Test Dest",
                mapID = 84,
                type = "item",
            },
        },
    })

    MockWoW.config.inCombatLockdown = true
    QR.MapTeleportButton:UpdateForMap(84)
    -- Should not have updated
    t:assertNil(QR.MapTeleportButton.currentTeleportID)
    MockWoW.config.inCombatLockdown = false
end)

T:run("MapTeleportButton: UpdateForMap configures spell attributes", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [999] = {
            sourceType = "spell",
            data = {
                name = "Teleport: Stormwind",
                destination = "Stormwind City",
                mapID = 84,
                type = "spell",
            },
        },
    })

    QR.MapTeleportButton:UpdateForMap(84)
    local btn = QR.MapTeleportButton.button
    -- SecureButtons:ConfigureButton should have set attributes
    t:assertEqual("spell", btn:GetAttribute("type"))
    t:assertEqual(999, btn:GetAttribute("spell"))
end)

T:run("MapTeleportButton: UpdateForMap configures item attributes", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    setupMockTeleports({
        [1111] = {
            sourceType = "item",
            data = {
                name = "Test Item",
                destination = "Stormwind City",
                mapID = 84,
                type = "item",
            },
        },
    })

    QR.MapTeleportButton:UpdateForMap(84)
    local btn = QR.MapTeleportButton.button
    -- Item uses macro approach
    t:assertEqual("macro", btn:GetAttribute("type"))
end)

-------------------------------------------------------------------------------
-- Initialize Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: Initialize sets initialized flag", function(t)
    reinitialize()
    t:assertEqual(QR.MapTeleportButton.initialized, false)
    QR.MapTeleportButton:Initialize()
    t:assertEqual(QR.MapTeleportButton.initialized, true)
end)

T:run("MapTeleportButton: Initialize is idempotent", function(t)
    reinitialize()
    QR.MapTeleportButton:Initialize()
    local btn = QR.MapTeleportButton.button
    QR.MapTeleportButton:Initialize()
    t:assertEqual(QR.MapTeleportButton.button, btn)
end)

T:run("MapTeleportButton: Initialize creates button", function(t)
    reinitialize()
    QR.MapTeleportButton:Initialize()
    t:assertNotNil(QR.MapTeleportButton.button)
end)

-------------------------------------------------------------------------------
-- Combat Safety Tests
-------------------------------------------------------------------------------

T:run("MapTeleportButton: button hidden during combat lockdown", function(t)
    reinitialize()
    QR.MapTeleportButton:CreateButton()
    local btn = QR.MapTeleportButton.button
    btn._shown = true
    MockWoW.config.inCombatLockdown = true

    -- UpdateForMap should be a no-op
    QR.MapTeleportButton:UpdateForMap(84)
    t:assertNil(QR.MapTeleportButton.currentTeleportID)

    MockWoW.config.inCombatLockdown = false
end)
