QuickRouteDB = QuickRouteDB or {}
QuickRouteDB.useIconButtons = false
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
QR_DOC.OpenView(function()
  QR_DOC.HideOverlapping({"PlayerFrame","TargetFrame"})
  QR_DOC.RebuildGraph()
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(2133, 0.46, 0.50))
  SlashCmdList["QRWP"]("")
  local f = _G.QuickRouteMainFrame
  if f and f.SetHeight then f:SetHeight(f:GetHeight() * 0.55) end
  QR_DOC.Reposition()
end)
