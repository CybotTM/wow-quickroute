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

T:run("ServiceRouter: localization keys exist", function(t)
    local L = QR.L
    t:assertNotNil(L["SERVICE_AUCTION_HOUSE"], "SERVICE_AUCTION_HOUSE")
    t:assertNotNil(L["SERVICE_BANK"], "SERVICE_BANK")
    t:assertNotNil(L["SERVICE_VOID_STORAGE"], "SERVICE_VOID_STORAGE")
    t:assertNotNil(L["SERVICE_CRAFTING_TABLE"], "SERVICE_CRAFTING_TABLE")
    t:assertNotNil(L["SERVICE_NEAREST"], "SERVICE_NEAREST")
    t:assertNotNil(L["DEST_SEARCH_SERVICES"], "DEST_SEARCH_SERVICES")
end)

-------------------------------------------------------------------------------
-- 2. ServiceRouter Module
-------------------------------------------------------------------------------

T:run("ServiceRouter: module exists", function(t)
    t:assertNotNil(QR.ServiceRouter, "ServiceRouter exists")
end)

T:run("ServiceRouter: GetServiceTypes returns all types", function(t)
    local types = QR.ServiceRouter:GetServiceTypes()
    t:assertTrue(#types >= 4, "At least 4 service types")
    local found = {}
    for _, st in ipairs(types) do found[st] = true end
    t:assertTrue(found["AUCTION_HOUSE"] == true, "Has AUCTION_HOUSE")
    t:assertTrue(found["BANK"] == true, "Has BANK")
    t:assertTrue(found["VOID_STORAGE"] == true, "Has VOID_STORAGE")
    t:assertTrue(found["CRAFTING_TABLE"] == true, "Has CRAFTING_TABLE")
end)

T:run("ServiceRouter: GetServiceTypes is sorted", function(t)
    local types = QR.ServiceRouter:GetServiceTypes()
    for i = 2, #types do
        t:assertTrue(types[i-1] < types[i], "Sorted: " .. types[i-1] .. " < " .. types[i])
    end
end)

T:run("ServiceRouter: GetLocations filters by faction (Alliance)", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local locs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    t:assertTrue(#locs > 0, "Has AH locations for Alliance")
    for _, loc in ipairs(locs) do
        t:assertTrue(loc.faction == "Alliance" or loc.faction == "both",
            "No Horde-only locations for Alliance player")
    end
end)

T:run("ServiceRouter: GetLocations filters by faction (Horde)", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()
    local locs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    t:assertTrue(#locs > 0, "Has AH locations for Horde")
    for _, loc in ipairs(locs) do
        t:assertTrue(loc.faction == "Horde" or loc.faction == "both",
            "No Alliance-only locations for Horde player")
    end
end)

T:run("ServiceRouter: GetLocations returns empty for unknown type", function(t)
    resetState()
    local locs = QR.ServiceRouter:GetLocations("NONEXISTENT")
    t:assertEqual(0, #locs, "Empty for unknown type")
end)

T:run("ServiceRouter: GetServiceName returns localized name", function(t)
    resetState()
    t:assertEqual("Auction House", QR.ServiceRouter:GetServiceName("AUCTION_HOUSE"))
    t:assertEqual("Bank", QR.ServiceRouter:GetServiceName("BANK"))
    t:assertEqual("Void Storage", QR.ServiceRouter:GetServiceName("VOID_STORAGE"))
    t:assertEqual("Crafting Table", QR.ServiceRouter:GetServiceName("CRAFTING_TABLE"))
end)

T:run("ServiceRouter: GetCityName returns map name", function(t)
    resetState()
    local name = QR.ServiceRouter:GetCityName({ mapID = 84 })
    t:assertNotNil(name, "City name not nil")
    t:assertTrue(#name > 0, "City name not empty")
end)

T:run("ServiceRouter: GetCityName handles nil mapID", function(t)
    resetState()
    local name = QR.ServiceRouter:GetCityName({})
    t:assertNotNil(name, "Returns fallback for nil mapID")
    t:assertEqual("Map 0", name, "Fallback is 'Map 0'")
end)

T:run("ServiceRouter: FindByAlias maps correctly", function(t)
    resetState()
    t:assertEqual("AUCTION_HOUSE", QR.ServiceRouter:FindByAlias("ah"))
    t:assertEqual("BANK", QR.ServiceRouter:FindByAlias("bank"))
    t:assertEqual("VOID_STORAGE", QR.ServiceRouter:FindByAlias("void"))
    t:assertEqual("CRAFTING_TABLE", QR.ServiceRouter:FindByAlias("craft"))
    t:assertNil(QR.ServiceRouter:FindByAlias("unknown"))
    t:assertNil(QR.ServiceRouter:FindByAlias(nil))
end)

T:run("ServiceRouter: FindByAlias is case-insensitive", function(t)
    resetState()
    t:assertEqual("AUCTION_HOUSE", QR.ServiceRouter:FindByAlias("AH"))
    t:assertEqual("BANK", QR.ServiceRouter:FindByAlias("BANK"))
end)

T:run("ServiceRouter: FindNearest returns nil for unknown type", function(t)
    resetState()
    local loc, cost, result = QR.ServiceRouter:FindNearest("NONEXISTENT")
    t:assertNil(loc, "No location for unknown type")
    t:assertNil(cost, "No cost for unknown type")
    t:assertNil(result, "No result for unknown type")
end)

T:run("ServiceRouter: GetLocations includes neutral for both factions", function(t)
    -- Alliance should see "both" entries
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local allianceLocs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    local allianceHasBoth = false
    for _, loc in ipairs(allianceLocs) do
        if loc.faction == "both" then allianceHasBoth = true end
    end
    t:assertTrue(allianceHasBoth, "Alliance sees neutral locations")

    -- Horde should see "both" entries
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()
    local hordeLocs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    local hordeHasBoth = false
    for _, loc in ipairs(hordeLocs) do
        if loc.faction == "both" then hordeHasBoth = true end
    end
    t:assertTrue(hordeHasBoth, "Horde sees neutral locations")
end)

T:run("ServiceRouter: GetLocations count differs by faction", function(t)
    -- Alliance and Horde should see different faction-specific entries
    -- but both should see "both" entries
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local allianceLocs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")

    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()
    local hordeLocs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")

    -- Both should have entries (faction-specific + neutral)
    t:assertTrue(#allianceLocs > 0, "Alliance has AH locations")
    t:assertTrue(#hordeLocs > 0, "Horde has AH locations")

    -- Count neutral entries in each (should be same)
    local allianceNeutral, hordeNeutral = 0, 0
    for _, loc in ipairs(allianceLocs) do
        if loc.faction == "both" then allianceNeutral = allianceNeutral + 1 end
    end
    for _, loc in ipairs(hordeLocs) do
        if loc.faction == "both" then hordeNeutral = hordeNeutral + 1 end
    end
    t:assertEqual(allianceNeutral, hordeNeutral, "Same number of neutral locations")
end)

T:run("ServiceRouter: /qr slash command aliases wired", function(t)
    -- Verify ServiceRouter has the needed methods for slash commands
    t:assertNotNil(QR.ServiceRouter, "ServiceRouter module loaded")
    t:assertNotNil(QR.ServiceRouter.FindByAlias, "Has FindByAlias method")
    t:assertNotNil(QR.ServiceRouter.RouteToNearest, "Has RouteToNearest method")
    -- Verify all slash aliases map correctly
    t:assertEqual("AUCTION_HOUSE", QR.ServiceRouter:FindByAlias("ah"))
    t:assertEqual("BANK", QR.ServiceRouter:FindByAlias("bank"))
    t:assertEqual("VOID_STORAGE", QR.ServiceRouter:FindByAlias("void"))
    t:assertEqual("CRAFTING_TABLE", QR.ServiceRouter:FindByAlias("craft"))
end)

T:run("ServiceRouter: Initialize sets up module", function(t)
    resetState()
    -- Should not error
    QR.ServiceRouter:Initialize()
    t:assertNotNil(QR.ServiceRouter, "ServiceRouter still exists after init")
end)
