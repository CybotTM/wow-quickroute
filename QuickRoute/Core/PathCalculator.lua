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

--- Safe wrapper for TravelTime:EstimateWalkingTime with fallback
-- @param x1 number Source X coordinate (0-1)
-- @param y1 number Source Y coordinate (0-1)
-- @param x2 number Destination X coordinate (0-1)
-- @param y2 number Destination Y coordinate (0-1)
-- @param canFly boolean Whether player can fly
-- @return number Estimated travel time in seconds
local function SafeEstimateWalkingTime(x1, y1, x2, y2, canFly)
    -- Use TravelTime module directly (pure math, no pcall needed)
    if QR.TravelTime and QR.TravelTime.EstimateWalkingTime then
        return QR.TravelTime:EstimateWalkingTime(x1, y1, x2, y2, canFly)
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
    ["Silvermoon City"] = {mapID = 110, x = 0.5850, y = 0.1920, faction = "Horde"},
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
                            canFly
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

    if self.graph.nodes[PLAYER_NODE] then
        self.graph.nodes[PLAYER_NODE].mapID = mapID
        self.graph.nodes[PLAYER_NODE].x = x
        self.graph.nodes[PLAYER_NODE].y = y
    end
end

--- Connect a node to other nodes on the same map with walking edges
-- Uses zone adjacency data for proper cross-zone connections
-- @param nodeName string The node to connect
-- @param mapID number The map ID
-- @param x number The X coordinate (0-1)
-- @param y number The Y coordinate (0-1)
function PathCalculator:ConnectNearbyNodes(nodeName, mapID, x, y)
    -- Only assume flying for the player's current map; remote maps use ground speed
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local canFly = (mapID == playerMapID) and GetCachedIsFlyable() or false

    -- First pass: connect to nodes on the same map
    for otherName, otherData in pairs(self.graph.nodes) do
        if otherName ~= nodeName and otherData.mapID == mapID then
            -- Calculate walking time between nodes
            local walkTime = SafeEstimateWalkingTime(
                x, y,
                otherData.x, otherData.y,
                canFly
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
function PathCalculator:ConnectViaContinentRouting(nodeName, mapID, x, y)
    local destContinent = QR.GetContinentForZone and QR.GetContinentForZone(mapID)
    local connectedSomething = false

    QR:Debug(string_format("Routing for map %d, continent: %s",
        mapID, tostring(destContinent)))

    -- Strategy 1: Connect to directly adjacent zones
    local adjacentZones = QR.GetAdjacentZones and QR.GetAdjacentZones(mapID) or {}
    for _, adj in ipairs(adjacentZones) do
        -- Find nodes on the adjacent zone
        for otherName, otherData in pairs(self.graph.nodes) do
            if otherName ~= nodeName and otherData.mapID == adj.zone then
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

        if hubMapID then
            -- Find the hub node
            for otherName, otherData in pairs(self.graph.nodes) do
                if otherName ~= nodeName and otherData.mapID == hubMapID then
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

        if bestNode then
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

        for otherName, otherData in pairs(self.graph.nodes) do
            if otherName ~= nodeName and otherData.mapID then
                local otherContinent = QR.GetContinentForZone and QR.GetContinentForZone(otherData.mapID)

                -- Calculate cross-continent time
                local baseTime = CROSS_CONTINENT_TIME
                if destContinent and otherContinent and QR.GetCrossContinentTravel then
                    baseTime = QR.GetCrossContinentTravel(otherContinent, destContinent)
                end

                -- Connect to hub/city nodes on other continents (let Dijkstra optimize)
                -- Also connect to the single best non-hub as fallback
                if otherData.nodeType == "hub" or otherData.nodeType == "city" then
                    local hubTime = baseTime - 60  -- 1 minute bonus for hubs
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

        -- Fallback: if no hub/city nodes found, connect to single best node
        if connectCount == 0 then
            local bestNode, bestTime = nil, math_huge
            for otherName, otherData in pairs(self.graph.nodes) do
                if otherName ~= nodeName and otherData.mapID then
                    local baseTime = CROSS_CONTINENT_TIME
                    if baseTime < bestTime then
                        bestTime = baseTime
                        bestNode = otherName
                    end
                end
            end
            if bestNode then
                local bestData = self.graph.nodes[bestNode]
                local otherContinent = QR.GetContinentForZone and QR.GetContinentForZone(bestData.mapID)
                self.graph:AddBidirectionalEdge(nodeName, bestNode, bestTime, "travel", {
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

        -- Get localized display name for destination node
        -- Uses C_Map API to resolve zone and continent names for the player's locale
        local localizedToNode = GetLocalizedNodeDisplayName(toNode, toNodeData and toNodeData.mapID)

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

