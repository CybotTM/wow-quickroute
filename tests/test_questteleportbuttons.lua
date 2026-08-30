-------------------------------------------------------------------------------
-- test_questteleportbuttons.lua
-- Tests for the QuestTeleportButtons module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Stash original mock state for restoration
local origQuestWaypoints = {}
local origQuestTitles = {}
local origKnownSpells = {}
local origOwnedToys = {}
local origBagItems = {}
local origQuestWatches = {}
local origInCombat = false

-- Helper: save and restore global state
local function saveState()
    origInCombat = MockWoW.config.inCombatLockdown
    origQuestWaypoints = {}
    for k, v in pairs(MockWoW.config.questWaypoints) do origQuestWaypoints[k] = v end
    origQuestTitles = {}
    for k, v in pairs(MockWoW.config.questTitles) do origQuestTitles[k] = v end
    origKnownSpells = {}
    for k, v in pairs(MockWoW.config.knownSpells) do origKnownSpells[k] = v end
    origOwnedToys = {}
    for k, v in pairs(MockWoW.config.ownedToys) do origOwnedToys[k] = v end
    origBagItems = {}
    for k, v in pairs(MockWoW.config.bagItems) do origBagItems[k] = v end
    origQuestWatches = {}
    for k, v in pairs(MockWoW.config.questWatches) do origQuestWatches[k] = v end
end

local function restoreState()
    MockWoW.config.inCombatLockdown = origInCombat
    MockWoW.config.questWaypoints = origQuestWaypoints
    MockWoW.config.questTitles = origQuestTitles
    MockWoW.config.knownSpells = origKnownSpells
    MockWoW.config.ownedToys = origOwnedToys
    MockWoW.config.bagItems = origBagItems
    MockWoW.config.questWatches = origQuestWatches
end

-- Helper: reinitialize the module for clean tests
local function reinitialize()
    restoreState()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.questWatches = {}
    MockWoW.config.questWaypoints = {}
    MockWoW.config.questTitles = {}

    -- Reset the module state
    QR.QuestTeleportButtons.initialized = false
    QR.QuestTeleportButtons.pool = {}
    QR.QuestTeleportButtons.activeButtons = {}
    QR.QuestTeleportButtons.questCache = {}
    QR.QuestTeleportButtons.updateElapsed = 0
    QR.QuestTeleportButtons.enabled = true
    QR.QuestTeleportButtons.updateFrame = nil
    QR.QuestTeleportButtons.eventFrame = nil
end

-- Helper: set up test teleport data
-- Creates a known spell teleport to Stormwind (mapID=84)
local function setupTestTeleports()
    MockWoW.config.knownSpells[3561] = true  -- Teleport: Stormwind
    -- Rescan inventory so GetAllTeleports picks it up
    if QR.PlayerInventory and QR.PlayerInventory.ScanAll then
        QR.PlayerInventory:ScanAll()
    end
end

