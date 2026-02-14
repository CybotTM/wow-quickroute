-- WaypointIntegration.lua
-- Integrates with TomTom and native WoW waypoint systems
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, type, tostring, pcall = pairs, type, tostring, pcall
local ipairs = ipairs
local string_format = string.format
local table_insert, table_concat = table.insert, table.concat
local CreateFrame = CreateFrame
local GetTime = GetTime
local wipe = wipe

-------------------------------------------------------------------------------
-- WaypointIntegration Module
-------------------------------------------------------------------------------
QR.WaypointIntegration = {}

local WaypointIntegration = QR.WaypointIntegration

-- Module-scope source definitions (initialized after methods are defined)
local waypointSourceDefs
local activeWaypointSources

-- Event frame for waypoint events
local eventFrame = nil

-- Quest coordinate cache to avoid repeated expensive zone scans
local questCoordCache = {} -- { [questID] = { mapID, x, y, time } or { time = t } for "not found" }
local QUEST_COORD_CACHE_TTL = 30 -- seconds

-------------------------------------------------------------------------------
-- Waypoint Source Detection
-------------------------------------------------------------------------------

--- Check if TomTom addon is available
-- @return boolean True if TomTom is loaded
function WaypointIntegration:HasTomTom()
    return TomTom ~= nil
end

--- Get TomTom's current waypoint if available
-- @return table|nil {mapID, x, y, title} or nil if no waypoint
function WaypointIntegration:GetTomTomWaypoint()
    if not self:HasTomTom() then
        return nil
    end

    local waypoint = nil

    -- Method 1: GetClosestWaypoint (older TomTom versions)
    if TomTom.GetClosestWaypoint then
        local uid = TomTom:GetClosestWaypoint()
        if uid then
            if type(uid) == "table" then
                waypoint = uid
            elseif TomTom.waypoints and TomTom.waypoints[uid] then
                waypoint = TomTom.waypoints[uid]
            end
        end
    end

    -- Method 2: GetCrazyArrowTarget (newer TomTom versions)
    if not waypoint and TomTom.GetCrazyArrow then
        local arrow = TomTom:GetCrazyArrow()
        if arrow and arrow.waypoint then
            waypoint = arrow.waypoint
        end
    end

    -- Method 3: Direct waydb access
    if not waypoint and TomTom.waydb then
        -- Get current map
        local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if currentMapID and TomTom.waydb[currentMapID] then
            -- Get first waypoint on current map
            for _, wp in pairs(TomTom.waydb[currentMapID]) do
                waypoint = wp
                break
            end
        end
    end

    -- Method 4: Check profile waypoints
    if not waypoint and TomTom.db and TomTom.db.profile and TomTom.db.profile.waypoints then
        local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if currentMapID then
            local mapWaypoints = TomTom.db.profile.waypoints[currentMapID]
            if mapWaypoints then
                for _, wp in pairs(mapWaypoints) do
                    waypoint = wp
                    break
                end
            end
        end
    end

    if not waypoint then
        return nil
    end

    -- Extract waypoint info - TomTom stores coordinates as 0-1 range
    local mapID = waypoint.mapID or waypoint.m or waypoint[1]
    local x = waypoint.x or waypoint[2]
    local y = waypoint.y or waypoint[3]
    local title = waypoint.title or waypoint.desc or waypoint[4] or QR.L["WAYPOINT_TOMTOM"]

    -- Type-check TomTom waypoint fields to prevent bad data propagation
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end

    return {
        mapID = mapID,
        x = x,
        y = y,
        title = type(title) == "string" and title or QR.L["WAYPOINT_TOMTOM"],
    }
end

