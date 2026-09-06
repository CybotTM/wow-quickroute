local T, QR, MockWoW = ...

local function withSearch(callback)
    local saved = { att = _G.AllTheThings, attc = _G.ATTC, item = _G.C_Item, timer = _G.C_Timer,
        secret = _G.issecretvalue, panel = QR.TeleportPanel, routing = QR.POIRouting,
        combat = MockWoW.config.inCombatLockdown }
    local queue, routes, lookups = {}, {}, {}
    local vendor = {npcID = 182257, name = "Vilo", coords = { [1970] = {{34.8,64.1}} }, parent = {headerID = -58}}
    local items, npcs = { [190237] = {{itemID = 190237, parent = vendor}} }, { [182257] = {vendor} }
    local names = { [182257] = "Vilo" }
    local itemNames = { [190237] = "Translokationsmatrix der Mittler" }
    local att = { NPCNameFromID = names, HeaderConstants = {VENDORS = -58}, GetRawFieldContainer = function(field)
        return field == "itemID" and items or npcs
    end, SearchForFieldContainer = function() error("Recursive ATT discovery is forbidden") end }
    _G.AllTheThings, _G.ATTC = att, nil
    _G.C_Item = { IsItemDataCachedByID = function(id) return itemNames[id] ~= nil end,
        GetItemNameByID = function(id) return itemNames[id] end,
        GetItemInfo = function(query)
            if query == itemNames[190237] then return query, "|Hitem:190237::::::::|h[Matrix]|h" end
        end,
        RequestLoadItemDataByID = function() error("Search cannot request uncached items") end }
    _G.C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end,
        NewTimer = function(_, fn)
            local timer = { Cancel = function(self) self.cancelled = true end }
            queue[#queue + 1] = function() if not timer.cancelled then fn() end end
            return timer
        end }
    local available = true
    QR.TeleportPanel = { GetATTSourceLocation = function(_, entry, expected)
        lookups[#lookups + 1] = entry
        if not available or (expected and expected ~= vendor) then return nil end
        if (entry.isNPC and entry.id == 182257) or (not entry.isNPC and entry.id == 190237) then
            return {mapID = 1970, x = .348, y = .641, name = "Vilo", npcID = 182257,
                source = "ATT", sourceKind = "npc", sourceID = 182257, attSourceNode = vendor}
        end
    end }
    QR.POIRouting = { RouteToMapPosition = function(_, ...) routes[#routes + 1] = {...} end }
    MockWoW.config.inCombatLockdown = false
    local ds = setmetatable({isShowing = true, rows = {}}, {__index = QR.DestinationSearch})
    ds.RefreshDropdown = function(self, query) self._lastQuery = query; self.refreshes = (self.refreshes or 0) + 1 end
    local function tick() local fn = table.remove(queue, 1); if fn then fn(); return true end end
    local function drain() for _ = 1, 2000 do if not tick() then return end end; error("Search did not terminate") end
    local ok, err = pcall(callback, ds, att, items, npcs, names, itemNames, tick, drain, routes, lookups,
        function(value) available = value end, function(value) vendor = value end, saved.panel)
    _G.AllTheThings, _G.ATTC, _G.C_Item, _G.C_Timer = saved.att, saved.attc, saved.item, saved.timer
    _G.issecretvalue, QR.TeleportPanel, QR.POIRouting = saved.secret, saved.panel, saved.routing
    MockWoW.config.inCombatLockdown = saved.combat
    if not ok then error(err) end
end

T:run("ATT destination search: cached German item name resolves Vilo before scanning unrelated keys", function(t)
    withSearch(function(ds, _, items, _, _, _, tick, drain, routes)
        t:assertNotNil(ds.StartATTSearch, "The on-demand ATT search entry point exists")
        if not ds.StartATTSearch then return end
        for id = 200000, 260000 do items[id] = {} end
        ds:StartATTSearch("Translokationsmatrix der Mittler")
        tick()
        local row = ds._attSearch.results[1]
        t:assertNotNil(row, "An exact cached name resolves before the large index scan")
        t:assertEqual(190237, row and row.attEntry.id, "Result retains the requested item ID")
        t:assertEqual(182257, row and row.npcID, "Result identifies Vilo as the source")
        ds:SelectResult(row)
        t:assertEqual(1, #routes, "Selecting the item starts one source route")
        t:assertEqual(1970, routes[1] and routes[1][1], "Route targets Zereth Mortis")
        t:assertEqual(.348, routes[1] and routes[1][2], "Route uses recorded vendor coordinates")
        drain()
    end)
end)

T:run("ATT destination search: NPC, ID and item-link queries use existing indexed sources", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        for _, query in ipairs({"Vilo", "190237", "|Hitem:190237::::::::|h[Matrix]|h"}) do
            ds:CancelATTSearch()
            ds:StartATTSearch(query)
            drain()
            local result = ds._attSearch.results[1]
            t:assertNotNil(result, "Indexed source matches " .. query)
            t:assertEqual(query == "Vilo", result and result.attEntry.isNPC == true, "NPC queries retain the NPC field")
        end
    end)
end)

T:run("ATT destination search: literal queries, frame limits and partial results remain explicit", function(t)
    withSearch(function(ds, _, items, _, names, _, tick, drain, _, lookups)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        names[182257] = "Vilo %[literal]"
        ds:StartATTSearch("%[literal]")
        drain()
        t:assertEqual(1, #ds._attSearch.results, "Search uses literal substrings, not Lua patterns")
        ds:CancelATTSearch()
        for id = 200000, 260000 do items[id] = {} end
        ds:StartATTSearch("not cached")
        tick()
        t:assertTrue(ds._attSearch.scanned <= 200, "At most 200 index keys are inspected in one callback")
        t:assertTrue(#lookups <= 1, "Unmatched keys do not resolve source ancestry")
        drain()
        t:assertTrue(ds._attSearch.limited, "An index beyond the total work budget is marked incomplete")
        t:assertTrue(ds._attSearch.scanned <= 40000, "Total index work is bounded per query")
        t:assertFalse(ds._attSearch.searching, "A truncated query terminates")
    end)
end)

T:run("ATT destination search: typing, hiding and combat cancel pending source lookups", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain, _, lookups)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        ds:StartATTSearch("190237")
        ds:OnSearchTextChanged("Vilo")
        drain()
        t:assertEqual(0, #lookups, "A new keystroke cancels the old query before debounce ends")
        ds:StartATTSearch("190237")
        ds:HideDropdown()
        drain()
        t:assertEqual(0, #lookups, "Closing the picker cancels queued source work")
        ds.isShowing = true
        ds:StartATTSearch("190237")
        MockWoW.config.inCombatLockdown = true
        drain()
        t:assertEqual(0, #lookups, "Entering combat prevents queued source work")
    end)
end)

T:run("ATT destination search: selection revalidates item, provider and exact source identity", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain, routes, _, setAvailable, setVendor)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        ds:StartATTSearch("190237"); drain()
        local row = ds._attSearch.results[1]
        setAvailable(false); ds:SelectResult(row)
        t:assertEqual(0, #routes, "Lost access blocks a previously visible source")
        setAvailable(true); ds:StartATTSearch("190237"); drain(); row = ds._attSearch.results[1]
        setVendor({npcID = 182257}); ds:SelectResult(row)
        t:assertEqual(0, #routes, "A replacement NPC object cannot silently replace the selected source")
        ds:StartATTSearch("190237"); drain(); row = ds._attSearch.results[1]
        _G.AllTheThings = {}; ds:SelectResult(row)
        t:assertEqual(0, #routes, "A replaced ATT provider invalidates old results")
    end)
end)

T:run("ATT destination search: unavailable APIs and secret cached names are ignored safely", function(t)
    withSearch(function(ds, att, _, _, names, _, _, drain)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        local secret = {}
        _G.issecretvalue = function(value) return value == secret end
        names[182257] = secret
        C_Item.IsItemDataCachedByID = function() error("Restricted API") end
        ds:StartATTSearch("Vilo"); drain()
        t:assertEqual(0, #ds._attSearch.results, "Secret names and failed cache reads cannot create results")
        ds:CancelATTSearch()
        att.GetRawFieldContainer = function() return nil end
        ds:StartATTSearch("Vilo")
        t:assertNil(ds._attSearch, "Unloaded ATT indexes do not trigger database construction")
    end)
end)

T:run("ATT destination search: dense unavailable matches have a bounded source budget", function(t)
    withSearch(function(ds, _, _, _, names, _, _, drain, _, lookups)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        for id = 200000, 201000 do names[id] = "Unroutable vendor " .. id end
        ds:StartATTSearch("Unroutable vendor")
        drain()
        t:assertEqual(80, #lookups, "At most 80 ancestry checks run even when every matching source is unavailable")
        t:assertTrue(ds._attSearch.limited, "Unexamined matching sources remain explicitly partial")
        t:assertEqual(0, #ds._attSearch.results, "Unverified locations never become destinations")
        local seen = 0
        for _ in pairs(ds._attSearch.seen) do seen = seen + 1 end
        t:assertTrue(seen <= 80, "Dedupe storage cannot grow into a second ATT index")
    end)
end)

T:run("ATT destination search: an absent NPC name cache does not misclassify item IDs", function(t)
    withSearch(function(ds, att, _, _, _, itemNames, _, drain)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        att.NPCNameFromID = nil
        itemNames[190237] = "Matrix %[literal] |Tbad|t"
        ds:StartATTSearch("%[literal]")
        drain()
        local row = ds._attSearch.results[1]
        t:assertNotNil(row, "Cached item substring search works without NPC names")
        t:assertFalse(row and row.attEntry.isNPC, "The item index never falls through into the NPC stage")
        t:assertTrue(row and row.name:find("||Tbad||t", 1, true) ~= nil, "Result names escape WoW texture markup")
    end)
end)

T:run("ATT destination search: result rendering preserves catalogue priority and suppresses duplicate NPCs", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        local known = {name = "Vilo", npcID = 182257, mapID = 1970, x = .348, y = .641, source = "catalogue"}
        local rendered, headers = {}, {}
        ds.frame = {SetHeight = function() end, scrollChild = {SetHeight = function() end}}
        ds.collapsedSections = {}
        ds.ReleaseAllRows = function() rendered, headers = {}, {} end
        ds.CreateSectionHeader = function(_, key, _, y) headers[#headers + 1] = key; return {}, y + 24 end
        ds.CreateResultRow = function(_, entry, y)
            rendered[#rendered + 1] = entry
            return {SetScript = function() end}, y + 22
        end
        ds.CollectResults = function() return {waypoints = {}, quests = {}, cities = {}, dungeons = {}, services = {},
            currencies = {}, catalog = {known}} end
        ds.RefreshDropdown = QR.DestinationSearch.RefreshDropdown
        ds:RefreshDropdown("Vilo")
        drain()
        t:assertEqual("catalog", headers[1], "Existing catalogue section keeps its result priority")
        t:assertEqual("att", headers[2], "Optional ATT sources follow existing destinations")
        local destinations = 0
        for _, row in ipairs(rendered) do if not row.informational then destinations = destinations + 1 end end
        t:assertEqual(1, destinations, "The identical catalogued NPC is not listed twice")
        ds._attSearch.limited = true
        ds:RefreshDropdown("Vilo")
        local hint = false
        for _, row in ipairs(rendered) do if row.name == QR.L["ATT_SEARCH_MORE"] then hint = row.informational == true end end
        t:assertTrue(hint, "Truncated searches display the partial-result hint in the picker")
    end)
end)

T:run("ATT destination search: the actual ATT source helper routes a cached item without collection ownership", function(t)
    withSearch(function(ds, att, items, npcs, _, _, _, drain, routes, _, _, _, actualPanel)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        QR.TeleportPanel = actualPanel
        items[190237][1].minReputation = {2478,42000}
        att.SearchForField = function(field, id) return (field == "npcID" and npcs or items)[id] end
        att.CurrentCharacterFilters = function() return true end
        ds:StartATTSearch("Translokationsmatrix der Mittler")
        drain()
        local row = ds._attSearch.results[1]
        t:assertNotNil(row, "A known vendor source is searchable without owning its item")
        t:assertEqual(182257, row and row.attSourceID, "The source helper retains Vilo's identity")
        t:assertTrue(row and row.attPurchaseRequirement, "Unmet or unknown purchase reputation is disclosed without hiding the vendor")
        t:assertEqual("Vilo", row and row.tag, "The source NPC remains visible beside a long item name")
        ds:SelectResult(row)
        t:assertEqual(1, #routes, "Selection revalidates through the real ATT source helper")
        t:assertTrue(routes[1] and math.abs(routes[1][3] - .641) < .000001, "The real helper preserves the source coordinate")
    end)
end)

T:run("ATT destination search: delayed source selection uses fresh coordinates and remains combat guarded", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain, routes)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        local resolve = QR.TeleportPanel.GetATTSourceLocation
        QR.TeleportPanel.GetATTSourceLocation = function(self, entry, expected)
            local point = resolve(self, entry, expected)
            if point then point.questID = 123; if expected then point.x = .4 end end
            return point
        end
        ds:StartATTSearch("190237"); drain()
        local row = ds._attSearch.results[1]
        MockWoW.config.inCombatLockdown = true
        ds:SelectResult(row)
        t:assertEqual(0, #routes, "A direct invocation cannot start source navigation during combat")
        MockWoW.config.inCombatLockdown = false
        ds:SelectResult(row)
        t:assertEqual(1, #routes, "A quest-source result navigates without needing a currently watched quest")
        t:assertEqual(.4, routes[1] and routes[1][2], "The current coordinate replaces the old search snapshot")
    end)
end)

T:run("ATT destination search: a row from the previous query cannot route during debounce", function(t)
    withSearch(function(ds, _, _, _, _, _, _, drain, routes)
        if not ds.StartATTSearch then t:assert(false, "ATT search is implemented"); return end
        ds:StartATTSearch("190237"); drain()
        local row = ds._attSearch.results[1]
        ds:OnSearchTextChanged("Vilo")
        ds:SelectResult(row)
        t:assertEqual(0, #routes, "Typing a new query invalidates the previous clickable source row immediately")
        drain()
    end)
end)