-- Helper: set up a tracked quest with waypoint
local function setupTrackedQuest(questID, mapID, title)
    title = title or ("Test Quest " .. tostring(questID))
    MockWoW.config.questTitles[questID] = title
    MockWoW.config.questWaypoints[questID] = { mapID = mapID, x = 0.5, y = 0.5 }
    local watches = MockWoW.config.questWatches
    watches[#watches + 1] = questID
end

-------------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------------

-- Save state at start
saveState()

T:run("QuestTeleportButtons: module exists with expected API", function(t)
    t:assertNotNil(QR.QuestTeleportButtons, "Module exists")
    t:assertEqual(type(QR.QuestTeleportButtons.Initialize), "function", "Initialize method")
    t:assertEqual(type(QR.QuestTeleportButtons.RefreshButtons), "function", "RefreshButtons method")
    t:assertEqual(type(QR.QuestTeleportButtons.ReleaseAllButtons), "function", "ReleaseAllButtons method")
    t:assertEqual(type(QR.QuestTeleportButtons.InvalidateCache), "function", "InvalidateCache method")
    t:assertEqual(type(QR.QuestTeleportButtons.SetEnabled), "function", "SetEnabled method")
    t:assertEqual(type(QR.QuestTeleportButtons.OnUpdate), "function", "OnUpdate method")
    t:assertEqual(type(QR.QuestTeleportButtons.GetPoolSize), "function", "GetPoolSize method")
    t:assertEqual(type(QR.QuestTeleportButtons.GetCacheTTL), "function", "GetCacheTTL method")
end)

T:run("QuestTeleportButtons: Initialize creates button pool", function(t)
    reinitialize()
    t:assertEqual(QR.QuestTeleportButtons.initialized, false, "Not initialized before Initialize()")
    QR.QuestTeleportButtons:Initialize()
    t:assertEqual(QR.QuestTeleportButtons.initialized, true, "Initialized after Initialize()")
    t:assertEqual(#QR.QuestTeleportButtons.pool, QR.QuestTeleportButtons:GetPoolSize(),
        "Pool has correct number of buttons")
end)

T:run("QuestTeleportButtons: Initialize is idempotent", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    local firstPool = QR.QuestTeleportButtons.pool
    local poolSize = #firstPool
    QR.QuestTeleportButtons:Initialize()
    t:assertEqual(#QR.QuestTeleportButtons.pool, poolSize, "Pool size unchanged after re-init")
    t:assertEqual(QR.QuestTeleportButtons.pool, firstPool, "Pool table reference unchanged")
end)

T:run("QuestTeleportButtons: Initialize deferred during combat", function(t)
    reinitialize()
    MockWoW.config.inCombatLockdown = true
    QR.QuestTeleportButtons:Initialize()
    -- Should NOT be initialized during combat
    t:assertEqual(QR.QuestTeleportButtons.initialized, false, "Not initialized during combat")
    t:assertEqual(#QR.QuestTeleportButtons.pool, 0, "No buttons created during combat")
    -- After combat ends, calling Initialize directly should work
    MockWoW.config.inCombatLockdown = false
    QR.QuestTeleportButtons:Initialize()
    t:assertEqual(QR.QuestTeleportButtons.initialized, true, "Initialized after combat ends")
end)

T:run("QuestTeleportButtons: pool buttons have correct properties", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()

    for i, btn in ipairs(QR.QuestTeleportButtons.pool) do
        t:assertNotNil(btn, "Button " .. i .. " exists")
        t:assertEqual(btn.inUse, false, "Button " .. i .. " not in use")
        t:assertNil(btn.questID, "Button " .. i .. " has no questID")
        t:assertNotNil(btn.icon, "Button " .. i .. " has icon texture")
        t:assertNotNil(btn._scripts["OnEnter"], "Button " .. i .. " has OnEnter handler")
        t:assertNotNil(btn._scripts["OnLeave"], "Button " .. i .. " has OnLeave handler")
    end
end)

T:run("QuestTeleportButtons: RefreshButtons with no tracked quests", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()

    QR.QuestTeleportButtons:RefreshButtons()
    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 0, "No active buttons when no quests tracked")
end)

T:run("QuestTeleportButtons: RefreshButtons creates button for tracked quest with teleport", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()

    -- Track a quest in Stormwind (mapID 84) - same map as our teleport
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()

    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertGreaterThan(activeCount, 0, "Has active button for quest with matching teleport")
    t:assertNotNil(QR.QuestTeleportButtons.activeButtons[12345], "Button exists for quest 12345")
end)

T:run("QuestTeleportButtons: button configured correctly for spell", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()

    local btn = QR.QuestTeleportButtons.activeButtons[12345]
    t:assertNotNil(btn, "Button exists")
    t:assertEqual(btn.questID, 12345, "questID set correctly")
    t:assertEqual(btn.inUse, true, "Button marked as in use")
    t:assertEqual(btn:GetAttribute("type"), "spell", "Button type is spell")
    t:assertEqual(btn:GetAttribute("spell"), 3561, "Spell ID set correctly")
end)

T:run("QuestTeleportButtons: no button when quest has no coordinates", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()

    -- Track a quest with NO waypoint coordinates
    MockWoW.config.questTitles[99999] = "Mystery Quest"
    MockWoW.config.questWatches = { 99999 }

    QR.QuestTeleportButtons:RefreshButtons()

    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 0, "No button for quest without coordinates")
end)

T:run("QuestTeleportButtons: no button when no teleport matches quest", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    -- Don't set up any teleports - clear known spells
    MockWoW.config.knownSpells = {}
    MockWoW.config.ownedToys = {}
    MockWoW.config.bagItems = {}
    if QR.PlayerInventory and QR.PlayerInventory.ScanAll then
        QR.PlayerInventory:ScanAll()
    end

    setupTrackedQuest(11111, 84, "Remote Quest")

    QR.QuestTeleportButtons:RefreshButtons()

    -- No crash is the main assertion
    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 0, "No button when no teleports available")
end)

