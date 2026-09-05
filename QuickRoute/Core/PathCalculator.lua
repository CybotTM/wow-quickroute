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
    zeppelin = true, tram = true, jump = true,
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

local function IsFiniteNumber(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value
        and value > -math_huge and value < math_huge
end

local function IsCoordinate(value)
    return IsFiniteNumber(value) and value >= 0 and value <= 1
end

local function IsMapID(value)
    return IsFiniteNumber(value) and value > 0 and value == math_floor(value)
end

--- Resolve a parent-map click without changing the location it represents.
-- Map IDs and normalized coordinates form one value; never relabel coordinates.
-- Returns the original point if the client cannot project it, nil for bad input.
function PathCalculator:ResolveMapPosition(mapID, x, y)
    if not IsMapID(mapID) or not IsCoordinate(x) or not IsCoordinate(y) then return nil end
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfoAtPosition
        and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then
        return mapID, x, y
    end
    local ok, childMapID, childX, childY = pcall(function()
        local info = C_Map.GetMapInfo(mapID)
        if not info or not info.mapType then return end
        local targetMapID
        if info.mapType <= 2 then
            local child = C_Map.GetMapInfoAtPosition(mapID, x, y)
            targetMapID = child and child.mapID
        elseif info.mapType == 5 and IsMapID(info.parentMapID) then
            -- Outdoor microzones have their own normalized coordinates. Use
            -- the client transform (e.g. The Den -> Harandar), never relabel.
            local parent = C_Map.GetMapInfo(info.parentMapID)
            if parent and parent.mapType == 3 then targetMapID = info.parentMapID end
        end
        if not IsMapID(targetMapID) or targetMapID == mapID then return end
        local worldID, worldPos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not worldID or not worldPos then return end
        local resolvedID, pos = C_Map.GetMapPosFromWorldPos(worldID, worldPos, targetMapID)
        if resolvedID ~= targetMapID or not pos then return end
        local px, py = pos:GetXY()
        if IsCoordinate(px) and IsCoordinate(py) then return resolvedID, px, py end
    end)
    if ok and childMapID then return childMapID, childX, childY end
    return mapID, x, y
end

--- Movement capability comes from measured/usable character abilities.
local function GetCachedIsFlyable()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if QR.TravelTime.CanFly then return QR.TravelTime:CanFly(mapID) end
    return false
end

local flyableCacheFrame = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "TAXI_NODE_STATUS_CHANGED", "TAXIMAP_OPENED",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_GAINED" }) do
    flyableCacheFrame:RegisterEvent(event)
end
flyableCacheFrame:SetScript("OnEvent", function()
    if QR.TravelTime.ClearMovementCache then QR.TravelTime:ClearMovementCache() end
    PathCalculator.graphDirty = true
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
    self.zoneTravelGraph = nil
    self.zoneTravelCache = nil
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
        self:AddConditionalConnections()
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

    -- Flight last, so every edge it might replace already exists. Run earlier,
    -- AddFlightEdges wrote into empty slots and its "only if it beats what is
    -- there" guard had nothing to compare against: ConnectIslandNodes then saw
    -- the node as connected and skipped the continent edge it would otherwise
    -- have written. The result was still faster at the shipped FLIGHT_SPEED,
    -- but only by margin -- recalibrating the speed below ~17 yd/s made flight
    -- routes slower than the ones they displaced. Now the guard decides it.
    success, err = pcall(function()
        self:AddFlightEdges()
    end)
    if not success then
        QR:Error("AddFlightEdges failed: " .. tostring(err))
        buildSuccess = false
        buildError = buildError or err
    end

    -- Only mark clean if all steps succeeded
    self.graphDirty = not buildSuccess
    -- Remembered so CalculatePath can notice a faction change. Recorded even
    -- on a failed build: a half-built graph belongs to the faction it was
    -- attempted for.
    self.graphFaction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()

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

--- Add sourced access-gated portals and explicit NPC phase changes.
function PathCalculator:AddConditionalConnections()
    local transitions = QR.TravelTransitions
    if not transitions then return end
    for id, data in pairs(transitions.nodes) do
        local node = {}
        for key, value in pairs(data) do node[key] = value end
        local mapID, x, y = self:ResolveMapPosition(node.mapID, node.x, node.y)
        if mapID then node.mapID, node.x, node.y = mapID, x, y end
        node.nodeType = "transition"
        self.graph:AddNode("Travel:" .. id, node)
    end
    for _, edge in ipairs(transitions.edges) do
        local from, to = "Travel:" .. edge.from, "Travel:" .. edge.to
        local seconds = edge.cost or (edge.method == "phaseswitch" and 10
            or edge.method == "flight" and 120 or QR.TravelTime:GetPortalTime())
        if edge.method == "portal" and not edge.noLoadingScreen then seconds = seconds + (QR.db and QR.db.loadingScreenTime or 0) end
        if edge.method == "flight" and edge.distanceYards then
            seconds = QR.TravelTime.FLIGHT_OVERHEAD + edge.distanceYards / QR.TravelTime.FLIGHT_SPEED
        end
        local function add(source, target)
            local targetData, sourceData = self.graph.nodes[target], self.graph.nodes[source]
            local requirements = edge.requirements
            if edge.method == "flight" then
                requirements = {}
                for key, value in pairs(edge.requirements or {}) do requirements[key] = value end
                requirements.flightDiscovery = { sourceData, targetData }
            end
            if edge.method ~= "flight" or (QR.TravelRequirements and QR.TravelRequirements:Check(requirements, nil, true) == true) then
                self.graph:AddEdgeOption(source, target, seconds, edge.method, {
                    requirements = requirements,
                    fromMapID = sourceData.mapID, toMapID = targetData.mapID,
                    flightPoint = edge.method == "flight" and { mapID=sourceData.mapID, x=sourceData.x, y=sourceData.y } or nil,
                    estimatedTime = edge.distanceYards ~= nil,
                    instructionKey = edge.instructionKey,
                    phaseMapID = edge.method == "phaseswitch" and (targetData.phaseCheckMapID or targetData.mapID) or nil,
                    phaseArtID = edge.method == "phaseswitch" and targetData.mapArtID or nil,
                })
            end
        end
        add(from, to)
        if not edge.oneway then add(to, from) end
    end
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
                    if nodeA.name == PLAYER_NODE or nodeB.name == PLAYER_NODE
                        or (existingEdge and existingEdge.edgeType == "flight" and existingEdge.data and existingEdge.data.requirements)
                        or (reverseEdge and reverseEdge.edgeType == "flight" and reverseEdge.data and reverseEdge.data.requirements)
                        or ((not existingEdge or existingEdge.edgeType == "travel")
                        and (not reverseEdge or reverseEdge.edgeType == "travel")) then
                        -- Calculate walking time
                        local walkTime = SafeEstimateWalkingTime(
                            nodeA.data.x or 0.5, nodeA.data.y or 0.5,
                            nodeB.data.x or 0.5, nodeB.data.y or 0.5,
                            canFly, mapID
                        )

                        -- Add bidirectional walking edge
                        local edgeData = {
                            autoConnected = true,
                            mapID = mapID,
                        }
                        self.graph:AddEdgeOption(nodeA.name, nodeB.name, walkTime, "walk", edgeData)
                        self.graph:AddEdgeOption(nodeB.name, nodeA.name, walkTime, "walk", edgeData)
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
            if not QR.TravelRequirements or not QR.TravelRequirements:HasReplacement(hubData.mapID, portal.mapID, "portal") then
                self.graph:AddEdge(hubName, destName, travelTime, "portal", { portalData = portal })
            end
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
        local replaced = QR.TravelRequirements and QR.TravelRequirements:HasReplacement(
            transport.from.mapID, transport.to.mapID, transport.type or "portal")
        if not replaced then
            self.graph:AddEdge(fromName, toName, travelTime, transport.type, { transportData = transport })
        end

        -- Preserve each independent direction/method. A ship remains available
        -- even if a sourced quest-gated portal connects the same pair of maps.
        local reverseReplaced = QR.TravelRequirements and QR.TravelRequirements:HasReplacement(
            transport.to.mapID, transport.from.mapID, transport.type or "portal")
        if transport.bidirectional and not reverseReplaced then
            self.graph:AddEdge(toName, fromName, travelTime, transport.type, { transportData = transport })
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
        local destinations
        if QR.TeleportDestinations then
            destinations = QR.TeleportDestinations:GetDestinations(teleportID, teleport)
        else
            local data = teleport.data
            if QR.Hearthstone then data = QR.Hearthstone:ResolveTeleport(data) end
            destinations = data and { data } or {}
        end
        for _, data in ipairs(destinations) do
            local usable = not (issecretvalue and issecretvalue(teleport.isUsable)) and teleport.isUsable ~= false
            local eligible = QR.PlayerInfo:CanUseTeleport(data)
            if data and data.mapID and not data.isDynamic and not data.isRandom and usable and eligible then
                local destName = data.nodeKey or data.destination or data.name

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
                    local travelTime = QR.TravelTime:GetEffectiveTime(teleportID, data, includeCooldown, teleport.sourceType)
                    -- Add loading screen time cost for teleports
                    local loadingTime = QR.db and QR.db.loadingScreenTime or 0
                    travelTime = travelTime + loadingTime

                    self.graph:AddEdgeOption(PLAYER_NODE, destName, travelTime, "teleport", {
                        teleportID = teleportID,
                        teleportData = data,
                        sourceType = teleport.sourceType,
                        requirements = data.requirements,
                    })
                end
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
    if not outgoing then return end
    local includeCooldown = QR.db and QR.db.considerCooldowns
    local loadingTime = QR.db and QR.db.loadingScreenTime or 0
    for target, edge in pairs(outgoing) do
        local options = {}
        for _, option in ipairs(edge.alternatives or { edge }) do
            local data = option.data
            if option.edgeType == "teleport" and data and data.teleportID and data.teleportData then
                local seconds = QR.TravelTime:GetEffectiveTime(
                    data.teleportID, data.teleportData, includeCooldown, data.sourceType) + loadingTime
                if IsFiniteNumber(seconds) then
                    options[#options + 1] = {
                        weight = math_max(0.001, seconds), edgeType = "teleport", data = data,
                    }
                end
            else
                options[#options + 1] = option
            end
        end
        self.graph:SetEdgeOptions(PLAYER_NODE, target, options)
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
    destMapID, destX, destY = self:ResolveMapPosition(destMapID, destX, destY)
    if not destMapID then return nil end
    if type(destTitle) ~= "string" then destTitle = nil end
    -- Rebuild graph if needed. Faction is part of "needed": AddZoneNodes and
    -- AddFlightEdges both read it at build time, so a graph built before a
    -- pandaren picked a side describes the wrong character. Nothing else can
    -- change faction mid-session, so this comparison is free the rest of the
    -- time.
    local faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    if self.graph and self.graphFaction and faction and self.graphFaction ~= faction then
        QR:Debug("PathCalculator: faction changed from " .. tostring(self.graphFaction)
            .. " to " .. tostring(faction) .. ", rebuilding the graph")
        self.graphDirty = true
    end
    if self.graphDirty or not self.graph then
        self:BuildGraph()
        if self.graphDirty or not self.graph then return nil end
    end

    -- Update player location node
    if self:UpdatePlayerLocation() == false then return nil end

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
    local baseName, suffix = destName, 1
    while self.graph.nodes[destName] do
        suffix = suffix + 1
        destName = baseName .. " #" .. suffix
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
    local path, totalTime, pathEdges
    if QR.TravelRequirements then
        path, totalTime, pathEdges = QR.TravelRequirements:FindPath(self.graph, PLAYER_NODE, destName)
    else
        path, totalTime, pathEdges = self.graph:FindShortestPath(PLAYER_NODE, destName)
    end

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

--- Create a reusable calculator with its own graph and position caches.
-- Transport topology is copied once; current access/phase requirements are
-- still evaluated on every query. Exclusions are fixed for this context.
function PathCalculator:CreateRouteContext(options)
    -- Only methods may fall through. A nil cache/index on the private object
    -- must never expose mutable state from the live PathCalculator singleton.
    local calculator = setmetatable({ graphDirty = false }, { __index = function(_, key)
        local value = PathCalculator[key]
        if type(value) == "function" then return value end
    end })
    local discoveryOverride = self.knownFlightZonesOverride
    if type(discoveryOverride) == "table" then
        calculator.knownFlightZonesOverride = {}
        for mapID, known in pairs(discoveryOverride) do calculator.knownFlightZonesOverride[mapID] = known end
    elseif type(discoveryOverride) == "boolean" then
        calculator.knownFlightZonesOverride = discoveryOverride
    end
    local excludeCooldowns = options and options.excludeCooldowns == true
    local baselineNodes = {}
    local originMapID, originX, originY
    local function prepare(instance, filterTeleports)
        local graph = instance.graph
        if not graph then return end
        if filterTeleports and excludeCooldowns then
            for from, outgoing in pairs(graph.edges) do
                for to, selected in pairs(outgoing) do
                    local retained = {}
                    for _, edge in ipairs(selected.alternatives or { selected }) do
                        if edge.edgeType ~= "teleport" then retained[#retained+1] = edge end
                    end
                    graph:SetEdgeOptions(from, to, retained)
                end
            end
        end
        baselineNodes = {}
        for name in pairs(graph.nodes) do baselineNodes[name] = true end
        instance.nodeIndex = nil
    end
    local base = self.graph
    local faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    if not base or self.graphDirty or (self.graphFaction and faction and self.graphFaction ~= faction) then
        local ok = pcall(PathCalculator.BuildGraph, calculator)
        if not ok or calculator.graphDirty or not calculator.graph then return nil end
        prepare(calculator, true)
    else
        local graph = QR.Graph:New()
        for name, data in pairs(base.nodes) do
            local node = {}
            for key, value in pairs(data) do node[key] = value end
            graph:AddNode(name, node)
        end
        for from, outgoing in pairs(base.edges) do
            for to, selected in pairs(outgoing) do
                local alternatives = {}
                for _, edge in ipairs(selected.alternatives or { selected }) do
                    if not (excludeCooldowns and edge.edgeType == "teleport") then
                        alternatives[#alternatives+1] = edge
                    end
                end
                graph:SetEdgeOptions(from, to, alternatives)
            end
        end
        calculator.graph, calculator.graphDirty = graph, false
        calculator.graphFaction = faction
        calculator.zoneTravelGraph, calculator.zoneTravelCache = nil, nil
        prepare(calculator, false)
    end
    -- CalculatePath can rebuild after a faction change. Such a rebuild remains
    -- private and must preserve this context's personal-teleport exclusion.
    calculator.BuildGraph = function(instance)
        local graph = PathCalculator.BuildGraph(instance)
        prepare(instance, true)
        return graph
    end
    calculator.UpdatePlayerLocation = function(instance)
        if not originMapID then return false end
        local graph = instance.graph
        local node = graph.nodes[PLAYER_NODE]
        if not node then
            graph:AddNode(PLAYER_NODE, { nodeType = "player" })
            node = graph.nodes[PLAYER_NODE]
            baselineNodes[PLAYER_NODE] = true
        end
        node.mapID, node.x, node.y = originMapID, originX, originY
        instance:ReconnectPlayerNode(originMapID, originX, originY)
        return true
    end
    calculator.CalculatePathFrom = function(instance, startMapID, startX, startY, destMapID, destX, destY, queryOptions)
        local mapID, x, y = instance:ResolveMapPosition(startMapID, startX, startY)
        if not mapID then return nil end
        originMapID, originX, originY = mapID, x, y
        local ok, result = pcall(PathCalculator.CalculatePath, instance,
            destMapID, destX, destY, queryOptions and queryOptions.title)
        -- CalculatePath normally removes its destination. Also recover when a
        -- connection/API/search failure interrupts it after that node is added.
        if instance.graph then
            for name in pairs(instance.graph.nodes) do
                if not baselineNodes[name] then instance.graph:RemoveNode(name) end
            end
        end
        if not ok then
            instance.nodeIndex = nil
            QR:Debug("Hypothetical route calculation failed: " .. tostring(result))
            return nil
        end
        return result
    end
    return calculator
end

--- Backward-compatible one-shot query; tours can reuse CreateRouteContext.
function PathCalculator:CalculatePathFrom(startMapID, startX, startY, destMapID, destX, destY, options)
    startMapID, startX, startY = self:ResolveMapPosition(startMapID, startX, startY)
    if not startMapID then return nil end
    local context = self:CreateRouteContext(options)
    if not context then return nil end
    return context:CalculatePathFrom(startMapID, startX, startY, destMapID, destX, destY, options)
end

--- Update player location node with current position
function PathCalculator:UpdatePlayerLocation()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    -- Abort if no valid map (e.g., in instance loading, unmapped area)
    if not mapID then
        QR:Debug("Cannot get player map ID (instance/loading?)")
        return false
    end

    local posOk, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not posOk or not pos then return false end
    local coordOK, x, y = pcall(pos.GetXY, pos)
    if not coordOK or not IsCoordinate(x) or not IsCoordinate(y) then return false end

    local node = self.graph.nodes[PLAYER_NODE]
    if not node then
        self.graphDirty = true
        return false
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
    return true
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
    local function containsTeleport(edge)
        if not edge then return false end
        if edge.edgeType == "teleport" then return true end
        for _, option in ipairs(edge.alternatives or {}) do
            if option.edgeType == "teleport" then return true end
        end
        return false
    end
    return containsTeleport(graph:GetEdge(from, to)) or containsTeleport(graph:GetEdge(to, from))
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
            local retained = {}
            for _, option in ipairs(edge.alternatives or { edge }) do
                if option.edgeType ~= "walk" and option.edgeType ~= "travel" then
                    retained[#retained + 1] = option
                end
            end
            self.graph:SetEdgeOptions(PLAYER_NODE, otherName, retained)
        end
        for _, incoming in pairs(self.graph.edges) do
            local edge = incoming[PLAYER_NODE]
            if edge and (edge.edgeType == "walk" or edge.edgeType == "travel") then
                incoming[PLAYER_NODE] = nil
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
            and (nodeName == PLAYER_NODE or otherName == PLAYER_NODE
                or CanOverwriteWithWalk(self.graph, nodeName, otherName)) then
            -- Calculate walking time between nodes
            local walkTime = SafeEstimateWalkingTime(
                x, y,
                otherData.x, otherData.y,
                canFly, mapID
            )

            -- Add bidirectional walking edge
            local edgeData = {
                distance = QR.TravelTime:CalculateDistance(x, y, otherData.x, otherData.y),
            }
            self.graph:AddEdgeOption(nodeName, otherName, walkTime, "walk", edgeData)
            self.graph:AddEdgeOption(otherName, nodeName, walkTime, "walk", edgeData)
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
    return not existing or existing.edgeType == "travel"
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

--- Connect only through documented zone links. A shared continent is not
-- evidence of a transport: disconnected islands must stay disconnected.
-- Costs are directed and cached per source map for this graph generation.
function PathCalculator:ConnectViaContinentRouting(nodeName, mapID, x, y)
    if not QR.BuildZoneTravelGraph then return end
    if not self.zoneTravelGraph then
        self.zoneTravelGraph = QR.BuildZoneTravelGraph()
        self.zoneTravelCache = {}
    end
    local function costsFrom(sourceMapID)
        local costs = self.zoneTravelCache[sourceMapID]
        if not costs then
            costs = self.zoneTravelGraph:FindDistances(sourceMapID)
            self.zoneTravelCache[sourceMapID] = costs
        end
        return costs
    end
    local forward = costsFrom(mapID)
    for otherName, otherData in pairs(self.graph.nodes) do
        local otherMapID = otherData.mapID
        if otherName ~= nodeName and otherMapID and otherMapID ~= mapID then
            local playerPair = nodeName == PLAYER_NODE or otherName == PLAYER_NODE
            local seconds = forward[otherMapID]
            if seconds and (playerPair or CanOverwriteWithTravel(self.graph, nodeName, otherName)) then
                self.graph:AddEdgeOption(nodeName, otherName, seconds, "travel", {
                    fromMapID = mapID, toMapID = otherMapID,
                    note = "Documented overland zone connections",
                })
            end
            seconds = costsFrom(otherMapID)[mapID]
            if seconds and (playerPair or CanOverwriteWithTravel(self.graph, otherName, nodeName)) then
                self.graph:AddEdgeOption(otherName, nodeName, seconds, "travel", {
                    fromMapID = otherMapID, toMapID = mapID,
                    note = "Documented overland zone connections",
                })
            end
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
            local travelTime = QR.TravelTime:GetEffectiveTime(teleportID, data, includeCooldown, teleport.sourceType)
            travelTime = travelTime + (QR.db and QR.db.loadingScreenTime or 0)

            self.graph:AddEdgeOption(PLAYER_NODE, destName, travelTime, "teleport", {
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

--- The flight point in a zone that THIS player can actually use.
-- Most zones have one flight master per faction and they are not in the same
-- place: The Hinterlands has Aerie Peak in the north-west for the Alliance and
-- Revantusk Village in the south-east for the Horde, and neutral towns like
-- Booty Bay and Gadgetzan have two nodes a few yards apart. Collapsing that to
-- one entry per zone priced 45 of 141 zones from a flight master half the
-- players cannot walk up to.
--
-- Returns nil when the zone has no flight master for this faction, which is a
-- real answer: 17 zones are Alliance-only and 12 are Horde-only.
--
-- Anything that is not one of the two factions -- "Neutral" for a pandaren who
-- has not chosen a side, or any value the client returns that is neither --
-- gets the primary entry, which is what the addon did before this filter
-- existed. The first version tested `not faction` instead, which can never be
-- true because GetFaction falls back to "Alliance"; a neutral character
-- therefore matched no branch and lost 74 of 141 zones and 392 of its 479
-- flight edges. (A neutral character has 479 on main, not the 599 an Alliance
-- one has, because AddZoneNodes withholds the faction capitals from them --
-- so fewer zones carry a graph node in the first place.)
--
-- Note what this branch does NOT cover: a client that has not answered yet.
-- UnitFactionGroup returns nil there and GetFaction turns that into
-- "Alliance", so such a character is filtered as Alliance rather than falling
-- through here. The fallback is for a genuine third value, not for silence.
-- @param uiMapID number
-- @return table|nil
function PathCalculator:FlightPointFor(uiMapID)
    local point = QR.FlightPoints and QR.FlightPoints[uiMapID]
    if not point then
        return nil
    end
    -- The QR.PlayerInfo guard is defence in depth, not covered code: the
    -- module is set at load and no build path reaches here without it, so
    -- dropping it reddens nothing. It is kept because a false faction here
    -- silently filters the whole flight network.
    local faction = QR.PlayerInfo and QR.PlayerInfo:GetFaction()
    if faction ~= "Alliance" and faction ~= "Horde" then
        return point
    end
    if point.faction == "both" or point.faction == faction then
        return point
    end
    local alt = point.alt
    -- alt.faction is always the opposite of the primary's, so reaching here
    -- means this is the player's side. The check is defence in depth against a
    -- future generator that emits a third shape, not covered code: replacing
    -- it with `if alt then` reddens nothing.
    if alt and alt.faction == faction then
        return alt
    end
    return nil
end

--- Which flight points the player has actually discovered.
-- Returns a set keyed by uiMapID, or nil when the client cannot tell us. nil is
-- not the same as empty: empty means "the player has none", nil means "do not
-- model flight at all", and the caller treats them differently. Flying from a
-- flight master you have not discovered is not possible, so guessing here would
-- hand out routes that cannot be walked.
-- @return table|nil Set of uiMapIDs, or nil if the client does not say
function PathCalculator:GetKnownFlightZones()
    if self.knownFlightZonesOverride ~= nil then return self.knownFlightZonesOverride end
    if not C_TaxiMap then return nil end
    -- Unlike GetAllTaxiNodes, this works without an open flight-master session.
    local discovery = C_TaxiMap.GetTaxiNodesForMap
    local query = discovery or C_TaxiMap.GetAllTaxiNodes
    if not query then return nil end
    local known = {}
    for uiMapID in pairs(QR.FlightPoints or {}) do
        local point = self:FlightPointFor(uiMapID)
        local ok, nodes = pcall(query, uiMapID)
        if point and ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                -- FlightPathState: Current=0, Reachable=1, Unreachable=2.
                local available = discovery and node.isUndiscovered == false
                    or (not discovery and (node.state == 0 or node.state == 1))
                local pos = node.position
                -- Generated data does not yet carry taxi node IDs. Match the
                -- exact modeled master by normalized position, never just zone.
                if available and pos and IsCoordinate(pos.x) and IsCoordinate(pos.y)
                    and math.abs(pos.x - point.x) <= 0.001
                    and math.abs(pos.y - point.y) <= 0.001 then
                    known[uiMapID] = true
                    break
                end
            end
        end
    end
    return known
end

--- The graph node a zone's flight edges attach to.
-- NodesOnMap yields whatever pairs() order the node table happens to have, so
-- taking its first element makes the graph depend on hash order: adding an
-- unrelated teleport rehashes the table and re-anchors flight edges on maps
-- that have nothing to do with it. Sorting fixes that.
--
-- The player node is excluded outright. It carries the position the graph was
-- built at, and ReconnectPlayerNode drops only walk and travel edges when the
-- player moves -- a flight edge would survive the move and price a flight from
-- a zone the player has left, which is a route that cannot be taken rather
-- than merely a bad estimate.
--
-- The node that best stands for the zone wins, by nodeType. A dungeon-prefix
-- test was not enough: it left Stormwind and Ironforge anchored on the Deeprun
-- Tram platform, because "Deeprun Tram (...)" sorts before "Stormwind City"
-- and neither is a dungeon. Of the anchored maps only 5 were a city that way;
-- 15 were a transport endpoint and 14 a portal destination.
local FLIGHT_ANCHOR_RANK = {
    city = 1,
    hub = 2,
    destination = 3,
    teleport_dest = 4,
    transport = 5,
}
local FLIGHT_ANCHOR_RANK_DEFAULT = 6   -- dungeons and anything unclassified

function PathCalculator:FlightAnchorForMap(mapID)
    local candidates = {}
    for _, name in ipairs(self:NodesOnMap(mapID)) do
        if name ~= PLAYER_NODE then
            candidates[#candidates + 1] = name
        end
    end
    if #candidates == 0 then
        return nil
    end
    local nodes = self.graph.nodes
    local function rank(name)
        local data = nodes[name]
        local nodeType = data and data.nodeType
        return (nodeType and FLIGHT_ANCHOR_RANK[nodeType]) or FLIGHT_ANCHOR_RANK_DEFAULT
    end
    table_sort(candidates, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then
            return ra < rb
        end
        return a < b
    end)
    return candidates[1]
end

--- True when two flight zones are on the same taxi network.
-- Sharing a world map (continentID) is necessary but not sufficient. World map
-- 530 holds Outland and the Burning Crusade starting zones together, because
-- they share a coordinate space, and they are not one flight network -- without
-- the second test the graph offered 50 flights that cannot be taken, including
-- Azuremyst Isle to Shattrath. The addon's own continent is the second opinion,
-- and it is the same notion the rest of the routing uses.
--
-- Only world maps that actually mix continents are held to the stricter test.
-- Falling back to "allow" whenever a continent is unknown re-opened the bug for
-- any zone QR.ZoneToContinent does not cover -- map 530 has one such zone, and a
-- node placed on it would have flown to Shattrath again. On a world map whose
-- flight zones all belong to one continent there is nothing to disambiguate, so
-- an unknown zone there is allowed through.
--
-- A *_NEUTRAL continent is a wildcard on its own world map: the addon files
-- Mechagon and Tol Dagor under BFA_NEUTRAL while the rest of Kul Tiras is
-- KUL_TIRAS, and those flights do exist. Two named continents on one world map
-- stay separate, which is what keeps Kul Tiras and Zandalar apart.
local mixedWorldMaps

local function IsNeutral(continent)
    return continent ~= nil and continent:find("NEUTRAL", 1, true) ~= nil
end

local function WorldMapMixesContinents(continentID)
    if not mixedWorldMaps then
        mixedWorldMaps = {}
        local seen = {}
        -- Both halves of a zone's entry, not just the primary. The alternate
        -- carries its own world map, and a world map that only an alternate
        -- puts a second continent on would otherwise never be flagged mixed --
        -- SameFlightNetwork would then short-circuit to "same network" and
        -- offer a flight the strict test exists to refuse. No shipped zone has
        -- its two nodes on different world maps, so this changes nothing
        -- today; it is here so the alternate is treated like the entry it is.
        local function note(uiMapID, worldMap)
            local continent = QR.GetContinentForZone and QR.GetContinentForZone(uiMapID)
            if not continent or IsNeutral(continent) then
                return
            end
            local known = seen[worldMap]
            if not known then
                seen[worldMap] = continent
            elseif known ~= continent then
                mixedWorldMaps[worldMap] = true
            end
        end
        for uiMapID, point in pairs(QR.FlightPoints or {}) do
            note(uiMapID, point.continentID)
            if point.alt then
                note(uiMapID, point.alt.continentID)
            end
        end
    end
    return mixedWorldMaps[continentID] or false
end

local function SameFlightNetwork(a, b)
    if a.point.continentID ~= b.point.continentID then
        return false
    end
    if not WorldMapMixesContinents(a.point.continentID) then
        return true
    end
    -- No IsNeutral test here. One was written and was dead code: a world map
    -- carrying a neutral continent alongside a single named one is not
    -- "mixed", so it returns above and never reaches this line. Kul Tiras and
    -- Mechagon are allowed by that early return, not by a wildcard. Removing
    -- the dead clause is also what lets a test see the difference -- with it
    -- present, forcing every world map through the strict path changed
    -- nothing observable.
    local ca = QR.GetContinentForZone and QR.GetContinentForZone(a.mapID)
    local cb = QR.GetContinentForZone and QR.GetContinentForZone(b.mapID)
    return ca ~= nil and cb ~= nil and ca == cb
end

--- Write one direction of a flight edge, if it is allowed and worth writing.
--
-- The teleport guard below is defence in depth, not covered code, and the same
-- kind as the backward half of HasTeleportEdge. Teleport edges are only ever
-- written PLAYER_NODE -> destination, and FlightAnchorForMap excludes the
-- player node, so no flight write can currently meet one: replacing the guard
-- with `true` reddens nothing. It is kept for the case where a future anchor
-- rule does reach a teleport destination from the other side.
-- @return boolean true when an edge was written
function PathCalculator:WriteFlightEdge(from, to, seconds, data)
    if not CanOverwriteWithWalk(self.graph, from, to) then
        return false
    end
    local existing = self.graph:GetEdge(from, to)
    -- Flying is only worth an edge where it beats what is already there;
    -- otherwise it clutters the graph with a slower alternative Dijkstra would
    -- never take, and -- worse -- discards the portal or transport data the
    -- edge it replaced was carrying.
    if existing and seconds >= existing.weight then
        return false
    end
    self.graph:AddEdge(from, to, seconds, "flight", data)
    return true
end

--- Connect the zones the player can fly between.
-- Two flight zones are connected when they share both a world map and the
-- addon's own continent: from any flight master the game auto-routes multi-hop
-- to every point you have discovered on that map, so the per-path topology adds
-- nothing at this granularity.
--
-- The weight is the real distance between the two flight points divided by
-- FLIGHT_SPEED, plus a fixed overhead for talking to the flight master and the
-- takeoff and landing. The distance is exact -- it comes from the client's
-- TaxiNodes positions -- and only the speed is an estimate.
function PathCalculator:AddFlightEdges()
    if not QR.FlightPoints then
        return
    end
    local known = self:GetKnownFlightZones()
    if not known then
        QR:Debug("PathCalculator: no flight point data from the client, skipping flight edges")
        return
    end

    -- Only zones the graph already models AND the player has discovered.
    local usable = {}
    for uiMapID in pairs(QR.FlightPoints) do
        local point = self:FlightPointFor(uiMapID)
        if point and known[uiMapID] and next(self:NodesOnMap(uiMapID)) then
            usable[#usable + 1] = { mapID = uiMapID, point = point }
        end
    end
    -- No sort here on purpose. Iteration order does not reach the result:
    -- WriteFlightEdge writes only when the new weight beats what is already
    -- there, so the cheapest pair wins whichever order the pairs arrive in. A
    -- sort would look like it was load-bearing and no defect injection could
    -- redden it. The order that DOES matter is the anchor choice, which
    -- FlightAnchorForMap sorts.

    local speed = QR.TravelTime.FLIGHT_SPEED
    local overhead = QR.TravelTime.FLIGHT_OVERHEAD
    local added = 0
    for i = 1, #usable do
        for j = i + 1, #usable do
            local a, b = usable[i], usable[j]
            if SameFlightNetwork(a, b) then
                local nodeA = self:FlightAnchorForMap(a.mapID)
                local nodeB = self:FlightAnchorForMap(b.mapID)
                -- nodeA ~= nodeB is defence in depth, not covered code: no
                -- two flight zones currently resolve to the same anchor (0
                -- collisions over all 136), so removing it reddens nothing.
                if nodeA and nodeB and nodeA ~= nodeB then
                    local dx = a.point.worldX - b.point.worldX
                    local dy = a.point.worldY - b.point.worldY
                    local yards = math_sqrt(dx * dx + dy * dy)
                    local seconds = overhead + yards / speed
                    -- Each direction is decided on its own. The graph holds one
                    -- edge per ordered pair and portals and one-way transports
                    -- are written unpaired, so a bidirectional write guarded by
                    -- the forward edge alone replaces a portal nobody looked at:
                    -- Valdrakken -> The Waking Shores went from a 10s portal to
                    -- a 101s flight that way, because the guard checked the
                    -- other direction.
                    --
                    -- Each direction also gets its OWN data. Sharing one table
                    -- made "from" mean the far end on half the edges: 301 of
                    -- 599. That was invisible while nothing read it, and became
                    -- a wrong waypoint the moment something did -- a player in
                    -- Mount Hyjal was sent to Teldrassil to board the flight.
                    -- Only the two map IDs. fromNode and toNode were carried
                    -- here and read by nothing, which is the same shape as the
                    -- unread x/y that let a transposed projection sit in the
                    -- data for four review rounds.
                    if self:WriteFlightEdge(nodeA, nodeB, seconds, {
                        fromMapID = a.mapID, toMapID = b.mapID,
                    }) then
                        added = added + 1
                    end
                    if self:WriteFlightEdge(nodeB, nodeA, seconds, {
                        fromMapID = b.mapID, toMapID = a.mapID,
                    }) then
                        added = added + 1
                    end
                end
            end
        end
    end
    if added > 0 then
        QR:Debug(string_format("PathCalculator: %d flight edge(s)", added))
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

        -- The edge only fills a gap, never overrides. It used to be allowed to
        -- overwrite destX and destY unconditionally while destMapID stayed
        -- with the node, so a step could name one node's map and another
        -- node's position -- the shape that put a flight waypoint in the wrong
        -- zone twice. Nothing writes toX or toY into edge.data (the portal
        -- descriptor that has them is nested under portalData), so those two
        -- branches were reading a field that is never set; they are gone.
        --
        -- The toMapID fallback stays and currently never fires: every edge
        -- carrying it has a to-node, so the node's map always wins. It is here
        -- for an edge whose node is missing, not because it does work today.
        if edge.data and edge.data.toMapID then
            step.destMapID = step.destMapID or edge.data.toMapID
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
                step.teleportData = teleportData
                step.choiceText = teleportData.choiceText
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
        elseif edge.edgeType == "phaseswitch" then
            step.phaseMapID, step.phaseArtID = edge.data.phaseMapID, edge.data.phaseArtID
            step.action = string_format(L["STEP_CHANGE_PHASE_TO"], toNodeData and toNodeData.name or localizedToNode)
        elseif edge.edgeType == "walk" or edge.edgeType == "travel" then
            -- Walk/travel step: localized node name already includes disambiguation
            step.action = string_format(L["STEP_GO_TO"], localizedToNode)
        elseif edge.edgeType == "boat" then
            step.action = string_format(L["STEP_TAKE_BOAT"], localizedToNode)
        elseif edge.edgeType == "zeppelin" then
            step.action = string_format(L["STEP_TAKE_ZEPPELIN"], localizedToNode)
        elseif edge.edgeType == "tram" then
            step.action = string_format(L["STEP_TAKE_TRAM"], localizedToNode)
        elseif edge.edgeType == "flight" then
            -- ACTION_FLY_TO already exists in every locale because the route
            -- list uses it; without this branch a flight leg fell through to
            -- STEP_GO_TO and every text surface but that list read "Go to X".
            step.action = string_format(L["ACTION_FLY_TO"], localizedToNode)
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

        -- A boarded transport starts where you board it, so navigation points
        -- at the from node rather than at the destination.
        if edge.edgeType == "portal" or edge.edgeType == "boat"
            or edge.edgeType == "zeppelin" or edge.edgeType == "tram"
            or edge.edgeType == "flight" or edge.edgeType == "phaseswitch" or edge.edgeType == "jump" then
            if fromNodeData then
                step.navMapID = fromNodeData.mapID
                step.navX = fromNodeData.x or 0.5
                step.navY = fromNodeData.y or 0.5
                step.navTitle = step.action
                step.navLabel = fromNodeData.name
            end
        end

        -- The block above already put the waypoint on the right MAP, via the
        -- from node. Only the position still needs correcting: that node is
        -- whatever FlightAnchorForMap ranked highest on the map, which for the
        -- Badlands is a dungeon entrance 0.48 of the zone from Fuselight.
        -- QR.FlightPoints carries the flight master's own position -- nothing
        -- read it until this block, which is why a transposed x/y went
        -- unnoticed for four review rounds.
        if edge.edgeType == "flight" and edge.data and QR.FlightPoints then
            local master = edge.data.flightPoint or self:FlightPointFor(edge.data.fromMapID)
            if master and master.x and master.y then
                step.navX = master.x
                step.navY = master.y
            end
        end

        if edge.data and edge.data.instructionKey then
            step.instructionKey = edge.data.instructionKey
            step.action = string_format(L[step.instructionKey], localizedToNode)
            step.navTitle = step.action
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
            and step.destMapID == nextStep.destMapID
            and IsCoordinate(step.destX) and IsCoordinate(step.destY)
            and step.destX == nextStep.destX and step.destY == nextStep.destY then
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
