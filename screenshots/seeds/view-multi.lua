-- Render the real trip UI with a pasted three-stop route, before starting it.
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
QR_DOC.OpenView(function()
  QR_DOC.HideOverlapping({"PlayerFrame", "TargetFrame", "ObjectiveTrackerFrame", "GameMenuFrame"})
  SlashCmdList["QRMULTI"]("")
  local QR = QR_DOC.FindQR()
  if QR and QR.MultiRoute and QR.MultiRoute.editBox then
    QR.MultiRoute.editBox:SetText("/way #84 62.0 72.0 Stormwind Portal Room\n/way #87 36.6 3.6 Ironforge\n/way #84 52.2 45.4 Stormwind Bank")
    QR.MultiRoute.frame:SetScale(1.4)
  end
end)