T:run("QuestTeleportButtons: cache returns same result within TTL", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()
    t:assertNotNil(QR.QuestTeleportButtons.questCache[12345], "Cache populated for quest")
    t:assertNotNil(QR.QuestTeleportButtons.questCache[12345].teleportID, "Cache has teleportID")

    local cachedID = QR.QuestTeleportButtons.questCache[12345].teleportID

    -- Second refresh should use cached value
    QR.QuestTeleportButtons:RefreshButtons()
    t:assertEqual(QR.QuestTeleportButtons.questCache[12345].teleportID, cachedID,
        "Cache returns same teleportID")
end)

T:run("QuestTeleportButtons: InvalidateCache clears all entries", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()
    t:assertNotNil(QR.QuestTeleportButtons.questCache[12345], "Cache has entry before invalidation")

    QR.QuestTeleportButtons:InvalidateCache()
    local cacheCount = 0
    for _ in pairs(QR.QuestTeleportButtons.questCache) do cacheCount = cacheCount + 1 end
    t:assertEqual(cacheCount, 0, "Cache empty after invalidation")
end)

T:run("QuestTeleportButtons: ReleaseAllButtons clears active buttons", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()
    local countBefore = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do countBefore = countBefore + 1 end
    t:assertGreaterThan(countBefore, 0, "Has active buttons before release")

    QR.QuestTeleportButtons:ReleaseAllButtons()
    local countAfter = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do countAfter = countAfter + 1 end
    t:assertEqual(countAfter, 0, "No active buttons after release")
end)

T:run("QuestTeleportButtons: SetEnabled(false) releases buttons", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()
    local countBefore = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do countBefore = countBefore + 1 end
    t:assertGreaterThan(countBefore, 0, "Has active buttons while enabled")

    QR.QuestTeleportButtons:SetEnabled(false)
    local countAfter = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do countAfter = countAfter + 1 end
    t:assertEqual(countAfter, 0, "No active buttons after disable")
    t:assertEqual(QR.QuestTeleportButtons.enabled, false, "enabled flag is false")
end)

T:run("QuestTeleportButtons: SetEnabled(true) re-enables refresh", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:SetEnabled(false)
    QR.QuestTeleportButtons:SetEnabled(true)
    t:assertEqual(QR.QuestTeleportButtons.enabled, true, "enabled flag is true")

    local countAfter = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do countAfter = countAfter + 1 end
    t:assertGreaterThan(countAfter, 0, "Has active buttons after re-enable")
end)

T:run("QuestTeleportButtons: RefreshButtons skipped during combat", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    MockWoW.config.inCombatLockdown = true
    QR.QuestTeleportButtons:RefreshButtons()

    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 0, "No buttons created during combat")

    MockWoW.config.inCombatLockdown = false
end)

T:run("QuestTeleportButtons: RefreshButtons skipped when not initialized", function(t)
    reinitialize()
    -- Don't initialize
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()
    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 0, "No buttons when not initialized")
end)

