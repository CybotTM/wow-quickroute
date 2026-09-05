local T, QR = ...

T:run("MultiRoute: paste accepts percent coordinates, labels and both map syntaxes", function(t)
    local stops = QR.MultiRoute:ParseWaypoints("/way 84 1 100 First\n/way #85 50.5 0 Second")
    t:assertEqual(2, #stops, "two pasted destinations")
    t:assertEqual(0.01, stops[1].x, "one means one percent, not normalized one")
    t:assertEqual(1, stops[1].y, "100 percent reaches map edge")
    t:assertEqual(85, stops[2].mapID, "hash map ID parsed")
    t:assertEqual("Second", stops[2].title, "label preserved")
end)

T:run("MultiRoute: invalid or excessive lists fail atomically", function(t)
    for _, text in ipairs({"/way 84 -1 50", "/way 84 50 101", "/run dangerous()", "/way 84 20 30\ninvalid", string.rep("x", 8193)}) do
        local stops, err = QR.MultiRoute:ParseWaypoints(text)
        t:assertNil(stops, "invalid input yields no partial list")
        t:assertNotNil(err, "invalid input explains failure")
    end
    local stops = QR.MultiRoute:ParseWaypoints(string.rep("/way 84 50 50\n", 21))
    t:assertNil(stops, "21 destinations exceed bounded work")
end)

T:run("MultiRoute: imports all active TomTom maps excluding addon navigation pins", function(t)
    local saved = TomTom
    TomTom = { waypoints = {
        [84] = { a = {84, 0.2, 0.3, title = "First"}, b = {84, 0.4, 0.5, title = "QR: Walk", from = "QuickRoute"} },
        [85] = { c = {85, 0.6, 0.7, title = "Second"} },
    } }
    local stops = QR.MultiRoute:CollectTomTomWaypoints()
    t:assertEqual(2, #stops, "both maps imported without generated navigation pin")
    TomTom = saved
end)

T:run("MultiRoute: each leg chooses current fastest reachable stop and recalculates after completion", function(t)
    local mr = QR.MultiRoute
    local calc, show, db = QR.PathCalculator.CalculatePath, mr.DisplayRoute, QR.db
    local costs = { [84] = 80, [85] = 10, [86] = 25 }
    QR.db = {}
    QR.PathCalculator.CalculatePath = function(_, mapID)
        return { totalTime = costs[mapID], steps = {} }
    end
    local shown
    mr.DisplayRoute = function(_, stop) shown = stop.mapID end
    mr:Start({{mapID=84,x=0.5,y=0.5}, {mapID=85,x=0.5,y=0.5}, {mapID=86,x=0.5,y=0.5}}, true)
    t:assertEqual(85, shown, "first destination has lowest route time")
    costs[84], costs[86] = 5, 90
    mr:Next()
    t:assertEqual(84, shown, "second choice uses new costs after travel")
    t:assertEqual(1, mr.completed, "only completed stop is removed")
    t:assertEqual(2, #mr.stops, "remaining destinations retained")
    mr:Clear()
    QR.PathCalculator.CalculatePath, mr.DisplayRoute, QR.db = calc, show, db
end)

T:run("MultiRoute: unreachable destinations stay pending and preserve-order mode does not skip", function(t)
    local mr = QR.MultiRoute
    local calc, show = QR.PathCalculator.CalculatePath, mr.DisplayRoute
    QR.PathCalculator.CalculatePath = function(_, mapID)
        if mapID == 85 then return {totalTime=5,steps={}} end
    end
    mr.DisplayRoute = function() end
    mr:Start({{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, false)
    t:assertNil(mr.currentIndex, "unreachable first stop is not bypassed in input order")
    t:assertEqual(2, #mr.stops, "unreachable stop is never discarded")
    mr:Clear()
    QR.PathCalculator.CalculatePath, mr.DisplayRoute = calc, show
end)

T:run("MultiRoute: cancel invalidates asynchronous work", function(t)
    local mr = QR.MultiRoute
    local after, calc, show = C_Timer.After, QR.PathCalculator.CalculatePath, mr.DisplayRoute
    local callbacks, shown = {}, 0
    C_Timer.After = function(_, callback) callbacks[#callbacks+1] = callback end
    QR.PathCalculator.CalculatePath = function() return {totalTime=5,steps={}} end
    mr.DisplayRoute = function() shown = shown+1 end
    mr:Start({{mapID=84,x=0.5,y=0.5}}, true)
    mr:Clear()
    for _, callback in ipairs(callbacks) do callback() end
    t:assertEqual(0, shown, "cancelled calculation cannot overwrite current route")
    C_Timer.After, QR.PathCalculator.CalculatePath, mr.DisplayRoute = after, calc, show
end)

T:run("MultiRoute: trip window exposes paste controls and reuses its frame", function(t)
    local mr = QR.MultiRoute
    local combat = InCombatLockdown
    _G.InCombatLockdown = function() return false end
    local ok, err = pcall(mr.Show, mr)
    t:assertTrue(ok, "trip window opens: " .. tostring(err))
    t:assertNotNil(mr.editBox, "multiline paste editor is available")
    local frame = mr.frame
    mr:Show()
    t:assertEqual(frame, mr.frame, "reopening reuses the window")
    if frame then frame:Hide() end
    _G.InCombatLockdown = combat
end)
