if QuickRouteDB then QuickRouteDB.availabilityFilter = "usable"; QuickRouteDB.groupByDestination = true end
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
QR_DOC.OpenView(function() QR_DOC.HideOverlapping({"PlayerFrame", "TargetFrame", "ObjectiveTrackerFrame"}); SlashCmdList["QRTELEPORTS"]("") end)
