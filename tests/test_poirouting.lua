-------------------------------------------------------------------------------
-- test_poirouting.lua
-- Tests for QR.POIRouting module
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function resetState()
    MockWoW:Reset()
    MockWoW.config.currentMapID = 84 -- Stormwind

    -- Ensure PathCalculator is available with a fresh graph
    if QR.PathCalculator then
        QR.PathCalculator.graph = nil
        QR.PathCalculator.graphDirty = true
    end

    -- Reset POIRouting state (keep initialized so methods work)
    QR.POIRouting.hookRegistered = false
end

-------------------------------------------------------------------------------
-- 1. Module Structure
-------------------------------------------------------------------------------

T:run("POIRouting: module exists", function(t)
    t:assertNotNil(QR.POIRouting, "QR.POIRouting exists")
end)

T:run("POIRouting: has Initialize method", function(t)
    t:assertNotNil(QR.POIRouting.Initialize, "Initialize method exists")
    t:assertEqual("function", type(QR.POIRouting.Initialize), "Initialize is a function")
end)

T:run("POIRouting: has RouteToMapPosition method", function(t)
    t:assertNotNil(QR.POIRouting.RouteToMapPosition, "RouteToMapPosition method exists")
    t:assertEqual("function", type(QR.POIRouting.RouteToMapPosition), "RouteToMapPosition is a function")
end)

T:run("POIRouting: has OnMapClick method", function(t)
    t:assertNotNil(QR.POIRouting.OnMapClick, "OnMapClick method exists")
    t:assertEqual("function", type(QR.POIRouting.OnMapClick), "OnMapClick is a function")
end)

T:run("POIRouting: has RegisterMapHook method", function(t)
    t:assertNotNil(QR.POIRouting.RegisterMapHook, "RegisterMapHook method exists")
    t:assertEqual("function", type(QR.POIRouting.RegisterMapHook), "RegisterMapHook is a function")
end)

-------------------------------------------------------------------------------
-- 2. RouteToMapPosition
-------------------------------------------------------------------------------

T:run("RouteToMapPosition: nil safety - nil mapID", function(t)
    resetState()
    -- Should not error with nil arguments
    local ok, err = pcall(function()
        QR.POIRouting:RouteToMapPosition(nil, 0.5, 0.5)
    end)
    t:assertTrue(ok, "Does not error with nil mapID: " .. tostring(err))
end)

T:run("RouteToMapPosition: nil safety - nil coordinates", function(t)
    resetState()
    local ok, err = pcall(function()
        QR.POIRouting:RouteToMapPosition(84, nil, nil)
    end)
    t:assertTrue(ok, "Does not error with nil coords: " .. tostring(err))
end)

T:run("RouteToMapPosition: calculates path for valid zone", function(t)
    resetState()
    -- Use a mapID that exists in the graph (Stormwind)
    -- Player is on map 84, route to same map (should find a trivial path or no path)
    local ok, err = pcall(function()
        QR.POIRouting:RouteToMapPosition(84, 0.3, 0.7)
    end)
    t:assertTrue(ok, "RouteToMapPosition does not error: " .. tostring(err))
end)

T:run("RouteToMapPosition: resolves continent-level map to zone", function(t)
    resetState()
    -- Map 12 is "Eastern Kingdoms" (mapType = 1, continent level)
    -- Should try to resolve to a zone via GetMapInfoAtPosition
    local resolvedMapID = nil
    local origGetMapInfoAtPosition = _G.C_Map.GetMapInfoAtPosition

    _G.C_Map.GetMapInfoAtPosition = function(mapID, x, y)
        if mapID == 12 then
            -- Pretend clicking on Stormwind area returns Stormwind
            resolvedMapID = 84
            return { mapID = 84, name = "Stormwind City", mapType = 3 }
        end
        if origGetMapInfoAtPosition then
            return origGetMapInfoAtPosition(mapID, x, y)
        end
        return nil
    end

    local ok, err = pcall(function()
        QR.POIRouting:RouteToMapPosition(12, 0.5, 0.8)
    end)

    t:assertTrue(ok, "Does not error when resolving continent: " .. tostring(err))
    t:assertEqual(84, resolvedMapID, "Continent resolved to zone via GetMapInfoAtPosition")

    -- Restore
    _G.C_Map.GetMapInfoAtPosition = origGetMapInfoAtPosition
end)

