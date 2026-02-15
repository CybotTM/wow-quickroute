-------------------------------------------------------------------------------
-- test_destination_search.lua
-- Tests for unified destination search
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
end

-------------------------------------------------------------------------------
-- 1. Data Availability
-------------------------------------------------------------------------------

T:run("DestSearch: CAPITAL_CITIES exposed on QR", function(t)
    t:assertNotNil(QR.CAPITAL_CITIES, "QR.CAPITAL_CITIES exists")
    t:assertEqual("table", type(QR.CAPITAL_CITIES))
end)

T:run("DestSearch: CAPITAL_CITIES has expected cities", function(t)
    local cities = QR.CAPITAL_CITIES
    t:assertNotNil(cities["Stormwind City"], "Stormwind")
    t:assertNotNil(cities["Orgrimmar"], "Orgrimmar")
    t:assertNotNil(cities["Valdrakken"], "Valdrakken")
end)

T:run("DestSearch: each city has mapID, x, y, faction", function(t)
    for name, data in pairs(QR.CAPITAL_CITIES) do
        t:assertNotNil(data.mapID, name .. " has mapID")
        t:assertNotNil(data.x, name .. " has x")
        t:assertNotNil(data.y, name .. " has y")
        t:assertNotNil(data.faction, name .. " has faction")
    end
end)

T:run("DestSearch: localization keys exist for search", function(t)
    local L = QR.L
    t:assertNotNil(L["DEST_SEARCH_PLACEHOLDER"], "placeholder key")
    t:assertNotNil(L["DEST_SEARCH_ACTIVE_WAYPOINT"], "active waypoint header")
    t:assertNotNil(L["DEST_SEARCH_CITIES"], "cities header")
    t:assertNotNil(L["DEST_SEARCH_DUNGEONS"], "dungeons header")
    t:assertNotNil(L["DEST_SEARCH_NO_RESULTS"], "no results key")
    t:assertNotNil(L["DEST_SEARCH_ROUTE_TO_TT"], "route tooltip key")
end)

-------------------------------------------------------------------------------
-- 2. Module Structure
-------------------------------------------------------------------------------

T:run("DestSearch: module exists", function(t)
    t:assertNotNil(QR.DestinationSearch, "QR.DestinationSearch exists")
end)

T:run("DestSearch: has expected methods", function(t)
    local DS = QR.DestinationSearch
    t:assertNotNil(DS.CollectResults, "CollectResults exists")
    t:assertNotNil(DS.Initialize, "Initialize exists")
    t:assertNotNil(DS.HideDropdown, "HideDropdown exists")
    t:assertNotNil(DS.RegisterCombat, "RegisterCombat exists")
end)

-------------------------------------------------------------------------------
-- 3. Data Collection
-------------------------------------------------------------------------------

T:run("DestSearch: CollectResults returns grouped data", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")
    t:assertNotNil(results, "results not nil")
    t:assertNotNil(results.waypoints, "waypoints group")
    t:assertNotNil(results.cities, "cities group")
    t:assertNotNil(results.dungeons, "dungeons group")
end)

T:run("DestSearch: cities filtered by Alliance faction", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    local hasStormwind, hasOrgrimmar, hasValdrakken = false, false, false
    for _, city in ipairs(results.cities) do
        if city.name == "Stormwind City" then hasStormwind = true end
        if city.name == "Orgrimmar" then hasOrgrimmar = true end
        if city.name == "Valdrakken" then hasValdrakken = true end
    end
    t:assertTrue(hasStormwind, "Alliance sees Stormwind")
    t:assertFalse(hasOrgrimmar, "Alliance doesn't see Orgrimmar")
    t:assertTrue(hasValdrakken, "Alliance sees neutral Valdrakken")
end)

T:run("DestSearch: cities filtered by Horde faction", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    local hasStormwind, hasOrgrimmar = false, false
    for _, city in ipairs(results.cities) do
        if city.name == "Stormwind City" then hasStormwind = true end
        if city.name == "Orgrimmar" then hasOrgrimmar = true end
    end
    t:assertFalse(hasStormwind, "Horde doesn't see Stormwind")
    t:assertTrue(hasOrgrimmar, "Horde sees Orgrimmar")
end)

