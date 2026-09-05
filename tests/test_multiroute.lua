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

T:run("MultiRoute: disconnected tour falls back to current fastest leg and replans after completion", function(t)
    local mr = QR.MultiRoute
    local calc, show, db = QR.PathCalculator.CalculatePath, mr.DisplayRoute, QR.db
    local from, context = QR.PathCalculator.CalculatePathFrom, QR.PathCalculator.CreateRouteContext
    QR.PathCalculator.CreateRouteContext = nil
    QR.PathCalculator.CalculatePathFrom = function() return nil end
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
    QR.PathCalculator.CalculatePathFrom, QR.PathCalculator.CreateRouteContext = from, context
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

T:run("MultiRoute: complete-tour order uses isolated origin costs and live executable leg", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local from, calc, show, db = pc.CalculatePathFrom, pc.CalculatePath, mr.DisplayRoute, QR.db
    local createContext = pc.CreateRouteContext
    local getMap, getPosition = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition
    C_Map.GetBestMapForUnit = function() return 84 end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return 0.5,0.5 end} end
    QR.db = {}
    local matrix = {[84]={[85]=1,[86]=2,[87]=4},[85]={[86]=100,[87]=100},[86]={[85]=1,[87]=1},[87]={[85]=1,[86]=1}}
    local calls, contexts, liveDestination, shown = 0, 0
    pc.CalculatePathFrom = function() error("Tour must reuse its context") end
    pc.CreateRouteContext = function(_, options)
        contexts = contexts + 1
        t:assertTrue(options.excludeCooldowns, "tour matrix excludes consumable teleport assumptions")
        return {CalculatePathFrom=function(_, a, _, _, b)
            calls = calls + 1
            return {totalTime=matrix[a][b],steps={}}
        end}
    end
    pc.CalculatePath = function(_, mapID)
        liveDestination = mapID
        return {totalTime=0.75,steps={{type="teleport"}}}
    end
    mr.DisplayRoute = function(_, stop, result) shown = {stop=stop,result=result} end
    mr:Start({{mapID=85,x=0.5,y=0.5},{mapID=86,x=0.5,y=0.5},{mapID=87,x=0.5,y=0.5}}, true)
    t:assertEqual(9, calls, "three-stop tour compares nine directed legs")
    t:assertEqual(1, contexts, "all directed comparisons reuse one isolated graph")
    t:assertEqual(86, shown.stop.mapID, "whole-tour optimum starts at second-nearest destination")
    t:assertEqual(86, liveDestination, "displayed leg recalculated from actual player state")
    t:assertEqual(0.75, shown.result.totalTime, "live teleport time replaces reusable estimate")
    t:assertEqual(4, mr.planCost, "separate whole-tour estimate preserved")
    t:assertEqual(85, mr.stops[3].mapID, "expensive outgoing destination placed last")
    mr:Clear()
    pc.CalculatePathFrom, pc.CalculatePath, mr.DisplayRoute, QR.db = from, calc, show, db
    pc.CreateRouteContext = createContext
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = getMap, getPosition
end)

