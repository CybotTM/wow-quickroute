-------------------------------------------------------------------------------
-- test_currency_pois.lua
-- Places that take a currency without being merchants (Data/CurrencyPOIs.lua).
-- The owner's case of 2026-11-16: "Händlerdevisen" (Trader's Tender, 2032)
-- had no "QuickRoute to vendor" button, because the Trading Post is no merchant.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local SR = QR.ServiceRouter
local TENDER = 2032

local function asFaction(faction, fn)
    local saved = { faction = MockWoW.config.playerFaction, db = QR.db }
    MockWoW.config.playerFaction = faction
    QR.PlayerInfo:InvalidateCache()
    QR.db = { currencyVendors = {} }
    local ok, err = pcall(fn)
    MockWoW.config.playerFaction, QR.db = saved.faction, saved.db
    QR.PlayerInfo:InvalidateCache()
    if not ok then error(err, 0) end
end

local function maps(locations)
    local found = {}
    for _, loc in ipairs(locations) do found[loc.mapID] = loc end
    return found
end

T:run("CurrencyPOIs: four Trading Posts take Trader's Tender", function(t)
    local count = 0
    for _, poi in ipairs(QR.CurrencyPOIs) do
        if poi.currencyID == TENDER then
            count = count + 1
            t:assertTrue(poi.x > 0 and poi.x < 1 and poi.y > 0 and poi.y < 1,
                "AreaPOI " .. poi.areaPoiID .. " lies inside its map")
            t:assertEqual("TRADING_POST", poi.nameKey, "named as the Trading Post")
        end
    end
    t:assertEqual(4, count, "Stormwind, Orgrimmar, Dornogal and Silvermoon")
end)

T:run("CurrencyPOIs: an Alliance character is offered its own city and the shared ones", function(t)
    asFaction("Alliance", function()
        local found = maps(SR:GetCurrencyLocations(TENDER))
        t:assertNotNil(found[84], "Stormwind")
        t:assertNil(found[85], "not Orgrimmar")
        t:assertNotNil(found[2339], "Dornogal")
        t:assertNotNil(found[2393], "Silvermoon")
        t:assertEqual(QR.L["TRADING_POST"], found[84] and found[84].name, "named in the client language")
        t:assertEqual("catalogue", found[84] and found[84].source, "a reference location")
    end)
end)

T:run("CurrencyPOIs: a Horde character is offered Orgrimmar, not Stormwind", function(t)
    asFaction("Horde", function()
        local found = maps(SR:GetCurrencyLocations(TENDER))
        t:assertNotNil(found[85], "Orgrimmar")
        t:assertNil(found[84], "not Stormwind")
    end)
end)

T:run("CurrencyPOIs: Trader's Tender is searchable and routable", function(t)
    asFaction("Alliance", function()
        local listed = false
        for _, currency in ipairs(SR:GetKnownCurrencies(true)) do
            if currency.currencyID == TENDER then listed = true end
        end
        t:assertTrue(listed, "the currency list includes Trader's Tender")
        t:assertEqual(0, #SR:GetCurrencyLocations(9999), "an unrelated currency gains no Trading Post")
        local savedAfter, savedPrint = C_Timer.After, QR.Print
        C_Timer.After = function() end
        QR.Print = function() end
        local ok, result = pcall(SR.RouteToCurrency, SR, TENDER)
        C_Timer.After, QR.Print = savedAfter, savedPrint
        if not ok then error(result, 0) end
        t:assertTrue(result, "a route request starts the vendor search")
    end)
end)
