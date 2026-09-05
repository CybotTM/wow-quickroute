local T, QR = ...

-- Restore every borrowed table/function even if the test body raises.
local function isolated(body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local ok, err = pcall(body, replace)
    for i = #saved, 1, -1 do
        local item = saved[i]
        item[1][item[2]] = item[3]
    end
    if not ok then error(err) end
end

T:run("Routing integrity: malformed graph costs cannot poison Dijkstra", function(t)
    local graph = QR.Graph:New()
    graph:AddNode("A")
    graph:AddNode("B")
    for _, weight in ipairs({ 0 / 0, math.huge, -math.huge, "12", {} }) do
        local ok, accepted = pcall(graph.AddEdge, graph, "A", "B", weight)
        t:assertTrue(ok, "Malformed weight is handled without an exception")
        t:assertFalse(accepted, "Malformed weight is rejected")
    end
    t:assertNil(graph:GetEdge("A", "B"), "No invalid edge remains in the graph")
end)

T:run("Routing integrity: overland routes compete with cooldown teleports", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 37, x = 0.5, y = 0.5 })
        graph:AddNode("Target", { mapID = 84, x = 0.5, y = 0.5 })
        graph:AddEdge("Player Location", "Target", 3600, "teleport", {
            teleportID = 1, teleportData = { mapID = 84 },
        })
        replace(pc, "graph", graph)
        replace(pc, "zoneTravelGraph", nil)
        replace(pc, "zoneTravelCache", nil)
        replace(QR, "ZoneAdjacencies", { [37] = { { zone = 84, travelTime = 30 } }, [84] = {} })
        pc:ConnectViaContinentRouting("Player Location", 37, 0.5, 0.5)
        local _, cost, edges = graph:FindShortestPath("Player Location", "Target")
        t:assertEqual(30, cost, "Thirty-second overland route beats one-hour teleport cooldown")
        t:assertEqual("travel", edges[1].edgeType, "Route keeps overland directions")
        t:assertNil(graph:GetEdge("Target", "Player Location"), "One-way zone connection stays one-way")
    end)
end)

T:run("Routing integrity: loading screens cannot reuse a stale player position", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        replace(pc, "graph", graph)
        replace(pc, "graphDirty", false)
        replace(pc, "graphFaction", nil)
        replace(C_Map, "GetBestMapForUnit", function() return nil end)
        t:assertNil(pc:CalculatePath(84, 0.6, 0.6), "No route is promised from the previous zone while loading")
    end)
end)

T:run("Routing integrity: rounded destination-name collisions preserve permanent nodes", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        graph:AddNode("Target", { mapID = 84, x = 0.4, y = 0.4 })
        graph:AddNode("Target (50, 50)", { mapID = 84, x = 0.8, y = 0.8 })
        local permanent = graph.nodes["Target (50, 50)"]
        replace(pc, "graph", graph)
        replace(pc, "graphDirty", false)
        replace(pc, "graphFaction", nil)
        replace(pc, "nodeIndex", nil)
        replace(pc, "UpdatePlayerLocation", function() return true end)
        t:assertNotNil(pc:CalculatePath(84, 0.5, 0.5, "Target"), "Colliding title still returns a route")
        t:assertEqual(permanent, graph.nodes["Target (50, 50)"], "Temporary cleanup cannot remove an existing location")
    end)
end)

T:run("Routing integrity: taxi state zero is current and state two is unreachable", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        replace(pc, "knownFlightZonesOverride", nil)
        replace(QR, "FlightPoints", {
            [84] = { x = 0.5, y = 0.5, faction = "both" },
            [87] = { x = 0.5, y = 0.5, faction = "both" },
            [125] = { x = 0.5, y = 0.5, faction = "both" },
        })
        replace(_G, "C_TaxiMap", { GetAllTaxiNodes = function(mapID)
            local state = mapID == 84 and 0 or (mapID == 87 and 1 or 2)
            return { { state = state, position = { x = 0.5, y = 0.5 } } }
        end })
        local known = pc:GetKnownFlightZones()
        t:assertTrue(known[84], "Current flight master (state 0) is usable")
        t:assertTrue(known[87], "Reachable flight master (state 1) is usable")
        t:assertNil(known[125], "Unreachable flight master (state 2) is excluded")
    end)
end)