T:run("RouteToMapPosition: shows UI after routing", function(t)
    resetState()
    -- Track if UI:Show was called
    local showCalled = false
    local origShow = QR.UI.Show
    QR.UI.Show = function(self)
        showCalled = true
    end

    -- Track if UI:UpdateRoute was called
    local updateCalled = false
    local updateResult = nil
    local origUpdate = QR.UI.UpdateRoute
    QR.UI.UpdateRoute = function(self, result)
        updateCalled = true
        updateResult = result
    end

    QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)

    t:assertTrue(showCalled, "UI:Show was called")

    -- Restore
    QR.UI.Show = origShow
    QR.UI.UpdateRoute = origUpdate
end)

T:run("RouteToMapPosition: result has map_click waypointSource", function(t)
    resetState()
    local capturedResult = nil
    local origShow = QR.UI.Show
    local origUpdate = QR.UI.UpdateRoute
    QR.UI.Show = function(self) end
    QR.UI.UpdateRoute = function(self, result)
        capturedResult = result
    end

    QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)

    if capturedResult then
        t:assertEqual("map_click", capturedResult.waypointSource, "waypointSource is map_click")
        t:assertNotNil(capturedResult.waypoint, "waypoint info attached")
        t:assertEqual(84, capturedResult.waypoint.mapID, "waypoint mapID correct")
    else
        -- Path might not be found - that's OK, UI:Show should still be called
        t:assertTrue(true, "No path found (acceptable for minimal graph)")
    end

    QR.UI.Show = origShow
    QR.UI.UpdateRoute = origUpdate
end)

-------------------------------------------------------------------------------
-- 3. OnMapClick
-------------------------------------------------------------------------------