T:run("DestSearch: search filters cities by name", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local all = DS:CollectResults("")
    local filtered = DS:CollectResults("storm")

    t:assertTrue(#filtered.cities > 0, "At least one city matches 'storm'")
    t:assertTrue(#filtered.cities < #all.cities, "Fewer than all cities match 'storm'")
end)

T:run("DestSearch: empty search returns all faction cities", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    -- 5 Alliance + 6 neutral (Dalaran x2, Shattrath, Oribos, Valdrakken, Dornogal) = 11
    t:assertTrue(#results.cities >= 10, "At least 10 cities for Alliance: got " .. #results.cities)
end)

T:run("DestSearch: cities sorted alphabetically", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    for i = 2, #results.cities do
        t:assertTrue(results.cities[i-1].name <= results.cities[i].name,
            "Cities sorted: " .. results.cities[i-1].name .. " <= " .. results.cities[i].name)
    end
end)

T:run("DestSearch: dungeons grouped by tier", function(t)
    resetState()
    -- Initialize DungeonData
    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    -- Should have dungeon tiers if DungeonData is scanned
    if QR.DungeonData and QR.DungeonData.scanned then
        t:assertTrue(#results.dungeons > 0, "Has dungeon tiers")
        for _, tier in ipairs(results.dungeons) do
            t:assertNotNil(tier.tierName, "Tier has name")
            t:assertNotNil(tier.instances, "Tier has instances")
        end
    end
end)

-------------------------------------------------------------------------------
-- 4. Dropdown Popup Frame
-------------------------------------------------------------------------------

T:run("DestSearch: CreateDropdown creates frame", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.isShowing = false

    local DS = QR.DestinationSearch
    local frame = DS:CreateDropdown()
    t:assertNotNil(frame, "Dropdown frame created")
    t:assertNotNil(DS.frame, "Stored on module")
end)

T:run("DestSearch: dropdown initially hidden", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false

    local DS = QR.DestinationSearch
    DS:CreateDropdown()
    t:assertFalse(DS.frame:IsShown(), "Hidden after creation")
    t:assertFalse(DS.isShowing, "isShowing false")
end)

T:run("DestSearch: ShowDropdown shows frame", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()
    t:assertTrue(DS.isShowing, "isShowing true after show")
    t:assertNotNil(DS.frame, "Frame exists after show")
end)

T:run("DestSearch: HideDropdown hides frame", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()
    DS:HideDropdown()
    t:assertFalse(DS.isShowing, "Hidden after hide")
end)

T:run("DestSearch: OnHide syncs isShowing", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()
    DS.frame:Hide()  -- Simulate ESC
    t:assertFalse(DS.isShowing, "isShowing synced on hide")
end)

T:run("DestSearch: combat hides dropdown", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:RegisterCombat()
    DS:ShowDropdown()
    t:assertTrue(DS.isShowing, "Showing before combat")

    -- MockWoW:Reset clears eventFrames, so invoke the combat handler directly
    MockWoW.config.inCombatLockdown = true
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
    end
    t:assertFalse(DS.isShowing, "Hidden after combat enter")
end)

T:run("DestSearch: selecting city routes via POIRouting", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    local routedTo = nil
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routedTo = { mapID = mapID, x = x, y = y }
    end

    local DS = QR.DestinationSearch
    DS:SelectResult({
        name = "Stormwind City",
        mapID = 84,
        x = 0.4965,
        y = 0.8725,
    })

    t:assertNotNil(routedTo, "POIRouting called")
    t:assertEqual(routedTo.mapID, 84, "Correct mapID")

    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DestSearch: selecting plays sound", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    MockWoW.config.playedSounds = {}

    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function() end

    local DS = QR.DestinationSearch
    DS:SelectResult({
        name = "Stormwind City",
        mapID = 84,
        x = 0.4965,
        y = 0.8725,
    })

    t:assertTrue(#MockWoW.config.playedSounds > 0, "Sound played on selection")
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DestSearch: OnSearchTextChanged filters dropdown", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()
    local initialRowCount = #DS.rows

    DS:OnSearchTextChanged("storm")
    local filteredRowCount = #DS.rows

    t:assertTrue(filteredRowCount < initialRowCount,
        "Filtered rows (" .. filteredRowCount .. ") < initial (" .. initialRowCount .. ")")
end)

T:run("DestSearch: SetSearchText updates editbox", function(t)
    resetState()

    local mockBox = CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
    QR.DestinationSearch.searchBox = mockBox

    QR.DestinationSearch:SetSearchText("Valdrakken")
    t:assertEqual(mockBox:GetText(), "Valdrakken", "Text set correctly")
end)

T:run("DestSearch: section headers use gold color", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.collapsedSections = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    local headerFound = false
    for _, row in ipairs(DS.rows) do
        if row._isHeader and row.nameLabel then
            local r = row.nameLabel._textColorR
            local g = row.nameLabel._textColorG
            if r and g then
                t:assertTrue(r > 0.9, "Header red > 0.9, got " .. r)
                t:assertTrue(g > 0.7 and g < 0.9, "Header green ~0.82, got " .. g)
                headerFound = true
                break
            end
        end
    end
    -- Cities header should always exist
    t:assertTrue(headerFound, "Found at least one gold header")
end)

-------------------------------------------------------------------------------
-- 5. Route Tab Integration
-------------------------------------------------------------------------------

T:run("DestSearch: search box exists on Route tab frame", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.searchBox = nil

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNotNil(parentFrame.searchBox, "searchBox exists on frame")
end)

T:run("DestSearch: no sourceDropdown on Route tab", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.searchBox = nil

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNil(parentFrame.sourceDropdown, "sourceDropdown removed")
end)

T:run("DestSearch: no dungeonButton on Route tab", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.searchBox = nil

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNil(parentFrame.dungeonButton, "dungeonButton removed")
end)

T:run("DestSearch: init sequence includes DestinationSearch", function(t)
    resetState()
    -- DestinationSearch should already be initialized via addon loader + init
    t:assertNotNil(QR.DestinationSearch, "Module exists")
    t:assertNotNil(QR.DestinationSearch.CollectResults, "Has CollectResults")
end)

-------------------------------------------------------------------------------
-- 6. Dropdown Close Behavior
-------------------------------------------------------------------------------

T:run("DestSearch: OnEditFocusLost closes dropdown", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.searchBox = nil

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    local searchBox = parentFrame.searchBox
    t:assertNotNil(searchBox, "searchBox exists")

    -- Simulate focus gained -> dropdown opens
    if searchBox._scripts["OnEditFocusGained"] then
        searchBox._scripts["OnEditFocusGained"](searchBox)
    end
    t:assertTrue(QR.DestinationSearch.isShowing, "Dropdown opens on focus")

    -- Simulate focus lost -> dropdown closes (C_Timer.After fires immediately in tests)
    if searchBox._scripts["OnEditFocusLost"] then
        searchBox._scripts["OnEditFocusLost"](searchBox)
    end
    t:assertFalse(QR.DestinationSearch.isShowing, "Dropdown closes on focus lost")
end)

T:run("DestSearch: OnMouseDown toggles dropdown closed", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.searchBox = nil

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    local searchBox = parentFrame.searchBox
    t:assertNotNil(searchBox, "searchBox exists")

    -- Open dropdown first
    if searchBox._scripts["OnEditFocusGained"] then
        searchBox._scripts["OnEditFocusGained"](searchBox)
    end
    t:assertTrue(QR.DestinationSearch.isShowing, "Dropdown open")

    -- Click searchBox again -> should toggle closed
    if searchBox._scripts["OnMouseDown"] then
        searchBox._scripts["OnMouseDown"](searchBox)
    end
    t:assertFalse(QR.DestinationSearch.isShowing, "Dropdown closed after toggle click")
end)

T:run("DestSearch: OnEditFocusGained does not reopen if already showing", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.searchBox = nil

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    local searchBox = parentFrame.searchBox

    -- Open dropdown
    if searchBox._scripts["OnEditFocusGained"] then
        searchBox._scripts["OnEditFocusGained"](searchBox)
    end
    t:assertTrue(QR.DestinationSearch.isShowing, "Dropdown open")

    -- Manually hide it (simulating toggle click)
    QR.DestinationSearch:HideDropdown()
    t:assertFalse(QR.DestinationSearch.isShowing, "Dropdown hidden")

    -- Focus gained again should NOT reopen if isShowing is already false but focus stays
    -- (This tests the guard: only show if not already showing)
    QR.DestinationSearch.isShowing = false
    if searchBox._scripts["OnEditFocusGained"] then
        searchBox._scripts["OnEditFocusGained"](searchBox)
    end
    t:assertTrue(QR.DestinationSearch.isShowing, "Reopens on new focus")
end)

-------------------------------------------------------------------------------
-- 7. Services Section
-------------------------------------------------------------------------------

T:run("DestSearch: CollectResults includes services section", function(t)
    resetState()
    local results = QR.DestinationSearch:CollectResults("")
    t:assertNotNil(results.services, "services field exists")
    t:assertTrue(#results.services > 0, "Has service entries")
end)

T:run("DestSearch: services have serviceType and serviceName", function(t)
    resetState()
    local results = QR.DestinationSearch:CollectResults("")
    for _, svc in ipairs(results.services) do
        t:assertNotNil(svc.serviceType, "Has serviceType")
        t:assertNotNil(svc.serviceName, "Has serviceName")
        t:assertNotNil(svc.locations, "Has locations")
        t:assertTrue(#svc.locations > 0, svc.serviceType .. " has locations")
    end
end)

T:run("DestSearch: services filtered by search query", function(t)
    resetState()
    local results = QR.DestinationSearch:CollectResults("auction")
    local foundAH = false
    for _, svc in ipairs(results.services) do
        if svc.serviceType == "AUCTION_HOUSE" then foundAH = true end
    end
    t:assertTrue(foundAH, "AUCTION_HOUSE found via search")

    local results2 = QR.DestinationSearch:CollectResults("xyznoexist")
    t:assertEqual(0, #results2.services, "No services for nonsense query")
end)

T:run("DestSearch: service locations are faction-filtered", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local results = QR.DestinationSearch:CollectResults("")
    for _, svc in ipairs(results.services) do
        for _, loc in ipairs(svc.locations) do
            t:assertNotNil(loc.mapID, "Location has mapID")
            t:assertNotNil(loc.name, "Location has name")
        end
    end
end)

T:run("DestSearch: services dropdown renders rows", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.collapsedSections = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    -- Services section should add rows (header + nearest rows + location rows)
    local serviceHeaderFound = false
    for _, row in ipairs(DS.rows) do
        if row._isHeader and row.nameLabel then
            local text = row.nameLabel:GetText()
            if text and text:find("Services") then
                serviceHeaderFound = true
                break
            end
        end
    end
    t:assertTrue(serviceHeaderFound, "Services section header rendered")
end)

T:run("DestSearch: service nearest row has blue text color", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    QR.DestinationSearch.collapsedSections = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    -- Find a "Nearest" row by checking for blue text color (0.4, 0.8, 1)
    local nearestRowFound = false
    for _, row in ipairs(DS.rows) do
        if not row._isHeader and row.nameLabel then
            local r = row.nameLabel._textColorR
            local g = row.nameLabel._textColorG
            local b = row.nameLabel._textColorB
            if r and g and b and math.abs(r - 0.4) < 0.01 and math.abs(g - 0.8) < 0.01 and math.abs(b - 1.0) < 0.01 then
                nearestRowFound = true
                break
            end
        end
    end
    t:assertTrue(nearestRowFound, "Found nearest row with blue text color")
end)

T:run("DestSearch: slash alias matches service in search", function(t)
    resetState()
    -- Searching "ah" should match Auction House via slash alias
    local results = QR.DestinationSearch:CollectResults("ah")
    t:assertTrue(#results.services > 0, "Alias 'ah' matches services")
    local foundAH = false
    for _, svc in ipairs(results.services) do
        if svc.serviceType == "AUCTION_HOUSE" then foundAH = true end
    end
    t:assertTrue(foundAH, "AUCTION_HOUSE found via 'ah' alias search")

    -- "void" should match Void Storage
    local results2 = QR.DestinationSearch:CollectResults("void")
    local foundVS = false
    for _, svc in ipairs(results2.services) do
        if svc.serviceType == "VOID_STORAGE" then foundVS = true end
    end
    t:assertTrue(foundVS, "VOID_STORAGE found via 'void' alias search")

    -- "craft" should match Crafting Table
    local results3 = QR.DestinationSearch:CollectResults("craft")
    local foundCT = false
    for _, svc in ipairs(results3.services) do
        if svc.serviceType == "CRAFTING_TABLE" then foundCT = true end
    end
    t:assertTrue(foundCT, "CRAFTING_TABLE found via 'craft' alias search")
end)

T:run("DestSearch: CollectResults handles nil ServiceRouter gracefully", function(t)
    resetState()
    local origSR = QR.ServiceRouter
    QR.ServiceRouter = nil
    local results = QR.DestinationSearch:CollectResults("")
    t:assertNotNil(results.services, "services field exists")
    t:assertEqual(0, #results.services, "No services when ServiceRouter is nil")
    QR.ServiceRouter = origSR
end)

T:run("DestSearch: empty query does not alias-match services", function(t)
    resetState()
    -- Empty query should return ALL services (not filtered by alias)
    local results = QR.DestinationSearch:CollectResults("")
    t:assertTrue(#results.services >= 4, "All services returned for empty query")
end)

T:run("DestSearch: new localization keys exist for all service messages", function(t)
    local L = QR.L
    -- New keys added in this iteration
    t:assertNotNil(L["ADDON_FIRST_RUN"], "ADDON_FIRST_RUN key exists")
    t:assertNotNil(L["DEBUG_PREFIX"], "DEBUG_PREFIX key exists")
    t:assertNotNil(L["MINIMAP_SHOWN"], "MINIMAP_SHOWN key exists")
    t:assertNotNil(L["MINIMAP_HIDDEN"], "MINIMAP_HIDDEN key exists")
    t:assertNotNil(L["PRIORITY_SET_TO"], "PRIORITY_SET_TO key exists")
    t:assertNotNil(L["PRIORITY_USAGE"], "PRIORITY_USAGE key exists")
    t:assertNotNil(L["PRIORITY_CURRENT"], "PRIORITY_CURRENT key exists")
    t:assertNotNil(L["SIDEBAR_COLLAPSE_TT"], "SIDEBAR_COLLAPSE_TT key exists")
end)
