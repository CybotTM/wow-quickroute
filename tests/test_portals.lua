-------------------------------------------------------------------------------
-- test_portals.lua
-- Tests for QR.PortalHubs, QR.StandalonePortals, and portal query functions
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-- Valid portal transport types
local VALID_PORTAL_TYPES = {
    boat = true,
    zeppelin = true,
    portal = true,
    tram = true,
}

-- Valid faction values
local VALID_FACTIONS = {
    Alliance = true,
    Horde = true,
    both = true,
}

-------------------------------------------------------------------------------
-- 1. Static Data Tables Exist
-------------------------------------------------------------------------------

T:run("Portals: PortalHubs table exists and is non-empty", function(t)
    t:assertNotNil(QR.PortalHubs, "PortalHubs table exists")
    local count = 0
    for _ in pairs(QR.PortalHubs) do count = count + 1 end
    t:assertGreaterThan(count, 0, "PortalHubs has entries")
end)

T:run("Portals: StandalonePortals table exists and is non-empty", function(t)
    t:assertNotNil(QR.StandalonePortals, "StandalonePortals table exists")
    t:assertGreaterThan(#QR.StandalonePortals, 0, "StandalonePortals has entries")
end)

-------------------------------------------------------------------------------
-- 2. PortalHubs Data Structure Validation
-------------------------------------------------------------------------------

T:run("Portals: Every hub has required fields (mapID, x, y, faction, portals)", function(t)
    for hubName, hubData in pairs(QR.PortalHubs) do
        t:assertNotNil(hubData.mapID,
            hubName .. " has mapID")
        t:assertGreaterThan(hubData.mapID, 0,
            hubName .. " mapID > 0")
        t:assertNotNil(hubData.x,
            hubName .. " has x coordinate")
        t:assertNotNil(hubData.y,
            hubName .. " has y coordinate")
        t:assertNotNil(hubData.faction,
            hubName .. " has faction")
        t:assert(VALID_FACTIONS[hubData.faction],
            hubName .. " faction is valid (got: " .. tostring(hubData.faction) .. ")")
        t:assertNotNil(hubData.portals,
            hubName .. " has portals table")
        t:assertGreaterThan(#hubData.portals, 0,
            hubName .. " has at least one portal")
    end
end)

T:run("Portals: Hub coordinates are in normalized range [0, 1]", function(t)
    for hubName, hubData in pairs(QR.PortalHubs) do
        t:assert(hubData.x >= 0 and hubData.x <= 1,
            hubName .. " x in [0,1] (got: " .. tostring(hubData.x) .. ")")
        t:assert(hubData.y >= 0 and hubData.y <= 1,
            hubName .. " y in [0,1] (got: " .. tostring(hubData.y) .. ")")
    end
end)

T:run("Portals: Every hub portal has required fields (destination, mapID, x, y)", function(t)
    for hubName, hubData in pairs(QR.PortalHubs) do
        for i, portal in ipairs(hubData.portals) do
            local label = hubName .. " portal #" .. i
            t:assertNotNil(portal.destination,
                label .. " has destination")
            t:assertNotNil(portal.mapID,
                label .. " has mapID")
            t:assertGreaterThan(portal.mapID, 0,
                label .. " mapID > 0")
            t:assertNotNil(portal.x,
                label .. " has x coordinate")
            t:assertNotNil(portal.y,
                label .. " has y coordinate")
            t:assert(portal.x >= 0 and portal.x <= 1,
                label .. " x in [0,1] (got: " .. tostring(portal.x) .. ")")
            t:assert(portal.y >= 0 and portal.y <= 1,
                label .. " y in [0,1] (got: " .. tostring(portal.y) .. ")")
        end
    end
end)

T:run("Portals: Hub portal faction restrictions are valid", function(t)
    for hubName, hubData in pairs(QR.PortalHubs) do
        for i, portal in ipairs(hubData.portals) do
            if portal.faction then
                local label = hubName .. " portal #" .. i .. " (" .. portal.destination .. ")"
                t:assert(VALID_FACTIONS[portal.faction],
                    label .. " faction is valid (got: " .. tostring(portal.faction) .. ")")
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- 3. StandalonePortals Data Structure Validation
-------------------------------------------------------------------------------

T:run("Portals: Every standalone portal has required fields", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        local label = "StandalonePortal #" .. i .. " (" .. (portal.name or "unnamed") .. ")"
        t:assertNotNil(portal.name,
            label .. " has name")
        t:assertNotNil(portal.from,
            label .. " has from")
        t:assertNotNil(portal.from.mapID,
            label .. " from has mapID")
        t:assertGreaterThan(portal.from.mapID, 0,
            label .. " from mapID > 0")
        t:assertNotNil(portal.from.x,
            label .. " from has x")
        t:assertNotNil(portal.from.y,
            label .. " from has y")
        t:assertNotNil(portal.to,
            label .. " has to")
        t:assertNotNil(portal.to.mapID,
            label .. " to has mapID")
        t:assertGreaterThan(portal.to.mapID, 0,
            label .. " to mapID > 0")
        t:assertNotNil(portal.to.x,
            label .. " to has x")
        t:assertNotNil(portal.to.y,
            label .. " to has y")
        t:assertNotNil(portal.travelTime,
            label .. " has travelTime")
        t:assertGreaterThan(portal.travelTime, 0,
            label .. " travelTime > 0")
        t:assertNotNil(portal.faction,
            label .. " has faction")
        t:assert(VALID_FACTIONS[portal.faction],
            label .. " faction is valid (got: " .. tostring(portal.faction) .. ")")
        t:assertNotNil(portal.type,
            label .. " has type")
        t:assert(VALID_PORTAL_TYPES[portal.type],
            label .. " type is valid (got: " .. tostring(portal.type) .. ")")
    end
end)

T:run("Portals: Standalone portal coordinates in normalized range [0, 1]", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        local label = portal.name or ("StandalonePortal #" .. i)
        t:assert(portal.from.x >= 0 and portal.from.x <= 1,
            label .. " from.x in [0,1]")
        t:assert(portal.from.y >= 0 and portal.from.y <= 1,
            label .. " from.y in [0,1]")
        t:assert(portal.to.x >= 0 and portal.to.x <= 1,
            label .. " to.x in [0,1]")
        t:assert(portal.to.y >= 0 and portal.to.y <= 1,
            label .. " to.y in [0,1]")
    end
end)

T:run("Portals: All standalone portals are bidirectional", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        local label = portal.name or ("StandalonePortal #" .. i)
        t:assertTrue(portal.bidirectional,
            label .. " is bidirectional")
    end
end)

T:run("Portals: Portal type distribution includes expected types", function(t)
    local types = {}
    for _, portal in ipairs(QR.StandalonePortals) do
        types[portal.type] = (types[portal.type] or 0) + 1
    end
    t:assertGreaterThan(types["boat"] or 0, 0, "Has boat portals")
    t:assertGreaterThan(types["zeppelin"] or 0, 0, "Has zeppelin portals")
    t:assertGreaterThan(types["tram"] or 0, 0, "Has tram portals")
    t:assertGreaterThan(types["portal"] or 0, 0, "Has portal-type portals")
end)

-------------------------------------------------------------------------------
-- 4. Map ID Validation (all reference valid maps > 0)
-------------------------------------------------------------------------------

T:run("Portals: Hub mapIDs are positive integers", function(t)
    for hubName, hubData in pairs(QR.PortalHubs) do
        t:assert(type(hubData.mapID) == "number" and hubData.mapID > 0 and hubData.mapID == math.floor(hubData.mapID),
            hubName .. " mapID is a positive integer (got: " .. tostring(hubData.mapID) .. ")")
        for i, portal in ipairs(hubData.portals) do
            t:assert(type(portal.mapID) == "number" and portal.mapID > 0 and portal.mapID == math.floor(portal.mapID),
                hubName .. " portal #" .. i .. " mapID is positive integer")
        end
    end
end)

T:run("Portals: Standalone portal mapIDs are positive integers", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        local label = portal.name or ("StandalonePortal #" .. i)
        t:assert(type(portal.from.mapID) == "number" and portal.from.mapID > 0,
            label .. " from.mapID is positive")
        t:assert(portal.from.mapID == math.floor(portal.from.mapID),
            label .. " from.mapID is integer")
        t:assert(type(portal.to.mapID) == "number" and portal.to.mapID > 0,
            label .. " to.mapID is positive")
        t:assert(portal.to.mapID == math.floor(portal.to.mapID),
            label .. " to.mapID is integer")
    end
end)

-------------------------------------------------------------------------------
-- 5. GetAvailablePortals() - Alliance Filtering
-------------------------------------------------------------------------------

T:run("Portals: GetAvailablePortals exists", function(t)
    t:assertNotNil(QR.GetAvailablePortals, "GetAvailablePortals function exists")
end)

T:run("Portals: GetAvailablePortals returns hubs and standalone tables", function(t)
    local savedFaction = MockWoW.config.playerFaction
    local savedClass = MockWoW.config.playerClass
    MockWoW.config.playerFaction = "Alliance"
    MockWoW.config.playerClass = "MAGE"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()
    t:assertNotNil(result, "Result is not nil")
    t:assertNotNil(result.hubs, "Result has hubs table")
    t:assertNotNil(result.standalone, "Result has standalone table")

    MockWoW.config.playerFaction = savedFaction
    MockWoW.config.playerClass = savedClass
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: Alliance sees Alliance and neutral hubs, not Horde hubs", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    -- Alliance-specific hubs
    t:assertNotNil(result.hubs["Stormwind Portal Room"],
        "Alliance sees Stormwind Portal Room")
    t:assertNotNil(result.hubs["Boralus"],
        "Alliance sees Boralus")

    -- Neutral hubs
    t:assertNotNil(result.hubs["Oribos"],
        "Alliance sees Oribos")
    t:assertNotNil(result.hubs["Valdrakken"],
        "Alliance sees Valdrakken")
    t:assertNotNil(result.hubs["Dornogal"],
        "Alliance sees Dornogal")
    t:assertNotNil(result.hubs["Dalaran (Broken Isles)"],
        "Alliance sees Dalaran (Broken Isles)")
    t:assertNotNil(result.hubs["Shattrath City"],
        "Alliance sees Shattrath City")
    t:assertNotNil(result.hubs["Dalaran (Northrend)"],
        "Alliance sees Dalaran (Northrend)")

    -- Horde hubs should be absent
    t:assertNil(result.hubs["Orgrimmar Portal Room"],
        "Alliance does NOT see Orgrimmar Portal Room")
    t:assertNil(result.hubs["Dazar'alor"],
        "Alliance does NOT see Dazar'alor")

    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: Alliance sees tram and boats, not zeppelins", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    local hasTram = false
    local hasBoat = false
    local hasHordeZeppelin = false
    for _, p in ipairs(result.standalone) do
        if p.type == "tram" then hasTram = true end
        if p.type == "boat" and p.faction == "Alliance" then hasBoat = true end
        if p.type == "zeppelin" and p.faction == "Horde" then hasHordeZeppelin = true end
    end

    t:assertTrue(hasTram, "Alliance has Deeprun Tram")
    t:assertTrue(hasBoat, "Alliance has boats")
    t:assertFalse(hasHordeZeppelin, "Alliance does NOT have Horde zeppelins")

    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
end)

-------------------------------------------------------------------------------
-- 6. GetAvailablePortals() - Horde Filtering
-------------------------------------------------------------------------------

T:run("Portals: Horde sees Horde and neutral hubs, not Alliance hubs", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    -- Horde-specific hubs
    t:assertNotNil(result.hubs["Orgrimmar Portal Room"],
        "Horde sees Orgrimmar Portal Room")
    t:assertNotNil(result.hubs["Dazar'alor"],
        "Horde sees Dazar'alor")

    -- Neutral hubs
    t:assertNotNil(result.hubs["Oribos"],
        "Horde sees Oribos")
    t:assertNotNil(result.hubs["Valdrakken"],
        "Horde sees Valdrakken")
    t:assertNotNil(result.hubs["Dornogal"],
        "Horde sees Dornogal")

    -- Alliance hubs should be absent
    t:assertNil(result.hubs["Stormwind Portal Room"],
        "Horde does NOT see Stormwind Portal Room")
    t:assertNil(result.hubs["Boralus"],
        "Horde does NOT see Boralus")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: Horde sees zeppelins, not Alliance tram or boats", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    local hasZeppelin = false
    local hasTram = false
    local hasAllianceBoat = false
    for _, p in ipairs(result.standalone) do
        if p.type == "zeppelin" then hasZeppelin = true end
        if p.type == "tram" then hasTram = true end
        if p.type == "boat" and p.faction == "Alliance" then hasAllianceBoat = true end
    end

    t:assertTrue(hasZeppelin, "Horde has zeppelins")
    t:assertFalse(hasTram, "Horde does NOT have Deeprun Tram")
    t:assertFalse(hasAllianceBoat, "Horde does NOT have Alliance boats")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

-------------------------------------------------------------------------------
-- 7. GetAvailablePortals() - Neutral Hub Faction Filtering
-------------------------------------------------------------------------------

T:run("Portals: Neutral hubs filter sub-portals by faction (Alliance)", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()
    local dalaran = result.hubs["Dalaran (Broken Isles)"]
    t:assertNotNil(dalaran, "Dalaran (Broken Isles) hub accessible to Alliance")

    -- Alliance should see Alliance and neutral portals, but not Horde
    local hasAlliancePortal = false
    local hasHordePortal = false
    local hasNeutralPortal = false
    for _, portal in ipairs(dalaran.portals) do
        if portal.faction == "Alliance" then hasAlliancePortal = true end
        if portal.faction == "Horde" then hasHordePortal = true end
        if not portal.faction then hasNeutralPortal = true end
    end

    t:assertTrue(hasAlliancePortal, "Alliance sees Alliance portals in Dalaran BI")
    t:assertFalse(hasHordePortal, "Alliance does NOT see Horde portals in Dalaran BI")
    t:assertTrue(hasNeutralPortal, "Alliance sees neutral portals in Dalaran BI")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: Neutral hubs filter sub-portals by faction (Horde)", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()
    local dalaran = result.hubs["Dalaran (Broken Isles)"]
    t:assertNotNil(dalaran, "Dalaran (Broken Isles) hub accessible to Horde")

    local hasAlliancePortal = false
    local hasHordePortal = false
    local hasNeutralPortal = false
    for _, portal in ipairs(dalaran.portals) do
        if portal.faction == "Alliance" then hasAlliancePortal = true end
        if portal.faction == "Horde" then hasHordePortal = true end
        if not portal.faction then hasNeutralPortal = true end
    end

    t:assertFalse(hasAlliancePortal, "Horde does NOT see Alliance portals in Dalaran BI")
    t:assertTrue(hasHordePortal, "Horde sees Horde portals in Dalaran BI")
    t:assertTrue(hasNeutralPortal, "Horde sees neutral portals in Dalaran BI")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

-------------------------------------------------------------------------------
-- 8. GetAvailablePortals() - Class-Restricted Portals (Druid Dreamway)
-------------------------------------------------------------------------------

T:run("Portals: Druid sees Dreamway portals", function(t)
    local savedFaction = MockWoW.config.playerFaction
    local savedClass = MockWoW.config.playerClass
    local savedClassName = MockWoW.config.playerClassName
    MockWoW.config.playerFaction = "Alliance"
    MockWoW.config.playerClass = "DRUID"
    MockWoW.config.playerClassName = "Druid"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    local dreamwayCount = 0
    for _, p in ipairs(result.standalone) do
        if p.class == "DRUID" then
            dreamwayCount = dreamwayCount + 1
        end
    end
    t:assertGreaterThan(dreamwayCount, 0, "Druid sees Dreamway portals")

    MockWoW.config.playerFaction = savedFaction
    MockWoW.config.playerClass = savedClass
    MockWoW.config.playerClassName = savedClassName
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: Non-Druid does NOT see Dreamway portals", function(t)
    local savedFaction = MockWoW.config.playerFaction
    local savedClass = MockWoW.config.playerClass
    local savedClassName = MockWoW.config.playerClassName
    MockWoW.config.playerFaction = "Alliance"
    MockWoW.config.playerClass = "MAGE"
    MockWoW.config.playerClassName = "Mage"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    local dreamwayCount = 0
    for _, p in ipairs(result.standalone) do
        if p.class == "DRUID" then
            dreamwayCount = dreamwayCount + 1
        end
    end
    t:assertEqual(0, dreamwayCount, "Non-Druid does NOT see Dreamway portals")

    MockWoW.config.playerFaction = savedFaction
    MockWoW.config.playerClass = savedClass
    MockWoW.config.playerClassName = savedClassName
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: All Druid Dreamway portals have class=DRUID and type=portal", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        if portal.name and portal.name:find("Dreamway") then
            local label = portal.name
            t:assertEqual("DRUID", portal.class, label .. " class is DRUID")
            t:assertEqual("portal", portal.type, label .. " type is portal")
            t:assertEqual("both", portal.faction, label .. " faction is both")
            t:assertEqual(5, portal.travelTime, label .. " travelTime is 5")
            t:assertTrue(portal.bidirectional, label .. " is bidirectional")
        end
    end
end)

-------------------------------------------------------------------------------
-- 9. GetPortalHub() - Hub Lookup by Name
-------------------------------------------------------------------------------

T:run("Portals: GetPortalHub returns known hub", function(t)
    t:assertNotNil(QR.GetPortalHub, "GetPortalHub function exists")

    local hub = QR:GetPortalHub("Stormwind Portal Room")
    t:assertNotNil(hub, "Stormwind Portal Room found")
    t:assertEqual(84, hub.mapID, "Stormwind Portal Room mapID is 84")
    t:assertEqual("Alliance", hub.faction, "Stormwind Portal Room faction is Alliance")
end)

T:run("Portals: GetPortalHub returns nil for unknown hub", function(t)
    local hub = QR:GetPortalHub("Nonexistent City")
    t:assertNil(hub, "Unknown hub returns nil")
end)

T:run("Portals: GetPortalHub returns correct data for each known hub", function(t)
    local expectedHubs = {
        ["Stormwind Portal Room"] = { mapID = 84, faction = "Alliance" },
        ["Boralus"] = { mapID = 1161, faction = "Alliance" },
        ["Orgrimmar Portal Room"] = { mapID = 85, faction = "Horde" },
        ["Dazar'alor"] = { mapID = 1165, faction = "Horde" },
        ["Dalaran (Broken Isles)"] = { mapID = 627, faction = "both" },
        ["Oribos"] = { mapID = 1670, faction = "both" },
        ["Valdrakken"] = { mapID = 2112, faction = "both" },
        ["Dornogal"] = { mapID = 2339, faction = "both" },
        ["Shattrath City"] = { mapID = 111, faction = "both" },
        ["Dalaran (Northrend)"] = { mapID = 125, faction = "both" },
    }

    for hubName, expected in pairs(expectedHubs) do
        local hub = QR:GetPortalHub(hubName)
        t:assertNotNil(hub, hubName .. " exists")
        t:assertEqual(expected.mapID, hub.mapID, hubName .. " mapID correct")
        t:assertEqual(expected.faction, hub.faction, hubName .. " faction correct")
    end
end)

-------------------------------------------------------------------------------
-- 10. GetPortalsToMap() - Find Portals by Destination
-------------------------------------------------------------------------------

T:run("Portals: GetPortalsToMap returns portals for a known destination", function(t)
    t:assertNotNil(QR.GetPortalsToMap, "GetPortalsToMap function exists")

    -- Ironforge (mapID 87) should be reachable from:
    -- Stormwind Portal Room hub portal, Deeprun Tram standalone, Dalaran hubs
    local portals = QR:GetPortalsToMap(87)
    t:assertNotNil(portals, "Result is not nil")
    t:assertGreaterThan(#portals, 0, "Found portals to Ironforge (87)")
end)

T:run("Portals: GetPortalsToMap returns empty table for unreachable map", function(t)
    -- Use a very high map ID that definitely doesn't exist
    local portals = QR:GetPortalsToMap(999999)
    t:assertNotNil(portals, "Result is a table (not nil)")
    t:assertEqual(0, #portals, "No portals to nonexistent map")
end)

T:run("Portals: GetPortalsToMap finds hub portals", function(t)
    -- Oribos (1670) is reachable from Stormwind and Orgrimmar portal rooms
    local portals = QR:GetPortalsToMap(1670)
    local hasHubPortal = false
    for _, p in ipairs(portals) do
        if p.type == "hub_portal" then
            hasHubPortal = true
            break
        end
    end
    t:assertTrue(hasHubPortal, "GetPortalsToMap finds hub_portal entries for Oribos")
end)

T:run("Portals: GetPortalsToMap finds standalone portals (forward direction)", function(t)
    -- Borean Tundra (mapID 114) is a destination of standalone boat/zeppelin portals
    local portals = QR:GetPortalsToMap(114)
    local hasStandalone = false
    for _, p in ipairs(portals) do
        if p.type == "boat" or p.type == "zeppelin" then
            hasStandalone = true
            break
        end
    end
    t:assertTrue(hasStandalone,
        "GetPortalsToMap finds standalone portals to Borean Tundra (114)")
end)

T:run("Portals: GetPortalsToMap finds bidirectional reverse portals", function(t)
    -- Stormwind (84) is the "from" side of Deeprun Tram, which is bidirectional
    -- so GetPortalsToMap(84) should find a "(Return)" entry from Ironforge
    local portals = QR:GetPortalsToMap(84)
    local hasReturn = false
    for _, p in ipairs(portals) do
        if p.name and p.name:find("%(Return%)") then
            hasReturn = true
            break
        end
    end
    t:assertTrue(hasReturn,
        "GetPortalsToMap(84) finds bidirectional return portals to Stormwind")
end)

T:run("Portals: GetPortalsToMap result has correct structure for hub_portal", function(t)
    local portals = QR:GetPortalsToMap(1670)  -- Oribos
    t:assertGreaterThan(#portals, 0, "Found portals to Oribos")

    for _, p in ipairs(portals) do
        if p.type == "hub_portal" then
            t:assertNotNil(p.hubName, "hub_portal has hubName")
            t:assertNotNil(p.hubMapID, "hub_portal has hubMapID")
            t:assertNotNil(p.hubX, "hub_portal has hubX")
            t:assertNotNil(p.hubY, "hub_portal has hubY")
            t:assertNotNil(p.destination, "hub_portal has destination")
            t:assertNotNil(p.destMapID, "hub_portal has destMapID")
            t:assertNotNil(p.destX, "hub_portal has destX")
            t:assertNotNil(p.destY, "hub_portal has destY")
            t:assertNotNil(p.faction, "hub_portal has faction")
            break
        end
    end
end)

T:run("Portals: GetPortalsToMap result has correct structure for standalone", function(t)
    local portals = QR:GetPortalsToMap(114)  -- Borean Tundra
    t:assertGreaterThan(#portals, 0, "Found portals to Borean Tundra")

    for _, p in ipairs(portals) do
        if p.type == "boat" or p.type == "zeppelin" then
            t:assertNotNil(p.name, "standalone has name")
            t:assertNotNil(p.fromMapID, "standalone has fromMapID")
            t:assertNotNil(p.fromX, "standalone has fromX")
            t:assertNotNil(p.fromY, "standalone has fromY")
            t:assertNotNil(p.toMapID, "standalone has toMapID")
            t:assertNotNil(p.toX, "standalone has toX")
            t:assertNotNil(p.toY, "standalone has toY")
            t:assertNotNil(p.travelTime, "standalone has travelTime")
            t:assertNotNil(p.faction, "standalone has faction")
            break
        end
    end
end)

-------------------------------------------------------------------------------
-- 11. Bidirectional Connection Validation
-------------------------------------------------------------------------------

T:run("Portals: Bidirectional standalone portals have distinct from/to mapIDs", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        if portal.bidirectional then
            local label = portal.name or ("StandalonePortal #" .. i)
            -- from and to should reference different map IDs
            -- (or at least different coordinates for same-map portals)
            local differentMap = portal.from.mapID ~= portal.to.mapID
            local differentCoords = portal.from.x ~= portal.to.x or portal.from.y ~= portal.to.y
            t:assert(differentMap or differentCoords,
                label .. " bidirectional portal has distinct from/to locations")
        end
    end
end)

T:run("Portals: GetPortalsToMap returns both directions for bidirectional portals", function(t)
    -- Deeprun Tram: Stormwind (84) <-> Ironforge (87)
    local toIronforge = QR:GetPortalsToMap(87)
    local toStormwind = QR:GetPortalsToMap(84)

    local foundTramToIronforge = false
    local foundTramToStormwind = false

    for _, p in ipairs(toIronforge) do
        if p.type == "tram" then foundTramToIronforge = true end
    end
    for _, p in ipairs(toStormwind) do
        if p.type == "tram" or (p.name and p.name:find("Tram")) then
            foundTramToStormwind = true
        end
    end

    t:assertTrue(foundTramToIronforge, "Tram reachable when searching for Ironforge")
    t:assertTrue(foundTramToStormwind, "Tram reachable when searching for Stormwind")
end)

-------------------------------------------------------------------------------
-- 12. Specific Known Portal Hubs Spot Checks
-------------------------------------------------------------------------------

T:run("Portals: Stormwind Portal Room has expected destinations", function(t)
    local hub = QR:GetPortalHub("Stormwind Portal Room")
    t:assertNotNil(hub, "Hub exists")

    local destinations = {}
    for _, portal in ipairs(hub.portals) do
        destinations[portal.destination] = portal.mapID
    end

    t:assertNotNil(destinations["Boralus"], "Has portal to Boralus")
    t:assertNotNil(destinations["Oribos"], "Has portal to Oribos")
    t:assertNotNil(destinations["Valdrakken"], "Has portal to Valdrakken")
    t:assertNotNil(destinations["Dornogal"], "Has portal to Dornogal")
    t:assertNotNil(destinations["Ironforge"], "Has portal to Ironforge")
    t:assertNotNil(destinations["Exodar"], "Has portal to Exodar")
end)

T:run("Portals: Orgrimmar Portal Room has expected destinations", function(t)
    local hub = QR:GetPortalHub("Orgrimmar Portal Room")
    t:assertNotNil(hub, "Hub exists")

    local destinations = {}
    for _, portal in ipairs(hub.portals) do
        destinations[portal.destination] = portal.mapID
    end

    t:assertNotNil(destinations["Dazar'alor"], "Has portal to Dazar'alor")
    t:assertNotNil(destinations["Oribos"], "Has portal to Oribos")
    t:assertNotNil(destinations["Valdrakken"], "Has portal to Valdrakken")
    t:assertNotNil(destinations["Dornogal"], "Has portal to Dornogal")
    t:assertNotNil(destinations["Silvermoon City"], "Has portal to Silvermoon City")
    t:assertNotNil(destinations["Thunder Bluff"], "Has portal to Thunder Bluff")
end)

T:run("Portals: Neutral hubs (Oribos, Valdrakken, Dornogal) have faction-capital portals", function(t)
    local neutralHubs = { "Oribos", "Valdrakken", "Dornogal" }
    for _, hubName in ipairs(neutralHubs) do
        local hub = QR:GetPortalHub(hubName)
        t:assertNotNil(hub, hubName .. " hub exists")

        local hasAllianceCapital = false
        local hasHordeCapital = false
        for _, portal in ipairs(hub.portals) do
            if portal.mapID == 84 then hasAllianceCapital = true end  -- Stormwind
            if portal.mapID == 85 then hasHordeCapital = true end     -- Orgrimmar
        end
        t:assertTrue(hasAllianceCapital,
            hubName .. " has portal to Stormwind (Alliance capital)")
        t:assertTrue(hasHordeCapital,
            hubName .. " has portal to Orgrimmar (Horde capital)")
    end
end)

-------------------------------------------------------------------------------
-- 13. Druid Dreamway Specific Tests
-------------------------------------------------------------------------------

T:run("Portals: Dreamway portal count is 6", function(t)
    local dreamwayCount = 0
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.class == "DRUID" then
            dreamwayCount = dreamwayCount + 1
        end
    end
    t:assertEqual(6, dreamwayCount, "Exactly 6 Druid Dreamway portals")
end)

T:run("Portals: Dreamway portals all originate from Emerald Dreamway (mapID 715)", function(t)
    for _, portal in ipairs(QR.StandalonePortals) do
        if portal.class == "DRUID" then
            t:assertEqual(715, portal.from.mapID,
                portal.name .. " originates from Emerald Dreamway (715)")
        end
    end
end)

-------------------------------------------------------------------------------
-- 14. Neutral Boat (Ratchet to Booty Bay)
-------------------------------------------------------------------------------

T:run("Portals: Neutral boat (Ratchet-Booty Bay) accessible to both factions", function(t)
    -- Test as Alliance
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local allianceResult = QR:GetAvailablePortals()
    local allianceHasNeutralBoat = false
    for _, p in ipairs(allianceResult.standalone) do
        if p.name and p.name:find("Ratchet") and p.name:find("Booty Bay") then
            allianceHasNeutralBoat = true
            break
        end
    end
    t:assertTrue(allianceHasNeutralBoat, "Alliance sees Ratchet-Booty Bay boat")

    -- Test as Horde
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local hordeResult = QR:GetAvailablePortals()
    local hordeHasNeutralBoat = false
    for _, p in ipairs(hordeResult.standalone) do
        if p.name and p.name:find("Ratchet") and p.name:find("Booty Bay") then
            hordeHasNeutralBoat = true
            break
        end
    end
    t:assertTrue(hordeHasNeutralBoat, "Horde sees Ratchet-Booty Bay boat")

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

-------------------------------------------------------------------------------
-- 15. Edge Cases
-------------------------------------------------------------------------------

T:run("Portals: GetAvailablePortals filtered hubs have correct structure", function(t)
    local savedFaction = MockWoW.config.playerFaction
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local result = QR:GetAvailablePortals()

    for hubName, hub in pairs(result.hubs) do
        t:assertNotNil(hub.mapID, hubName .. " filtered hub has mapID")
        t:assertNotNil(hub.x, hubName .. " filtered hub has x")
        t:assertNotNil(hub.y, hubName .. " filtered hub has y")
        t:assertNotNil(hub.faction, hubName .. " filtered hub has faction")
        t:assertNotNil(hub.portals, hubName .. " filtered hub has portals")
        t:assertGreaterThan(#hub.portals, 0,
            hubName .. " filtered hub has at least one portal")
    end

    MockWoW.config.playerFaction = savedFaction
    QR.PlayerInfo:InvalidateCache()
end)

T:run("Portals: No standalone portal has nil or empty name", function(t)
    for i, portal in ipairs(QR.StandalonePortals) do
        t:assert(type(portal.name) == "string" and #portal.name > 0,
            "StandalonePortal #" .. i .. " name is non-empty string")
    end
end)

T:run("Portals: No hub has zero portals after filtering for any valid faction", function(t)
    for _, faction in ipairs({"Alliance", "Horde"}) do
        local savedFaction = MockWoW.config.playerFaction
        MockWoW.config.playerFaction = faction
        QR.PlayerInfo:InvalidateCache()

        local result = QR:GetAvailablePortals()
        for hubName, hub in pairs(result.hubs) do
            t:assertGreaterThan(#hub.portals, 0,
                hubName .. " has portals for " .. faction)
        end

        MockWoW.config.playerFaction = savedFaction
        QR.PlayerInfo:InvalidateCache()
    end
end)