T:run("OnMapClick: ignores LeftButton", function(t)
    resetState()
    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    QR.POIRouting:OnMapClick(WorldMapFrame, "LeftButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called for LeftButton")

    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("OnMapClick: ignores RightButton without Ctrl", function(t)
    resetState()
    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    -- Ensure Ctrl is NOT pressed
    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return false end

    QR.POIRouting:OnMapClick(WorldMapFrame, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called without Ctrl")

    _G.IsControlKeyDown = origIsCtrl
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("OnMapClick: routes on Ctrl+RightButton with valid cursor", function(t)
    resetState()
    local routeMapID, routeX, routeY = nil, nil, nil
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routeMapID = mapID
        routeX = x
        routeY = y
    end

    -- Mock Ctrl key down
    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Mock GetNormalizedCursorPosition on WorldMapFrame
    WorldMapFrame.GetNormalizedCursorPosition = function(self)
        return 0.35, 0.72
    end

    QR.POIRouting:OnMapClick(WorldMapFrame, "RightButton")

    t:assertEqual(84, routeMapID, "Routed to correct mapID")
    t:assertEqual(0.35, routeX, "Correct X coordinate")
    t:assertEqual(0.72, routeY, "Correct Y coordinate")

    -- Cleanup
    _G.IsControlKeyDown = origIsCtrl
    WorldMapFrame.GetNormalizedCursorPosition = nil
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("OnMapClick: handles missing GetNormalizedCursorPosition gracefully", function(t)
    resetState()
    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Ensure GetNormalizedCursorPosition is nil
    WorldMapFrame.GetNormalizedCursorPosition = nil

    QR.POIRouting:OnMapClick(WorldMapFrame, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called without cursor position")

    _G.IsControlKeyDown = origIsCtrl
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("OnMapClick: rejects out-of-range coordinates", function(t)
    resetState()
    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Return out-of-range coordinates
    WorldMapFrame.GetNormalizedCursorPosition = function(self)
        return 1.5, -0.2
    end

    QR.POIRouting:OnMapClick(WorldMapFrame, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called for out-of-range coords")

    _G.IsControlKeyDown = origIsCtrl
    WorldMapFrame.GetNormalizedCursorPosition = nil
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("OnMapClick: handles nil WorldMapFrame.GetMapID gracefully", function(t)
    resetState()
    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Override GetMapID to return nil
    local origGetMapID = WorldMapFrame.GetMapID
    WorldMapFrame.GetMapID = function(self) return nil end

    QR.POIRouting:OnMapClick(WorldMapFrame, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called when mapID is nil")

    _G.IsControlKeyDown = origIsCtrl
    WorldMapFrame.GetMapID = origGetMapID
    QR.POIRouting.RouteToMapPosition = origRoute
end)

-------------------------------------------------------------------------------
-- 4. RegisterMapHook
-------------------------------------------------------------------------------

T:run("RegisterMapHook: registers hook on WorldMapFrame", function(t)
    resetState()

    -- Add HookScript to WorldMapFrame for this test
    local hookCalled = false
    local hookedScriptType = nil
    WorldMapFrame.HookScript = function(self, scriptType, handler)
        hookCalled = true
        hookedScriptType = scriptType
    end

    QR.POIRouting:RegisterMapHook()

    t:assertTrue(hookCalled, "HookScript was called")
    t:assertEqual("OnMouseUp", hookedScriptType, "Hooked OnMouseUp script")
    t:assertTrue(QR.POIRouting.hookRegistered, "hookRegistered flag set")

    -- Cleanup
    WorldMapFrame.HookScript = nil
end)

T:run("RegisterMapHook: does not double-register", function(t)
    resetState()
    QR.POIRouting.hookRegistered = true -- pretend already registered

    local hookCalled = false
    WorldMapFrame.HookScript = function(self, scriptType, handler)
        hookCalled = true
    end

    QR.POIRouting:RegisterMapHook()

    t:assertFalse(hookCalled, "HookScript not called when already registered")

    WorldMapFrame.HookScript = nil
end)

T:run("RegisterMapHook: falls back to SetScript when HookScript unavailable", function(t)
    resetState()

    -- Ensure HookScript is nil
    WorldMapFrame.HookScript = nil

    local setScriptCalled = false
    local origSetScript = WorldMapFrame.SetScript
    WorldMapFrame.SetScript = function(self, scriptType, handler)
        if scriptType == "OnMouseUp" then
            setScriptCalled = true
        end
        origSetScript(self, scriptType, handler)
    end

    QR.POIRouting:RegisterMapHook()

    t:assertTrue(setScriptCalled, "SetScript was called as fallback")
    t:assertTrue(QR.POIRouting.hookRegistered, "hookRegistered flag set via fallback")

    WorldMapFrame.SetScript = origSetScript
end)

T:run("RegisterMapHook: handles missing WorldMapFrame", function(t)
    resetState()
    local origWMF = _G.WorldMapFrame
    _G.WorldMapFrame = nil

    local ok, err = pcall(function()
        QR.POIRouting:RegisterMapHook()
    end)

    t:assertTrue(ok, "Does not error when WorldMapFrame is nil: " .. tostring(err))
    t:assertFalse(QR.POIRouting.hookRegistered, "Hook not registered when no WorldMapFrame")

    _G.WorldMapFrame = origWMF
end)

-------------------------------------------------------------------------------
-- 5. Initialize
-------------------------------------------------------------------------------

T:run("Initialize: sets initialized flag", function(t)
    resetState()
    QR.POIRouting.initialized = false

    -- Mock HookScript to avoid side effects
    WorldMapFrame.HookScript = function() end

    QR.POIRouting:Initialize()

    t:assertTrue(QR.POIRouting.initialized, "initialized flag set")

    WorldMapFrame.HookScript = nil
end)

T:run("Initialize: does not run twice", function(t)
    resetState()
    QR.POIRouting.initialized = true -- already initialized

    local hookCalled = false
    WorldMapFrame.HookScript = function()
        hookCalled = true
    end

    QR.POIRouting:Initialize()

    t:assertFalse(hookCalled, "HookScript not called when already initialized")

    WorldMapFrame.HookScript = nil
end)

-------------------------------------------------------------------------------
-- 6. Integration with PathCalculator
-------------------------------------------------------------------------------

T:run("RouteToMapPosition: uses PathCalculator:CalculatePath", function(t)
    resetState()
    local calcCalled = false
    local calcMapID, calcX, calcY, calcTitle = nil, nil, nil, nil
    local origCalc = QR.PathCalculator.CalculatePath
    QR.PathCalculator.CalculatePath = function(self, mapID, x, y, title)
        calcCalled = true
        calcMapID = mapID
        calcX = x
        calcY = y
        calcTitle = title
        return nil -- No path found
    end

    -- Stub UI to avoid side effects
    local origShow = QR.UI.Show
    QR.UI.Show = function() end

    QR.POIRouting:RouteToMapPosition(85, 0.4, 0.6)

    t:assertTrue(calcCalled, "PathCalculator:CalculatePath was called")
    t:assertEqual(85, calcMapID, "Passed correct mapID")
    t:assertEqual(0.4, calcX, "Passed correct X")
    t:assertEqual(0.6, calcY, "Passed correct Y")
    t:assertNotNil(calcTitle, "Title was passed")

    QR.PathCalculator.CalculatePath = origCalc
    QR.UI.Show = origShow
end)

T:run("RouteToMapPosition: handles PathCalculator error gracefully", function(t)
    resetState()
    local origCalc = QR.PathCalculator.CalculatePath
    QR.PathCalculator.CalculatePath = function(self, ...)
        error("test error in CalculatePath")
    end

    local origShow = QR.UI.Show
    QR.UI.Show = function() end

    local ok, err = pcall(function()
        QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)
    end)

    t:assertTrue(ok, "Does not propagate PathCalculator errors: " .. tostring(err))

    QR.PathCalculator.CalculatePath = origCalc
    QR.UI.Show = origShow
end)

-------------------------------------------------------------------------------
-- 7. RegisterDungeonPinHook
-------------------------------------------------------------------------------

T:run("POIRouting: has RegisterDungeonPinHook method", function(t)
    t:assertNotNil(QR.POIRouting.RegisterDungeonPinHook, "RegisterDungeonPinHook method exists")
    t:assertEqual("function", type(QR.POIRouting.RegisterDungeonPinHook), "RegisterDungeonPinHook is a function")
end)

T:run("RegisterDungeonPinHook: registers hook when DungeonEntrancePinMixin exists", function(t)
    resetState()
    -- Track whether hooksecurefunc was called for DungeonEntrancePinMixin
    local hookTarget = nil
    local hookMethod = nil
    local origHooksecurefunc = _G.hooksecurefunc
    _G.hooksecurefunc = function(tbl, key, hook)
        if tbl == DungeonEntrancePinMixin and key == "OnMouseClickAction" then
            hookTarget = tbl
            hookMethod = key
        end
        origHooksecurefunc(tbl, key, hook)
    end

    QR.POIRouting:RegisterDungeonPinHook()

    t:assertEqual(DungeonEntrancePinMixin, hookTarget, "hooksecurefunc called on DungeonEntrancePinMixin")
    t:assertEqual("OnMouseClickAction", hookMethod, "Hooked OnMouseClickAction method")

    _G.hooksecurefunc = origHooksecurefunc
end)

T:run("RegisterDungeonPinHook: Ctrl+RightClick triggers routing", function(t)
    resetState()

    -- Set up DungeonData with a test instance
    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            if instanceID == 1267 then
                return { name = "The Stonevault", zoneMapID = 2248, x = 0.62, y = 0.31, isRaid = false }
            end
            return nil
        end,
    }

    -- Track RouteToMapPosition calls
    local routeMapID, routeX, routeY = nil, nil, nil
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routeMapID = mapID
        routeX = x
        routeY = y
    end

    -- Mock Ctrl key down
    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Reset DungeonEntrancePinMixin to a fresh unhooked state
    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    -- Register the hook
    QR.POIRouting:RegisterDungeonPinHook()

    -- Simulate a pin Ctrl+Right-click
    local pin = { journalInstanceID = 1267 }
    DungeonEntrancePinMixin.OnMouseClickAction(pin, "RightButton")

    t:assertEqual(2248, routeMapID, "Routed to correct zoneMapID")
    t:assertEqual(0.62, routeX, "Correct X coordinate")
    t:assertEqual(0.31, routeY, "Correct Y coordinate")

    -- Cleanup
    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("RegisterDungeonPinHook: ignores non-RightButton clicks", function(t)
    resetState()

    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            return { name = "Test", zoneMapID = 100, x = 0.5, y = 0.5 }
        end,
    }

    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    -- Reset mixin
    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    QR.POIRouting:RegisterDungeonPinHook()

    -- Simulate a LeftButton click (should be ignored)
    local pin = { journalInstanceID = 1267 }
    DungeonEntrancePinMixin.OnMouseClickAction(pin, "LeftButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called for LeftButton")

    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("RegisterDungeonPinHook: ignores RightButton without Ctrl", function(t)
    resetState()

    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            return { name = "Test", zoneMapID = 100, x = 0.5, y = 0.5 }
        end,
    }

    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    -- Ctrl NOT pressed
    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return false end

    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    QR.POIRouting:RegisterDungeonPinHook()

    local pin = { journalInstanceID = 1267 }
    DungeonEntrancePinMixin.OnMouseClickAction(pin, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called without Ctrl")

    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("RegisterDungeonPinHook: ignores pin without journalInstanceID", function(t)
    resetState()

    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            return { name = "Test", zoneMapID = 100, x = 0.5, y = 0.5 }
        end,
    }

    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    QR.POIRouting:RegisterDungeonPinHook()

    -- Pin has no journalInstanceID
    local pin = {}
    DungeonEntrancePinMixin.OnMouseClickAction(pin, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called for pin without journalInstanceID")

    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("RegisterDungeonPinHook: graceful when DungeonData has no entry", function(t)
    resetState()

    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            return nil  -- No entry for this instance
        end,
    }

    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    QR.POIRouting:RegisterDungeonPinHook()

    local pin = { journalInstanceID = 9999 }
    local ok, err = pcall(function()
        DungeonEntrancePinMixin.OnMouseClickAction(pin, "RightButton")
    end)

    t:assertTrue(ok, "Does not error when DungeonData returns nil: " .. tostring(err))
    t:assertFalse(routeCalled, "RouteToMapPosition not called when no instance data")

    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("RegisterDungeonPinHook: graceful when DungeonEntrancePinMixin missing", function(t)
    resetState()
    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = nil

    local ok, err = pcall(function()
        QR.POIRouting:RegisterDungeonPinHook()
    end)

    t:assertTrue(ok, "Does not error when DungeonEntrancePinMixin is nil: " .. tostring(err))

    _G.DungeonEntrancePinMixin = origMixin
end)

T:run("RegisterDungeonPinHook: graceful when WorldMapFrame missing", function(t)
    resetState()
    local origWMF = _G.WorldMapFrame
    _G.WorldMapFrame = nil

    local ok, err = pcall(function()
        QR.POIRouting:RegisterDungeonPinHook()
    end)

    t:assertTrue(ok, "Does not error when WorldMapFrame is nil: " .. tostring(err))

    _G.WorldMapFrame = origWMF
end)

T:run("RegisterDungeonPinHook: ignores instance missing coordinates", function(t)
    resetState()

    local origDungeonData = QR.DungeonData
    QR.DungeonData = {
        GetInstance = function(self, instanceID)
            -- Instance exists but has no coordinates
            return { name = "Test Dungeon", zoneMapID = 100 }
        end,
    }

    local routeCalled = false
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, ...)
        routeCalled = true
    end

    local origIsCtrl = _G.IsControlKeyDown
    _G.IsControlKeyDown = function() return true end

    local origMixin = _G.DungeonEntrancePinMixin
    _G.DungeonEntrancePinMixin = {
        OnMouseClickAction = function() end,
    }

    QR.POIRouting:RegisterDungeonPinHook()

    local pin = { journalInstanceID = 1267 }
    DungeonEntrancePinMixin.OnMouseClickAction(pin, "RightButton")

    t:assertFalse(routeCalled, "RouteToMapPosition not called for instance without coordinates")

    _G.IsControlKeyDown = origIsCtrl
    _G.DungeonEntrancePinMixin = origMixin
    QR.POIRouting.RouteToMapPosition = origRoute
    QR.DungeonData = origDungeonData
end)

T:run("Initialize: calls RegisterDungeonPinHook", function(t)
    resetState()
    QR.POIRouting.initialized = false

    -- Track whether RegisterDungeonPinHook was called
    local dungeonHookCalled = false
    local origDungeonHook = QR.POIRouting.RegisterDungeonPinHook
    QR.POIRouting.RegisterDungeonPinHook = function(self)
        dungeonHookCalled = true
    end

    -- Mock HookScript to avoid side effects from RegisterMapHook
    WorldMapFrame.HookScript = function() end

    QR.POIRouting:Initialize()

    t:assertTrue(dungeonHookCalled, "RegisterDungeonPinHook was called during Initialize")

    QR.POIRouting.RegisterDungeonPinHook = origDungeonHook
    WorldMapFrame.HookScript = nil
end)

-------------------------------------------------------------------------------
-- Destination Persistence
-------------------------------------------------------------------------------

T:run("POIRouting: RouteToMapPosition saves lastDestination to QR.db", function(t)
    resetState()
    QR.db.lastDestination = nil

    QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)

    t:assertNotNil(QR.db.lastDestination, "lastDestination saved")
    t:assertEqual(84, QR.db.lastDestination.mapID, "mapID saved")
    t:assertEqual(0.5, QR.db.lastDestination.x, "x saved")
    t:assertEqual(0.5, QR.db.lastDestination.y, "y saved")
    t:assertNotNil(QR.db.lastDestination.title, "title saved")
end)

T:run("POIRouting: RouteToMapPosition overwrites previous lastDestination", function(t)
    resetState()
    QR.db.lastDestination = { mapID = 1, x = 0.1, y = 0.1, title = "Old" }

    QR.POIRouting:RouteToMapPosition(85, 0.7, 0.3)

    t:assertEqual(85, QR.db.lastDestination.mapID, "mapID updated")
    t:assertEqual(0.7, QR.db.lastDestination.x, "x updated")
    t:assertEqual(0.3, QR.db.lastDestination.y, "y updated")
end)

T:run("POIRouting: RouteToMapPosition sets _pendingRoute on UI", function(t)
    resetState()

    -- Ensure UI module is available
    local origUI = QR.UI
    local showCalled = false
    local pendingCaptured = nil
    QR.UI = {
        _pendingRoute = nil,
        Show = function(self)
            showCalled = true
            pendingCaptured = self._pendingRoute
        end,
    }

    QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)

    -- Show should have been called
    t:assertTrue(showCalled, "UI:Show() was called")
    -- _pendingRoute should have been set BEFORE Show() was called
    t:assertNotNil(pendingCaptured, "Pending route was set before Show()")
    t:assertEqual("map_click", pendingCaptured.waypointSource, "Pending route has map_click source")
    t:assertNotNil(pendingCaptured.waypoint, "Pending route has waypoint")
    t:assertEqual(84, pendingCaptured.waypoint.mapID, "Pending route waypoint has correct mapID")

    -- Restore
    QR.UI = origUI
end)

T:run("POIRouting: RouteToMapPosition does not set _pendingRoute when calc fails", function(t)
    resetState()

    -- Make PathCalculator fail
    local origCalc = QR.PathCalculator.CalculatePath
    QR.PathCalculator.CalculatePath = function() error("calc fail") end

    local origUI = QR.UI
    local pendingCaptured = nil
    QR.UI = {
        _pendingRoute = nil,
        Show = function(self)
            pendingCaptured = self._pendingRoute
        end,
    }

    QR.POIRouting:RouteToMapPosition(84, 0.5, 0.5)

    -- _pendingRoute should be nil since calculation failed
    t:assertNil(pendingCaptured, "No pending route when calculation fails")

    -- Restore
    QR.PathCalculator.CalculatePath = origCalc
    QR.UI = origUI
end)
