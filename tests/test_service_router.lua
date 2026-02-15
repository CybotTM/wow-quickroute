-------------------------------------------------------------------------------
-- test_service_router.lua
-- Tests for Service POI routing
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
end

-------------------------------------------------------------------------------
-- 1. Data Availability
-------------------------------------------------------------------------------

T:run("ServicePOIs: QR.ServicePOIs exists", function(t)
    t:assertNotNil(QR.ServicePOIs, "ServicePOIs table exists")
end)

T:run("ServicePOIs: has all 4 service types", function(t)
    t:assertNotNil(QR.ServicePOIs.AUCTION_HOUSE, "AUCTION_HOUSE exists")
    t:assertNotNil(QR.ServicePOIs.BANK, "BANK exists")
    t:assertNotNil(QR.ServicePOIs.VOID_STORAGE, "VOID_STORAGE exists")
    t:assertNotNil(QR.ServicePOIs.CRAFTING_TABLE, "CRAFTING_TABLE exists")
end)

T:run("ServicePOIs: each entry has mapID, x, y, faction", function(t)
    for serviceType, locations in pairs(QR.ServicePOIs) do
        for i, loc in ipairs(locations) do
            local label = serviceType .. "[" .. i .. "]"
            t:assertNotNil(loc.mapID, label .. " has mapID")
            t:assertNotNil(loc.x, label .. " has x")
            t:assertNotNil(loc.y, label .. " has y")
            t:assertNotNil(loc.faction, label .. " has faction")
            t:assertTrue(loc.faction == "Alliance" or loc.faction == "Horde" or loc.faction == "both",
                label .. " faction is valid")
        end
    end
end)

T:run("ServicePOIs: coordinates are in 0-1 range", function(t)
    for serviceType, locations in pairs(QR.ServicePOIs) do
        for i, loc in ipairs(locations) do
            local label = serviceType .. "[" .. i .. "]"
            t:assertTrue(loc.x >= 0 and loc.x <= 1, label .. " x in range")
            t:assertTrue(loc.y >= 0 and loc.y <= 1, label .. " y in range")
        end
    end
end)

T:run("ServicePOIs: QR.ServiceTypes has metadata for each service", function(t)
    for serviceType in pairs(QR.ServicePOIs) do
        t:assertNotNil(QR.ServiceTypes[serviceType],
            serviceType .. " has metadata in ServiceTypes")
        t:assertNotNil(QR.ServiceTypes[serviceType].icon,
            serviceType .. " has icon")
        t:assertNotNil(QR.ServiceTypes[serviceType].slashAlias,
            serviceType .. " has slashAlias")
    end
end)

T:run("ServicePOIs: AH has both Alliance and Horde entries", function(t)
    local hasAlliance, hasHorde, hasBoth = false, false, false
    for _, loc in ipairs(QR.ServicePOIs.AUCTION_HOUSE) do
        if loc.faction == "Alliance" then hasAlliance = true end
        if loc.faction == "Horde" then hasHorde = true end
        if loc.faction == "both" then hasBoth = true end
    end
    t:assertTrue(hasAlliance, "AH has Alliance entries")
    t:assertTrue(hasHorde, "AH has Horde entries")
    t:assertTrue(hasBoth, "AH has neutral entries")
end)
