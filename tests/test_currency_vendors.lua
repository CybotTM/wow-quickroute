local T, QR, MockWoW = ...

local function withMerchant(fn)
    local saved = { db = QR.db, UnitGUID = _G.UnitGUID, UnitName = _G.UnitName,
        merchant = _G.C_MerchantFrame, currency = _G.C_CurrencyInfo, time = _G.time,
        map = C_Map, pc = QR.PathCalculator, catalog = QR.Catalog, faction = MockWoW.config.playerFaction }
    QR.db = { currencyVendors = {} }
    QR.Catalog = nil
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
    QR.Catalog = saved.catalog
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

T:run("Currency vendors: unvisited catalogue locations merge with observed precedence", function(t)
    withMerchant(function()
        QR.Catalog = { GetCurrencyLocations = function()
            return {
                {npcID = 12345, name = "Old Position", mapID = 84, x = 0.2, y = 0.2, source = "catalogue"},
                {npcID = 999, name = "New Seller", mapID = 85, x = 0.4, y = 0.4, source = "catalogue"},
            }
        end }
        t:assertEqual(2, #QR.ServiceRouter:GetCurrencyLocations(2003), "Unvisited source vendors are available before merchant interaction")
        QR.ServiceRouter:ObserveMerchant()
        local results = QR.ServiceRouter:GetCurrencyLocations(2003)
        t:assertEqual(2, #results, "Observed vendor replaces the same NPC's catalogue point")
        local merchant
        for _, loc in ipairs(results) do if loc.npcID == 12345 then merchant = loc end end
        t:assertEqual(0.3, merchant and merchant.x, "Observed interaction position has precedence")
        QR.db.currencyVendors.corrupt = {character = "Player-1-A", faction = "Alliance", source = "merchant",
            name = "Broken", mapID = 84, x = 0.4, y = 0.5, currencies = {[2003] = true}}
        t:assertEqual(2, #QR.ServiceRouter:GetCurrencyLocations(2003), "Corrupted NPC identity is discarded during merge")
    end)
end)

T:run("Currency vendors: origin changes restart comparison without mixing travel estimates", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        C_Map.GetBestMapForUnit = function() return 85 end
        QR.ServiceRouter:ObserveMerchant()
        local origin, pending, routed, calls = 84, {}, nil, 0
        C_Map.GetBestMapForUnit = function() return origin end
        QR.PathCalculator = { CalculatePath = function(_, mapID)
            calls = calls + 1
            return {totalTime = origin == mapID and 10 or 90}
        end }
        local savedAfter = C_Timer.After
        C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
        local ok, err = pcall(function()
            QR.ServiceRouter:FindNearestCurrencyVendorAsync(2003, function(loc) routed = loc end)
            pending[1]()
            origin = 85
            local index = 2
            while pending[index] do pending[index](); index = index + 1 end
            t:assertEqual(85, routed and routed.mapID, "New origin chooses its own nearest vendor")
            t:assertEqual(3, calls, "Old-origin first comparison is discarded and both candidates are recomputed")
        end)
        C_Timer.After = savedAfter
        if not ok then error(err) end
    end)
end)

T:run("Currency vendors: sustained movement aborts after bounded restarts", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        local pending, reason, calls, x = {}, nil, 0, 0.3
        C_Map.GetPlayerMapPosition = function() return {x = x, y = 0.5} end
        QR.PathCalculator = {CalculatePath = function() calls = calls + 1; return {totalTime = 10} end}
        local savedAfter = C_Timer.After
        C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
        local ok, err = pcall(function()
            QR.ServiceRouter:FindNearestCurrencyVendorAsync(2003, function(_, _, _, why) reason = why end)
            for index = 1, 10 do
                if not pending[index] then break end
                x = x + 0.02
                pending[index]()
            end
            t:assertEqual("position_changed", reason, "Ongoing movement reports why comparison stopped")
            t:assertEqual(2, calls, "Only two restart calculations are allowed")
        end)
        C_Timer.After = savedAfter
        if not ok then error(err) end
    end)
end)

T:run("Currency vendors: picker allows explicit vendor selection and return to currencies", function(t)
    withMerchant(function()
        QR.ServiceRouter:ObserveMerchant()
        local ds = QR.DestinationSearch
        local oldShowing, oldCurrency, oldSelected, oldFrame = ds.isShowing, ds._currencyOnly, ds._selectedCurrencyID, ds.frame
        ds:ShowCurrencyDropdown()
        local entry
        for _, row in ipairs(ds.rows) do if row._entryData and row._entryData.currencyID == 2003 then entry = row._entryData; break end end
        t:assertTrue(entry and entry.selectCurrency, "Currency picker row opens its vendor choices")
        ds:SelectResult(entry)
        t:assertEqual(2003, ds._selectedCurrencyID, "Selected currency is retained while viewing vendors")
        local direct, fastest, back
        for _, row in ipairs(ds.rows) do
            local data = row._entryData
            if data and data.source == "merchant" then direct = data end
            if data and data.currencyID == 2003 then fastest = data end
            if data and data.currencyBack then back = data end
        end
        t:assertNotNil(direct, "Individual observed vendor has a direct route row")
        t:assertNotNil(fastest, "Fastest eligible vendor action remains available")
        ds:SelectResult(back)
        t:assertNil(ds._selectedCurrencyID, "Back control returns to currency list")
        ds:HideDropdown()
        ds.isShowing, ds._currencyOnly, ds._selectedCurrencyID = oldShowing, oldCurrency, oldSelected
        if oldFrame and oldShowing then oldFrame:Show() end
    end)
end)

T:run("Currency vendors: changed merchant acceptance suppresses obsolete catalogue costs", function(t)
    withMerchant(function()
        QR.Catalog = {GetCurrencyLocations = function()
            return {{npcID=12345,name="Reference Seller",mapID=84,x=0.2,y=0.2,source="catalogue"}}
        end}
        _G.C_MerchantFrame.GetMerchantCurrencies = function() return {3008} end
        QR.ServiceRouter:ObserveMerchant()
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(2003), "Observed absence of a cost suppresses the old catalogue offering")
        _G.C_MerchantFrame.GetMerchantCurrencies = function() return {} end
        local count = _G.GetMerchantNumItems
        _G.GetMerchantNumItems = function() return 5 end
        QR.ServiceRouter:ObserveMerchant()
        _G.GetMerchantNumItems = count
        t:assertEqual(0, #QR.ServiceRouter:GetCurrencyLocations(3008), "Loaded merchant with no currency costs suppresses every old reference cost")
        t:assertEqual(1, #QR.ServiceRouter:GetCurrencyLocations(), "Bounded negative observation remains for this character")
    end)
end)