T:run("Routing integrity: discovery belongs to the modeled flight master", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        replace(pc, "knownFlightZonesOverride", nil)
        replace(QR, "FlightPoints", { [84] = { x = 0.5, y = 0.5, faction = "both" } })
        local nodes = { { isUndiscovered = false, position = { x = 0.1, y = 0.1 } } }
        replace(_G, "C_TaxiMap", {
            GetTaxiNodesForMap = function() return nodes end,
            GetAllTaxiNodes = function() error("Current-master API must not override discovery") end,
        })
        t:assertNil(pc:GetKnownFlightZones()[84], "Different discovered master does not unlock selected master")
        nodes[1].position = { x = 0.5, y = 0.5 }
        t:assertTrue(pc:GetKnownFlightZones()[84], "Selected master is available outside a taxi session")
        nodes[1].isUndiscovered = true
        t:assertNil(pc:GetKnownFlightZones()[84], "Undiscovered selected master is excluded")
    end)
end)

T:run("Routing integrity: invalid destinations return nil without touching the graph", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        replace(pc, "BuildGraph", function() error("Invalid input reached graph build") end)
        replace(pc, "graphDirty", true)
        local invalid = {
            { nil, 0.5, 0.5 }, { "84", 0.5, 0.5 }, { -1, 0.5, 0.5 },
            { 84.5, 0.5, 0.5 }, { math.huge, 0.5, 0.5 },
            { 84, nil, 0.5 }, { 84, "0.5", 0.5 }, { 84, -0.1, 0.5 },
            { 84, 1.1, 0.5 }, { 84, 0 / 0, 0.5 }, { 84, 0.5, math.huge },
        }
        for _, destination in ipairs(invalid) do
            local ok, route = pcall(pc.CalculatePath, pc, unpack(destination, 1, 3))
            t:assertTrue(ok, "Invalid destination does not raise")
            t:assertNil(route, "Invalid destination has no route")
        end
    end)
end)

T:run("Routing integrity: continent points transform coordinates with their map", function(t)
    isolated(function(replace)
        replace(_G, "CreateVector2D", function(x, y)
            return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
        end)
        replace(C_Map, "GetMapInfo", function() return { mapType = 2 } end)
        replace(C_Map, "GetMapInfoAtPosition", function() return { mapID = 84 } end)
        replace(C_Map, "GetWorldPosFromMapPos", function(mapID, pos)
            t:assertEqual(13, mapID, "World conversion uses original map")
            t:assertEqual(0.6, pos.x, "World conversion uses original X")
            return 0, CreateVector2D(100, 200)
        end)
        replace(C_Map, "GetMapPosFromWorldPos", function(worldID, pos, targetMap)
            t:assertEqual(0, worldID, "World map ID is preserved including zero")
            t:assertEqual(100, pos.x, "World position is passed through")
            return targetMap, CreateVector2D(0.2, 0.8)
        end)
        local mapID, x, y = QR.PathCalculator:ResolveMapPosition(13, 0.6, 0.7)
        t:assertEqual(84, mapID, "Destination map is the child zone")
        t:assertEqual(0.2, x, "Destination X is transformed to the child")
        t:assertEqual(0.8, y, "Destination Y is transformed to the child")
        replace(C_Map, "GetWorldPosFromMapPos", nil)
        mapID, x, y = QR.PathCalculator:ResolveMapPosition(13, 0.6, 0.7)
        t:assertEqual(13, mapID, "Missing conversion preserves source map")
        t:assertEqual(0.6, x, "Missing conversion preserves source X")
        t:assertEqual(0.7, y, "Missing conversion preserves source Y")
    end)
end)

T:run("Routing integrity: zone travel minimizes time rather than hop count", function(t)
    isolated(function(replace)
        replace(QR, "ZoneToContinent", { [1] = "TEST", [2] = "TEST", [3] = "TEST", [4] = "TEST" })
        replace(QR, "ZoneAdjacencies", {
            [1] = { { zone = 3, travelTime = 100 }, { zone = 2, travelTime = 10 } },
            [2] = { { zone = 3, travelTime = 10 } }, [3] = {}, [4] = {},
        })
        t:assertEqual(20, QR.EstimateSameContinentTravel(1, 3), "Two fast hops beat one slow hop")
        t:assertNil(QR.EstimateSameContinentTravel(1, 4), "Disconnected zones do not invent a route")
        t:assertNil(QR.EstimateSameContinentTravel(3, 1), "One-way links cannot be walked backward")
    end)
end)

