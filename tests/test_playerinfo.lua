-------------------------------------------------------------------------------
-- test_playerinfo.lua
-- Tests for QR.PlayerInfo (cached faction, class and profession lookups)
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    QR.PlayerInfo:InvalidateCache()
end

-------------------------------------------------------------------------------
-- HasEngineering
--
-- Regression: nothing tested this. HasEngineering gates every engineering
-- teleporter in both the teleport panel and the mini panel, so forcing it to
-- false hid a whole class of teleports from the UI without a single failure.
-------------------------------------------------------------------------------

T:run("PlayerInfo:HasEngineering: true when the skill line matches", function(t)
    resetState()
    MockWoW.config.professions[1] = { name = "Engineering", skillLineID = 202 }
    QR.PlayerInfo:InvalidateCache()

    t:assertTrue(QR.PlayerInfo:HasEngineering(),
        "an Engineering profession is recognised by its skill line")
end)

T:run("PlayerInfo:HasEngineering: false for a different profession", function(t)
    resetState()
    MockWoW.config.professions[1] = { name = "Tailoring", skillLineID = 197 }
    QR.PlayerInfo:InvalidateCache()

    t:assertFalse(QR.PlayerInfo:HasEngineering(),
        "Tailoring is not Engineering")
end)

T:run("PlayerInfo:HasEngineering: found in the second profession slot too", function(t)
    resetState()
    MockWoW.config.professions[1] = { name = "Mining", skillLineID = 186 }
    MockWoW.config.professions[2] = { name = "Engineering", skillLineID = 202 }
    QR.PlayerInfo:InvalidateCache()

    t:assertTrue(QR.PlayerInfo:HasEngineering(),
        "the second slot is checked as well as the first")
end)

T:run("PlayerInfo:HasEngineering: false with no professions at all", function(t)
    resetState()

    t:assertFalse(QR.PlayerInfo:HasEngineering(),
        "a character with no professions does not have Engineering")
end)

T:run("PlayerInfo:HasEngineering: the answer is cached until invalidated", function(t)
    resetState()
    MockWoW.config.professions[1] = { name = "Engineering", skillLineID = 202 }
    QR.PlayerInfo:InvalidateCache()
    t:assertTrue(QR.PlayerInfo:HasEngineering(), "Engineering is picked up")

    -- Dropping the profession without invalidating must not change the answer:
    -- the cache is the point, and a test that did not check this would not
    -- notice the cache being removed.
    MockWoW.config.professions[1] = nil
    t:assertTrue(QR.PlayerInfo:HasEngineering(),
        "the cached answer survives until InvalidateCache is called")

    QR.PlayerInfo:InvalidateCache()
    t:assertFalse(QR.PlayerInfo:HasEngineering(),
        "and is re-read after invalidation")
end)

-------------------------------------------------------------------------------
-- Faction and class
-------------------------------------------------------------------------------

T:run("PlayerInfo:GetFaction: reads the mock's faction and caches it", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    t:assertEqual("Horde", QR.PlayerInfo:GetFaction(), "faction is read from the client")

    MockWoW.config.playerFaction = "Alliance"
    t:assertEqual("Horde", QR.PlayerInfo:GetFaction(), "and cached until invalidated")

    QR.PlayerInfo:InvalidateCache()
    t:assertEqual("Alliance", QR.PlayerInfo:GetFaction(), "then re-read")
end)

-------------------------------------------------------------------------------
-- IsOnAnyMap: the player's map or one of its ancestors
-------------------------------------------------------------------------------

T:run("PlayerInfo:IsOnAnyMap: true on the listed map itself", function(t)
    MockWoW:Reset()
    MockWoW.config.currentMapID = 504
    t:assertTrue(QR.PlayerInfo:IsOnAnyMap({ 504 }))
end)

T:run("PlayerInfo:IsOnAnyMap: true on a map nested inside a listed one", function(t)
    MockWoW:Reset()
    MockWoW.mapDatabase[508] = { mapID = 508, name = "Throne of Thunder", mapType = 4, parentMapID = 504 }
    MockWoW.config.currentMapID = 508
    local result = QR.PlayerInfo:IsOnAnyMap({ 504 })
    MockWoW.mapDatabase[508] = nil
    t:assertTrue(result)
end)

T:run("PlayerInfo:IsOnAnyMap: false elsewhere", function(t)
    MockWoW:Reset()
    MockWoW.config.currentMapID = 84  -- Stormwind City, under Eastern Kingdoms
    t:assertFalse(QR.PlayerInfo:IsOnAnyMap({ 504, 680 }))
end)

T:run("PlayerInfo:IsOnAnyMap: true when the game cannot say where the player is", function(t)
    MockWoW:Reset()
    MockWoW.config.currentMapID = nil
    t:assertTrue(QR.PlayerInfo:IsOnAnyMap({ 504 }))
end)
