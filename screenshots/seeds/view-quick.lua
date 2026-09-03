if QuickRouteDB then QuickRouteDB.availabilityFilter = "usable"; QuickRouteDB.groupByDestination = true end
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
QR_DOC.OpenView(function() QR_DOC.HideOverlapping({"ObjectiveTrackerFrame", "PlayerFrame", "MinimapCluster"}); local h = QRMinimapButton and QRMinimapButton:GetScript("OnClick"); if h then h(QRMinimapButton, "MiddleButton") end end)
