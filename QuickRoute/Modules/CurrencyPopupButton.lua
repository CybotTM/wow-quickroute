-- CurrencyPopupButton.lua
-- Adds a "QuickRoute to vendor" button to the options popup of Blizzard's
-- currency window (TokenFramePopup, opened by a click on a currency row).
--
-- The button is shown only when a vendor that accepts the currency is known
-- (an observed merchant or the destination catalogue). A currency without one
-- is filed in the travel observations (DataCollection list missingVendors), so
-- the gap can be curated later.
local ADDON_NAME, QR = ...

local CreateFrame = CreateFrame
local pcall, type = pcall, type

QR.CurrencyPopupButton = {
    button = nil,
    initialized = false,
    hooked = false,
    currencyID = nil,
}

local CPB = QR.CurrencyPopupButton

-- Height the popup grows by while the button is shown.
CPB.EXTRA_HEIGHT = 28
local BUTTON_WIDTH, BUTTON_HEIGHT = 150, 22

local function HasVendor(currencyID)
    local SR = QR.ServiceRouter
    if not (SR and SR.GetCurrencyLocations) then return false end
    local ok, locations = pcall(SR.GetCurrencyLocations, SR, currencyID)
    return ok and type(locations) == "table" and #locations > 0
end

function CPB:CreateButton(popup)
    if self.button then return self.button end
    local L = QR.L
    local btn = QR.CreateModernButton(popup, BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetText(L["CURRENCY_POPUP_ROUTE"])
    btn:Hide()
    btn:SetScript("OnClick", function()
        local currencyID = CPB.currencyID
        if currencyID and QR.ServiceRouter then
            QR.ServiceRouter:RouteToCurrency(currencyID)
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["CURRENCY_POPUP_ROUTE"], 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["CURRENCY_POPUP_ROUTE_TT"], 0.7, 0.7, 0.7, true)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip_Hide() end)
    QR.AddMicroIcon(btn, 16)
    self.button = btn
    return btn
end

--- Runs after TokenFrame:UpdatePopup(entry), which has just sized the popup
-- for the currency of that row.
function CPB:Update(entry)
    local popup = _G.TokenFramePopup
    if not popup then return end
    local data = type(entry) == "table" and entry.elementData or nil
    local currencyID = type(data) == "table" and data.currencyID or nil
    if issecretvalue and issecretvalue(currencyID) then currencyID = nil end
    if type(currencyID) ~= "number" or currencyID <= 0 then
        self.currencyID = nil
        if self.button then self.button:Hide() end
        return
    end
    self.currencyID = currencyID
    if not HasVendor(currencyID) then
        if self.button then self.button:Hide() end
        if QR.DataCollection then
            pcall(QR.DataCollection.RecordMissingVendor, QR.DataCollection, currencyID, "popup")
        end
        return
    end
    local btn = self:CreateButton(popup)
    btn:ClearAllPoints()
    local transfer = popup.CurrencyTransferToggleButton
    if transfer and transfer:IsShown() then
        -- Between the checkboxes and the transfer button, which is anchored
        -- to the bottom of the popup and moves down as the popup grows.
        btn:SetPoint("BOTTOMLEFT", transfer, "TOPLEFT", 0, 4)
    else
        btn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 23, 20)
    end
    -- UpdatePopup sets the height afresh on every call, so this never adds up.
    popup:SetHeight(popup:GetHeight() + self.EXTRA_HEIGHT)
    btn:Show()
end

function CPB:Hook()
    if self.hooked then return true end
    local tokenFrame = _G.TokenFrame
    if not (tokenFrame and _G.TokenFramePopup and type(tokenFrame.UpdatePopup) == "function") then
        return false
    end
    hooksecurefunc(tokenFrame, "UpdatePopup", function(_, entry)
        local ok, err = pcall(CPB.Update, CPB, entry)
        if not ok then QR:Debug("CurrencyPopupButton: " .. tostring(err)) end
    end)
    self.hooked = true
    return true
end

function CPB:Initialize()
    if self.initialized then return end
    self.initialized = true
    if self:Hook() then return end
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", function(frame, _, addonName)
        if addonName == "Blizzard_TokenUI" and CPB:Hook() then
            frame:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