--- Get waypoint from super-tracked quest
-- Uses C_SuperTrack and C_QuestLog APIs
-- @return table|nil {mapID, x, y, title} or nil if no tracked quest waypoint
function WaypointIntegration:GetSuperTrackedWaypoint()
    -- Get the super-tracked quest ID (with API availability check)
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then
        return nil
    end
    local questID = C_SuperTrack.GetSuperTrackedQuestID()
    if not questID or questID == 0 then
        return nil
    end

    local questTitle = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or QR.L["SOURCE_QUEST"]

    -- Check quest coordinate cache
    local now = GetTime()
    local cached = questCoordCache[questID]
    if cached and (now - cached.time) < QUEST_COORD_CACHE_TTL then
        if cached.mapID then
            QR:Debug(string_format("Quest %d: Using cached coords map %d", questID, cached.mapID))
            return {
                mapID = cached.mapID,
                x = cached.x,
                y = cached.y,
                title = questTitle,
            }
        else
            -- Cached "not found" result
            return nil
        end
    end

    -- Build transit hub set from PortalHubs (cities that are routing intermediaries)
    local transitHubMapIDs = {}
    if QR.PortalHubs then
        for _, hubData in pairs(QR.PortalHubs) do
            if hubData and hubData.mapID then
                transitHubMapIDs[hubData.mapID] = true
            end
        end
    end
    local transitFallback = nil

    -- Check for intermediate waypoint text (e.g. "Go to Valdrakken")
    -- When GetNextWaypointText returns non-nil, the waypoint from GetNextWaypoint
    -- is an INTERMEDIATE navigation step (like a portal room), NOT the final objective.
    -- In that case, we save it as fallback and search for the actual destination.
    local isIntermediateWaypoint = false
    if C_QuestLog.GetNextWaypointText then
        local wpText = C_QuestLog.GetNextWaypointText(questID)
        if wpText and wpText ~= "" then
            questTitle = questTitle .. " - " .. wpText
            isIntermediateWaypoint = true
            QR:Debug(string_format("Quest %d: intermediate waypoint detected (text: %s)", questID, wpText))
        end
    end

    -- Method 1: GetNextWaypoint returns the actual target mapID + coordinates
    -- Works even when the quest objective is on a different map from the player
    -- Added in Patch 8.2.0
    if C_QuestLog.GetNextWaypoint then
        local wpMapID, wpX, wpY = C_QuestLog.GetNextWaypoint(questID)
        if wpMapID and wpX and wpY then
            QR:Debug(string_format("Quest %d: GetNextWaypoint -> map %d (%.4f, %.4f)", questID, wpMapID, wpX, wpY))

            -- Check if the returned map is continent/world level (mapType 0=Cosmic, 1=World, 2=Continent)
            -- Continent-level coordinates are NOT valid on zone-level maps, so we must resolve
            local useContinent = false
            if C_Map and C_Map.GetMapInfo then
                local mapInfo = C_Map.GetMapInfo(wpMapID)
                if mapInfo and mapInfo.mapType and mapInfo.mapType <= 2 then
                    useContinent = true
                    QR:Debug(string_format("Quest %d: map %d is continent-level (type %d), resolving to zone",
                        questID, wpMapID, mapInfo.mapType))

                    -- Resolve continent to zone
                    if C_Map.GetMapInfoAtPosition then
                        local childInfo = C_Map.GetMapInfoAtPosition(wpMapID, wpX, wpY)
                        if childInfo and childInfo.mapID and childInfo.mapID ~= wpMapID then
                            -- Got a zone - get zone-level coordinates via GetNextWaypointForMap
                            if C_QuestLog.GetNextWaypointForMap then
                                local zoneX, zoneY = C_QuestLog.GetNextWaypointForMap(questID, childInfo.mapID)
                                if zoneX and zoneY then
                                    QR:Debug(string_format("Quest %d: Resolved continent %d -> zone %d (%s) coords (%.4f, %.4f)",
                                        questID, wpMapID, childInfo.mapID, childInfo.name or "?", zoneX, zoneY))
                                    if isIntermediateWaypoint or transitHubMapIDs[childInfo.mapID] then
                                        QR:Debug(string_format("Quest %d: zone %d is intermediate/transit, scanning for final destination", questID, childInfo.mapID))
                                        transitFallback = { mapID = childInfo.mapID, x = zoneX, y = zoneY }
                                    else
                                        questCoordCache[questID] = { mapID = childInfo.mapID, x = zoneX, y = zoneY, time = now }
                                        return {
                                            mapID = childInfo.mapID,
                                            x = zoneX,
                                            y = zoneY,
                                            title = questTitle,
                                        }
                                    end
                                end
                            end
                            -- Fallback: use zone mapID but skip continent coords (let methods below handle it)
                            QR:Debug(string_format("Quest %d: Resolved to zone %d but couldn't get zone coords, falling through",
                                questID, childInfo.mapID))
                        end
                    end
                    -- Fall through to other methods for zone-level coordinates
                end
            end

            if not useContinent then
                if isIntermediateWaypoint or transitHubMapIDs[wpMapID] then
                    QR:Debug(string_format("Quest %d: waypoint map %d is %s, scanning for final destination",
                        questID, wpMapID, isIntermediateWaypoint and "intermediate" or "transit hub"))
                    transitFallback = { mapID = wpMapID, x = wpX, y = wpY }
                    -- Fall through to Methods 2-5 to find actual objective
                else
                    questCoordCache[questID] = { mapID = wpMapID, x = wpX, y = wpY, time = now }
                    return {
                        mapID = wpMapID,
                        x = wpX,
                        y = wpY,
                        title = questTitle,
                    }
                end
            end
        end
    end

    -- Method 2: GetNextWaypointForMap projects the objective onto a specific map
    -- Signature: C_QuestLog.GetNextWaypointForMap(questID, uiMapID) -> x, y
    -- NOTE: Skip when intermediate - GetNextWaypointForMap also returns projected
    -- intermediate waypoints, not the actual objective location
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not isIntermediateWaypoint and playerMapID and C_QuestLog.GetNextWaypointForMap then
        local wpX, wpY = C_QuestLog.GetNextWaypointForMap(questID, playerMapID)
        if wpX and wpY and not (transitFallback and transitHubMapIDs[playerMapID]) then
            QR:Debug(string_format("Quest %d: GetNextWaypointForMap -> (%.4f, %.4f) on map %d", questID, wpX, wpY, playerMapID))
            questCoordCache[questID] = { mapID = playerMapID, x = wpX, y = wpY, time = now }
            return {
                mapID = playerMapID,
                x = wpX,
                y = wpY,
                title = questTitle,
            }
        end
    end

    -- Method 3: GetQuestsOnMap returns all quests with POIs on a specific map
    if playerMapID and C_QuestLog.GetQuestsOnMap then
        local questsOnMap = C_QuestLog.GetQuestsOnMap(playerMapID)
        if questsOnMap then
            for _, questInfo in ipairs(questsOnMap) do
                if questInfo.questID == questID then
                    local qx, qy = questInfo.x, questInfo.y
                    if qx and qy and (qx ~= 0 or qy ~= 0) and not (transitFallback and transitHubMapIDs[playerMapID]) then
                        QR:Debug(string_format("Quest %d: GetQuestsOnMap -> (%.4f, %.4f)", questID, qx, qy))
                        questCoordCache[questID] = { mapID = playerMapID, x = qx, y = qy, time = now }
                        return {
                            mapID = playerMapID,
                            x = qx,
                            y = qy,
                            title = questTitle,
                        }
                    end
                end
            end
        end
    end

    -- Method 3b: Broad scan using GetQuestsOnMap across all zone maps
    -- GetQuestsOnMap returns actual objective POIs (not intermediate waypoints),
    -- making it reliable for finding the true destination when Method 1 returned an intermediate step.
    -- Only runs when intermediate waypoint is detected and Method 3 didn't find the objective on player's map.
    if isIntermediateWaypoint and C_QuestLog.GetQuestsOnMap then
        QR:Debug(string_format("Quest %d: Broad GetQuestsOnMap scan for actual objective", questID))
        local scannedMaps = {}
        if playerMapID then scannedMaps[playerMapID] = true end

        -- Phase 1: Scan all known zones from QR.Continents
        if QR.Continents then
            for _, continentData in pairs(QR.Continents) do
                for _, zoneID in ipairs(continentData.zones) do
                    if not scannedMaps[zoneID] then
                        scannedMaps[zoneID] = true
                        local questsOnMap = C_QuestLog.GetQuestsOnMap(zoneID)
                        if questsOnMap then
                            for _, questInfo in ipairs(questsOnMap) do
                                if questInfo.questID == questID then
                                    local qx, qy = questInfo.x, questInfo.y
                                    if qx and qy and (qx ~= 0 or qy ~= 0) then
                                        QR:Debug(string_format("Quest %d: Broad GetQuestsOnMap found objective on map %d (%.4f, %.4f)", questID, zoneID, qx, qy))
                                        questCoordCache[questID] = { mapID = zoneID, x = qx, y = qy, time = now }
                                        return {
                                            mapID = zoneID,
                                            x = qx,
                                            y = qy,
                                            title = questTitle,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Phase 2: Dynamic map discovery via C_Map.GetMapChildrenInfo
        -- Catches zones not in our hardcoded list (e.g. Tazavesh, instance zones)
        -- World map (947) -> all descendant zone maps (mapType 3)
        -- Only returns results for ROUTABLE zones (known continent) — unroutable maps
        -- (e.g. K'aresh) are skipped so the transit fallback is used instead.
        if C_Map and C_Map.GetMapChildrenInfo then
            local childMaps = C_Map.GetMapChildrenInfo(947, 3, true) -- world, zones, all descendants
            if childMaps then
                for _, childInfo in ipairs(childMaps) do
                    local childMapID = childInfo.mapID
                    if childMapID and not scannedMaps[childMapID] then
                        scannedMaps[childMapID] = true
                        local questsOnMap = C_QuestLog.GetQuestsOnMap(childMapID)
                        if questsOnMap then
                            for _, questInfo in ipairs(questsOnMap) do
                                if questInfo.questID == questID then
                                    local qx, qy = questInfo.x, questInfo.y
                                    if qx and qy and (qx ~= 0 or qy ~= 0) then
                                        -- Verify the zone is routable (has a known continent)
                                        local continent = QR.GetContinentForZone and QR.GetContinentForZone(childMapID)
                                        if continent then
                                            QR:Debug(string_format("Quest %d: Dynamic scan found routable objective on map %d (%s) (%.4f, %.4f)",
                                                questID, childMapID, childInfo.name or "?", qx, qy))
                                            questCoordCache[questID] = { mapID = childMapID, x = qx, y = qy, time = now }
                                            return {
                                                mapID = childMapID,
                                                x = qx,
                                                y = qy,
                                                title = questTitle,
                                            }
                                        else
                                            QR:Debug(string_format("Quest %d: Dynamic scan found objective on map %d (%s) but zone is not routable, skipping",
                                                questID, childMapID, childInfo.name or "?"))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Method 4: For world quests, try C_TaskQuest.GetQuestLocation
    if playerMapID and C_TaskQuest and C_TaskQuest.GetQuestLocation then
        local tqX, tqY = C_TaskQuest.GetQuestLocation(questID, playerMapID)
        if tqX and tqY and (tqX ~= 0 or tqY ~= 0) and not (transitFallback and transitHubMapIDs[playerMapID]) then
            QR:Debug(string_format("Quest %d: TaskQuest.GetQuestLocation -> (%.4f, %.4f)", questID, tqX, tqY))
            questCoordCache[questID] = { mapID = playerMapID, x = tqX, y = tqY, time = now }
            return {
                mapID = playerMapID,
                x = tqX,
                y = tqY,
                title = questTitle,
            }
        end
    end

    -- Method 5: Broad scan - try GetNextWaypointForMap on all known zone maps
    -- Only runs when faster methods fail; result is cached to avoid repeated scans
    -- NOTE: Skip when intermediate - GetNextWaypointForMap projects intermediate waypoints
    -- onto zone maps, causing false positives (e.g. Elwynn Forest for a Stormwind portal waypoint)
    if not isIntermediateWaypoint and C_QuestLog.GetNextWaypointForMap and QR.Continents then
        for _, continentData in pairs(QR.Continents) do
            for _, zoneID in ipairs(continentData.zones) do
                if zoneID ~= playerMapID then  -- already checked player's map in Method 2
                    local wpX, wpY = C_QuestLog.GetNextWaypointForMap(questID, zoneID)
                    if wpX and wpY and not transitHubMapIDs[zoneID] then
                        QR:Debug(string_format("Quest %d: Broad scan found on map %d (%.4f, %.4f)", questID, zoneID, wpX, wpY))
                        questCoordCache[questID] = { mapID = zoneID, x = wpX, y = wpY, time = now }
                        return {
                            mapID = zoneID,
                            x = wpX,
                            y = wpY,
                            title = questTitle,
                        }
                    end
                end
            end
        end
    end

    -- If we had a transit hub fallback but found nothing better, use it
    if transitFallback then
        QR:Debug(string_format("Quest %d: no better destination found, using transit hub fallback map %d", questID, transitFallback.mapID))
        questCoordCache[questID] = { mapID = transitFallback.mapID, x = transitFallback.x, y = transitFallback.y, time = now }
        return { mapID = transitFallback.mapID, x = transitFallback.x, y = transitFallback.y, title = questTitle }
    end

    -- No coordinates found from any API - cache negative result to avoid repeated scans
    QR:Debug(string_format("Quest %d (%s): no coordinates found from any API", questID, questTitle))
    questCoordCache[questID] = { time = now }
    return nil
end

--- Get the user's map pin (manual waypoint)
-- Uses C_Map.HasUserWaypoint and C_Map.GetUserWaypoint
-- @return table|nil {mapID, x, y, title} or nil if no map pin
function WaypointIntegration:GetMapPing()
    -- Check API availability and if user has set a waypoint on the map
    if not (C_Map and C_Map.HasUserWaypoint) then
        return nil
    end
    if not C_Map.HasUserWaypoint() then
        return nil
    end

    local point = C_Map.GetUserWaypoint()
    if not point then
        return nil
    end

    -- point is a UiMapPoint with mapID and position
    local mapID = point.uiMapID
    local position = point.position

    -- Fallback: use the map the player is currently viewing or the player's current map
    if not mapID or mapID == 0 then
        -- Try WorldMapFrame's current map first (if map is open)
        if WorldMapFrame and WorldMapFrame.GetMapID then
            mapID = WorldMapFrame:GetMapID()
        end
        -- Final fallback: player's current zone
        if not mapID or mapID == 0 then
            mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        end
    end

    if not position then
        return nil
    end

    if not position.x or not position.y then
        return nil
    end

    -- Resolve continent-level maps to specific zone
    -- When a user places a pin on a continent map (e.g. Pandaria = 424),
    -- the uiMapID is the continent, not the specific zone. Resolve it.
    if mapID and C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(mapID)
        if mapInfo and mapInfo.mapType and mapInfo.mapType <= 2 then
            -- mapType 0=Cosmic, 1=World, 2=Continent — try to resolve to zone
            if C_Map.GetMapInfoAtPosition then
                local childInfo = C_Map.GetMapInfoAtPosition(mapID, position.x, position.y)
                if childInfo and childInfo.mapID and childInfo.mapID ~= mapID then
                    QR:Debug(string_format(
                        "Resolved continent map %d to zone %d (%s)",
                        mapID, childInfo.mapID, childInfo.name or "?"))
                    mapID = childInfo.mapID
                end
            end
        end
    end

    return {
        mapID = mapID,
        x = position.x,
        y = position.y,
        title = QR.L["SOURCE_MAP_PIN"],
    }
end

-------------------------------------------------------------------------------
-- Active Waypoint Selection
-------------------------------------------------------------------------------

--- Get the current active waypoint from any source
-- Priority is configurable via QR.db.waypointPriority
-- @return table|nil waypoint {mapID, x, y, title}
-- @return string|nil source "mappin", "tomtom", "quest", or nil
function WaypointIntegration:GetActiveWaypoint()
    local priority = QR.db and QR.db.waypointPriority or "mappin"

    local sources = activeWaypointSources

    -- Define order based on priority setting
    local order
    if priority == "quest" then
        order = {"quest", "mappin", "tomtom"}
    elseif priority == "tomtom" then
        order = {"tomtom", "mappin", "quest"}
    else
        -- Default: "mappin"
        order = {"mappin", "tomtom", "quest"}
    end

    for _, src in ipairs(order) do
        local wp = sources[src]()
        if wp then return wp, src end
    end
    return nil, nil
end

--- Get all currently available waypoints from all sources
-- @return table Array of {key, waypoint, label} entries
function WaypointIntegration:GetAllAvailableWaypoints()
    local available = {}
    local L = QR.L
    for _, src in ipairs(waypointSourceDefs) do
        local wp = src.getter()
        if wp then
            local label = L[src.labelKey]
            if wp.title and wp.title ~= "" then
                label = label .. ": " .. wp.title
            end
            table_insert(available, { key = src.key, waypoint = wp, label = label })
        end
    end
    return available
end

-------------------------------------------------------------------------------
-- Path Calculation Integration
-------------------------------------------------------------------------------

--- Calculate path to the active waypoint
-- Gets active waypoint and calculates path using PathCalculator
-- @return table|nil Path result with waypoint info added, or nil if no waypoint/path
function WaypointIntegration:CalculatePathToWaypoint()
    local waypoint, source = self:GetActiveWaypoint()
    if not waypoint then
        return nil
    end

    -- Detect if player is inside an instance
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        QR:Log("WARN", "Player is inside instance, pathfinding may be limited")
    end

    -- Calculate path using PathCalculator
    local result = QR.PathCalculator:CalculatePath(
        waypoint.mapID,
        waypoint.x,
        waypoint.y,
        waypoint.title
    )

    if not result then
        return nil
    end

    -- Add waypoint info to result
    result.waypoint = waypoint
    result.waypointSource = source

    return result
end

-------------------------------------------------------------------------------
-- Event Handling and Hooks
-------------------------------------------------------------------------------

--- Called when a waypoint changes (from any source)
-- Updates UI if showing
function WaypointIntegration:OnWaypointChanged()
    local waypoint, source = self:GetActiveWaypoint()

    if waypoint then
        QR:Log("INFO", string_format("Waypoint changed (%s) -> %s at map %d (%.2f, %.2f)",
            source or "?", waypoint.title or "?", waypoint.mapID or 0, waypoint.x or 0, waypoint.y or 0))
        QR:Debug(string_format(
            "Waypoint changed (%s) -> %s at %d (%.2f, %.2f)",
            source or "?",
            waypoint.title or "?",
            waypoint.mapID or 0,
            waypoint.x or 0,
            waypoint.y or 0
        ))
    else
        QR:Log("INFO", "Waypoint cleared")
        QR:Debug("Waypoint cleared")
    end

    -- Auto-show UI when waypoint changes (if auto-destination is enabled)
    if QR.UI then
        if QR.db and QR.db.autoDestination then
            -- Auto-show and route to new waypoint
            QR.UI:Show()
        elseif QR.MainFrame and QR.MainFrame.isShowing and QR.MainFrame.activeTab == "route" then
            QR.UI:RefreshRoute()
        end
    end
end

--- Called when waypoint is cleared
function WaypointIntegration:OnWaypointCleared()
    QR:Debug("Waypoint cleared")

    -- Update UI if showing
    if QR.UI and QR.UI.frame and QR.UI.frame:IsShown() then
        QR.UI:RefreshRoute()
    end
end

--- Register hooks for TomTom and WoW events
-- Safe to call multiple times; hooks are only registered once
function WaypointIntegration:RegisterHooks()
    if self.hooksRegistered then
        return
    end
    self.hooksRegistered = true

    -- Create event frame if not exists
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    -- Register WoW events
    eventFrame:RegisterEvent("USER_WAYPOINT_UPDATED")
    eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")

    eventFrame:SetScript("OnEvent", function(self, event, ...)
        local ok, err = pcall(function()
            if event == "USER_WAYPOINT_UPDATED" then
                -- Map pin added/removed
                if C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
                    WaypointIntegration:OnWaypointChanged()
                else
                    WaypointIntegration:OnWaypointCleared()
                end
            elseif event == "SUPER_TRACKING_CHANGED" then
                -- Clear quest coordinate cache on tracking change
                wipe(questCoordCache)
                WaypointIntegration:OnWaypointChanged()
            end
        end)
        if not ok then
            QR:Error("Waypoint event error: " .. tostring(err))
        end
    end)

    -- Hook TomTom callbacks if available
    if self:HasTomTom() then
        local tomtomOk, tomtomErr = pcall(function()
            -- TomTom fires callbacks when waypoints change
            if TomTom.RegisterCallback then
                TomTom:RegisterCallback("Waypoint", function(event, uid, mapID, x, y, title)
                    -- Skip if QuickRoute itself is setting the waypoint (prevents feedback loop)
                    if not WaypointIntegration._settingWaypoint then
                        WaypointIntegration:OnWaypointChanged()
                    end
                end)
            end

            -- Alternative: hook SetClosestWaypoint if available (using safe post-hook)
            if TomTom.SetClosestWaypoint then
                -- Use hooksecurefunc for safe hooking that doesn't overwrite other addons' hooks
                hooksecurefunc(TomTom, "SetClosestWaypoint", function()
                    if not WaypointIntegration._settingWaypoint then
                        WaypointIntegration:OnWaypointChanged()
                    end
                end)
            end
        end)

        if tomtomOk then
            QR:Debug("TomTom integration enabled")
        else
            QR:Warn("TomTom hook registration failed: " .. tostring(tomtomErr))
        end
    end
end

-------------------------------------------------------------------------------
-- Waypoint Setting
-------------------------------------------------------------------------------

--- Set a TomTom waypoint or native map pin
-- @param mapID number The destination map ID
-- @param x number X coordinate (0-1)
-- @param y number Y coordinate (0-1)
-- @param title string Optional waypoint title
-- @return table|nil TomTom waypoint UID or nil for native waypoint
function WaypointIntegration:SetTomTomWaypoint(mapID, x, y, title)
    if not mapID then
        QR:Error("Cannot set waypoint - no mapID provided")
        return nil
    end

    -- Deduplicate: skip if setting the exact same waypoint we just set
    local now = GetTime and GetTime() or 0
    if self._lastWpMapID == mapID and self._lastWpX == x and self._lastWpY == y
        and self._lastWpTitle == title and (now - (self._lastWpTime or 0)) < 2 then
        return self._lastWpUID
    end
    self._lastWpMapID = mapID
    self._lastWpX = x
    self._lastWpY = y
    self._lastWpTitle = title
    self._lastWpTime = now

    if TomTom then
        -- Use TomTom addon
        -- Sanitize title: escape pipe characters to prevent UI string injection
        local safeTitle = title and title:gsub("|", "||") or "QuickRoute"
        local opts = {
            title = safeTitle,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
        }
        -- Guard: prevent TomTom callback from triggering OnWaypointChanged
        self._settingWaypoint = true
        local uid = TomTom:AddWaypoint(mapID, x, y, opts)
        self._settingWaypoint = false
        self._lastWpUID = uid
        QR:Print("|cFF00FF00QuickRoute|r: TomTom waypoint set for " .. (safeTitle or "destination"))
        return uid
    end

    -- Fallback to native waypoint using C_Map API
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local success, err = pcall(function()
            local uiMapPoint = UiMapPoint.CreateFromCoordinates(mapID, x, y)
            C_Map.SetUserWaypoint(uiMapPoint)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
        if success then
            QR:Print("|cFF00FF00QuickRoute|r: Native waypoint set for " .. (title or "destination"))
            return nil
        else
            QR:Warn("Native waypoint API failed: " .. tostring(err))
        end
    else
        QR:Warn("No waypoint system available (install TomTom for better support)")
    end
    return nil
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the WaypointIntegration module
-- Called from QuickRoute:OnPlayerLogin
function WaypointIntegration:Initialize()
    self:RegisterHooks()

    QR:Debug("WaypointIntegration initialized")
end

-- Initialize module-scope source definitions (all methods are now defined)
-- Single source of truth - activeWaypointSources is derived from waypointSourceDefs
waypointSourceDefs = {
    { key = "mappin", getter = function() return WaypointIntegration:GetMapPing() end, labelKey = "WAYPOINT_MAP_PIN" },
    { key = "tomtom", getter = function() return WaypointIntegration:GetTomTomWaypoint() end, labelKey = "WAYPOINT_TOMTOM" },
    { key = "quest",  getter = function() return WaypointIntegration:GetSuperTrackedWaypoint() end, labelKey = "WAYPOINT_QUEST" },
}

-- Derive lookup table from waypointSourceDefs to avoid duplication
activeWaypointSources = {}
for _, src in ipairs(waypointSourceDefs) do
    activeWaypointSources[src.key] = src.getter
end

-------------------------------------------------------------------------------
-- Slash Command
-------------------------------------------------------------------------------

--- Debug command to show what waypoint sources are detected
--- Use "copy" subcommand to open the copy-paste debug popup
SLASH_QRDEBUG1 = "/qrdebug"
SlashCmdList["QRDEBUG"] = function(msg)
    -- /qrdebug copy → open the Copy Debug popup (markdown, ready for GitHub issues)
    if msg and msg:lower():find("copy") then
        if QR.UI and QR.UI.CopyDebugToClipboard then
            QR.UI:CopyDebugToClipboard()
        else
            print("|cFFFF0000QuickRoute|r: UI not loaded yet")
        end
        return
    end
    print("|cFF00FF00QuickRoute|r: Waypoint Detection Debug")
    print("----------------------------------------")

    -- Check native map pin
    local hasUserWP = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
    print(string_format("  C_Map.HasUserWaypoint(): %s", tostring(hasUserWP)))
    if hasUserWP then
        local point = C_Map.GetUserWaypoint()
        if point then
            print(string_format("    -> uiMapID: %s", tostring(point.uiMapID)))
            print(string_format("    -> position: x=%.4f, y=%.4f",
                point.position and point.position.x or 0,
                point.position and point.position.y or 0))
        end
    end

    -- Show fallback map info
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    print(string_format("  Player current map: %s", tostring(playerMapID)))
    if WorldMapFrame and WorldMapFrame.GetMapID then
        print(string_format("  WorldMapFrame map: %s", tostring(WorldMapFrame:GetMapID())))
    end

    -- Check TomTom
    local hasTomTom = TomTom ~= nil
    print(string_format("  TomTom loaded: %s", tostring(hasTomTom)))
    if hasTomTom then
        local uid = TomTom.GetClosestWaypoint and TomTom:GetClosestWaypoint()
        print(string_format("    -> GetClosestWaypoint: %s (type: %s)", tostring(uid), type(uid)))

        -- Try to get waypoint data
        if uid then
            if type(uid) == "table" then
                local keys = {}
                for k in pairs(uid) do keys[#keys + 1] = tostring(k) end
                print(string_format("    -> uid is table with keys: %s", table_concat(keys, ", ")))
                local m = uid.mapID or uid.m or uid[1]
                local x = uid.x or uid[2]
                local y = uid.y or uid[3]
                print(string_format("    -> mapID: %s, x: %s, y: %s", tostring(m), tostring(x), tostring(y)))
            end
        end

        -- Check crazy arrow
        if TomTom.GetCrazyArrowTarget then
            local arrowTarget = TomTom:GetCrazyArrowTarget()
            print(string_format("    -> GetCrazyArrowTarget: %s", tostring(arrowTarget)))
        end
    end

    -- Check super-tracked quest
    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    print(string_format("  Super-tracked quest: %s", tostring(questID)))

    if questID and questID ~= 0 then
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or "?"
        print(string_format("    -> Title: %s", title))

        -- Method 1: GetNextWaypoint (cross-map, added 8.2.0)
        if C_QuestLog.GetNextWaypoint then
            local wpMap, wpX, wpY = C_QuestLog.GetNextWaypoint(questID)
            print(string_format("    -> GetNextWaypoint: map=%s x=%s y=%s",
                tostring(wpMap), tostring(wpX), tostring(wpY)))
        else
            print("    -> GetNextWaypoint: API not available")
        end

        -- Method 2: GetNextWaypointForMap (projection onto player map)
        if C_QuestLog.GetNextWaypointForMap and playerMapID then
            local fmX, fmY = C_QuestLog.GetNextWaypointForMap(questID, playerMapID)
            print(string_format("    -> GetNextWaypointForMap(%d, %d): x=%s y=%s",
                questID, playerMapID, tostring(fmX), tostring(fmY)))
        end

        -- Method 3: GetNextWaypointText
        if C_QuestLog.GetNextWaypointText then
            local wpText = C_QuestLog.GetNextWaypointText(questID)
            print(string_format("    -> GetNextWaypointText: %s", tostring(wpText)))
        end

        -- Method 4: GetQuestsOnMap match
        if C_QuestLog.GetQuestsOnMap and playerMapID then
            local questsOnMap = C_QuestLog.GetQuestsOnMap(playerMapID)
            local found = false
            if questsOnMap then
                for _, qi in ipairs(questsOnMap) do
                    if qi.questID == questID then
                        print(string_format("    -> GetQuestsOnMap match: x=%s y=%s",
                            tostring(qi.x), tostring(qi.y)))
                        found = true
                        break
                    end
                end
            end
            if not found then
                print(string_format("    -> GetQuestsOnMap: quest not on map %d", playerMapID))
            end
        end

        -- Method 5: C_TaskQuest (world quests)
        if C_TaskQuest and C_TaskQuest.GetQuestLocation and playerMapID then
            local tqX, tqY = C_TaskQuest.GetQuestLocation(questID, playerMapID)
            if tqX and tqY then
                print(string_format("    -> TaskQuest.GetQuestLocation: x=%s y=%s",
                    tostring(tqX), tostring(tqY)))
            end
        end

        -- Distance info
        if C_QuestLog.GetDistanceSqToQuest then
            local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
            print(string_format("    -> DistanceSqToQuest: %s (onContinent: %s)",
                tostring(distSq), tostring(onContinent)))
        end
    end

    -- Final result
    local waypoint, source = WaypointIntegration:GetActiveWaypoint()
    print("----------------------------------------")
    if waypoint then
        print(string_format("|cFF00FF00RESULT:|r Found waypoint from '%s'", source))
        print(string_format("  Title: %s", waypoint.title or "?"))
        print(string_format("  MapID: %d, Position: (%.2f, %.2f)", waypoint.mapID or 0, waypoint.x or 0, waypoint.y or 0))
    else
        print("|cFFFF0000RESULT:|r No waypoint detected")
    end
    print("")
    print("|cFF888888Tip: Use |cFFFFFF00/qrdebug copy|r|cFF888888 or the Copy Debug button for full diagnostics (markdown, ready for bug reports)|r")
end

SLASH_QRWP1 = "/qrwp"
SlashCmdList["QRWP"] = function(msg)
    local success, err = pcall(function()
        -- Ensure modules are initialized
        if QR.PathCalculator and not QR.PathCalculator.graph then
            QR.PathCalculator:BuildGraph()
        end

        -- Get active waypoint
        local waypoint, source = WaypointIntegration:GetActiveWaypoint()

        if not waypoint then
            print("|cFFFF0000QuickRoute|r: No active waypoint found")
            print("  Set a waypoint using: Map pin, TomTom, or quest tracking")
            -- Also show UI with error
            if QR.UI then
                QR.UI:Show()
            end
            return
        end

        print(string_format("|cFF00FF00QuickRoute|r: Calculating path to %s...", waypoint.title))
        print(string_format("  Source: %s | Map: %d | Position: (%.2f, %.2f)",
            source, waypoint.mapID or 0, waypoint.x or 0, waypoint.y or 0))

        -- Calculate path
        local result = WaypointIntegration:CalculatePathToWaypoint()

        -- Show UI with result
        if QR.UI then
            QR.UI:Show()
            if result then
                QR.UI:UpdateRoute(result)
            else
                QR.UI:ClearRoute()
            end
        end

        if not result then
            print("|cFFFF0000QuickRoute|r: No path found to waypoint")
            return
        end

        print("----------------------------------------")
        print(string_format("|cFFFFFF00Destination:|r %s", waypoint.title))
        print(string_format("|cFFFFFF00Total time:|r %s",
            QR.CooldownTracker and QR.CooldownTracker:FormatTime(result.totalTime) or tostring(result.totalTime)))
        print("----------------------------------------")
        print("|cFFFFFF00Steps:|r")

        if result.steps then
            for i, step in ipairs(result.steps) do
                local timeStr = QR.CooldownTracker and QR.CooldownTracker:FormatTime(step.time) or "?"
                print(string_format("  %d. %s |cFFAAAAAA(%s)|r", i, step.action or "?", timeStr))
            end
        end

        print("----------------------------------------")
    end)

    if not success then
        print("|cFFFF0000QuickRoute ERROR:|r " .. tostring(err))
    end
end
