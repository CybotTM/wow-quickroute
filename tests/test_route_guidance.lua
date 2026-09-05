-- A failed/new route must not retain actionable cards or delayed old waypoints.
local T, QR, MockWoW = ...

local function route(label)
    return { totalTime = 10, waypoint = { mapID = 84, x = .1, y = .2, title = label }, steps = {
        { type = "teleport", teleportID = 8690, sourceType = "spell", fromMapID = 84,
            destMapID = 85, destX = .1, destY = .2, to = label, time = 10 },
    } }
end

local function withState(callback)
    local ui, wp, db = QR.UI, QR.WaypointIntegration, QR.db
    local old = { after = C_Timer.After, get = wp.GetActiveWaypoint, calc = QR.PathCalculator.CalculatePath,
        set = wp.SetTomTomWaypoint, clear = wp.ClearTomTomWaypoints, update = ui.UpdateRoute,
        automatic = db.autoWaypoint, locked = db.destinationLocked, destination = db.lastDestination,
        pending = ui._pendingPOIRoute, calculating = ui.isCalculating,
        mainShown = QR.MainFrame.frame and QR.MainFrame.frame:IsShown(),
        contentShown = ui.frame and ui.frame:IsShown(), showing = QR.MainFrame.isShowing,
        restoreAfterCombat = QR.MainFrame.wasShowingBeforeCombat }
    if not QR.MainFrame.frame then QR.MainFrame:CreateFrame() end
    if not ui.frame then ui:CreateContent(QR.MainFrame:GetContentFrame("route")) end
    ui.frame:Show()
    QR.MainFrame.frame:Show()
    ui._pendingPOIRoute, ui.isCalculating = nil, false
    db.autoWaypoint, db.destinationLocked = false, false
    local ok, err = pcall(callback, ui, wp, db)
    ui:ClearStepLabels()
    C_Timer.After, wp.GetActiveWaypoint, QR.PathCalculator.CalculatePath = old.after, old.get, old.calc
    wp.SetTomTomWaypoint, wp.ClearTomTomWaypoints, ui.UpdateRoute = old.set, old.clear, old.update
    db.autoWaypoint, db.destinationLocked, db.lastDestination = old.automatic, old.locked, old.destination
    ui._pendingPOIRoute, ui.isCalculating = old.pending, old.calculating
    if old.mainShown then QR.MainFrame.frame:Show() else QR.MainFrame.frame:Hide() end
    if old.contentShown then ui.frame:Show() else ui.frame:Hide() end
    QR.MainFrame.isShowing, QR.MainFrame.wasShowingBeforeCombat = old.showing, old.restoreAfterCombat
    if not ok then error(err) end
end

