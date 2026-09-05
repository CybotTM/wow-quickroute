local T, QR = ...

T:run("Map click: projected coordinates reach calculator and saved destination together", function(t)
    local pc, poi, ui = QR.PathCalculator, QR.POIRouting, QR.UI
    local resolve, calc, show, db, pending = pc.ResolveMapPosition, pc.CalculatePath, ui.Show, QR.db, ui._pendingPOIRoute
    local destination
    QR.db = {}
    pc.ResolveMapPosition = function() return 84, 0.2, 0.3 end
    pc.CalculatePath = function(_, mapID, x, y) destination = {mapID,x,y}; return {steps={},totalTime=1} end
    ui.Show = function() end
    poi:RouteToMapPosition(12, 0.5, 0.8)
    t:assertEqual(84, destination[1], "zone map ID used")
    t:assertEqual(0.2, destination[2], "projected X used")
    t:assertEqual(0.3, QR.db.lastDestination.y, "projected Y persisted")
    pc.ResolveMapPosition, pc.CalculatePath, ui.Show, QR.db, ui._pendingPOIRoute = resolve, calc, show, db, pending
end)

T:run("Map click: unreachable selection clears stale pending route and locks requested target", function(t)
    local calc, show, db, pending = QR.PathCalculator.CalculatePath, QR.UI.Show, QR.db, QR.UI._pendingPOIRoute
    QR.db = {}
    QR.PathCalculator.CalculatePath = function() return nil end
    QR.UI.Show = function() end
    QR.UI._pendingPOIRoute = { waypoint = {mapID=85,x=0.1,y=0.1} }
    QR.POIRouting:RouteToMapPosition(84, 0.2, 0.3)
    t:assertNil(QR.UI._pendingPOIRoute, "stale route discarded")
    t:assertTrue(QR.db.destinationLocked, "requested target cannot fall back to unrelated quest")
    QR.PathCalculator.CalculatePath, QR.UI.Show, QR.db, QR.UI._pendingPOIRoute = calc, show, db, pending
end)
