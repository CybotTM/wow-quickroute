-- Explicit phase assumptions when retail cannot report a remote zone's state.
local ADDON_NAME, QR = ...
local ipairs, format = ipairs, string.format
QR.PhasePanel = { rows = {} }
local Panel = QR.PhasePanel

function Panel:Refresh()
    if not self.frame or not QR.TravelRequirements then return end
    for i, zone in ipairs(QR.TravelRequirements:GetPhaseOptions()) do
        local row = self.rows[i]
        if row then
            local phaseName = QR.L["PHASE_UNKNOWN"]
            for j, phase in ipairs(zone.phases) do
                if zone.currentArtID == phase.artID then phaseName = QR.L[j == 1 and "PHASE_PAST" or "PHASE_PRESENT"] end
            end
            local source = zone.source == "assumed" and QR.L["PHASE_ASSUMED"] or QR.L["PHASE_DETECTED"]
            row.label:SetText(zone.name .. "  ·  " .. (zone.known and format(source, phaseName) or phaseName))
            row.auto:SetText(QR.L["PHASE_AUTO"])
        end
    end
end

function Panel:Show()
    if InCombatLockdown() then QR:Print(QR.L["CANNOT_USE_IN_COMBAT"]); return end
    if not QR.TravelRequirements then return end
    if not self.frame then
        local L = QR.L
        local zones = QR.TravelRequirements:GetPhaseOptions()
        local frame = QR.CreateStandardWindow({name="QuickRoutePhaseFrame",title=L["PHASE_TITLE"],width=580,height=140+#zones*60})
        self.frame = frame
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetSize(548, 48)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["PHASE_HINT"])
        for i, zone in ipairs(zones) do
            local row = {}
            self.rows[i] = row
            row.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("TOPLEFT", 16, -100-(i-1)*60)
            row.label:SetWidth(548)
            row.label:SetJustifyH("LEFT")
            local function button(text, column, artID)
                local btn = QR.CreateModernButton(frame, 176, 24)
                btn:SetPoint("TOPLEFT", 16+column*186, -122-(i-1)*60)
                btn:SetText(text)
                btn:SetScript("OnClick", function()
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    if InCombatLockdown() then return end
                    QR.TravelRequirements:SetPhaseOverride(zone.mapID, artID)
                    self:Refresh()
                end)
                return btn
            end
            row.auto = button(L["PHASE_AUTO"], 0, nil)
            for j, phase in ipairs(zone.phases) do
                button(L[j == 1 and "PHASE_PAST" or "PHASE_PRESENT"], j, phase.artID)
            end
        end
        frame:SetScript("OnShow", function() self:Refresh() end)
    end
    QR.FitWindowScale(self.frame, QR.db and QR.db.windowScale or 1)
    self:Refresh()
    self.frame:Show()
end
