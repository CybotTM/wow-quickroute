-------------------------------------------------------------------------------
-- test_zone_bound_teleports.lua
-- A teleport item that works only inside one area (requirements.usableOnMaps).
-- The owner's report of 2026-11-17: the quest teleport button offered the
-- Potion of Venomous Return (item 279550) outside the Vaults of Atal'Utek
-- (map 2509), and the client answered "Ihr müsst im Gebiet 'Die Kammern von
-- Atal'Utek' sein."
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local POTION = 279550
local VAULTS = 2509
local STORMWIND = 84
-- A map inside the Vaults, for the parent-chain rule; not a real UiMapID.
local INNER = 990509

local TR = QR.TravelRequirements

local function withInnerMap(fn)
    local saved = MockWoW.mapDatabase[INNER]
    MockWoW.mapDatabase[INNER] = { mapID = INNER, name = "Inner", mapType = 3, parentMapID = VAULTS }
    local ok, err = pcall(fn)
    MockWoW.mapDatabase[INNER] = saved
    if not ok then error(err, 0) end
end

T:run("Zone-bound teleports: the potion is limited to the Vaults of Atal'Utek", function(t)
    local entry = QR.TeleportDestinationData["item:" .. POTION]
    t:assertNotNil(entry, "the potion is in the travel data")
    local destination = entry and entry.destinations[1] or {}
    local maps = destination.requirements and destination.requirements.usableOnMaps
    t:assertNotNil(maps, "its landing carries usableOnMaps")
    t:assertEqual(1, maps and #maps or 0, "one map")
    t:assertEqual(VAULTS, maps and maps[1], "the Vaults of Atal'Utek")
    local landings = QR.TeleportDestinations:GetDestinations(POTION, QR.TeleportItemsData[POTION])
    local landing = landings[1] or {}
    t:assertEqual(maps, landing.requirements and landing.requirements.usableOnMaps,
        "the resolved landing keeps the limit, so the route edge carries it")
end)

T:run("Zone-bound teleports: the check reads the start map and the maps it lies within", function(t)
    MockWoW:Reset()
    local req = { usableOnMaps = { VAULTS } }
    t:assertTrue(TR:Check(req, nil, true, VAULTS), "a search starting in the Vaults may use it")
    t:assertFalse(TR:Check(req, nil, true, STORMWIND), "one starting in Stormwind may not")
    withInnerMap(function()
        t:assertTrue(TR:Check(req, nil, true, INNER), "a map inside the Vaults counts as the Vaults")
    end)
    MockWoW.config.currentMapID = VAULTS
    t:assertTrue(TR:Check(req), "outside a search the player's map is the start: in the Vaults")
    MockWoW.config.currentMapID = STORMWIND
    t:assertFalse(TR:Check(req), "and in Stormwind")
    t:assertFalse(TR:Check({ anyOf = { usableOnMaps = { VAULTS } } }, nil, true, STORMWIND),
        "anyOf passes the start map on")
    t:assertTrue(TR:Check({ anyOf = { usableOnMaps = { VAULTS } } }, nil, true, VAULTS),
        "in both directions")
    MockWoW:Reset()
end)

T:run("Zone-bound teleports: the search takes the teleport only from inside the area", function(t)
    MockWoW:Reset()
    local function search(startMap)
        local graph = QR.Graph:New()
        graph:AddNode("Start", { mapID = startMap, x = 0.5, y = 0.5 })
        graph:AddNode("Mid", { mapID = startMap, x = 0.6, y = 0.6 })
        graph:AddNode("Goal", { mapID = VAULTS, x = 0.44, y = 0.62 })
        graph:AddEdge("Start", "Goal", 2, "teleport",
            { teleportID = POTION, requirements = { usableOnMaps = { VAULTS } } })
        graph:AddEdge("Start", "Mid", 50, "walk", {})
        graph:AddEdge("Mid", "Goal", 50, "walk", {})
        return TR:FindPath(graph, "Start", "Goal")
    end
    local path, cost = search(VAULTS)
    t:assertEqual(2, cost, "from inside the Vaults the potion is the route")
    t:assertEqual(2, path and #path or 0, "one hop")
    path, cost = search(STORMWIND)
    t:assertEqual(100, cost, "from Stormwind the route walks around it")
    t:assertEqual(3, path and #path or 0, "through the middle node")
    -- The player's own map must not decide a search that starts elsewhere
    -- (a multi-route leg).
    MockWoW.config.currentMapID = VAULTS
    path, cost = search(STORMWIND)
    t:assertEqual(100, cost, "the start node's map decides, not the player's")
    MockWoW.config.currentMapID = STORMWIND
    path, cost = search(VAULTS)
    t:assertEqual(2, cost, "in both directions: a leg from the Vaults takes the potion")
    MockWoW:Reset()
end)

T:run("Zone-bound teleports: the planner's edge for an owned potion carries the limit", function(t)
    MockWoW:Reset()
    local PC = QR.PathCalculator
    local savedBags = MockWoW.config.bagItems
    MockWoW.config.bagItems = { [POTION] = { bagID = 0, slot = 1, count = 1 } }
    local ok, err = pcall(function()
        MockWoW.config.currentMapID = STORMWIND
        MockWoW.config.playerX, MockWoW.config.playerY = 0.5, 0.5
        QR.PlayerInventory:ScanAll()
        PC.graphDirty = true
        local destination = QR.TeleportDestinationData["item:" .. POTION].destinations[1]
        local result, failure = PC:CalculatePath(destination.mapID, destination.x, destination.y, "Amani Foothold")
        local outgoing = PC.graph.edges["Player Location"] or {}
        local edge = outgoing[destination.nodeKey]
        local option
        for _, candidate in ipairs(edge and (edge.alternatives or { edge }) or {}) do
            if candidate.data and candidate.data.teleportID == POTION then option = candidate end
        end
        t:assertNotNil(option, "the owned potion is a teleport edge from the player")
        local requirements = option and option.data.requirements
        t:assertFalse(TR:Check(requirements, nil, true, STORMWIND), "which Stormwind may not use")
        t:assertTrue(TR:Check(requirements, nil, true, VAULTS), "and the Vaults may")
        -- The mock world has no other way into the Vaults, so the planner
        -- reports the potion's limit instead of a route through it.
        t:assertNil(result, "no route through the potion from Stormwind")
        t:assertEqual("blocked", failure and failure.reason, "the failure names the blocked step")
        t:assertEqual(destination.nodeKey, failure and failure.blockedTo, "the potion's landing")
    end)
    MockWoW.config.bagItems = savedBags
    QR.PlayerInventory:ScanAll()
    PC.graphDirty = true
    MockWoW:Reset()
    if not ok then error(err, 0) end
end)
