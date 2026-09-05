local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
QR_DOC.OpenView(function()
  QR_DOC.HideOverlapping({"PlayerFrame", "TargetFrame", "ObjectiveTrackerFrame", "GameMenuFrame"})
  local QR = QR_DOC.FindQR()
  if QR and QR.PhasePanel then QR.PhasePanel:Show(); QR.PhasePanel.frame:SetScale(1.4) end
end)
