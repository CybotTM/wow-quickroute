-------------------------------------------------------------------------------
-- test_currency_popup_button.lua
-- The "QuickRoute to vendor" button in the options popup of Blizzard's
-- currency window, and the missingVendors observation for a currency that no
-- known vendor accepts.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local CPB = QR.CurrencyPopupButton
local SR = QR.ServiceRouter
local DC = QR.DataCollection

local KNOWN, UNKNOWN, SOLD = 3316, 4242, 3418

-- A stand-in for Blizzard_TokenUI: TokenFrame:UpdatePopup(entry) sizes the
-- popup afresh on every call, as the real one does (CalculateBestHeight).
local function makeTokenUI(transferShown)
    local popup = CreateFrame("Frame", "TokenFramePopup")
    popup:SetHeight(100)
    popup.CurrencyTransferToggleButton = CreateFrame("Button", nil, popup)
    if transferShown then popup.CurrencyTransferToggleButton:Show() else popup.CurrencyTransferToggleButton:Hide() end
    local tokenFrame = CreateFrame("Frame", "TokenFrame")
    function tokenFrame:UpdatePopup(entry)
        popup:SetHeight(popup.CurrencyTransferToggleButton:IsShown() and 135 or 100)
        self.lastEntry = entry
    end
    return tokenFrame, popup
end

local function entry(currencyID)
    return { elementData = { currencyID = currencyID, discovered = true } }
end

local function withPopup(opts, fn)
    local saved = {
        tokenFrame = _G.TokenFrame, popup = _G.TokenFramePopup,
        db = QR.db, getLocations = SR.GetCurrencyLocations, route = SR.RouteToCurrency,
        getSellers = SR.GetCurrencySellers, kind = CPB.kind,
        currency = _G.C_CurrencyInfo, print = QR.Print,
        button = CPB.button, initialized = CPB.initialized, hooked = CPB.hooked, currencyID = CPB.currencyID,
        unsaved = DC.unsavedCount,
    }
    QR.db = { dataCollection = opts.collection ~= false, currencyVendors = {} }
    CPB.button, CPB.initialized, CPB.hooked, CPB.currencyID = nil, false, false, nil
    SR.GetCurrencyLocations = function(_, currencyID)
        if currencyID == KNOWN then
            return { { mapID = 2339, x = 0.5, y = 0.5, npcID = 1, name = "Vendor" } }
        end
        return {}
    end
    SR.GetCurrencySellers = function(_, currencyID)
        if currencyID == SOLD then
            return { { mapID = 2393, x = 0.4, y = 0.6, npcID = 2, name = "Seller", source = "merchant" } }
        end
        return {}
    end
    _G.C_CurrencyInfo = { GetCurrencyInfo = function(id)
        return { name = id == UNKNOWN and "Mystery Tokens" or "Voidlight Marl" }
    end }
    QR.Print = function() end
    local tokenFrame, popup = nil, nil
    if opts.loaded ~= false then
        tokenFrame, popup = makeTokenUI(opts.transfer)
        _G.TokenFrame, _G.TokenFramePopup = tokenFrame, popup
    else
        _G.TokenFrame, _G.TokenFramePopup = nil, nil
    end
    local ok, err = pcall(fn, tokenFrame, popup)
    _G.TokenFrame, _G.TokenFramePopup = saved.tokenFrame, saved.popup
    QR.db, SR.GetCurrencyLocations, SR.RouteToCurrency = saved.db, saved.getLocations, saved.route
    SR.GetCurrencySellers, CPB.kind = saved.getSellers, saved.kind
    _G.C_CurrencyInfo, QR.Print = saved.currency, saved.print
    CPB.button, CPB.initialized, CPB.hooked, CPB.currencyID =
        saved.button, saved.initialized, saved.hooked, saved.currencyID
    DC.unsavedCount = saved.unsaved
    if not ok then error(err, 0) end
end

local function missing()
    return QR.db.observations and QR.db.observations.missingVendors or {}
end

