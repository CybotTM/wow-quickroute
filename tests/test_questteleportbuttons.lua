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
