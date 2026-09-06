local T, QR = ...

local function withSource(body)
    local cat, savedSource = QR.Catalog, QR.DestinationCatalog
    local savedCompleted, savedTitle = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetTitleForQuestID
    local savedTooltip = _G.C_TooltipInfo
    local source = {
        vendors = { { npcID = 10, name = "Index Merchant", currencyID = 2003,
            mapID = 84, x = 0.3, y = 0.5, requirements = {} } },
        npcs = {
            { npcID = 10, name = "Index Merchant", mapID = 84, x = 0.3, y = 0.5, requirements = {} },
            { npcID = 10, name = "Other Source Name", mapID = 85, x = 0.4, y = 0.5, requirements = {} },
        },
        quests = { { questID = 101, name = "Index Quest", role = "giver",
            mapID = 84, x = 0.6, y = 0.5, requirements = {} } },
    }
    QR.DestinationCatalog = source
    C_QuestLog.IsQuestFlaggedCompleted = function() return false end
    C_QuestLog.GetTitleForQuestID = function() return nil end
    _G.C_TooltipInfo = nil
    cat:Reset()
    local ok, err = pcall(body, cat, source)
    QR.DestinationCatalog = savedSource
    C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetTitleForQuestID = savedCompleted, savedTitle
    _G.C_TooltipInfo = savedTooltip
    cat:Reset()
    if not ok then error(err) end
end

T:run("Catalogue memory: currency and quest lookups do not allocate global search indexes", function(t)
    withSource(function(cat, source)
        local currencies = cat:GetCurrencies()
        t:assertEqual(2003, currencies[1], "Currency-only lookup retains the correct currency")
        t:assertNil(cat.byQuest, "Currency lookup does not allocate the quest-ID index")
        t:assertNil(cat.byNPC, "Currency lookup does not allocate the NPC-ID index")
        t:assertNil(cat.byMap, "Currency lookup does not allocate the map search index")
        t:assertNil(cat.searchRows, "Currency lookup does not allocate global search rows")
        t:assertNil(source.quests[1].searchName, "Currency lookup leaves quest source tables unexpanded")
        t:assertNil(source.npcs[1].searchName, "Currency lookup leaves NPC source tables unexpanded")
        local currencyIndex = cat.byCurrency
        local locations = cat:GetQuestLocations(101, "giver")
        t:assertEqual(1, #locations, "Quest lookup builds its own complete ID index")
        t:assertEqual(source.quests[1], locations[1], "Quest lookup preserves the source entry and role")
        t:assertEqual(currencyIndex, cat.byCurrency, "Adding a quest index retains the existing currency index")
        t:assertNil(cat.byNPC, "Quest lookup does not allocate the NPC-ID index")
        t:assertNil(cat.searchRows, "Quest lookup does not allocate global search rows")
        t:assertNil(source.quests[1].searchName, "Quest lookup does not expand source rows with search fields")
        local questIndex = cat.byQuest
        cat:Initialize()
        t:assertEqual(questIndex, cat.byQuest, "Full initialization reuses an already-built quest partition")
        t:assertEqual(currencyIndex, cat.byCurrency, "Full initialization reuses an already-built currency partition")
        t:assertEqual(2, #cat.byNPC[10], "Full initialization adds every NPC location")
        t:assertNil(cat.byNPC[101], "Already-indexed quests do not leak into the new NPC partition")
        t:assertEqual(1, #cat:GetQuestLocations(101), "Full initialization does not duplicate existing quest locations")
        cat:Initialize()
        t:assertEqual(3, #cat.searchRows, "Repeated full initialization does not duplicate search rows")
    end)
end)

T:run("Catalogue memory: search preserves localized duplicates without unrelated ID indexes", function(t)
    withSource(function(cat, source)
        local rows, more = cat:Search("index", 84, 1)
        t:assertEqual(1, #rows, "Search retains its result cap")
        t:assertTrue(more, "Search reports further matching destinations")
        t:assertNil(cat.byCurrency, "Global search does not allocate the currency index")
        t:assertNil(cat.byQuest, "Global search does not allocate the quest-ID index")
        t:assertNil(cat.byNPC, "Global search does not allocate the NPC-ID index")
        t:assertEqual(2, #cat:Search("", 84), "Empty search still uses the current-map index")
        t:assertEqual(1, #cat:Search("101", 84), "Numeric quest search still finds the giver")
        _G.C_TooltipInfo = { GetHyperlink = function()
            return { lines = { { leftText = "Rüstmeister" } } }
        end }
        cat:GetDisplayName(source.npcs[1])
        t:assertEqual(2, #cat:Search("rüstmeister", 84), "A live localized NPC name finds every location for its ID")
    end)
end)

T:run("Catalogue memory: full initialization and source replacement reset every partition", function(t)
    withSource(function(cat)
        cat:Initialize()
        for _, key in ipairs({ "byCurrency", "byQuest", "byNPC", "byMap", "searchRows" }) do
            t:assertNotNil(cat[key], "Explicit Initialize preserves the full " .. key .. " index")
        end
        local oldCurrency, oldQuest = cat.byCurrency, cat.byQuest
        QR.DestinationCatalog = { vendors = {}, quests = {}, npcs = {
            { npcID = 22, name = "Replacement Merchant", mapID = 85, x = 0.6, y = 0.7, requirements = {} },
        } }
        t:assertEqual(1, #cat:Search("replacement", 85), "Replacing the source builds fresh search rows")
        t:assertNil(cat.byCurrency, "Source replacement drops the obsolete currency partition")
        t:assertNil(cat.byQuest, "Source replacement drops the obsolete quest partition")
        t:assertNil(cat.byNPC, "Source replacement drops the obsolete NPC partition")
        t:assertEqual(0, #cat:Search("index", 84), "Former source names cannot survive a replacement")
        t:assertEqual(0, #cat:GetCurrencies(), "Removed currency offers do not survive a replacement")
        t:assert(cat.byCurrency ~= oldCurrency, "The currency partition belongs to the new source")
        t:assertEqual(0, #cat:GetQuestLocations(101), "Removed quest IDs do not survive a replacement")
        t:assert(cat.byQuest ~= oldQuest, "The quest partition belongs to the new source")
        QR.DestinationCatalog = nil
        cat:Reset()
        t:assertEqual(0, #cat:Search("", 84), "An absent source cannot reuse previously indexed rows")
    end)
end)