T:run("Route guidance: waypoint detection failure removes old actionable cards and arrow", function(t)
    withState(function(ui, wp)
        ui:UpdateRoute(route("Old target"))
        local arrow = "Old target"
        wp.ClearTomTomWaypoints = function() arrow = nil end
        wp.GetActiveWaypoint = function() error("Unavailable waypoint API") end
        ui:RefreshRoute()
        t:assertEqual(0, #ui.stepLabels, "Failure leaves zero actionable cards")
        t:assertNil(arrow, "Failure removes the old QR arrow")
    end)
end)

T:run("Route guidance: no path and calculation errors remove previous navigation", function(t)
    withState(function(ui, wp, db)
        db.destinationLocked = true
        db.lastDestination = { mapID = 84, x = .8, y = .9, title = "New target" }
        for _, fails in ipairs({ false, true }) do
            ui:UpdateRoute(route("Old target"))
            local arrow = "Old target"
            wp.ClearTomTomWaypoints = function() arrow = nil end
            QR.PathCalculator.CalculatePath = function()
                if fails then error("Calculation failed") end
                return nil
            end
            ui:RefreshRoute()
            t:assertEqual(0, #ui.stepLabels, "Failed calculation leaves zero cards")
            t:assertNil(arrow, "Failed calculation removes the previous arrow")
        end
    end)
end)

T:run("Route guidance: a new manual route removes the previous QR arrow", function(t)
    withState(function(ui, wp)
        local arrow = "Old target"
        wp.ClearTomTomWaypoints = function() arrow = nil end
        ui:UpdateRoute(route("New target"))
        t:assertNil(arrow, "New route does not retain navigation to the old target")
    end)
end)

T:run("Route guidance: clearing a route cancels its deferred auto waypoint", function(t)
    withState(function(ui, wp, db)
        local queue, arrow = {}, nil
        C_Timer.After = function(_, cb) queue[#queue + 1] = cb end
        wp.SetTomTomWaypoint = function(_, _, _, _, label) arrow = label end
        wp.ClearTomTomWaypoints = function() arrow = nil end
        db.autoWaypoint = true
        ui:UpdateRoute(route("Old target"))
        ui:ClearRoute()
        for _, cb in ipairs(queue) do cb() end
        t:assertNil(arrow, "A cleared route cannot restore its arrow next frame")
    end)
end)

T:run("Route guidance: newer route supersedes an older deferred auto waypoint", function(t)
    withState(function(ui, wp, db)
        local queue, arrow = {}, nil
        C_Timer.After = function(_, cb) queue[#queue + 1] = cb end
        wp.SetTomTomWaypoint = function(_, _, _, _, label) arrow = label end
        wp.ClearTomTomWaypoints = function() arrow = nil end
        db.autoWaypoint = true
        ui:UpdateRoute(route("Old target"))
        ui:UpdateRoute(route("New target"))
        queue[1]()
        t:assertNil(arrow, "Superseded callback cannot publish the old target")
        queue[2]()
        t:assertEqual("New target", arrow, "Latest route publishes its target")
    end)
end)

T:run("Route guidance: closing the route window cancels pending auto guidance", function(t)
    withState(function(ui, wp, db)
        local queue, arrow = {}, nil
        C_Timer.After = function(_, cb) queue[#queue + 1] = cb end
        wp.SetTomTomWaypoint = function(_, _, _, _, label) arrow = label end
        wp.ClearTomTomWaypoints = function() arrow = nil end
        db.autoWaypoint = true
        ui:UpdateRoute(route("Old target"))
        QR.MainFrame:Hide()
        for _, cb in ipairs(queue) do cb() end
        t:assertNil(arrow, "Closed window cannot publish queued guidance")
    end)
end)

T:run("Route guidance: partial rendering failure removes unsafe stale cards", function(t)
    withState(function(ui, wp, db)
        db.destinationLocked = true
        db.lastDestination = { mapID = 84, x = .8, y = .9, title = "New target" }
        QR.PathCalculator.CalculatePath = function() return route("New target") end
        local original = ui.UpdateRoute
        ui.UpdateRoute = function(self, result)
            original(self, result)
            error("Rendering failed after first card")
        end
        local arrow = "Old target"
        wp.ClearTomTomWaypoints = function() arrow = nil end
        ui:RefreshRoute()
        t:assertEqual(0, #ui.stepLabels, "Partial render leaves no executable card")
        t:assertNil(arrow, "Partial render removes old navigation")
        t:assertFalse(ui.isCalculating, "Rendering failure releases refresh guard")
    end)
end)

T:run("Native guidance: clear only the pin still owned by QuickRoute", function(t)
    local wp = QR.WaypointIntegration
    local old = { get = C_Map.GetUserWaypoint, clear = C_Map.ClearUserWaypoint, tomtom = TomTom,
        secret = issecretvalue,
        native = wp._lastWpNative, mapID = wp._lastWpMapID, x = wp._lastWpX, y = wp._lastWpY,
        uids = wp._tomtomUIDs, uid = wp._lastWpUID, title = wp._lastWpTitle, time = wp._lastWpTime }
    local cleared = 0
    local function check(get, expected, label)
        wp._lastWpNative, wp._lastWpMapID, wp._lastWpX, wp._lastWpY = true, 84, .1, .2
        C_Map.GetUserWaypoint = get
        cleared = 0
        wp:ClearTomTomWaypoints()
        t:assertEqual(expected, cleared, label)
    end
    local ok, err = pcall(function()
        TomTom, wp._tomtomUIDs = nil, {}
        C_Map.ClearUserWaypoint = function() cleared = cleared + 1 end
        check(function() return { uiMapID = 84, position = { x = .1, y = .2 } } end, 1,
            "Matching QR pin is removed")
        check(function() return { uiMapID = 84, position = { x = .8, y = .9 } } end, 0,
            "Replacement user pin is preserved")
        check(function() return nil end, 0, "Unknown pin ownership does not delete")
        check(function() error("API unavailable") end, 0, "Failed ownership API does not delete")
        check(nil, 0, "Absent ownership API does not delete")
        local secret = {}
        _G.issecretvalue = function(value) return value == secret or (old.secret and old.secret(value)) end
        check(function() return { uiMapID = 84, position = { x = secret, y = .2 } } end, 0,
            "Secret pin coordinates do not authorize deletion")
    end)
    _G.issecretvalue = old.secret
    C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint, TomTom = old.get, old.clear, old.tomtom
    wp._lastWpNative, wp._lastWpMapID, wp._lastWpX, wp._lastWpY = old.native, old.mapID, old.x, old.y
    wp._tomtomUIDs, wp._lastWpUID, wp._lastWpTitle, wp._lastWpTime = old.uids, old.uid, old.title, old.time
    if not ok then error(err) end
end)

T:run("Native guidance: internal super-tracking events preserve endpoint while user changes unlock it", function(t)
    local wp = QR.WaypointIntegration
    local saved = {tomtom=TomTom, set=C_Map.SetUserWaypoint, get=C_Map.GetUserWaypoint,
        clear=C_Map.ClearUserWaypoint, super=C_SuperTrack.SetSuperTrackedUserWaypoint,
        create=UiMapPoint.CreateFromCoordinates, changed=wp.OnWaypointChanged,
        locked=QR.db.destinationLocked, setting=wp._settingWaypoint,
        hooks=wp.hooksRegistered, eventFrames={},
        native=wp._lastWpNative, mapID=wp._lastWpMapID, x=wp._lastWpX, y=wp._lastWpY,
        uids=wp._tomtomUIDs, uid=wp._lastWpUID, title=wp._lastWpTitle, time=wp._lastWpTime}
    for index, frame in ipairs(MockWoW.eventFrames) do saved.eventFrames[index]=frame end
    local pin, changes = nil, 0
    local ok, err = pcall(function()
        TomTom, wp._tomtomUIDs = nil, {}
        wp.hooksRegistered = false
        wp:RegisterHooks()
        wp._lastWpNative, wp._lastWpMapID, wp._settingWaypoint = nil, nil, false
        wp.OnWaypointChanged = function() changes=changes+1 end
        UiMapPoint.CreateFromCoordinates = function(mapID,x,y)return {uiMapID=mapID,position={x=x,y=y}}end
        C_Map.GetUserWaypoint = function()return pin end
        C_Map.SetUserWaypoint = function(point)pin=point;MockWoW:FireEvent("USER_WAYPOINT_UPDATED")end
        C_Map.ClearUserWaypoint = function()
            pin=nil
            MockWoW:FireEvent("USER_WAYPOINT_UPDATED")
            MockWoW:FireEvent("SUPER_TRACKING_CHANGED")
        end
        C_SuperTrack.SetSuperTrackedUserWaypoint = function()MockWoW:FireEvent("SUPER_TRACKING_CHANGED")end
        QR.db.destinationLocked = true
        wp:SetTomTomWaypoint(84,.2,.3,"Intermediate travel step")
        t:assertTrue(QR.db.destinationLocked,"Creating a QR native arrow preserves the selected final endpoint")
        t:assertEqual(0,changes,"Internal native tracking cannot queue a replacement route to the intermediate pin")
        wp:ClearTomTomWaypoints()
        t:assertTrue(QR.db.destinationLocked,"Removing QR native guidance also preserves the endpoint")
        t:assertEqual(0,changes,"Internal cleanup cannot queue a feedback refresh")
        MockWoW:FireEvent("SUPER_TRACKING_CHANGED")
        t:assertFalse(QR.db.destinationLocked,"An explicit user tracking change still unlocks the selected endpoint")
        t:assertEqual(1,changes,"User tracking change requests exactly one normal refresh")
    end)
    TomTom, C_Map.SetUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint = saved.tomtom,saved.set,saved.get,saved.clear
    C_SuperTrack.SetSuperTrackedUserWaypoint, UiMapPoint.CreateFromCoordinates = saved.super,saved.create
    wp.OnWaypointChanged, QR.db.destinationLocked, wp._settingWaypoint = saved.changed,saved.locked,saved.setting
    wp.hooksRegistered, MockWoW.eventFrames = saved.hooks,saved.eventFrames
    wp._lastWpNative,wp._lastWpMapID,wp._lastWpX,wp._lastWpY = saved.native,saved.mapID,saved.x,saved.y
    wp._tomtomUIDs,wp._lastWpUID,wp._lastWpTitle,wp._lastWpTime = saved.uids,saved.uid,saved.title,saved.time
    if not ok then error(err) end
end)

T:run("Native guidance: its intermediate pin cannot override a newly tracked quest", function(t)
    local wp = QR.WaypointIntegration
    local saved = {tomtom=TomTom, has=C_Map.HasUserWaypoint, get=C_Map.GetUserWaypoint,
        tracked=C_SuperTrack.GetSuperTrackedQuestID, quest=wp.GetQuestWaypoint,
        priority=QR.db.waypointPriority, native=wp._lastWpNative,mapID=wp._lastWpMapID,x=wp._lastWpX,y=wp._lastWpY}
    local point, questID = {uiMapID=84,position={x=.2,y=.3}}, 1
    local ok,err = pcall(function()
        TomTom=nil
        QR.db.waypointPriority="mappin"
        C_Map.HasUserWaypoint=function()return true end
        C_Map.GetUserWaypoint=function()return point end
        C_SuperTrack.GetSuperTrackedQuestID=function()return questID end
        wp.GetQuestWaypoint=function(_,id)return {mapID=id==1 and 85 or 86,x=.8,y=.9,title="Tracked quest"}end
        wp._lastWpNative,wp._lastWpMapID,wp._lastWpX,wp._lastWpY=true,84,.2,.3
        t:assertNil(wp:GetMapPing(),"QR's own first-step arrow is not advertised as a user destination")
        local target,source=wp:GetActiveWaypoint()
        t:assertEqual("quest",source,"Tracked quest wins over QR-generated intermediate pin")
        t:assertEqual(85,target and target.mapID,"Current quest target is preserved")
        questID=2
        target,source=wp:GetActiveWaypoint()
        t:assertEqual("quest",source,"Switching tracked quest keeps the quest as input source")
        t:assertEqual(86,target and target.mapID,"New quest takes effect while old guidance pin still exists")
        point={uiMapID=84,position={x=.7,y=.6}}
        target,source=wp:GetActiveWaypoint()
        t:assertEqual("mappin",source,"A replacement user pin still wins under map-pin priority")
        t:assertEqual(.7,target and target.x,"Replacement user pin coordinates are preserved")
    end)
    TomTom,C_Map.HasUserWaypoint,C_Map.GetUserWaypoint=saved.tomtom,saved.has,saved.get
    C_SuperTrack.GetSuperTrackedQuestID,wp.GetQuestWaypoint=saved.tracked,saved.quest
    QR.db.waypointPriority=saved.priority
    wp._lastWpNative,wp._lastWpMapID,wp._lastWpX,wp._lastWpY=saved.native,saved.mapID,saved.x,saved.y
    if not ok then error(err) end
end)