T:run("CurrencyPopupButton: a currency with a known vendor gets the button", function(t)
    withPopup({ transfer = true }, function(tokenFrame, popup)
        CPB:Initialize()
        tokenFrame:UpdatePopup(entry(KNOWN))
        t:assertNotNil(CPB.button, "the button is created")
        t:assertTrue(CPB.button:IsShown(), "and shown")
        t:assertEqual(135 + CPB.EXTRA_HEIGHT, popup:GetHeight(), "the popup grows by the button's row")
        -- The mock's GetPoint reports the parent, so read the stored anchor.
        local point, relativeTo = unpack(CPB.button._points[1] or {})
        t:assertEqual("BOTTOMLEFT", point, "anchored by its bottom left")
        t:assertEqual(popup.CurrencyTransferToggleButton, relativeTo, "above the transfer button")
        t:assertEqual(0, #missing(), "a known currency is not filed as missing")

        tokenFrame:UpdatePopup(entry(KNOWN))
        t:assertEqual(135 + CPB.EXTRA_HEIGHT, popup:GetHeight(), "a second update does not grow it again")

        local routed
        SR.RouteToCurrency = function(_, query) routed = query end
        CPB.button:GetScript("OnClick")(CPB.button)
        t:assertEqual(KNOWN, routed, "a click routes to a vendor of that currency")
    end)
end)

T:run("CurrencyPopupButton: without the transfer button it sits at the bottom", function(t)
    withPopup({ transfer = false }, function(tokenFrame, popup)
        CPB:Initialize()
        tokenFrame:UpdatePopup(entry(KNOWN))
        -- The mock's GetPoint reports the parent, so read the stored anchor.
        local point, relativeTo = unpack(CPB.button._points[1] or {})
        t:assertEqual(popup, relativeTo, "anchored to the popup itself")
        t:assertEqual(100 + CPB.EXTRA_HEIGHT, popup:GetHeight(), "the popup grows by the button's row")
    end)
end)

T:run("CurrencyPopupButton: a currency without a vendor hides the button and is filed", function(t)
    withPopup({ transfer = true }, function(tokenFrame, popup)
        CPB:Initialize()
        tokenFrame:UpdatePopup(entry(KNOWN))
        tokenFrame:UpdatePopup(entry(UNKNOWN))
        t:assertFalse(CPB.button:IsShown(), "the button is hidden")
        t:assertEqual(135, popup:GetHeight(), "the popup keeps Blizzard's height")
        local list = missing()
        t:assertEqual(1, #list, "one entry for the currency")
        local e = list[1] or {}
        t:assertEqual(UNKNOWN, e.currencyID, "names the currency")
        t:assertEqual("Mystery Tokens", e.name, "with its name")
        t:assertEqual("popup", e.source, "and where it was seen")
        t:assertEqual(1, e.count, "seen once")

        tokenFrame:UpdatePopup(entry(UNKNOWN))
        t:assertEqual(1, #missing(), "a repeat adds no entry")
        t:assertEqual(2, (missing()[1] or {}).count, "it raises the count")
    end)
end)

T:run("CurrencyPopupButton: nothing is filed while the travel observations are off", function(t)
    withPopup({ transfer = true, collection = false }, function(tokenFrame)
        CPB:Initialize()
        tokenFrame:UpdatePopup(entry(UNKNOWN))
        t:assertNil(QR.db.observations, "no observations are written")
    end)
end)

T:run("CurrencyPopupButton: hooks the currency window once Blizzard_TokenUI loads", function(t)
    withPopup({ loaded = false }, function()
        CPB:Initialize()
        t:assertFalse(CPB.hooked, "nothing to hook before the window exists")
        local tokenFrame = makeTokenUI(true)
        _G.TokenFrame = tokenFrame
        MockWoW:FireEvent("ADDON_LOADED", "Blizzard_TokenUI")
        t:assertTrue(CPB.hooked, "hooked on ADDON_LOADED")
        tokenFrame:UpdatePopup(entry(KNOWN))
        t:assertTrue(CPB.button and CPB.button:IsShown(), "and the button appears")
    end)
end)

T:run("ServiceRouter: a route request for a currency without a vendor is filed", function(t)
    withPopup({ transfer = true }, function()
        t:assertFalse(SR:RouteToCurrency(UNKNOWN), "the request fails")
        local e = missing()[1] or {}
        t:assertEqual(UNKNOWN, e.currencyID, "the currency is filed")
        t:assertEqual("route", e.source, "from the route request")
        SR:RouteToCurrency("no such currency")
        t:assertEqual(1, #missing(), "an unknown name names no currency and files nothing")
    end)
end)

-- The owner's case of 2026-11-16: "Nebulöser Leerenkern" has no vendor that
-- takes it, but a merchant sells it.
T:run("CurrencyPopupButton: a currency no vendor takes but a merchant sells gets the seller button", function(t)
    withPopup({ transfer = true }, function(tokenFrame, popup)
        CPB:Initialize()
        tokenFrame:UpdatePopup(entry(SOLD))
        t:assertTrue(CPB.button and CPB.button:IsShown(), "the button is shown")
        t:assertEqual(QR.L["CURRENCY_POPUP_SELLER"], CPB.button:GetText(), "labelled for the seller")
        t:assertEqual(135 + CPB.EXTRA_HEIGHT, popup:GetHeight(), "the popup grows by the button's row")
        t:assertEqual(SOLD, (missing()[1] or {}).currencyID, "still filed: nowhere known to spend it")

        local routed, kind
        SR.RouteToCurrency = function(_, query, k) routed, kind = query, k end
        CPB.button:GetScript("OnClick")(CPB.button)
        t:assertEqual(SOLD, routed, "a click routes for that currency")
        t:assertEqual("seller", kind, "to a merchant selling it")

        tokenFrame:UpdatePopup(entry(KNOWN))
        t:assertEqual(QR.L["CURRENCY_POPUP_ROUTE"], CPB.button:GetText(), "a currency with a vendor gets the vendor label back")
        CPB.button:GetScript("OnClick")(CPB.button)
        t:assertNil(kind, "and routes to an accepting vendor")
    end)
end)
