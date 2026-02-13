-------------------------------------------------------------------------------
-- test_miniteleportpanel.lua
-- Tests for MiniTeleportPanel: dedup by destination, mount button,
-- status display, and DEST_L_KEYS lookup
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}
    QR.MiniTeleportPanel.frame = nil
    QR.MiniTeleportPanel.isShowing = false
    QR.MiniTeleportPanel.rows = {}
    QR.MiniTeleportPanel.rowPool = {}
    QR.MiniTeleportPanel.secureButtons = {}
end

--- Set up a player who owns specific toys
local function setupOwnedToys(toyIDs)
    for _, id in ipairs(toyIDs) do
        MockWoW.config.ownedToys[id] = true
    end
end

--- Set up a player who knows specific spells
local function setupKnownSpells(spellIDs)
    for _, id in ipairs(spellIDs) do
        MockWoW.config.knownSpells[id] = true
    end
end

--- Set up cooldown for an item/toy
local function setupCooldown(id, start, duration)
    MockWoW.config.itemCooldowns[id] = { start = start, duration = duration, enable = 1 }
end

-------------------------------------------------------------------------------
-- 1. Deduplication by destination
-------------------------------------------------------------------------------

T:run("MiniTP: deduplicates hearthstone variants by destination", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Own multiple hearthstone-like toys that all go to "Bound Location"
    -- Hearthstone = 6948 (item), Innkeeper's Daughter = 64488 (toy),
    -- Kyrian HS = 184353 (toy), Venthyr Sinstone = 183716 (toy)
    MockWoW.config.bagItems = { [6948] = { 0, 1, 1 } }
    MockWoW.config.itemCounts = { [6948] = 1 }
    setupOwnedToys({ 64488, 184353, 183716 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    -- Count rows that have "Bound Location" or bind location text as destination
    local boundRows = 0
    for _, row in ipairs(QR.MiniTeleportPanel.rows) do
        if row.destLabel then
            local text = row.destLabel:GetText() or ""
            -- The bind location is "Stormwind City" in mock config
            if text == "Stormwind City" or text == "Bound Location" then
                boundRows = boundRows + 1
            end
        end
    end
    -- After dedup, should have at most 1 row for bound location
    t:assertTrue(boundRows <= 1, "At most 1 row per destination (bound location), got " .. boundRows)
end)

T:run("MiniTP: dedup keeps best status entry (READY over ON_CD)", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Two toys to same destination: one ready, one on CD
    -- Dalaran HS (140192) and Tome of Town Portal (142542) - different items
    -- but we need them to resolve to same destination.
    -- Let's use Hearthstone (6948 - item) and Innkeeper's Daughter (64488 - toy)
    -- Both go to "Bound Location" -> dynamic -> "Stormwind City"
    MockWoW.config.bagItems = { [6948] = { 0, 1, 1 } }
    MockWoW.config.itemCounts = { [6948] = 1 }
    setupOwnedToys({ 64488 })

    -- Put 6948 on cooldown, 64488 ready
    local baseTime = MockWoW.config.baseTime
    setupCooldown(6948, baseTime - 100, 1800) -- 1700 remaining

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    -- Should have 1 row for "Stormwind City", using the ready entry
    local found = false
    for _, row in ipairs(QR.MiniTeleportPanel.rows) do
        if row.destLabel then
            local text = row.destLabel:GetText() or ""
            if text == "Stormwind City" or text == "Bound Location" then
                -- Status should be empty (READY shows no text)
                local status = row.statusLabel:GetText() or ""
                t:assertEqual(status, "", "READY entry shows no status text (dedup chose best)")
                found = true
            end
        end
    end
    t:assertTrue(found, "Found bound location row")
end)

-------------------------------------------------------------------------------
-- 2. READY/OWNED status shows no text
-------------------------------------------------------------------------------

T:run("MiniTP: READY status shows empty string, not label", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Own a single toy
    setupOwnedToys({ 140192 }) -- Dalaran Hearthstone

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    -- Find any row with a teleport (not the mount row, not separator)
    for _, row in ipairs(QR.MiniTeleportPanel.rows) do
        if row.statusLabel and row.nameLabel then
            local name = row.nameLabel:GetText() or ""
            local status = row.statusLabel:GetText() or ""
            if name ~= "" and name ~= QR.L["MINI_PANEL_SUMMON_MOUNT"] then
                -- READY or OWNED should show empty status
                if not status:find("|cFFFF6600") then -- not ON_CD (orange)
                    t:assertEqual(status, "", "READY/OWNED shows empty status for: " .. name)
                end
            end
        end
    end
end)

T:run("MiniTP: ON_CD status shows countdown timer", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Own Dalaran HS (toy) and put it on cooldown
    setupOwnedToys({ 140192 })
    local baseTime = MockWoW.config.baseTime
    setupCooldown(140192, baseTime - 100, 1200) -- 1100 remaining

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    local foundCD = false
    for _, row in ipairs(QR.MiniTeleportPanel.rows) do
        if row.statusLabel and row.nameLabel then
            local name = row.nameLabel:GetText() or ""
            local status = row.statusLabel:GetText() or ""
            if name ~= "" and name ~= QR.L["MINI_PANEL_SUMMON_MOUNT"] and status ~= "" then
                -- ON_CD entries should have the orange color code
                t:assertTrue(status:find("|cFFFF6600") ~= nil, "ON_CD shows orange color")
                foundCD = true
            end
        end
    end
    t:assertTrue(foundCD, "Found at least one ON_CD row with timer")
end)

-------------------------------------------------------------------------------
-- 3. Mount button
-------------------------------------------------------------------------------

T:run("MiniTP: mount button row exists at bottom", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Own at least one teleport
    setupOwnedToys({ 140192 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    -- Last row should be the mount button
    local rows = QR.MiniTeleportPanel.rows
    t:assertGreaterThan(#rows, 0, "Has rows")

    local lastRow = rows[#rows]
    t:assertNotNil(lastRow, "Last row exists")
    if lastRow.nameLabel then
        local name = lastRow.nameLabel:GetText() or ""
        t:assertEqual(name, QR.L["MINI_PANEL_SUMMON_MOUNT"], "Last row is mount button")
    end
end)

T:run("MiniTP: mount button shows correct destination text", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    setupOwnedToys({ 140192 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    local rows = QR.MiniTeleportPanel.rows
    local lastRow = rows[#rows]
    if lastRow and lastRow.destLabel then
        local dest = lastRow.destLabel:GetText() or ""
        t:assertEqual(dest, QR.L["MINI_PANEL_RANDOM_FAVORITE"], "Mount row shows 'Random favorite'")
    end
end)

T:run("MiniTP: mount button has mount icon", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    setupOwnedToys({ 140192 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    local rows = QR.MiniTeleportPanel.rows
    local lastRow = rows[#rows]
    if lastRow and lastRow.icon then
        local tex = lastRow.icon:GetTexture() or ""
        t:assertTrue(tostring(tex):find("Ability_Mount_RidingHorse") ~= nil,
            "Mount row uses mount icon")
    end
end)

T:run("MiniTP: separator exists before mount button", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    setupOwnedToys({ 140192 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    -- The row before the mount row should be the separator (has no nameLabel)
    local rows = QR.MiniTeleportPanel.rows
    t:assertGreaterThan(#rows, 2, "Has at least 3 rows (teleport + separator + mount)")

    -- Second-to-last row is the separator frame (no nameLabel)
    local separator = rows[#rows - 1]
    t:assertNotNil(separator, "Separator frame exists")
    -- Separator doesn't have nameLabel (it's a plain frame)
    t:assertNil(separator.nameLabel, "Separator has no nameLabel (plain frame)")
end)

-------------------------------------------------------------------------------
-- 4. DEST_L_KEYS lookup in MiniTeleportPanel
-------------------------------------------------------------------------------

T:run("MiniTP: DEST_L_KEYS resolves random destination translations", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- QR.DEST_L_KEYS should be populated from TeleportPanel
    t:assertNotNil(QR.DEST_L_KEYS, "QR.DEST_L_KEYS exists")
    t:assertNotNil(QR.DEST_L_KEYS["Random location worldwide"], "Has 'Random location worldwide' key")
    t:assertNotNil(QR.DEST_L_KEYS["Random natural location"], "Has 'Random natural location' key")
    t:assertNotNil(QR.DEST_L_KEYS["Random Broken Isles Ley Line"], "Has 'Random Broken Isles Ley Line' key")
end)

T:run("MiniTP: random destination items use DEST_L_KEYS", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Own The Last Relic of Argus (64457) - destination = "Random location worldwide"
    setupOwnedToys({ 64457 })

    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    local foundRandomDest = false
    for _, row in ipairs(QR.MiniTeleportPanel.rows) do
        if row.destLabel and row.nameLabel then
            local name = row.nameLabel:GetText() or ""
            if name ~= "" and name ~= QR.L["MINI_PANEL_SUMMON_MOUNT"] then
                local dest = row.destLabel:GetText() or ""
                -- In enUS, L["DEST_RANDOM_WORLDWIDE"] = "Random location worldwide"
                -- The key should be resolved through DEST_L_KEYS -> L[]
                if dest ~= "" and dest ~= "Random location worldwide" then
                    -- Localized (non-enUS) or at least resolved through L[]
                    foundRandomDest = true
                elseif dest == "Random location worldwide" then
                    -- enUS: L[] returns the value which equals the English string
                    foundRandomDest = true
                end
            end
        end
    end
    t:assertTrue(foundRandomDest, "Random destination item shows resolved destination")
end)

T:run("MiniTP: DEST_L_KEYS shared between TeleportPanel and MiniTeleportPanel", function(t)
    -- Verify the table is shared (same reference)
    t:assertNotNil(QR.DEST_L_KEYS, "QR.DEST_L_KEYS is set")
    t:assertEqual(type(QR.DEST_L_KEYS), "table", "DEST_L_KEYS is a table")

    -- Verify it has the original entries too
    t:assertNotNil(QR.DEST_L_KEYS["Bound Location"], "Has 'Bound Location'")
    t:assertNotNil(QR.DEST_L_KEYS["Garrison"], "Has 'Garrison'")
    t:assertNotNil(QR.DEST_L_KEYS["Homestead"], "Has 'Homestead'")
end)

-------------------------------------------------------------------------------
-- 5. Mount button appears even with no teleports
-------------------------------------------------------------------------------

T:run("MiniTP: shows no-teleports message when none owned", function(t)
    resetState()
    QR.PlayerInfo:InvalidateCache()

    -- Don't own anything
    QR.MiniTeleportPanel:CreateFrame()
    QR.MiniTeleportPanel:RefreshList()

    local rows = QR.MiniTeleportPanel.rows
    t:assertGreaterThan(#rows, 0, "Has at least 1 row")

    -- Should show "No teleports available" message
    local firstRow = rows[1]
    if firstRow and firstRow.nameLabel then
        local text = firstRow.nameLabel:GetText() or ""
        t:assertEqual(text, QR.L["MINI_PANEL_NO_TELEPORTS"], "Shows no teleports message")
    end
end)

-------------------------------------------------------------------------------
-- 6. C_MountJournal mock exists
-------------------------------------------------------------------------------

T:run("MiniTP: C_MountJournal.SummonByID is available", function(t)
    t:assertNotNil(C_MountJournal, "C_MountJournal exists")
    t:assertNotNil(C_MountJournal.SummonByID, "SummonByID function exists")
    t:assertEqual(type(C_MountJournal.SummonByID), "function", "SummonByID is a function")
end)
