local T, QR, MockWoW = ...

local function withMerchant(fn)
    local saved = { db = QR.db, UnitGUID = _G.UnitGUID, UnitName = _G.UnitName,
        merchant = _G.C_MerchantFrame, currency = _G.C_CurrencyInfo, time = _G.time,
        map = C_Map, pc = QR.PathCalculator, faction = MockWoW.config.playerFaction }
    QR.db = { currencyVendors = {} }
    _G.UnitGUID = function(unit)
        return unit == "player" and "Player-1-A" or "Creature-0-1-2-3-12345-0001"
    end
    _G.UnitName = function() return "Token Merchant" end
    _G.C_MerchantFrame = { GetMerchantCurrencies = function() return { 2003, 3008 } end }
    _G.C_CurrencyInfo = { GetCurrencyInfo = function(id)
        return { name = id == 2003 and "Dragon Isles Supplies" or "Valorstones" }
    end }
    _G.time = function() return 100000 end
    C_Map = { GetBestMapForUnit = function() return 84 end,
        GetPlayerMapPosition = function() return { x = 0.3, y = 0.7 } end }
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local ok, err = pcall(fn)
    QR.db, _G.UnitGUID, _G.UnitName = saved.db, saved.UnitGUID, saved.UnitName
    _G.C_MerchantFrame, _G.C_CurrencyInfo, _G.time = saved.merchant, saved.currency, saved.time
    C_Map, QR.PathCalculator = saved.map, saved.pc
    MockWoW.config.playerFaction = saved.faction
    QR.PlayerInfo:InvalidateCache()
    if not ok then error(err) end
end

T:run("Currency vendors: merchant observations retain accepted currencies and position", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        local vendors = QR.ServiceRouter:GetCurrencyLocations(2003)
        t:assertEqual(1, #vendors, "One observed vendor accepts supplies")
        if vendors[1] then
            t:assertEqual(84, vendors[1].mapID, "Observed map is Stormwind")
            t:assertEqual(0.3, vendors[1].x, "Observed interaction x is retained")
            t:assertEqual("Token Merchant", vendors[1].name, "Merchant name retained")
        end
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(9999), "Unknown currency has no invented vendors")
        t:assertEqual(2, #QR.ServiceRouter:GetKnownCurrencies(), "Two accepted currencies are searchable")
    end)
end)

T:run("Currency vendors: observations cannot grant another character access", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        _G.UnitGUID = function() return "Player-1-B" end
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(2003), "Other character sees no unverified vendors")
    end)
end)

T:run("Currency vendors: invalid coordinates and non-creature merchants are discarded", function(t)
    withMerchant(function()
        C_Map.GetPlayerMapPosition = function() return { x = 0 / 0, y = 0.7 } end
        QR.ServiceRouter:ObserveMerchant()
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(2003), "NaN position is not saved")
        C_Map.GetPlayerMapPosition = function() return { x = 0.3, y = 0.7 } end
        _G.UnitGUID = function(unit) return unit == "player" and "Player-1-A" or "Player-1-B" end
        QR.ServiceRouter:ObserveMerchant()
        t:assertEqual(0, #QR.ServiceRouter:GetKnownCurrencies(), "Player mount vendor is not stored as permanent NPC")
    end)
end)

T:run("Currency vendors: nearest uses travel time and skips invalid path costs", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        C_Map.GetBestMapForUnit = function() return 85 end
        QR.ServiceRouter:ObserveMerchant()
        QR.PathCalculator = { CalculatePath = function(_, mapID)
            return { totalTime = mapID == 85 and 25 or 100 }
        end }
        local loc, cost = QR.ServiceRouter:FindNearestCurrencyVendor(2003)
        t:assertEqual(85, loc and loc.mapID, "Teleport-accessible vendor wins by travel time")
        t:assertEqual(25, cost, "Shortest estimated travel time returned")
        QR.PathCalculator.CalculatePath = function() return { totalTime = -1 } end
        t:assertNil(QR.ServiceRouter:FindNearestCurrencyVendor(2003), "Negative path estimates never win")
    end)
end)

T:run("Currency vendors: repeated observations replace entries and bound saved history", function(t)
    withMerchant(function()
        for i = 1, 505 do
            _G.UnitGUID = function(unit)
                return unit == "player" and "Player-1-A" or ("Creature-0-1-2-3-" .. i .. "-0001")
            end
            QR.ServiceRouter:ObserveMerchant()
        end
        local count = 0
        for _ in pairs(QR.db.currencyVendors) do count = count + 1 end
        t:assertEqual(500, count, "Saved merchant history is capped at 500 locations")
        QR.ServiceRouter:ObserveMerchant()
        count = 0
        for _ in pairs(QR.db.currencyVendors) do count = count + 1 end
        t:assertEqual(500, count, "Revisiting does not grow history")
    end)
end)

T:run("Currency vendors: search exposes localized currency names and fastest route action", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        local results = QR.DestinationSearch:CollectResults("supplies")
        t:assertEqual(1, #(results.currencies or {}), "Name search finds the observed currency")
        if results.currencies and results.currencies[1] then
            t:assertEqual(2003, results.currencies[1].currencyID, "Result identifies spending currency")
        end
    end)
end)

T:run("Currency vendors: async search yields between vendors and cancellation cannot publish", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        C_Map.GetBestMapForUnit = function() return 85 end
        QR.ServiceRouter:ObserveMerchant()
        local after = C_Timer.After
        local pending, calls, published = {}, 0, 0
        C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
        QR.PathCalculator = { CalculatePath = function()
            calls = calls + 1
            return { totalTime = 20 }
        end }
        local ok, err = pcall(function()
            QR.ServiceRouter:FindNearestCurrencyVendorAsync(2003, function() published = published + 1 end)
            t:assertEqual(0, calls, "Search does no path work in the click handler")
            pending[1]()
            t:assertEqual(1, calls, "One candidate calculated per callback")
            QR.ServiceRouter:CancelCurrencyRouting()
            for index = 2, #pending do pending[index]() end
            t:assertEqual(0, published, "Canceled vendor choice never publishes over another route")
        end)
        C_Timer.After = after
        if not ok then error(err) end
    end)
end)

T:run("Currency vendors: a loaded merchant with no currency costs removes stale acceptance", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        _G.C_MerchantFrame.GetMerchantCurrencies = function() return {} end
        local oldCount = _G.GetMerchantNumItems
        _G.GetMerchantNumItems = function() return 5 end
        QR.ServiceRouter:ObserveMerchant()
        _G.GetMerchantNumItems = oldCount
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(2003), "Removed currency offering is not recommended again")
    end)
end)