T:run("QuestTeleportButtons: multiple tracked quests", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()

    setupTrackedQuest(111, 84, "Quest A")
    setupTrackedQuest(222, 84, "Quest B")
    setupTrackedQuest(333, 84, "Quest C")

    QR.QuestTeleportButtons:RefreshButtons()

    local activeCount = 0
    for _ in pairs(QR.QuestTeleportButtons.activeButtons) do activeCount = activeCount + 1 end
    t:assertEqual(activeCount, 3, "Three buttons for three quests")
    t:assertNotNil(QR.QuestTeleportButtons.activeButtons[111], "Button for quest 111")
    t:assertNotNil(QR.QuestTeleportButtons.activeButtons[222], "Button for quest 222")
    t:assertNotNil(QR.QuestTeleportButtons.activeButtons[333], "Button for quest 333")
end)

T:run("QuestTeleportButtons: OnUpdate throttles correctly", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()

    QR.QuestTeleportButtons.updateElapsed = 0
    QR.QuestTeleportButtons:OnUpdate(0.05)
    t:assertEqual(QR.QuestTeleportButtons.updateElapsed, 0.05, "Elapsed accumulated")

    QR.QuestTeleportButtons:OnUpdate(0.05)
    t:assertGreaterThan(QR.QuestTeleportButtons.updateElapsed, 0,
        "Elapsed still accumulating below threshold")
end)

T:run("QuestTeleportButtons: GetPoolSize returns expected value", function(t)
    t:assertEqual(QR.QuestTeleportButtons:GetPoolSize(), 8, "Pool size is 8")
end)

T:run("QuestTeleportButtons: GetCacheTTL returns expected value", function(t)
    t:assertEqual(QR.QuestTeleportButtons:GetCacheTTL(), 30, "Cache TTL is 30s")
end)

T:run("QuestTeleportButtons: button has tooltip text after configuration", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    setupTestTeleports()
    setupTrackedQuest(12345, 84, "Defend Stormwind")

    QR.QuestTeleportButtons:RefreshButtons()

    local btn = QR.QuestTeleportButtons.activeButtons[12345]
    t:assertNotNil(btn, "Button exists")
    t:assertNotNil(btn.tooltipText, "Button has tooltip text")
end)

T:run("QuestTeleportButtons: event frame created on Initialize", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    t:assertNotNil(QR.QuestTeleportButtons.eventFrame, "Event frame exists")
end)

T:run("QuestTeleportButtons: update frame created on Initialize", function(t)
    reinitialize()
    QR.QuestTeleportButtons:Initialize()
    t:assertNotNil(QR.QuestTeleportButtons.updateFrame, "Update frame exists")
end)

-- Restore state at end
restoreState()

-------------------------------------------------------------------------------
-- Objective tracker block collection
-------------------------------------------------------------------------------

-- Regression: this module read ObjectiveTrackerFrame.MODULES with a flat
-- usedBlocks[questID]. The tracker has been reshaped more than once, and when
-- the field is missing questBlocks stays empty — which sent every active
-- button down the else branch to btn:Hide(), so no quest teleport button was
-- ever positioned. The collector now understands the shapes that are known and
-- returns an empty table for one that is not, and the caller leaves the buttons
-- alone rather than hiding them all.
local function fakeBlock(id)
    return { id = id, HeaderText = { GetText = function() return "Quest " .. id end } }
end

local function withTracker(frame, fn)
    local original = _G.ObjectiveTrackerFrame
    _G.ObjectiveTrackerFrame = frame
    local ok, err = pcall(fn)
    _G.ObjectiveTrackerFrame = original
    if not ok then error(err, 0) end
end

T:run("CollectQuestBlocks: reads the current modules + EnumerateActiveBlocks shape", function(t)
    withTracker({
        modules = {
            {
                EnumerateActiveBlocks = function(self, callback)
                    callback(fakeBlock(101))
                    callback(fakeBlock(102))
                end,
            },
        },
    }, function()
        local blocks = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[101], "block 101 found via EnumerateActiveBlocks")
        t:assertNotNil(blocks[102], "block 102 found via EnumerateActiveBlocks")
    end)
end)