T:run("MultiRoute: saved trips restore per character without executing navigation", function(t)
    local mr, guid, db = QR.MultiRoute, UnitGUID, QR.db
    UnitGUID = function() return "Player-trip-test" end
    QR.db = { multiRouteTrips = {
        ["Player-trip-test"]={stops={{mapID=84,x=0.5,y=0.6,title="Saved"}},completed=2,optimize=true},
        ["Player-other"]={stops={{mapID=85,x=0.2,y=0.3}},completed=0},
    } }
    mr:Initialize()
    t:assertEqual(84, mr.stops[1].mapID, "restores only current character's trip")
    t:assertEqual(2, mr.completed, "retains completed count")
    t:assertFalse(mr.busy, "login does not launch unattended routing")
    t:assertNil(mr.currentIndex, "resume does not mark an unvisited stop completed")
    mr:Clear()
    t:assertNotNil(QR.db.multiRouteTrips["Player-other"], "clearing trip preserves another character")
    QR.db.multiRouteTrips["Player-trip-test"]={stops={{mapID=84,x=math.huge,y=0.6}}}
    mr:Initialize()
    t:assertEqual(0, #mr.stops, "invalid saved coordinate cannot restore a route")
    t:assertNil(QR.db.multiRouteTrips["Player-trip-test"], "invalid record removed")
    UnitGUID, QR.db = guid, db
end)

T:run("MultiRoute: moving during live-next fallback restarts every candidate", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local saved = {after=C_Timer.After, calc=pc.CalculatePath, show=mr.DisplayRoute,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition, db=QR.db}
    local pending, origin, shown, calls = {}, 84, nil, 0
    QR.db = {}
    C_Map.GetBestMapForUnit = function() return origin end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return 0.5,0.5 end} end
    C_Timer.After = function(_, callback) pending[#pending+1] = callback end
    pc.CalculatePath = function(_, mapID)
        calls = calls + 1
        return {totalTime=mapID == origin and 5 or 95,steps={}}
    end
    mr.DisplayRoute = function(_, stop) shown = stop.mapID end
    local ok, err = pcall(function()
        mr.stops, mr.total, mr.fastestNext = {{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, 2, true
        mr:SelectNext(true)
        pending[1]()
        origin = 85
        local index = 2
        while pending[index] do pending[index](); index = index + 1 end
        t:assertEqual(85, shown, "Movement recomputes ranking and selects new origin's closest stop")
        t:assertEqual(4, calls, "Old first candidate discarded, two candidates compared, winning leg refreshed")
        t:assertEqual(2, #mr.stops, "Movement never discards an unvisited destination")
    end)
    mr:Clear()
    C_Timer.After, pc.CalculatePath, mr.DisplayRoute = saved.after, saved.calc, saved.show
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, QR.db = saved.map, saved.position, saved.db
    if not ok then error(err) end
end)

T:run("MultiRoute: repeated movement stops bounded selection without publishing a stale leg", function(t)
    local mr, pc = QR.MultiRoute, QR.PathCalculator
    local saved = {after=C_Timer.After, calc=pc.CalculatePath, show=mr.DisplayRoute,
        map=C_Map.GetBestMapForUnit, position=C_Map.GetPlayerMapPosition, db=QR.db}
    local pending, x, published, calls = {}, 0.3, 0, 0
    QR.db = {}
    C_Map.GetBestMapForUnit = function() return 84 end
    C_Map.GetPlayerMapPosition = function() return {GetXY=function() return x,0.5 end} end
    C_Timer.After = function(_, callback) pending[#pending+1] = callback end
    pc.CalculatePath = function() calls = calls + 1; return {totalTime=5,steps={}} end
    mr.DisplayRoute = function() published = published + 1 end
    local ok, err = pcall(function()
        mr.stops, mr.total, mr.fastestNext = {{mapID=84,x=0.5,y=0.5},{mapID=85,x=0.5,y=0.5}}, 2, true
        mr:SelectNext(true)
        for index=1,10 do
            if not pending[index] then break end
            x = x + 0.02
            pending[index]()
        end
        t:assertEqual(0, published, "No stale winner is displayed during sustained movement")
        t:assertEqual(2, calls, "Only two restart calculations are allowed")
        t:assertFalse(mr.busy, "Aborted selection releases busy state")
        t:assertEqual(QR.L["MULTI_POSITION_CHANGED"], mr.message, "Status explains how to retry")
        t:assertEqual(2, #mr.stops, "Pending stops survive a bounded abort")
    end)
    mr:Clear()
    C_Timer.After, pc.CalculatePath, mr.DisplayRoute = saved.after, saved.calc, saved.show
    C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, QR.db = saved.map, saved.position, saved.db
    if not ok then error(err) end
end)
