-- PathCalculator.lua
-- Core path calculation module using Dijkstra's algorithm on a travel graph
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local math_sqrt, math_max, math_min, math_huge, math_floor = math.sqrt, math.max, math.min, math.huge, math.floor
local string_format = string.format
local table_insert, table_sort, table_concat = table.insert, table.sort, table.concat
local pcall = pcall

-- Constants
local CROSS_CONTINENT_TIME = 300  -- Default 5 minutes for cross-continent travel
local DEFAULT_COORDINATE = 0.5    -- Default coordinate when position unknown
local DEFAULT_WALK_SPEED = 7      -- Yards per second (walking speed)
local DEFAULT_FLY_SPEED = 31      -- Yards per second (310% flying)
local ZONE_SIZE_YARDS = 1000      -- Approximate zone size in yards for distance calc
local MIN_TRAVEL_TIME = 5         -- Minimum travel time in seconds
local DEBUG_DISPLAY_LIMIT = 5     -- Max items to show in debug output
local PLAYER_NODE = "Player Location"  -- Graph node key for player's current position
local EMPTY_NODE_LIST = {}  -- Shared empty result; never written to

-- Step types that transport the player to a specific location (for AbsorbRedundantWalkSteps)
-- flight intentionally excluded: flight masters deposit at a fixed point,
-- so the subsequent walk to the actual destination is meaningful, not redundant
local TRANSPORT_TYPES = {
    teleport = true, portal = true, boat = true,
    zeppelin = true, tram = true,
}

--- Safe wrapper for TravelTime:EstimateWalkingTime with fallback
-- @param x1 number Source X coordinate (0-1)
-- @param y1 number Source Y coordinate (0-1)
-- @param x2 number Destination X coordinate (0-1)
-- @param y2 number Destination Y coordinate (0-1)
-- @param canFly boolean Whether player can fly
-- @return number Estimated travel time in seconds
local function SafeEstimateWalkingTime(x1, y1, x2, y2, canFly, mapID)
    -- Use TravelTime module directly (pure math, no pcall needed)
    if QR.TravelTime and QR.TravelTime.EstimateWalkingTime then
        return QR.TravelTime:EstimateWalkingTime(x1, y1, x2, y2, canFly, mapID)
    end

    -- Fallback calculation
    local dx = (x2 - x1) * ZONE_SIZE_YARDS
    local dy = (y2 - y1) * ZONE_SIZE_YARDS
    local distance = math_sqrt(dx * dx + dy * dy)
    local speed = canFly and DEFAULT_FLY_SPEED or DEFAULT_WALK_SPEED
    return math_max(MIN_TRAVEL_TIME, distance / speed)
end

-------------------------------------------------------------------------------
-- PathCalculator Module
-------------------------------------------------------------------------------
QR.PathCalculator = {
    graph = nil,       -- The travel graph
    graphDirty = true, -- Flag to indicate graph needs rebuild
}

local PathCalculator = QR.PathCalculator

-- Cached flyable area result
local cachedIsFlyable = nil
local cachedIsFlyableMapID = nil

--- Get cached IsFlyableArea result (invalidated on zone change)
local function GetCachedIsFlyable()
    local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if cachedIsFlyableMapID ~= currentMapID then
        cachedIsFlyable = IsFlyableArea and IsFlyableArea() or false
        cachedIsFlyableMapID = currentMapID
    end
    return cachedIsFlyable
end

-- Register for zone change to invalidate flyable cache
local flyableCacheFrame = CreateFrame("Frame")
flyableCacheFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
flyableCacheFrame:SetScript("OnEvent", function()
    cachedIsFlyableMapID = nil  -- Invalidate cache
end)

--- Get a localized display name for a graph node
-- Uses C_Map to resolve localized zone and continent/parent names
-- Handles disambiguation like "Dalaran (Broken Isles)" → "Dalaran (Verheerte Inseln)" on deDE
-- @param nodeName string The graph node name (may contain English zone names)
-- @param mapID number The map ID for the node
-- @return string The localized display name
local function GetLocalizedNodeDisplayName(nodeName, mapID)
    if not mapID or not C_Map or not C_Map.GetMapInfo then
        return nodeName
    end

    local mapInfo = C_Map.GetMapInfo(mapID)
    if not mapInfo or not mapInfo.name then
        return nodeName
    end

    local zoneName = mapInfo.name

    -- Check if node name has a parenthetical disambiguation (e.g., "Dalaran (Broken Isles)")
    local _, parenthetical = nodeName:match("^(.+)%s*%((.+)%)$")
    if parenthetical and mapInfo.parentMapID then
        -- Get the localized parent (continent/region) name
        local parentInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
        if parentInfo and parentInfo.name and parentInfo.name ~= zoneName then
            return zoneName .. " (" .. parentInfo.name .. ")"
        end
    end

    return zoneName
end

-------------------------------------------------------------------------------
-- Node Location Data
-- Major cities and hubs with their map coordinates
-------------------------------------------------------------------------------

local CAPITAL_CITIES = {
    -- Alliance capitals
    ["Stormwind City"] = {mapID = 84, x = 0.4965, y = 0.8725, faction = "Alliance"},
    ["Ironforge"] = {mapID = 87, x = 0.2730, y = 0.7330, faction = "Alliance"},
    ["Darnassus"] = {mapID = 89, x = 0.4100, y = 0.4710, faction = "Alliance"},
    ["Exodar"] = {mapID = 103, x = 0.3970, y = 0.6247, faction = "Alliance"},
    ["Boralus"] = {mapID = 1161, x = 0.7025, y = 0.1725, faction = "Alliance"},

    -- Horde capitals
    ["Orgrimmar"] = {mapID = 85, x = 0.4690, y = 0.3870, faction = "Horde"},
    ["Undercity"] = {mapID = 90, x = 0.6549, y = 0.4161, faction = "Horde"},
    ["Thunder Bluff"] = {mapID = 88, x = 0.2920, y = 0.2740, faction = "Horde"},
    -- 2393 like Portals, ServicePOIs and the mage teleport. Leaving this at
    -- 110 made the destination search offer a Silvermoon on a different map
    -- than the one the portals land on, with two different routes for one city.
    ["Silvermoon City"] = {mapID = 2393, x = 0.5850, y = 0.1920, faction = "Horde"},
    ["Dazar'alor"] = {mapID = 1165, x = 0.5020, y = 0.4080, faction = "Horde"},

    -- Neutral hubs
    ["Dalaran (Northrend)"] = {mapID = 125, x = 0.4947, y = 0.4709, faction = "both"},
    ["Dalaran (Broken Isles)"] = {mapID = 627, x = 0.5044, y = 0.5313, faction = "both"},
    ["Shattrath City"] = {mapID = 111, x = 0.5410, y = 0.4120, faction = "both"},
    ["Oribos"] = {mapID = 1670, x = 0.4483, y = 0.6466, faction = "both"},
    ["Valdrakken"] = {mapID = 2112, x = 0.5835, y = 0.3535, faction = "both"},
    ["Dornogal"] = {mapID = 2339, x = 0.4850, y = 0.5520, faction = "both"},
}

-- Expose for DestinationSearch module
QR.CAPITAL_CITIES = CAPITAL_CITIES

-------------------------------------------------------------------------------
-- Graph Building Methods
-------------------------------------------------------------------------------