T:run("Routing integrity: unknown map cannot invent cross-continent transport", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Unknown", { mapID = 99999, x = 0.5, y = 0.5 })
        graph:AddNode("Stormwind", { mapID = 84, x = 0.5, y = 0.5, nodeType = "city" })
        replace(pc, "graph", graph)
        replace(pc, "nodeIndex", nil)
        replace(pc, "zoneTravelCache", nil)
        replace(pc, "zoneTravelGraph", nil)
        pc:ConnectViaContinentRouting("Unknown", 99999, 0.5, 0.5)
        t:assertNil(graph:FindShortestPath("Unknown", "Stormwind"), "Unmapped island has no invented transport")
    end)
end)

T:run("Routing integrity: alternate teleports compete and reprice without mutating saved routes", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        graph:AddNode("Target", { mapID = 125, x = 0.5, y = 0.5 })
        replace(pc, "graph", graph)
        replace(QR.db, "considerCooldowns", true)
        replace(QR.db, "loadingScreenTime", 0)
        replace(QR.db, "maxCooldownHours", 24)
        local costs = { [1] = 3, [2] = 60 }
        replace(QR.TravelTime, "GetEffectiveTime", function(_, id) return costs[id] end)
        replace(QR.PlayerInventory, "GetAllTeleports", function()
            return {
                [1] = { sourceType = "spell", data = { destination = "Target", mapID = 125 } },
                [2] = { sourceType = "toy", data = { destination = "Target", mapID = 125 } },
            }
        end)
        pc:AddPlayerTeleportEdges()
        local _, cost, firstEdges = graph:FindShortestPath("Player Location", "Target")
        t:assertEqual(3, cost, "Cheapest teleport wins regardless of table iteration")
        costs[1], costs[2] = 300, 8
        pc:RefreshTeleportEdgeWeights()
        local _, newCost, newEdges = graph:FindShortestPath("Player Location", "Target")
        t:assertEqual(8, newCost, "Alternate teleport becomes fastest when cooldown changes")
        t:assertEqual(2, newEdges[1].data.teleportID, "Route carries alternate teleport's actual ID")
        t:assertEqual(3, firstEdges[1].weight, "Previously returned route remains a snapshot")
    end)
end)

T:run("Routing integrity: walking competes with an owned teleport to the same location", function(t)
    isolated(function(replace)
        local pc = QR.PathCalculator
        local graph = QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.50, y = 0.50 })
        graph:AddNode("Target", { mapID = 84, x = 0.51, y = 0.50 })
        graph:AddEdge("Player Location", "Target", 300, "teleport", {
            teleportID = 1, teleportData = { mapID = 84 },
        })
        replace(pc, "graph", graph)
        replace(pc, "nodeIndex", nil)
        pc:ConnectSameMapNodes()
        local _, cost, edges = graph:FindShortestPath("Player Location", "Target")
        t:assert(cost < 300, "Nearby walk beats waiting five minutes")
        t:assertEqual("walk", edges[1].edgeType, "Fastest route describes walking")
        replace(QR.db, "loadingScreenTime", 0)
        replace(QR.TravelTime, "GetEffectiveTime", function() return 0.5 end)
        pc:RefreshTeleportEdgeWeights()
        local _, readyCost, readyEdges = graph:FindShortestPath("Player Location", "Target")
        t:assertEqual(0.5, readyCost, "Teleport becomes usable again when faster")
        t:assertEqual("teleport", readyEdges[1].edgeType, "Walking did not destroy the teleport option")
    end)
end)

T:run("Routing integrity: transport preserves walking directions to the final target", function(t)
    local steps = {
        { type = "teleport", time = 3, destMapID = 84, destX = 0.1, destY = 0.1 },
        { type = "walk", time = 50, destMapID = 84, destX = 0.9, destY = 0.9,
          navMapID = 84, navX = 0.9, navY = 0.9 },
    }
    local result = QR.PathCalculator:AbsorbRedundantWalkSteps(steps)
    t:assertEqual(2, #result, "Last-mile walk remains a separate actionable step")
    t:assertEqual(0.1, result[1].destX, "Teleport landing stays at its actual location")
    t:assertEqual(0.9, result[#result].navX, "Last waypoint reaches the target")
end)