T:run("CollectQuestBlocks: reads the nested usedBlocks[template][id] shape", function(t)
    withTracker({
        modules = {
            { usedBlocks = { ["QuestObjectiveTemplate"] = { [201] = fakeBlock(201) } } },
        },
    }, function()
        local blocks = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[201], "block 201 found via nested usedBlocks")
    end)
end)

T:run("CollectQuestBlocks: still reads the old MODULES + flat usedBlocks shape", function(t)
    withTracker({
        MODULES = {
            { usedBlocks = { [301] = fakeBlock(301) } },
        },
    }, function()
        local blocks = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[301], "block 301 found via the legacy shape")
    end)
end)

T:run("CollectQuestBlocks: an unknown tracker shape yields nothing rather than erroring", function(t)
    withTracker({ somethingElse = true }, function()
        -- next(), not #blocks: the table is keyed by questID, so the length
        -- operator is 0 whatever it contains.
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNil(next(blocks), "no blocks collected from an unrecognised tracker")
        t:assertFalse(recognised, "and the shape is reported as unrecognised")
    end)
end)

T:run("CollectQuestBlocks: an empty tracker of a known shape is not 'unrecognised'", function(t)
    -- The distinction decides whether the caller hides buttons whose quest block
    -- is gone or leaves them alone. Both cases return an empty table, so without
    -- the second return value they are indistinguishable.
    withTracker({ modules = { { usedBlocks = {} } } }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNil(next(blocks), "an empty tracker yields no blocks")
        t:assertTrue(recognised, "but its shape was recognised")
    end)
end)

T:run("CollectQuestBlocks: an enumerator that errors is not 'recognised'", function(t)
    -- The pcall around EnumerateActiveBlocks swallows the error, so an API
    -- change that makes it raise looks exactly like an empty tracker. Reporting
    -- that as recognised sent the caller into the loop that hides every button
    -- whose block is missing -- which, with no blocks collected, is all of them.
    withTracker({
        modules = {
            {
                EnumerateActiveBlocks = function()
                    error("tracker API changed")
                end,
            },
        },
    }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNil(next(blocks), "an erroring enumerator yields no blocks")
        t:assertFalse(recognised,
            "and an error is not evidence that the tracker is empty")
    end)
end)

T:run("CollectQuestBlocks: one failing provider beside a working one is not 'recognised'", function(t)
    -- recognised was OR-ed across modules, so a working sibling re-armed it
    -- after a module's enumerator had raised. The caller then hid every button
    -- whose block was missing -- and the failing module's blocks are exactly
    -- the missing ones.
    withTracker({
        modules = {
            { EnumerateActiveBlocks = function() error("tracker API changed") end },
            {
                EnumerateActiveBlocks = function(self, callback)
                    callback(fakeBlock(701))
                end,
            },
        },
    }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[701], "the working module's blocks are still collected")
        t:assertFalse(recognised,
            "but the set is incomplete, so the caller must not act on it")
    end)
end)

T:run("CollectQuestBlocks: a broken enumerator falls through to usedBlocks", function(t)
    -- The two shapes were an if/elseif, so a module carrying both got no
    -- fallback: a raised enumerator ended the attempt with the older shape
    -- sitting right there unread.
    withTracker({
        modules = {
            {
                EnumerateActiveBlocks = function() error("tracker API changed") end,
                usedBlocks = { ["QuestObjectiveTemplate"] = { [801] = fakeBlock(801) } },
            },
        },
    }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[801], "the older shape was read after the enumerator failed")
        t:assertTrue(recognised, "and the provider counts as read")
    end)
end)

T:run("CollectQuestBlocks: a module with neither shape is not a failed provider", function(t)
    -- The tracker holds many module types. One that provides no blocks at all
    -- must not make an otherwise complete read look incomplete.
    withTracker({
        modules = {
            { somethingElse = true },
            {
                EnumerateActiveBlocks = function(self, callback)
                    callback(fakeBlock(901))
                end,
            },
        },
    }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertNotNil(blocks[901], "the real provider was read")
        t:assertTrue(recognised, "and the unrelated module did not spoil it")
    end)
end)