--- Build the complete travel graph
-- Creates nodes for locations and edges for travel methods
-- @return Graph|nil The constructed travel graph, or nil on error
function PathCalculator:BuildGraph()
    -- Create new graph
    self.graph = QR.Graph:New()
    -- The index belongs to the graph that was just discarded. Leaving it in
    -- place is worse than having none: NodesOnMap would hand back names from
    -- the old object, AddEdge would refuse them, and the edges would vanish
    -- without an error.
    self.nodeIndex = nil
    if not self.graph then
        QR:Error("Failed to create graph")
        return nil
    end

    QR:Log("INFO", "BuildGraph started")

    local buildSuccess = true
    local buildError = nil

    -- Add zone/city nodes
    local success, err = pcall(function()
        self:AddZoneNodes()
    end)
    if not success then
        QR:Error("AddZoneNodes failed: " .. tostring(err))
        buildSuccess = false
        buildError = err
    end

    -- Add portal hub connections
    success, err = pcall(function()
        self:AddPortalConnections()
    end)
    if not success then
        QR:Error("AddPortalConnections failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Add player teleport edges
    success, err = pcall(function()
        self:AddPlayerTeleportEdges()
    end)
    if not success then
        QR:Error("AddPlayerTeleportEdges failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Add dungeon/raid entrance nodes
    success, err = pcall(function()
        self:AddDungeonNodes()
    end)
    if not success then
        QR:Error("AddDungeonNodes failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Dungeon teleports the player knows. Must come after AddDungeonNodes:
    -- the nodes these edges point at do not exist before it.
    success, err = pcall(function()
        self:AddDungeonTeleportEdges()
    end)
    if not success then
        QR:Error("AddDungeonTeleportEdges failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- IMPORTANT: Connect all nodes on the same map with walking edges
    -- This ensures teleport destinations connect to portal hubs on the same map
    success, err = pcall(function()
        self:ConnectSameMapNodes()
    end)
    if not success then
        QR:Error("ConnectSameMapNodes failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Connect island nodes to the continent graph.
    -- Portal destinations and dungeon entrances may be the only node on their
    -- map, leaving them isolated. Give each one a hub/continent edge so
    -- Dijkstra can traverse across maps.
    -- The player node last, once every other node and edge exists.
    success, err = pcall(function()
        self:ConnectPlayerNode()
    end)
    if not success then
        QR:Error("ConnectPlayerNode failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    success, err = pcall(function()
        self:ConnectIslandNodes()
    end)
    if not success then
        QR:Error("ConnectIslandNodes failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Only mark clean if all steps succeeded
    self.graphDirty = not buildSuccess

    -- Log graph stats
    local nodeCount, edgeCount = 0, 0
    for _ in pairs(self.graph.nodes) do nodeCount = nodeCount + 1 end
    for _, edges in pairs(self.graph.edges) do
        for _ in pairs(edges) do edgeCount = edgeCount + 1 end
    end
    QR:Log("INFO", string_format("BuildGraph complete: %d nodes, %d edges, success=%s",
        nodeCount, edgeCount, tostring(buildSuccess)))

    return self.graph
end

--- Connect all nodes that share the same mapID with walking edges
-- This is crucial for connecting teleport destinations to nearby portal hubs
function PathCalculator:ConnectSameMapNodes()
    -- Only assume flying for the player's CURRENT map; remote maps use ground speed
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local playerCanFly = GetCachedIsFlyable()

    -- Group nodes by mapID
    local nodesByMap = {}
    for nodeName, nodeData in pairs(self.graph.nodes) do
        if nodeData.mapID then
            if not nodesByMap[nodeData.mapID] then
                nodesByMap[nodeData.mapID] = {}
            end
            table_insert(nodesByMap[nodeData.mapID], {name = nodeName, data = nodeData})
        end
    end

    -- Connect nodes on the same map
    local connectionsAdded = 0
    for mapID, nodes in pairs(nodesByMap) do
        if #nodes > 1 then
            -- Only use flying speed for player's current map
            local canFly = (mapID == playerMapID) and playerCanFly or false

            -- Connect each pair of nodes on this map
            for i = 1, #nodes do
                for j = i + 1, #nodes do
                    local nodeA = nodes[i]
                    local nodeB = nodes[j]

                    -- Check if edge already exists; override coarse "travel" estimates
                    -- Check both directions since AddBidirectionalEdge writes both
                    local existingEdge = self.graph:GetEdge(nodeA.name, nodeB.name)
                    local reverseEdge = self.graph:GetEdge(nodeB.name, nodeA.name)
                    if (not existingEdge or existingEdge.edgeType == "travel")
                        and (not reverseEdge or reverseEdge.edgeType == "travel") then
                        -- Calculate walking time
                        local walkTime = SafeEstimateWalkingTime(
                            nodeA.data.x or 0.5, nodeA.data.y or 0.5,
                            nodeB.data.x or 0.5, nodeB.data.y or 0.5,
                            canFly, mapID
                        )

                        -- Add bidirectional walking edge
                        self.graph:AddBidirectionalEdge(nodeA.name, nodeB.name, walkTime, "walk", {
                            autoConnected = true,
                            mapID = mapID,
                        })
                        connectionsAdded = connectionsAdded + 1
                    end
                end
            end
        end
    end

    QR:Debug(string_format("Connected %d same-map node pairs", connectionsAdded))
end

--- Add capital cities and major hubs as nodes
-- Filters by player faction
function PathCalculator:AddZoneNodes()
    local playerFaction = QR.PlayerInfo:GetFaction()

    for nodeName, nodeData in pairs(CAPITAL_CITIES) do
        -- Check faction compatibility
        local factionMatch = nodeData.faction == "both" or nodeData.faction == playerFaction

        if factionMatch then
            self.graph:AddNode(nodeName, {
                mapID = nodeData.mapID,
                x = nodeData.x,
                y = nodeData.y,
                faction = nodeData.faction,
                nodeType = "city",
            })
        end
    end
end

--- Add portal hub nodes and their portal edges
-- Uses QR:GetAvailablePortals() to get faction-filtered portals
function PathCalculator:AddPortalConnections()
    local portals = QR:GetAvailablePortals()

    -- Add hub nodes and portal edges
    for hubName, hubData in pairs(portals.hubs) do
        -- Ensure hub node exists
        if not self.graph.nodes[hubName] then
            self.graph:AddNode(hubName, {
                mapID = hubData.mapID,
                x = hubData.x,
                y = hubData.y,
                faction = hubData.faction,
                nodeType = "hub",
            })
        end

        -- Add edges from hub to each portal destination
        for _, portal in ipairs(hubData.portals) do
            local destName = portal.destination

            -- Ensure destination node exists
            if not self.graph.nodes[destName] then
                self.graph:AddNode(destName, {
                    mapID = portal.mapID,
                    x = portal.x,
                    y = portal.y,
                    nodeType = "destination",
                })
            end

            -- Add portal edge with travel time as weight
            local travelTime = QR.TravelTime:GetPortalTime()
            -- Add loading screen time cost
            local loadingTime = QR.db and QR.db.loadingScreenTime or 0
            travelTime = travelTime + loadingTime
            self.graph:AddEdge(hubName, destName, travelTime, "portal", {
                portalData = portal,
            })
        end
    end

    -- Add standalone portal connections (boats, zeppelins, trams)
    for _, transport in ipairs(portals.standalone) do
        local fromName = transport.name .. " (Start)"
        local toName = transport.name .. " (End)"

        -- Create nodes for transport endpoints if needed
        if not self.graph.nodes[fromName] then
            self.graph:AddNode(fromName, {
                mapID = transport.from.mapID,
                x = transport.from.x,
                y = transport.from.y,
                nodeType = "transport",
            })
        end

        if not self.graph.nodes[toName] then
            self.graph:AddNode(toName, {
                mapID = transport.to.mapID,
                x = transport.to.x,
                y = transport.to.y,
                nodeType = "transport",
            })
        end

        -- Add transport edge
        local travelTime = transport.travelTime or QR.TravelTime:GetTransportTime(transport.type)
        self.graph:AddEdge(fromName, toName, travelTime, transport.type, {
            transportData = transport,
        })

        -- Add reverse edge if bidirectional
        if transport.bidirectional then
            self.graph:AddEdge(toName, fromName, travelTime, transport.type, {
                transportData = transport,
            })
        end
    end
end

--- Add edges for player's available teleport methods
-- Uses PlayerInventory:GetAllTeleports() to get available teleports
function PathCalculator:AddPlayerTeleportEdges()
    local teleports = QR.PlayerInventory:GetAllTeleports()

    -- Add "Player Location" as a special node
    if not self.graph.nodes[PLAYER_NODE] then
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then return end  -- In loading screen or unmapped area
        local posOk, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if not posOk then pos = nil end
        local x, y = DEFAULT_COORDINATE, DEFAULT_COORDINATE
        if pos then
            local px, py = pos:GetXY()
            if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
                x, y = px, py
            end
        end

        self.graph:AddNode(PLAYER_NODE, {
            mapID = mapID,
            x = x,
            y = y,
            nodeType = "player",
            isDynamic = true,
        })
    end

    -- Add edges from player location to each teleport destination
    for teleportID, teleport in pairs(teleports) do
        local data = teleport.data
        if data and data.mapID and not data.isDynamic and not data.isRandom then
            local destName = data.destination or data.name

            -- Ensure destination node exists
            if not self.graph.nodes[destName] then
                self.graph:AddNode(destName, {
                    mapID = data.mapID,
                    x = data.x or 0.5,
                    y = data.y or 0.5,
                    nodeType = "teleport_dest",
                })
            end

            -- Check max cooldown filter — skip teleports that exceed threshold
            local skipTeleport = false
            local maxCDHours = QR.db and QR.db.maxCooldownHours
            if maxCDHours and maxCDHours < 24 then  -- 24 = "no filter"
                local maxCDSeconds = maxCDHours * 3600
                if QR.CooldownTracker then
                    local cdInfo = QR.CooldownTracker:GetCooldown(teleportID, teleport.sourceType)
                    if cdInfo and cdInfo.duration and cdInfo.duration > maxCDSeconds then
                        skipTeleport = true
                    end
                end
            end

            if not skipTeleport then
                -- Calculate effective travel time (with optional cooldown wait)
                local includeCooldown = QR.db and QR.db.considerCooldowns
                local travelTime = QR.TravelTime:GetEffectiveTime(teleportID, data, includeCooldown)
                -- Add loading screen time cost for teleports
                local loadingTime = QR.db and QR.db.loadingScreenTime or 0
                travelTime = travelTime + loadingTime

                self.graph:AddEdge(PLAYER_NODE, destName, travelTime, "teleport", {
                    teleportID = teleportID,
                    teleportData = data,
                    sourceType = teleport.sourceType,
                })
            end
        end
    end
end

--- Re-price the player's teleport edges against live cooldown state.
-- AddPlayerTeleportEdges bakes the remaining cooldown into the edge weight, but
-- it only runs inside BuildGraph, and no cooldown event marks the graph dirty —
-- PlayerInventory registers BAG_UPDATE, PLAYER_EQUIPMENT_CHANGED, TOYS_UPDATED
-- and SPELLS_CHANGED, but neither BAG_UPDATE_COOLDOWN nor SPELL_UPDATE_COOLDOWN.
-- Weights therefore froze at build time in both directions: a teleport used
-- after the build stayed priced as ready, and one that was on cooldown during
-- the build stayed expensive long after it came back up.
-- Registering the cooldown events instead would mean a full rebuild on events
-- that fire constantly; this is O(number of teleports) and needs no rebuild.
function PathCalculator:RefreshTeleportEdgeWeights()
    local outgoing = self.graph and self.graph.edges[PLAYER_NODE]
    if not outgoing then
        return
    end

    local includeCooldown = QR.db and QR.db.considerCooldowns
    local loadingTime = QR.db and QR.db.loadingScreenTime or 0

    for _, edge in pairs(outgoing) do
        local data = edge.data
        if edge.edgeType == "teleport" and data and data.teleportID and data.teleportData then
            local travelTime = QR.TravelTime:GetEffectiveTime(
                data.teleportID, data.teleportData, includeCooldown)
            travelTime = travelTime + loadingTime
            if travelTime <= 0 then
                travelTime = 0.001  -- match Graph:AddEdge's epsilon
            end
            edge.weight = travelTime
        end
    end
end

--- Add dungeon/raid entrance nodes to the graph
-- Each entrance becomes a node connected to its parent zone via walking edge
function PathCalculator:AddDungeonNodes()
    if not QR.DungeonData or not QR.DungeonData.scanned then
        QR:Debug("PathCalculator: DungeonData not available, skipping dungeon nodes")
        return
    end

    -- First pass: add all dungeon nodes
    local dungeonNodes = {}
    local addedCount = 0
    for instanceID, inst in pairs(QR.DungeonData.instances) do
        if inst.zoneMapID and inst.x and inst.y and inst.name then
            local nodeName = "Dungeon: " .. inst.name
            self.graph:AddNode(nodeName, {
                mapID = inst.zoneMapID,
                x = inst.x,
                y = inst.y,
                journalInstanceID = instanceID,
                isRaid = inst.isRaid,
                isDungeon = true,
            })
            table_insert(dungeonNodes, {name = nodeName, mapID = inst.zoneMapID, x = inst.x, y = inst.y})
            addedCount = addedCount + 1
        end
    end

    -- Second pass: connect dungeon nodes via continent routing
    -- (all dungeon+teleport nodes exist by now, so adjacency edges work)
    -- The index is built once here rather than per node: without it each of the
    -- hundreds of dungeon nodes drives four full scans of the node table.
    self:BuildNodeIndex()
    for _, dn in ipairs(dungeonNodes) do
        self:ConnectViaContinentRouting(dn.name, dn.mapID, dn.x, dn.y)
    end

    QR:Debug(string_format("PathCalculator: added %d dungeon/raid entrance nodes", addedCount))
end

-------------------------------------------------------------------------------
-- Path Calculation Methods
-------------------------------------------------------------------------------

--- Calculate optimal path to a destination
-- Rebuilds graph, adds destination node, runs Dijkstra
-- @param destMapID number The destination map ID
-- @param destX number The destination X coordinate (0-1)
-- @param destY number The destination Y coordinate (0-1)
-- @return table|nil {path, totalTime, edges, steps} or nil if no path found
function PathCalculator:CalculatePath(destMapID, destX, destY, destTitle)
    -- Rebuild graph if needed
    if self.graphDirty or not self.graph then
        self:BuildGraph()
    end

    -- Resolve continent-level mapIDs to specific zones
    -- (mapType: 0=Cosmic, 1=World, 2=Continent, 3=Zone)
    if destMapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(destMapID)
        if mapInfo and mapInfo.mapType and mapInfo.mapType <= 2 then
            -- Try to resolve to a more specific zone using coordinates
            if C_Map.GetMapInfoAtPosition then
                local childInfo = C_Map.GetMapInfoAtPosition(destMapID, destX, destY)
                if childInfo and childInfo.mapID and childInfo.mapID ~= destMapID then
                    QR:Log("INFO", string_format("Resolved continent %d -> zone %d (%s)",
                        destMapID, childInfo.mapID, childInfo.name or "?"))
                    destMapID = childInfo.mapID
                end
            end
        end
    end

    -- Update player location node
    self:UpdatePlayerLocation()

    -- Cooldowns move without marking the graph dirty, so re-price the player's
    -- teleport edges against live state before searching.
    self:RefreshTeleportEdgeWeights()

    -- Build human-readable destination node name
    local destZoneName
    if C_Map and C_Map.GetMapInfo then
        local destMapInfo = C_Map.GetMapInfo(destMapID)
        if destMapInfo and destMapInfo.name then
            destZoneName = destMapInfo.name
        end
    end
    local destName
    if destTitle and destTitle ~= "" then
        destName = destTitle
    elseif destZoneName then
        destName = destZoneName
    else
        destName = string_format("Map %d", destMapID)
    end
    -- Ensure unique node name (title might conflict with existing nodes like city names)
    if self.graph.nodes[destName] then
        destName = destName .. string_format(" (%.0f, %.0f)", destX * 100, destY * 100)
    end

    -- Add destination node
    self.graph:AddNode(destName, {
        mapID = destMapID,
        x = destX,
        y = destY,
        nodeType = "destination",
    })

    -- Debug: Show destination continent info
    if QR.debugMode then
        local destContinent = QR.GetContinentForZone and QR.GetContinentForZone(destMapID) or "unknown"
        QR:Debug(string_format("Destination map %d is on continent: %s", destMapID, tostring(destContinent)))

        -- Show nodes on same continent
        local sameContinentNodes = {}
        for nodeName, nodeData in pairs(self.graph.nodes) do
            if nodeData.mapID then
                local nodeContinent = QR.GetContinentForZone and QR.GetContinentForZone(nodeData.mapID)
                if nodeContinent == destContinent then
                    table_insert(sameContinentNodes, string_format("%s (map %d)", nodeName, nodeData.mapID))
                end
            end
        end
        QR:Debug(string_format("  Nodes on same continent: %d", #sameContinentNodes))
        for i, name in ipairs(sameContinentNodes) do
            if i <= DEBUG_DISPLAY_LIMIT then
                QR:Debug(string_format("    - %s", name))
            end
        end
        if #sameContinentNodes > DEBUG_DISPLAY_LIMIT then
            QR:Debug(string_format("    ... and %d more", #sameContinentNodes - DEBUG_DISPLAY_LIMIT))
        end
    end

    -- Connect destination to nearby nodes on the same map
    self:ConnectNearbyNodes(destName, destMapID, destX, destY)

    -- Debug: Show edges created for destination
    if QR.debugMode then
        local destEdges = self.graph.edges[destName]
        if destEdges then
            local edgeCount = 0
            for _ in pairs(destEdges) do edgeCount = edgeCount + 1 end
            QR:Debug(string_format("Destination has %d outgoing edges:", edgeCount))
            local shown = 0
            for toNode, edge in pairs(destEdges) do
                if shown < DEBUG_DISPLAY_LIMIT then
                    QR:Debug(string_format("    -> %s (%s, %ds)", toNode, edge.edgeType, edge.weight))
                    shown = shown + 1
                end
            end
        else
            QR:Warn("Destination has NO outgoing edges!")
        end
    end

    -- Run Dijkstra's algorithm
    local path, totalTime, pathEdges = self.graph:FindShortestPath(PLAYER_NODE, destName)

    if not path then
        -- Clean up destination node on failure
        self.graph:RemoveNode(destName)
        QR:Debug("Dijkstra found no path")
        QR:Log("WARN", string_format("No path found to map %d (%.2f, %.2f)", destMapID, destX, destY))
        return nil
    end

    QR:Log("INFO", string_format("Path found to map %d: %d nodes, %ds", destMapID, #path, totalTime or 0))

    -- Build human-readable steps BEFORE removing destination node
    -- (BuildSteps needs node data for coordinates and zone name resolution)
    local stepOk, steps = pcall(function() return self:BuildSteps(path, pathEdges) end)

    -- Clean up temporary destination node (always, even if BuildSteps errors)
    self.graph:RemoveNode(destName)

    if not stepOk then
        QR:Error("BuildSteps error: " .. tostring(steps))
        return nil
    end

    -- Collapse consecutive walk/travel steps
    steps = self:CollapseConsecutiveSteps(steps)

    -- Absorb walk steps that follow a transport to the same map
    -- e.g. "Teleport to Stormwind" + "Go to Stormwind" → just "Teleport to Stormwind"
    steps = self:AbsorbRedundantWalkSteps(steps)

    return {
        path = path,
        totalTime = totalTime,
        edges = pathEdges,
        steps = steps,
    }
end

--- Update player location node with current position
function PathCalculator:UpdatePlayerLocation()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    -- Abort if no valid map (e.g., in instance loading, unmapped area)
    if not mapID then
        QR:Debug("Cannot get player map ID (instance/loading?)")
        return
    end

    local posOk, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not posOk then pos = nil end
    local x, y = DEFAULT_COORDINATE, DEFAULT_COORDINATE
    if pos then
        local px, py = pos:GetXY()
        if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
            x, y = px, py
        end
    end

    local node = self.graph.nodes[PLAYER_NODE]
    if not node then
        return
    end

    local moved = (node.mapID ~= mapID) or (node.x ~= x) or (node.y ~= y)

    node.mapID = mapID
    node.x = x
    node.y = y

    -- The node's walk and travel edges were computed once, in BuildGraph,
    -- against whatever map the player stood on then. Nothing marks the graph
    -- dirty on movement, so without this every route computed after a zone
    -- change until the next bag update started with a walk into the old zone.
    if moved then
        self:ReconnectPlayerNode(mapID, x, y)
    end
end

--- True when either direction between two nodes already holds a teleport edge.
-- The graph holds one edge per ordered pair, so every write is a replacement:
-- a teleport edge and a walk or travel edge between the same two nodes cannot
-- coexist. A teleport edge IS the teleport as far as the route is concerned --
-- the step carries its teleportID and its secure Use button off that edge -- so
-- an estimate written over it removes the teleport from every route until an
-- inventory event happens to rebuild the graph. ReconnectPlayerNode keeps the
-- teleport edges on purpose when the player moves; without this the very next
-- ConnectNearbyNodes overwrote them anyway.
--
-- Both directions are checked because the writers use AddBidirectionalEdge,
-- which writes both. The backward half is defence in depth, not covered code:
-- teleport edges are only ever written as PLAYER_NODE -> destination, and no
-- writer is currently reached with the player node as the target, so replacing
-- that half with `false` reddens nothing. It is kept for the case where a
-- future writer -- ConnectIslandNodes reaching a teleport destination node
-- with the player node among its candidates -- does arrive from the other side.
local function HasTeleportEdge(graph, from, to)
    local forward = graph:GetEdge(from, to)
    if forward and forward.edgeType == "teleport" then
        return true
    end
    local back = graph:GetEdge(to, from)
    return (back and back.edgeType == "teleport") or false
end

--- True when a walking edge may be written between two nodes.
local function CanOverwriteWithWalk(graph, from, to)
    return not HasTeleportEdge(graph, from, to)
end

--- Rebuild the player node's position-derived edges for its current map.
-- Walk and travel edges depend on where the player stands and are dropped;
-- teleport edges do not and are kept.
-- @param mapID number The player's current map ID
-- @param x number The X coordinate (0-1)
-- @param y number The Y coordinate (0-1)
function PathCalculator:ReconnectPlayerNode(mapID, x, y)
    local outgoing = self.graph.edges[PLAYER_NODE]
    if outgoing then
        for otherName, edge in pairs(outgoing) do
            if edge.edgeType == "walk" or edge.edgeType == "travel" then
                outgoing[otherName] = nil

                local incoming = self.graph.edges[otherName]
                local back = incoming and incoming[PLAYER_NODE]
                if back and (back.edgeType == "walk" or back.edgeType == "travel") then
                    incoming[PLAYER_NODE] = nil
                end
            end
        end
    end

    self:ConnectNearbyNodes(PLAYER_NODE, mapID, x, y)
end

--- Connect a node to other nodes on the same map with walking edges
-- Uses zone adjacency data for proper cross-zone connections
-- @param nodeName string The node to connect
-- @param mapID number The map ID
-- @param x number The X coordinate (0-1)
-- @param y number The Y coordinate (0-1)
function PathCalculator:ConnectNearbyNodes(nodeName, mapID, x, y)
    -- Called after the caller has added its node, so the index is refreshed
    -- here rather than reused from BuildGraph.
    self:BuildNodeIndex()

    -- Only assume flying for the player's current map; remote maps use ground speed
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local canFly = (mapID == playerMapID) and GetCachedIsFlyable() or false

    -- First pass: connect to nodes on the same map
    for otherName, otherData in pairs(self.graph.nodes) do
        if otherName ~= nodeName and otherData.mapID == mapID
            and CanOverwriteWithWalk(self.graph, nodeName, otherName) then
            -- Calculate walking time between nodes
            local walkTime = SafeEstimateWalkingTime(
                x, y,
                otherData.x, otherData.y,
                canFly, mapID
            )

            -- Add bidirectional walking edge
            self.graph:AddBidirectionalEdge(nodeName, otherName, walkTime, "walk", {
                distance = QR.TravelTime:CalculateDistance(x, y, otherData.x, otherData.y),
            })
        end
    end

    -- Always use continent routing for robust connectivity.
    -- Same-map nodes (e.g. dungeon entrances) may be isolated from the graph,
    -- so we need hub/continent edges regardless.
    self:ConnectViaContinentRouting(nodeName, mapID, x, y)
end

--- Connect a node using continent-aware routing
-- Uses ZoneAdjacency.lua data for proper geographic routing
-- @param nodeName string The node to connect
-- @param mapID number The map ID
-- @param x number The X coordinate (0-1)
-- @param y number The Y coordinate (0-1)
--- True when a coarse "travel" estimate may be written over whatever edge is
-- already there. Continent routing only estimates; a "walk" edge produced by
-- the same-map pass is measured from real coordinates and must not be replaced.
local function CanOverwriteWithTravel(graph, from, to)
    if HasTeleportEdge(graph, from, to) then
        return false
    end
    local existing = graph:GetEdge(from, to)
    return not existing or existing.edgeType ~= "walk"
end

--- Index the current nodes by map, by continent, and by hub/city status.
-- ConnectViaContinentRouting filters on nothing but equality, so a lookup
-- replaces a full scan without changing which nodes match. Rebuilt whenever the
-- set of nodes changes; ConnectViaContinentRouting falls back to scanning when
-- no index is present, so a missed rebuild costs speed rather than correctness.
function PathCalculator:BuildNodeIndex()
    local byMap, byContinent, hubsAndCities = {}, {}, {}

    for nodeName, nodeData in pairs(self.graph.nodes) do
        local mapID = nodeData.mapID
        if mapID then
            local bucket = byMap[mapID]
            if not bucket then
                bucket = {}
                byMap[mapID] = bucket
            end
            bucket[#bucket + 1] = nodeName

            local continent = QR.GetContinentForZone and QR.GetContinentForZone(mapID)
            if continent then
                local cont = byContinent[continent]
                if not cont then
                    cont = {}
                    byContinent[continent] = cont
                end
                cont[#cont + 1] = nodeName
            end
        end

        if nodeData.nodeType == "hub" or nodeData.nodeType == "city" then
            hubsAndCities[#hubsAndCities + 1] = nodeName
        end
    end

    self.nodeIndex = {
        byMap = byMap,
        byContinent = byContinent,
        hubsAndCities = hubsAndCities,
    }
    return self.nodeIndex
end

--- Node names on a given map, from the index when it exists.
-- @return table Array of node names
function PathCalculator:NodesOnMap(mapID)
    if self.nodeIndex then
        return self.nodeIndex.byMap[mapID] or EMPTY_NODE_LIST
    end
    local names = {}
    for nodeName, nodeData in pairs(self.graph.nodes) do
        if nodeData.mapID == mapID then
            names[#names + 1] = nodeName
        end
    end
    return names
end

function PathCalculator:ConnectViaContinentRouting(nodeName, mapID, x, y)
    local destContinent = QR.GetContinentForZone and QR.GetContinentForZone(mapID)
    local connectedSomething = false

    QR:Debug(string_format("Routing for map %d, continent: %s",
        mapID, tostring(destContinent)))

    -- Strategy 1: Connect to directly adjacent zones
    local adjacentZones = QR.GetAdjacentZones and QR.GetAdjacentZones(mapID) or {}
    for _, adj in ipairs(adjacentZones) do
        -- Find nodes on the adjacent zone
        for _, otherName in ipairs(self:NodesOnMap(adj.zone)) do
            if otherName ~= nodeName
                and CanOverwriteWithWalk(self.graph, nodeName, otherName) then
                self.graph:AddBidirectionalEdge(nodeName, otherName, adj.travelTime, "walk", {
                    note = "Adjacent zone travel",
                    fromMapID = mapID,
                    toMapID = adj.zone,
                })
                connectedSomething = true

                QR:Debug(string_format("  -> Connected to adjacent zone: %s (map %d) - %ds",
                    otherName, adj.zone, adj.travelTime))
            end
        end
    end

    -- Strategy 2: Connect to continent hub if we know the continent
    if destContinent and QR.Continents and QR.Continents[destContinent] then
        local playerFaction = QR.PlayerInfo:GetFaction()
        local hubMapID = QR.GetContinentHub and QR.GetContinentHub(destContinent, playerFaction)

        -- When the node is already on the hub map, the same-map pass in
        -- ConnectNearbyNodes has connected it with measured walk edges.
        -- EstimateSameContinentTravel(hub, hub) is 0, which AddEdge clamps to
        -- the 0.001 epsilon, so running this strategy here would replace every
        -- one of those walk edges with a free "travel" edge.
        --
        -- No test reddens on removing this check alone: CanOverwriteWithTravel
        -- below refuses the same writes for the same reason. It is kept because
        -- it states the condition where it is cheap to read, but do not count
        -- it as covered.
        if hubMapID and hubMapID ~= mapID then
            -- Find the hub node
            for _, otherName in ipairs(self:NodesOnMap(hubMapID)) do
                if otherName ~= nodeName
                    and CanOverwriteWithTravel(self.graph, nodeName, otherName) then
                    -- Estimate time from hub to destination
                    local travelTime = QR.EstimateSameContinentTravel and
                        QR.EstimateSameContinentTravel(hubMapID, mapID) or 180

                    self.graph:AddBidirectionalEdge(nodeName, otherName, travelTime, "travel", {
                        note = "Same continent via hub",
                        fromMapID = mapID,
                        toMapID = hubMapID,
                        continent = destContinent,
                    })
                    connectedSomething = true

                    QR:Debug(string_format("  -> Connected to continent hub: %s (map %d) - %ds",
                        otherName, hubMapID, travelTime))
                end
            end
        end
    end

    -- Strategy 3: Connect to nodes on the same continent (fallback)
    if not connectedSomething and destContinent then
        local bestNode, bestTime = nil, math_huge

        local sameContinent = self.nodeIndex and self.nodeIndex.byContinent[destContinent]
        if sameContinent then
            for _, otherName in ipairs(sameContinent) do
                local otherData = self.graph.nodes[otherName]
                if otherName ~= nodeName and otherData and otherData.mapID then
                    local travelTime = QR.EstimateSameContinentTravel and
                        QR.EstimateSameContinentTravel(otherData.mapID, mapID) or 180

                    if travelTime < bestTime then
                        bestTime = travelTime
                        bestNode = otherName
                    end
                end
            end
        else
            for otherName, otherData in pairs(self.graph.nodes) do
                if otherName ~= nodeName and otherData.mapID then
                    local otherContinent = QR.GetContinentForZone and QR.GetContinentForZone(otherData.mapID)

                    if otherContinent == destContinent then
                        local travelTime = QR.EstimateSameContinentTravel and
                            QR.EstimateSameContinentTravel(otherData.mapID, mapID) or 180

                        if travelTime < bestTime then
                            bestTime = travelTime
                            bestNode = otherName
                        end
                    end
                end
            end
        end

        -- A refused candidate counts as connected. It was refused because a
        -- measured walk edge to it already exists, which is strictly better
        -- than the estimate this strategy wanted to write — but leaving
        -- connectedSomething false sent the node on to the cross-continent last
        -- resort, which happily wrote a negative weight that AddEdge clamps to
        -- the 0.001 epsilon. A destination inside a capital then looked one
        -- free hop away and the route lost its real legs.
        if bestNode and not CanOverwriteWithTravel(self.graph, nodeName, bestNode) then
            connectedSomething = true
        elseif bestNode then
            local bestData = self.graph.nodes[bestNode]
            self.graph:AddBidirectionalEdge(nodeName, bestNode, bestTime, "travel", {
                note = "Same continent travel",
                fromMapID = mapID,
                toMapID = bestData.mapID,
                continent = destContinent,
            })
            connectedSomething = true

            QR:Debug(string_format("  -> Connected to same-continent node: %s (map %d) - %ds",
                bestNode, bestData.mapID, bestTime))
        end
    end

    -- Strategy 4: Cross-continent connections (last resort)
    -- Connect to ALL hub/city nodes on other continents so Dijkstra can find optimal routes
    if not connectedSomething then
        local connectCount = 0

        -- Only hub and city nodes are eligible below, so iterate just those.
        local candidates = self.nodeIndex and self.nodeIndex.hubsAndCities
        if not candidates then
            candidates = {}
            for otherName in pairs(self.graph.nodes) do
                candidates[#candidates + 1] = otherName
            end
        end

        for _, otherName in ipairs(candidates) do
            local otherData = self.graph.nodes[otherName]
            if otherName ~= nodeName and otherData and otherData.mapID then
                local otherContinent = QR.GetContinentForZone and QR.GetContinentForZone(otherData.mapID)

                -- Calculate cross-continent time
                local baseTime = CROSS_CONTINENT_TIME
                if destContinent and otherContinent and QR.GetCrossContinentTravel then
                    baseTime = QR.GetCrossContinentTravel(otherContinent, destContinent)
                end

                -- Connect to hub/city nodes on other continents (let Dijkstra optimize)
                -- Also connect to the single best non-hub as fallback
                -- Neither the continent check nor the floor below reddens a
                -- test on its own, and the state they guard cannot be reached
                -- from a built graph: strategy 4 runs only when nothing else
                -- connected the node, which with a known destContinent means
                -- its continent holds no other node -- so no candidate can
                -- share it, and baseTime stays at CROSS_CONTINENT_TIME. They
                -- are defence in depth against a data change, not covered code.
                if (otherData.nodeType == "hub" or otherData.nodeType == "city")
                    and otherContinent ~= destContinent
                    and CanOverwriteWithTravel(self.graph, nodeName, otherName) then
                    -- Floor the hub bonus: GetCrossContinentTravel returns 0 for
                    -- a continent to itself, and baseTime - 60 then goes
                    -- negative, which AddEdge clamps to the 0.001 epsilon and
                    -- Dijkstra reads as free.
                    local hubTime = baseTime - 60  -- 1 minute bonus for hubs
                    if hubTime < 1 then hubTime = 1 end
                    self.graph:AddBidirectionalEdge(nodeName, otherName, hubTime, "travel", {
                        note = "Cross-continent travel",
                        fromMapID = mapID,
                        toMapID = otherData.mapID,
                        fromContinent = destContinent,
                        toContinent = otherContinent,
                    })
                    connectCount = connectCount + 1
                end
            end
        end

        -- Fallback: no hub or city was connected, so attach the node to one
        -- other node rather than leaving it isolated.
        --
        -- Every candidate costs the same. This branch runs only when the node
        -- has no continent the hub pass could price against, so there is
        -- nothing to compare and no cheapest to find -- the previous shape
        -- looked like a search (bestNode, bestTime, a < comparison) while the
        -- compared value was the constant CROSS_CONTINENT_TIME, so it always
        -- took whichever name pairs() happened to yield first. That is Lua hash
        -- order: not stable between runs, and not reproducible from a bug
        -- report. Sorting picks the same node every time; it is for
        -- determinism, not for optimality.
        --
        -- Candidates the overwrite rules refuse are skipped rather than
        -- overwritten: this was the one write in the whole strategy without
        -- that check, so it replaced measured walk edges and teleport edges
        -- with a flat estimate. When every candidate is refused there is
        -- nothing to do -- the node already has real edges to them, which is
        -- the opposite of isolated.
        --
        -- Not reached by any graph the addon builds: instrumented over 612
        -- builds (every zone in ZoneAdjacencies, both factions, with and
        -- without class portals) the branch was entered 0 times. It is kept as
        -- defence in depth against a data change that leaves a node with no
        -- continent, which is exactly the state it exists for.
        if connectCount == 0 then
            local eligible = {}
            for otherName, otherData in pairs(self.graph.nodes) do
                if otherName ~= nodeName and otherData.mapID
                    and CanOverwriteWithTravel(self.graph, nodeName, otherName) then
                    eligible[#eligible + 1] = otherName
                end
            end
            table_sort(eligible)
            local bestNode = eligible[1]
            if bestNode then
                local bestData = self.graph.nodes[bestNode]
                local otherContinent = QR.GetContinentForZone and QR.GetContinentForZone(bestData.mapID)
                self.graph:AddBidirectionalEdge(nodeName, bestNode, CROSS_CONTINENT_TIME, "travel", {
                    note = "Cross-continent travel (fallback)",
                    fromMapID = mapID,
                    toMapID = bestData.mapID,
                    fromContinent = destContinent,
                    toContinent = otherContinent,
                })
                connectCount = 1
            end
        end

        if connectCount > 0 then
            QR:Debug(string_format("  -> Cross-continent: connected to %d hub/city nodes", connectCount))
        end
    end
end

--- Add an edge from the player to each dungeon they can teleport to.
-- Separate from AddPlayerTeleportEdges because that one runs before the dungeon
-- nodes exist and builds its own destination node from data.mapID, which these
-- spells do not carry: a dungeon teleport lands at an entrance the graph already
-- models, so it should reuse that node rather than invent a second one beside it.
function PathCalculator:AddDungeonTeleportEdges()
    if not QR.DungeonTeleportSpells or not QR.PlayerInventory then
        return
    end

    -- Index the dungeon nodes by instance, so a spell finds its entrance in one
    -- lookup rather than a scan per spell.
    local nodeByInstance = {}
    for nodeName, nodeData in pairs(self.graph.nodes) do
        if nodeData.isDungeon and nodeData.journalInstanceID then
            nodeByInstance[nodeData.journalInstanceID] = nodeName
        end
    end
    if not next(nodeByInstance) then
        return
    end

    local teleports = QR.PlayerInventory:GetAllTeleports()
    local added = 0
    for teleportID, teleport in pairs(teleports) do
        local data = teleport.data
        local instanceID = data and data.journalInstanceID
        local destName = instanceID and nodeByInstance[instanceID]
        if destName then
            local includeCooldown = QR.db and QR.db.considerCooldowns
            local travelTime = QR.TravelTime:GetEffectiveTime(teleportID, data, includeCooldown)
            travelTime = travelTime + (QR.db and QR.db.loadingScreenTime or 0)

            self.graph:AddEdge(PLAYER_NODE, destName, travelTime, "teleport", {
                teleportID = teleportID,
                teleportData = data,
                sourceType = teleport.sourceType,
            })
            added = added + 1
        end
    end

    if added > 0 then
        QR:Debug(string_format("PathCalculator: %d dungeon teleport edge(s)", added))
    end
end

--- Give the player node its position-derived edges at build time.
-- Without this the player is only connected by whatever teleports they own.
-- ConnectSameMapNodes reaches them only when another node shares their map, and
-- ConnectIslandNodes skips them by name, so a character with no teleports
-- standing somewhere with no other node -- Thunder Bluff, Warspear, most of
-- Pandaria and Draenor -- had a player node with zero edges and no route
-- anywhere until they happened to move, because ReconnectPlayerNode is the only
-- other caller and it is gated on the position having changed.
--
-- Measured on the tree before this change: 29 of the 153 zones in
-- ZoneAdjacencies could not route a teleport-less character to Stormwind.
function PathCalculator:ConnectPlayerNode()
    local nodeData = self.graph.nodes[PLAYER_NODE]
    if not nodeData or not nodeData.mapID then
        return
    end
    self:ConnectNearbyNodes(PLAYER_NODE, nodeData.mapID, nodeData.x, nodeData.y)
end

--- Connect island nodes that lack cross-map edges
-- Portal destinations and dungeon entrances may be the only node on their
-- map after ConnectSameMapNodes, leaving them isolated. This gives each
-- one continent routing edges so Dijkstra can traverse across maps.
function PathCalculator:ConnectIslandNodes()
    local connectedCount = 0

    for nodeName, nodeData in pairs(self.graph.nodes) do
        -- Skip player node and well-connected city/hub nodes
        if nodeName ~= PLAYER_NODE
            and nodeData.mapID
            and nodeData.nodeType ~= "city"
            and nodeData.nodeType ~= "hub"
        then
            -- Check if this node is connected to the broader graph:
            -- either has an edge to a different map, or to a city/hub node
            -- (which have portal edges to other maps)
            local isConnected = false
            local edges = self.graph.edges[nodeName]
            if edges then
                for destName, _ in pairs(edges) do
                    local destData = self.graph.nodes[destName]
                    if destData then
                        if destData.mapID ~= nodeData.mapID then
                            isConnected = true
                            break
                        end
                        if destData.nodeType == "city" or destData.nodeType == "hub" then
                            isConnected = true
                            break
                        end
                    end
                end
            end

            if not isConnected then
                self:ConnectViaContinentRouting(
                    nodeName, nodeData.mapID,
                    nodeData.x or DEFAULT_COORDINATE,
                    nodeData.y or DEFAULT_COORDINATE
                )
                connectedCount = connectedCount + 1
            end
        end
    end

    QR:Debug(string_format("ConnectIslandNodes: connected %d isolated nodes", connectedCount))
end

--- Build human-readable steps from path and edges
-- @param path table Array of node names
-- @param edges table Array of edge data
-- @return table Array of step descriptions
function PathCalculator:BuildSteps(path, edges)
    local steps = {}

    for i = 1, #path - 1 do
        local fromNode = path[i]
        local toNode = path[i + 1]
        local edge = edges[i]

        local step = {
            from = fromNode,
            to = toNode,
            time = edge.weight,
            type = edge.edgeType,
            action = "",
        }

        -- Get source node mapID for route progress tracking
        local fromNodeData = self.graph and self.graph.nodes and self.graph.nodes[fromNode]
        if fromNodeData then
            step.fromMapID = fromNodeData.mapID
        end

        -- Get destination node coordinates for Nav button
        local toNodeData = self.graph and self.graph.nodes and self.graph.nodes[toNode]
        if toNodeData then
            step.destMapID = toNodeData.mapID
            step.destX = toNodeData.x or 0.5
            step.destY = toNodeData.y or 0.5
        end

        -- Also get from edge data if available
        if edge.data then
            if edge.data.toMapID then
                step.destMapID = step.destMapID or edge.data.toMapID
            end
            if edge.data.toX then
                step.destX = edge.data.toX
            end
            if edge.data.toY then
                step.destY = edge.data.toY
            end
        end

        -- Get localized display names for source and destination nodes
        -- Uses C_Map API to resolve zone and continent names for the player's locale
        local localizedToNode = GetLocalizedNodeDisplayName(toNode, toNodeData and toNodeData.mapID)
        step.localizedTo = localizedToNode
        local localizedFromNode = GetLocalizedNodeDisplayName(fromNode, fromNodeData and fromNodeData.mapID)
        step.localizedFrom = localizedFromNode

        -- Build action description based on edge type
        local L = QR.L
        if edge.edgeType == "teleport" then
            local teleportData = edge.data.teleportData
            if teleportData then
                step.action = string_format(L["ACTION_USE_TELEPORT"],
                    teleportData.name or "teleport",
                    localizedToNode
                )
                step.teleportID = edge.data.teleportID
                step.sourceType = edge.data.sourceType
                -- Get coordinates from teleport data if available
                if teleportData.mapID then
                    step.destMapID = teleportData.mapID
                end
                if teleportData.x then
                    step.destX = teleportData.x
                end
                if teleportData.y then
                    step.destY = teleportData.y
                end
            else
                step.action = string_format(L["STEP_TELEPORT_TO"], localizedToNode)
            end
        elseif edge.edgeType == "portal" then
            step.action = string_format(L["STEP_TAKE_PORTAL"], localizedToNode)
        elseif edge.edgeType == "walk" or edge.edgeType == "travel" then
            -- Walk/travel step: localized node name already includes disambiguation
            step.action = string_format(L["STEP_GO_TO"], localizedToNode)
        elseif edge.edgeType == "boat" then
            step.action = string_format(L["STEP_TAKE_BOAT"], localizedToNode)
        elseif edge.edgeType == "zeppelin" then
            step.action = string_format(L["STEP_TAKE_ZEPPELIN"], localizedToNode)
        elseif edge.edgeType == "tram" then
            step.action = string_format(L["STEP_TAKE_TRAM"], localizedToNode)
        else
            step.action = string_format(L["STEP_GO_TO"], localizedToNode)
        end

        -- Navigation coordinates: where the player needs to physically walk
        -- For portal/transport steps, navigate to the entrance (from node)
        -- For walk/travel/teleport steps, navigate to the destination (to node)
        step.navMapID = step.destMapID
        step.navX = step.destX
        step.navY = step.destY
        step.navTitle = toNode

        if edge.edgeType == "portal" or edge.edgeType == "boat"
            or edge.edgeType == "zeppelin" or edge.edgeType == "tram" then
            if fromNodeData then
                step.navMapID = fromNodeData.mapID
                step.navX = fromNodeData.x or 0.5
                step.navY = fromNodeData.y or 0.5
                step.navTitle = step.action
            end
        end

        table_insert(steps, step)
    end

    return steps
end

--- Collapse consecutive walk/travel steps into a single step
-- Merges "Walk to A" + "Walk to B" into "Walk to B" with combined time
-- @param steps table Array of step objects from BuildSteps
-- @return table Collapsed steps array
function PathCalculator:CollapseConsecutiveSteps(steps)
    if not steps or #steps <= 1 then return steps end

    local collapsed = {}
    local i = 1
    while i <= #steps do
        local step = steps[i]
        -- Check if this is a walk/travel step that can be merged
        if step.type == "walk" or step.type == "travel" then
            -- Look ahead for consecutive walk/travel steps
            local combinedTime = step.time
            local lastStep = step
            local mergedCount = 0
            while i + 1 <= #steps and (steps[i + 1].type == "walk" or steps[i + 1].type == "travel") do
                i = i + 1
                combinedTime = combinedTime + steps[i].time
                lastStep = steps[i]
                mergedCount = mergedCount + 1
            end
            if mergedCount > 0 then
                -- Create merged step using the final destination
                local mergedStep = {}
                for k, v in pairs(lastStep) do mergedStep[k] = v end
                mergedStep.time = combinedTime
                mergedStep.from = step.from
                mergedStep.collapsed = true
                mergedStep.collapsedCount = mergedCount + 1
                table_insert(collapsed, mergedStep)
            else
                table_insert(collapsed, step)
            end
        else
            table_insert(collapsed, step)
        end
        i = i + 1
    end
    return collapsed
end

--- Absorb walk/travel steps that follow a transport step to the same map.
-- "Teleport to Stormwind" + "Go to Stormwind" becomes just "Teleport to Stormwind"
-- with the walk time added and destination coordinates updated.
-- @param steps table Array of step objects
-- @return table Steps with redundant walk steps absorbed
function PathCalculator:AbsorbRedundantWalkSteps(steps)
    if not steps or #steps <= 1 then return steps end

    local result = {}
    local i = 1
    while i <= #steps do
        local step = steps[i]
        local nextStep = steps[i + 1]

        -- Check: transport step followed by walk/travel to the same map
        if nextStep and TRANSPORT_TYPES[step.type]
            and (nextStep.type == "walk" or nextStep.type == "travel")
            and step.destMapID and nextStep.destMapID
            and step.destMapID == nextStep.destMapID then
            -- Absorb the walk into the transport step
            local merged = {}
            for k, v in pairs(step) do merged[k] = v end
            merged.time = (step.time or 0) + (nextStep.time or 0)
            -- Use the walk step's final destination but keep transport's nav coords
            merged.destX = nextStep.destX or step.destX
            merged.destY = nextStep.destY or step.destY
            merged.to = nextStep.to or step.to
            merged.localizedTo = nextStep.localizedTo or step.localizedTo
            -- Keep the transport step's nav coords (portal entrance), not the walk destination
            merged.navX = step.navX or nextStep.navX or nextStep.destX
            merged.navY = step.navY or nextStep.navY or nextStep.destY
            merged.navTitle = step.navTitle or nextStep.navTitle
            table_insert(result, merged)
            i = i + 2  -- skip the absorbed walk step
        else
            table_insert(result, step)
            i = i + 1
        end
    end
    return result
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

--- Called when player inventory changes
-- Marks graph as dirty for rebuild
function PathCalculator:OnInventoryChanged()
    self.graphDirty = true

    QR:Debug("Inventory changed, graph marked for rebuild")
end

-------------------------------------------------------------------------------
-- Debug Methods
-------------------------------------------------------------------------------

--- Print the current graph structure
function PathCalculator:PrintGraph()
    if not self.graph then
        print("|cFF00FF00QuickRoute|r: No graph built yet")
        return
    end

    self.graph:Print()
end

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

SLASH_QRPATH1 = "/qrpath"
SlashCmdList["QRPATH"] = function(msg)
    -- Parse arguments: mapID x y
    local args = {}
    for arg in string.gmatch(msg, "%S+") do
        table_insert(args, arg)
    end

    if #args < 3 then
        print("|cFF00FF00QuickRoute|r: Usage: /qrpath <mapID> <x> <y>")
        print("  Example: /qrpath 84 0.5 0.5")
        return
    end

    local destMapID = tonumber(args[1])
    local destX = tonumber(args[2])
    local destY = tonumber(args[3])

    if not destMapID or not destX or not destY then
        print("|cFFFF0000QuickRoute|r: Invalid arguments. Use numbers for mapID, x, and y")
        return
    end

    -- Validate mapID is a positive integer
    if destMapID <= 0 or destMapID ~= math_floor(destMapID) then
        QR:Print("|cFFFF0000Invalid map ID|r")
        return
    end

    -- Clamp coordinates to valid range
    destX = math_max(0, math_min(1, destX))
    destY = math_max(0, math_min(1, destY))

    print(string_format("|cFF00FF00QuickRoute|r: Calculating path to map %d (%.2f, %.2f)...",
        destMapID, destX, destY))

    local result = PathCalculator:CalculatePath(destMapID, destX, destY)

    if not result then
        print("|cFFFF0000QuickRoute|r: No path found to destination")
        return
    end

    print("----------------------------------------")
    print(string_format("|cFFFFFF00Total time:|r %s",
        QR.CooldownTracker:FormatTime(result.totalTime)))
    print("----------------------------------------")
    print("|cFFFFFF00Steps:|r")

    for i, step in ipairs(result.steps) do
        local timeStr = QR.CooldownTracker:FormatTime(step.time)
        print(string_format("  %d. %s |cFFAAAAAA(%s)|r", i, step.action, timeStr))
    end

    print("----------------------------------------")
end

-- Debug command to print graph
SLASH_QRGRAPH1 = "/qrgraph"
SlashCmdList["QRGRAPH"] = function(msg)
    -- Ensure graph is built
    if not PathCalculator.graph then
        PathCalculator:BuildGraph()
    end
    PathCalculator:PrintGraph()
end

-- Debug command to check zone adjacency data
SLASH_QRZONE1 = "/qrzone"
SlashCmdList["QRZONE"] = function(msg)
    local mapID = tonumber(msg)
    if not mapID then
        -- Use current map if no argument
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    -- Clamp to valid WoW map ID range
    if mapID and (mapID < 1 or mapID > 9999 or mapID ~= math_floor(mapID)) then
        print("|cFFFF0000QuickRoute|r: Invalid mapID: " .. tostring(msg))
        return
    end

    print(string_format("|cFF00FF00QuickRoute|r: Zone Adjacency Debug for MapID %d", mapID or 0))
    print("----------------------------------------")

    -- Check if ZoneAdjacency data is loaded
    if not QR.Continents then
        print("|cFFFF0000ERROR: QR.Continents not loaded!|r")
        return
    end

    if not QR.ZoneToContinent then
        print("|cFFFF0000ERROR: QR.ZoneToContinent not loaded!|r")
        return
    end

    -- Get continent for zone
    local continent = QR.GetContinentForZone and QR.GetContinentForZone(mapID)
    print(string_format("Continent: %s", tostring(continent)))

    if continent and QR.Continents[continent] then
        local contData = QR.Continents[continent]
        print(string_format("Continent Name: %s", contData.name))
        print(string_format("Hub MapID: %d", contData.hub or 0))
    end

    -- Get adjacent zones
    local adjacent = QR.GetAdjacentZones and QR.GetAdjacentZones(mapID) or {}
    print(string_format("Adjacent Zones: %d", #adjacent))
    for _, adj in ipairs(adjacent) do
        print(string_format("  -> MapID %d (%ds travel)", adj.zone, adj.travelTime))
    end

    -- Check graph nodes on same continent
    if PathCalculator.graph then
        local sameContinent = {}
        for nodeName, nodeData in pairs(PathCalculator.graph.nodes) do
            if nodeData.mapID then
                local nodeContinent = QR.GetContinentForZone and QR.GetContinentForZone(nodeData.mapID)
                if nodeContinent == continent then
                    table_insert(sameContinent, {name = nodeName, mapID = nodeData.mapID})
                end
            end
        end
        print(string_format("Graph nodes on same continent: %d", #sameContinent))
        for _, node in ipairs(sameContinent) do
            print(string_format("  - %s (map %d)", node.name, node.mapID))
        end
    else
        print("Graph not built yet")
    end

    print("----------------------------------------")
end

-- Debug command to test path calculation with verbose output
SLASH_QRDEBUGPATH1 = "/qrdebugpath"
SlashCmdList["QRDEBUGPATH"] = function(msg)
    local oldDebug = QR.debugMode
    QR.debugMode = true

    -- Wrap in pcall to ensure debugMode is always restored
    local success, errMsg = pcall(function()
        -- Get current waypoint
        local waypoint = QR.WaypointIntegration:GetActiveWaypoint()
        if not waypoint then
            print("|cFFFF0000QuickRoute|r: No waypoint set")
            return
        end

        print(string_format("|cFF00FF00QuickRoute|r: Debug path to %s (map %d)",
            waypoint.title or "waypoint", waypoint.mapID))

        -- Force rebuild graph
        PathCalculator.graphDirty = true
        local result = PathCalculator:CalculatePath(waypoint.mapID, waypoint.x, waypoint.y)

        if result then
            print("|cFF00FF00Path found!|r")
            for i, step in ipairs(result.steps) do
                print(string_format("  %d. %s", i, step.action))
            end
        else
            print("|cFFFF0000No path found|r")
        end
    end)

    -- Always restore debug mode
    QR.debugMode = oldDebug

    if not success then
        print("|cFFFF0000QuickRoute ERROR:|r " .. tostring(errMsg))
    end
end

