-- POIRouting.lua
-- Adds Ctrl+Right-click routing from the World Map canvas
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, type, tostring, pcall = pairs, type, tostring, pcall
local string_format = string.format

-------------------------------------------------------------------------------
-- POIRouting Module
-------------------------------------------------------------------------------
QR.POIRouting = {
    initialized = false,
    hookRegistered = false,
}

local POIRouting = QR.POIRouting

-------------------------------------------------------------------------------
-- Core Routing
-------------------------------------------------------------------------------

--- Route to a specific map position
-- Resolves continent-level maps to zones, calculates path, and shows in UI
-- @param mapID number The destination map ID
-- @param x number X coordinate (0-1)
-- @param y number Y coordinate (0-1)
function POIRouting:RouteToMapPosition(mapID, x, y)
    if not mapID or not x or not y then
        QR:Debug("POIRouting: invalid arguments")
        return
    end

    -- Get zone name for display
    local L = QR.L
    local zoneName = string_format((L and L["UNKNOWN"] or "Unknown") .. " (%d)", mapID)
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then
            zoneName = info.name
        end
    end

    -- Resolve continent-level maps to specific zone
    -- mapType: 0=Cosmic, 1=World, 2=Continent, 3=Zone
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.mapType and info.mapType <= 2 then
            if C_Map.GetMapInfoAtPosition then
                local child = C_Map.GetMapInfoAtPosition(mapID, x, y)
                if child and child.mapID and child.mapID ~= mapID then
                    QR:Debug(string_format(
                        "POIRouting: resolved continent %d -> zone %d (%s)",
                        mapID, child.mapID, child.name or "?"
                    ))
                    mapID = child.mapID
                    zoneName = child.name or zoneName
                end
            end
        end
    end

    QR:Debug(string_format(
        "POIRouting: routing to map %d (%s) at (%.4f, %.4f)",
        mapID, zoneName, x, y
    ))

    -- Calculate path
    local calcOk, result = pcall(function()
        return QR.PathCalculator:CalculatePath(mapID, x, y, zoneName)
    end)

    if not calcOk then
        QR:Error("POIRouting path calculation error: " .. tostring(result))
        result = nil
    end

    -- Save destination so it persists across close/reopen
    if QR.db then
        QR.db.lastDestination = { mapID = mapID, x = x, y = y, title = zoneName }
    end

    -- Show route in UI. Pass the pre-calculated result via _pendingPOIRoute so
    -- RefreshRoute (triggered by SetActiveTab during Show) uses it directly
    -- instead of re-calculating from the active waypoint.
    if QR.UI then
        if result then
            result.waypoint = { mapID = mapID, x = x, y = y, title = zoneName }
            result.waypointSource = "map_click"
            QR.UI._pendingPOIRoute = result
        end
        QR.UI:Show()
    end
end

-------------------------------------------------------------------------------
-- World Map Hook
-------------------------------------------------------------------------------

--- Register Ctrl+Right-click handler on the WorldMapFrame
-- Uses HookScript to avoid overriding existing handlers
function POIRouting:RegisterMapHook()
    if self.hookRegistered then
        return
    end

    if not WorldMapFrame then
        QR:Debug("POIRouting: WorldMapFrame not available, skipping hook")
        return
    end

    -- Wrap in pcall since HookScript or GetNormalizedCursorPosition may not exist
    local ok, err = pcall(function()
        -- Prefer HookScript to avoid overwriting existing handlers
        if WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnMouseUp", function(frame, button)
                POIRouting:OnMapClick(frame, button)
            end)
        else
            -- Fallback: preserve existing handler via raw hook
            local existing = WorldMapFrame.GetScript and WorldMapFrame:GetScript("OnMouseUp")
            WorldMapFrame:SetScript("OnMouseUp", function(frame, button, ...)
                if existing then
                    existing(frame, button, ...)
                end
                POIRouting:OnMapClick(frame, button)
            end)
        end
    end)

    if ok then
        self.hookRegistered = true
        QR:Debug("POIRouting: World Map hook registered")
    else
        QR:Warn("POIRouting: Failed to hook WorldMapFrame: " .. tostring(err))
    end
end

--- Handle mouse click on the World Map
-- Only triggers on Ctrl+Right-click to avoid interfering with normal map usage
-- @param frame Frame The WorldMapFrame
-- @param button string The mouse button ("LeftButton", "RightButton", etc.)
function POIRouting:OnMapClick(frame, button)
    if button ~= "RightButton" then
        return
    end

    -- Require Ctrl modifier to avoid interfering with normal right-click behavior
    if not (IsControlKeyDown and IsControlKeyDown()) then
        return
    end

    local mapID = nil
    if WorldMapFrame and WorldMapFrame.GetMapID then
        mapID = WorldMapFrame:GetMapID()
    end

    if not mapID then
        QR:Debug("POIRouting: no mapID from WorldMapFrame")
        return
    end

    -- Get cursor position relative to map canvas
    local cursorX, cursorY
    local posOk, posErr = pcall(function()
        if WorldMapFrame.GetNormalizedCursorPosition then
            cursorX, cursorY = WorldMapFrame:GetNormalizedCursorPosition()
        end
    end)

    if not posOk or not cursorX or not cursorY then
        QR:Debug("POIRouting: could not get cursor position: " .. tostring(posErr))
        return
    end

    -- Validate coordinates are in valid range
    if cursorX < 0 or cursorX > 1 or cursorY < 0 or cursorY > 1 then
        QR:Debug(string_format(
            "POIRouting: cursor position out of range (%.4f, %.4f)", cursorX, cursorY
        ))
        return
    end

    self:RouteToMapPosition(mapID, cursorX, cursorY)
end

-------------------------------------------------------------------------------
-- Dungeon Entrance Pin Hook
-------------------------------------------------------------------------------

--- Hook dungeon entrance map pins for Ctrl+Right-click routing
-- DungeonEntrancePinMixin is Blizzard's pin template for dungeon entrances
-- on the world map. We post-hook OnMouseClickAction to intercept Ctrl+Right-click.
function POIRouting:RegisterDungeonPinHook()
    if not WorldMapFrame then return end

    local ok, err = pcall(function()
        if DungeonEntrancePinMixin and DungeonEntrancePinMixin.OnMouseClickAction then
            hooksecurefunc(DungeonEntrancePinMixin, "OnMouseClickAction", function(pin, button)
                if button ~= "RightButton" then return end
                if not (IsControlKeyDown and IsControlKeyDown()) then return end
                if not pin.journalInstanceID then return end

                if QR.DungeonData then
                    local inst = QR.DungeonData:GetInstance(pin.journalInstanceID)
                    if inst and inst.zoneMapID and inst.x and inst.y then
                        POIRouting:RouteToMapPosition(inst.zoneMapID, inst.x, inst.y)
                    end
                end
            end)
            QR:Debug("POIRouting: Dungeon pin hook registered")
        else
            QR:Debug("POIRouting: DungeonEntrancePinMixin not available, pin hook skipped")
        end
    end)

    if not ok then
        QR:Debug("POIRouting: Failed to hook dungeon pins: " .. tostring(err))
    end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the POIRouting module
-- Called from QuickRoute:OnPlayerLogin
function POIRouting:Initialize()
    if self.initialized then
        return
    end
    self.initialized = true

    self:RegisterMapHook()
    self:RegisterDungeonPinHook()
    QR:Debug("POIRouting initialized")
end
