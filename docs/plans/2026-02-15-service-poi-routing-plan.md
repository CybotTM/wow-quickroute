# Service POI Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Route the player to the nearest Auction House, Bank, or Void Storage across all capital cities using Dijkstra-optimal travel time.

**Architecture:** Static service coordinate data in `Data/ServicePOIs.lua`, a `ServiceRouter` module for nearest-service Dijkstra lookup, integrated into the existing `DestinationSearch` dropdown as a new "Services" section, plus `/qr ah|bank|void` slash commands.

**Tech Stack:** WoW Lua 5.1, Dijkstra pathfinding via `QR.PathCalculator`, `QR.POIRouting:RouteToMapPosition()` for route triggering.

---

## Important Conventions

Before implementing, review these project conventions:

- **Global caching**: All Lua files cache globals as locals at file top: `local pairs, ipairs = pairs, ipairs` etc.
- **Localization**: Use `QR.L` for all user-visible strings. Keys defined in `Localization.lua` with metatable fallback to English.
- **Logging**: Use `QR:Debug()`, `QR:Error()`, `QR:Warn()`, `QR:Print()` — never raw `print()`.
- **Player info**: Use `QR.PlayerInfo:GetFaction()`, `:GetClass()` — never `UnitFactionGroup()` directly.
- **Tests**: Run with `~/.local/bin/lua5.1 tests/run_tests.lua`. All tests must pass (currently 9961).
- **UX patterns**: `PlaySound(SOUNDKIT.*)` on clicks, `QR.AddTooltipBranding(GameTooltip)` before `GameTooltip:Show()`, `GameTooltip_Hide()` on OnLeave.
- **Commits**: Signed with `-S`, conventional commit format, no AI attribution.

---

### Task 1: Static Service POI Data

Create the data file with AH, Bank, and Void Storage coordinates for all capital cities.

**Files:**
- Create: `QuickRoute/Data/ServicePOIs.lua`
- Modify: `QuickRoute/QuickRoute.toc` (add after `Data/DungeonEntrances.lua`)
- Modify: `tests/addon_loader.lua` (add after `"Data/DungeonEntrances.lua"`)
- Create: `tests/test_service_router.lua` (data validation tests)

**Implementation:**

Create `QuickRoute/Data/ServicePOIs.lua`:

```lua
-- ServicePOIs.lua
-- Static coordinates for common service NPCs (Auction House, Bank, Void Storage)
-- in capital cities. Used by ServiceRouter to find nearest service via Dijkstra.
local ADDON_NAME, QR = ...

QR.ServicePOIs = {
    AUCTION_HOUSE = {
        -- Alliance
        { mapID = 84,   x = 0.6105, y = 0.7064, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.2549, y = 0.7468, faction = "Alliance" },  -- Ironforge
        { mapID = 89,   x = 0.5481, y = 0.5642, faction = "Alliance" },  -- Darnassus
        { mapID = 103,  x = 0.4842, y = 0.6925, faction = "Alliance" },  -- Exodar
        { mapID = 1161, x = 0.7195, y = 0.1298, faction = "Alliance" },  -- Boralus
        -- Horde
        { mapID = 85,   x = 0.5430, y = 0.6295, faction = "Horde" },     -- Orgrimmar
        { mapID = 90,   x = 0.6617, y = 0.3707, faction = "Horde" },     -- Undercity
        { mapID = 88,   x = 0.3920, y = 0.5296, faction = "Horde" },     -- Thunder Bluff
        { mapID = 110,  x = 0.6748, y = 0.3048, faction = "Horde" },     -- Silvermoon
        { mapID = 1165, x = 0.4228, y = 0.3283, faction = "Horde" },     -- Dazar'alor
        -- Neutral
        { mapID = 125,  x = 0.4264, y = 0.6397, faction = "both" },      -- Dalaran (Northrend)
        { mapID = 627,  x = 0.4264, y = 0.5545, faction = "both" },      -- Dalaran (Broken Isles)
        { mapID = 1670, x = 0.5844, y = 0.5576, faction = "both" },      -- Oribos
        { mapID = 2112, x = 0.4686, y = 0.5695, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.5542, y = 0.5632, faction = "both" },      -- Dornogal
    },
    BANK = {
        -- Alliance
        { mapID = 84,   x = 0.6282, y = 0.6995, faction = "Alliance" },  -- Stormwind
        { mapID = 87,   x = 0.3530, y = 0.6270, faction = "Alliance" },  -- Ironforge
        { mapID = 89,   x = 0.4355, y = 0.3543, faction = "Alliance" },  -- Darnassus
        { mapID = 103,  x = 0.4734, y = 0.6435, faction = "Alliance" },  -- Exodar
        { mapID = 1161, x = 0.7600, y = 0.1657, faction = "Alliance" },  -- Boralus
        -- Horde
        { mapID = 85,   x = 0.5330, y = 0.6455, faction = "Horde" },     -- Orgrimmar
        { mapID = 90,   x = 0.6397, y = 0.4865, faction = "Horde" },     -- Undercity
        { mapID = 88,   x = 0.4530, y = 0.5230, faction = "Horde" },     -- Thunder Bluff
        { mapID = 110,  x = 0.5780, y = 0.2190, faction = "Horde" },     -- Silvermoon
        { mapID = 1165, x = 0.4468, y = 0.3538, faction = "Horde" },     -- Dazar'alor
        -- Neutral
        { mapID = 125,  x = 0.4777, y = 0.6335, faction = "both" },      -- Dalaran (Northrend)
        { mapID = 627,  x = 0.4777, y = 0.5310, faction = "both" },      -- Dalaran (Broken Isles)
        { mapID = 1670, x = 0.6176, y = 0.4818, faction = "both" },      -- Oribos
        { mapID = 2112, x = 0.5720, y = 0.3425, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.4952, y = 0.5188, faction = "both" },      -- Dornogal
    },
    VOID_STORAGE = {
        -- Void Storage is only in major faction capitals + some neutral hubs
        -- Alliance
        { mapID = 84,   x = 0.6253, y = 0.7025, faction = "Alliance" },  -- Stormwind (next to bank)
        { mapID = 87,   x = 0.3550, y = 0.6240, faction = "Alliance" },  -- Ironforge (near bank)
        -- Horde
        { mapID = 85,   x = 0.5350, y = 0.6430, faction = "Horde" },     -- Orgrimmar (near bank)
        { mapID = 90,   x = 0.6420, y = 0.4830, faction = "Horde" },     -- Undercity (near bank)
        -- Neutral
        { mapID = 2112, x = 0.5730, y = 0.3420, faction = "both" },      -- Valdrakken
        { mapID = 2339, x = 0.4945, y = 0.5200, faction = "both" },      -- Dornogal
    },
}

    CRAFTING_TABLE = {
        -- Crafting tables (The War Within profession stations) - current expansion hubs
        { mapID = 2339, x = 0.4780, y = 0.5280, faction = "both" },      -- Dornogal
        { mapID = 2112, x = 0.3580, y = 0.6240, faction = "both" },      -- Valdrakken
    },
}

-- Service type metadata for display and slash commands
QR.ServiceTypes = {
    AUCTION_HOUSE  = { icon = "Interface\\Icons\\INV_Misc_Coin_01", slashAlias = "ah" },
    BANK           = { icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue", slashAlias = "bank" },
    VOID_STORAGE   = { icon = "Interface\\Icons\\Spell_Nature_AstralRecalGroup", slashAlias = "void" },
    CRAFTING_TABLE = { icon = "Interface\\Icons\\Trade_Blacksmithing", slashAlias = "craft" },
}
```

Add to `QuickRoute.toc` after `Data\DungeonEntrances.lua`:
```
Data\ServicePOIs.lua
```

Add to `tests/addon_loader.lua` after `"Data/DungeonEntrances.lua"`:
```lua
"Data/ServicePOIs.lua",
```

**Tests** — create `tests/test_service_router.lua` with initial data tests:

```lua
T:run("ServicePOIs: QR.ServicePOIs exists", function(t)
    t:assertNotNil(QR.ServicePOIs, "ServicePOIs table exists")
end)

T:run("ServicePOIs: has AUCTION_HOUSE, BANK, VOID_STORAGE", function(t)
    t:assertNotNil(QR.ServicePOIs.AUCTION_HOUSE, "AUCTION_HOUSE exists")
    t:assertNotNil(QR.ServicePOIs.BANK, "BANK exists")
    t:assertNotNil(QR.ServicePOIs.VOID_STORAGE, "VOID_STORAGE exists")
end)

T:run("ServicePOIs: each entry has mapID, x, y, faction", function(t)
    for serviceType, locations in pairs(QR.ServicePOIs) do
        for i, loc in ipairs(locations) do
            local label = serviceType .. "[" .. i .. "]"
            t:assertNotNil(loc.mapID, label .. " has mapID")
            t:assertNotNil(loc.x, label .. " has x")
            t:assertNotNil(loc.y, label .. " has y")
            t:assertNotNil(loc.faction, label .. " has faction")
            t:assertTrue(loc.faction == "Alliance" or loc.faction == "Horde" or loc.faction == "both",
                label .. " faction is valid")
        end
    end
end)

T:run("ServicePOIs: QR.ServiceTypes has metadata for each service", function(t)
    for serviceType, _ in pairs(QR.ServicePOIs) do
        t:assertNotNil(QR.ServiceTypes[serviceType],
            serviceType .. " has metadata in ServiceTypes")
        t:assertNotNil(QR.ServiceTypes[serviceType].icon,
            serviceType .. " has icon")
        t:assertNotNil(QR.ServiceTypes[serviceType].slashAlias,
            serviceType .. " has slashAlias")
    end
end)
```

Register test file in `tests/run_tests.lua` (add `"test_service_router.lua"` to the test files list).

**Verify:** `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass.

**Commit:** `feat: add static service POI data for AH, Bank, Void Storage`

---

### Task 2: Localization Keys

Add SERVICE_* and DEST_SEARCH_SERVICES keys in all 10 languages.

**Files:**
- Modify: `QuickRoute/Localization.lua`

**Implementation:**

Add to the enUS section (after `DEST_SEARCH_NO_RESULTS`):

```lua
-- Service POI routing
L["SERVICE_AUCTION_HOUSE"] = "Auction House"
L["SERVICE_BANK"] = "Bank"
L["SERVICE_VOID_STORAGE"] = "Void Storage"
L["SERVICE_CRAFTING_TABLE"] = "Crafting Table"
L["SERVICE_NEAREST"] = "Nearest %s"
L["DEST_SEARCH_SERVICES"] = "Services"
```

Add translations for all 9 other locales:

| Key | deDE | frFR | esES | ptBR | ruRU | koKR | zhCN | zhTW | itIT |
|-----|------|------|------|------|------|------|------|------|------|
| SERVICE_AUCTION_HOUSE | Auktionshaus | Hotel des ventes | Casa de subastas | Casa de Leiloes | Аукцион | 경매장 | 拍卖行 | 拍賣場 | Casa d'aste |
| SERVICE_BANK | Bank | Banque | Banco | Banco | Банк | 은행 | 银行 | 銀行 | Banca |
| SERVICE_VOID_STORAGE | Leerenlager | Coffre du Vide | Deposito del Vacio | Armazem do Vazio | Хранилище Бездны | 공허 보관함 | 虚空仓库 | 虛空倉庫 | Deposito del Vuoto |
| SERVICE_CRAFTING_TABLE | Handwerkstisch | Table d'artisanat | Mesa de artesania | Mesa de Artesanato | Стол ремёсел | 제작대 | 制作台 | 製作檯 | Tavolo da lavoro |
| SERVICE_NEAREST | Naechste/r %s | %s le/la plus proche | %s mas cercano/a | %s mais proximo/a | Ближайший %s | 가장 가까운 %s | 最近的%s | 最近的%s | %s piu vicino/a |
| DEST_SEARCH_SERVICES | Dienste | Services | Servicios | Servicos | Сервисы | 서비스 | 服务 | 服務 | Servizi |

**Tests** — add to `tests/test_service_router.lua`:

```lua
T:run("ServiceRouter: localization keys exist", function(t)
    local L = QR.L
    t:assertNotNil(L["SERVICE_AUCTION_HOUSE"], "SERVICE_AUCTION_HOUSE")
    t:assertNotNil(L["SERVICE_BANK"], "SERVICE_BANK")
    t:assertNotNil(L["SERVICE_VOID_STORAGE"], "SERVICE_VOID_STORAGE")
    t:assertNotNil(L["SERVICE_NEAREST"], "SERVICE_NEAREST")
    t:assertNotNil(L["DEST_SEARCH_SERVICES"], "DEST_SEARCH_SERVICES")
end)
```

**Verify:** `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass.

**Commit:** `feat: add service POI localization keys in 10 languages`

---

### Task 3: ServiceRouter Module

Create the core module with faction filtering and nearest-service Dijkstra routing.

**Files:**
- Create: `QuickRoute/Modules/ServiceRouter.lua`
- Modify: `QuickRoute/QuickRoute.toc` (add after `Modules\DestinationSearch.lua`)
- Modify: `tests/addon_loader.lua` (add after `"Modules/DestinationSearch.lua"`)

**Implementation:**

Create `QuickRoute/Modules/ServiceRouter.lua`:

```lua
-- ServiceRouter.lua
-- Routes player to nearest service POI (AH, Bank, Void Storage) using Dijkstra.
local ADDON_NAME, QR = ...

local pairs, ipairs = pairs, ipairs
local string_format = string.format
local string_lower = string.lower
local table_insert, table_sort = table.insert, table.sort
local math_huge = math.huge

QR.ServiceRouter = {}

local SR = QR.ServiceRouter
local L

--- Get all service type keys
-- @return table Array of service type strings (e.g. {"AUCTION_HOUSE","BANK","VOID_STORAGE"})
function SR:GetServiceTypes()
    local types = {}
    if QR.ServicePOIs then
        for serviceType in pairs(QR.ServicePOIs) do
            table_insert(types, serviceType)
        end
        table_sort(types)
    end
    return types
end

--- Get faction-filtered locations for a service type
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return table Array of location entries with mapID, x, y, faction
function SR:GetLocations(serviceType)
    local pois = QR.ServicePOIs and QR.ServicePOIs[serviceType]
    if not pois then return {} end

    local playerFaction = QR.PlayerInfo and QR.PlayerInfo:GetFaction() or "Alliance"
    local filtered = {}
    for _, loc in ipairs(pois) do
        if loc.faction == "both" or loc.faction == playerFaction then
            table_insert(filtered, loc)
        end
    end
    return filtered
end

--- Get localized service name
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return string Localized name (e.g. "Auction House")
function SR:GetServiceName(serviceType)
    L = QR.L
    local key = "SERVICE_" .. serviceType
    -- SERVICE_AUCTION_HOUSE is the key format in Localization.lua
    return L and L[key] or serviceType
end

--- Get city name for a service location (via mapID -> C_Map.GetMapInfo)
-- @param loc table Location entry with mapID
-- @return string City name
function SR:GetCityName(loc)
    if loc.mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(loc.mapID)
        if info and info.name then return info.name end
    end
    return string_format("Map %d", loc.mapID or 0)
end

--- Find the nearest service location using Dijkstra path cost
-- @param serviceType string e.g. "AUCTION_HOUSE"
-- @return table|nil bestLocation, number|nil bestCost, table|nil bestResult
function SR:FindNearest(serviceType)
    local locations = self:GetLocations(serviceType)
    if #locations == 0 then return nil, nil, nil end

    local bestLoc, bestCost, bestResult = nil, math_huge, nil

    for _, loc in ipairs(locations) do
        -- Use PathCalculator to calculate route cost
        if QR.PathCalculator and loc.mapID and loc.x and loc.y then
            local result = QR.PathCalculator:CalculatePath(loc.mapID, loc.x, loc.y)
            if result and result.totalTime and result.totalTime < bestCost then
                bestCost = result.totalTime
                bestLoc = loc
                bestResult = result
            end
        end
    end

    return bestLoc, bestCost, bestResult
end

--- Route to the nearest service of the given type
-- Shows route in UI via POIRouting:RouteToMapPosition
-- @param serviceType string e.g. "AUCTION_HOUSE"
function SR:RouteToNearest(serviceType)
    L = QR.L
    local bestLoc = self:FindNearest(serviceType)
    if not bestLoc then
        QR:Print(string_format("|cFFFF6600QuickRoute:|r %s",
            L and L["DEST_SEARCH_NO_RESULTS"] or "No matching destinations"))
        return
    end

    if QR.POIRouting then
        local serviceName = self:GetServiceName(serviceType)
        local cityName = self:GetCityName(bestLoc)
        local title = string_format("%s (%s)", serviceName, cityName)
        QR.POIRouting:RouteToMapPosition(bestLoc.mapID, bestLoc.x, bestLoc.y)
        -- Update search box with result title
        if QR.DestinationSearch then
            QR.DestinationSearch:SetSearchText(title)
        end
    end
end

--- Find service type by slash alias (e.g. "ah" -> "AUCTION_HOUSE")
-- @param alias string Slash command alias
-- @return string|nil serviceType
function SR:FindByAlias(alias)
    if not alias or not QR.ServiceTypes then return nil end
    local aliasLower = string_lower(alias)
    for serviceType, meta in pairs(QR.ServiceTypes) do
        if meta.slashAlias == aliasLower then
            return serviceType
        end
    end
    return nil
end

function SR:Initialize()
    L = QR.L
    QR:Debug("ServiceRouter initialized")
end
```

Add to `QuickRoute.toc` after `Modules\DestinationSearch.lua`:
```
Modules\ServiceRouter.lua
```

Add to `tests/addon_loader.lua` after `"Modules/DestinationSearch.lua"`:
```lua
"Modules/ServiceRouter.lua",
```

**Tests** — add to `tests/test_service_router.lua`:

```lua
T:run("ServiceRouter: module exists", function(t)
    t:assertNotNil(QR.ServiceRouter, "ServiceRouter exists")
end)

T:run("ServiceRouter: GetServiceTypes returns all types", function(t)
    local types = QR.ServiceRouter:GetServiceTypes()
    t:assertTrue(#types >= 3, "At least 3 service types")
    -- Check specific types exist
    local found = {}
    for _, st in ipairs(types) do found[st] = true end
    t:assertTrue(found["AUCTION_HOUSE"], "Has AUCTION_HOUSE")
    t:assertTrue(found["BANK"], "Has BANK")
    t:assertTrue(found["VOID_STORAGE"], "Has VOID_STORAGE")
end)

T:run("ServiceRouter: GetLocations filters by faction (Alliance)", function(t)
    resetState()
    MockWoW.config.playerFaction = "Alliance"
    QR.PlayerInfo:InvalidateCache()
    local locs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    t:assertTrue(#locs > 0, "Has AH locations for Alliance")
    for _, loc in ipairs(locs) do
        t:assertTrue(loc.faction == "Alliance" or loc.faction == "both",
            "No Horde-only locations for Alliance player")
    end
end)

T:run("ServiceRouter: GetLocations filters by faction (Horde)", function(t)
    resetState()
    MockWoW.config.playerFaction = "Horde"
    QR.PlayerInfo:InvalidateCache()
    local locs = QR.ServiceRouter:GetLocations("AUCTION_HOUSE")
    t:assertTrue(#locs > 0, "Has AH locations for Horde")
    for _, loc in ipairs(locs) do
        t:assertTrue(loc.faction == "Horde" or loc.faction == "both",
            "No Alliance-only locations for Horde player")
    end
end)

T:run("ServiceRouter: GetServiceName returns localized name", function(t)
    resetState()
    local name = QR.ServiceRouter:GetServiceName("AUCTION_HOUSE")
    t:assertEqual("Auction House", name)
end)

T:run("ServiceRouter: GetCityName returns map name", function(t)
    resetState()
    -- mapID 84 = Stormwind in mock
    local name = QR.ServiceRouter:GetCityName({ mapID = 84 })
    t:assertNotNil(name, "City name not nil")
    t:assertTrue(#name > 0, "City name not empty")
end)

T:run("ServiceRouter: FindByAlias maps aliases correctly", function(t)
    resetState()
    t:assertEqual("AUCTION_HOUSE", QR.ServiceRouter:FindByAlias("ah"))
    t:assertEqual("BANK", QR.ServiceRouter:FindByAlias("bank"))
    t:assertEqual("VOID_STORAGE", QR.ServiceRouter:FindByAlias("void"))
    t:assertNil(QR.ServiceRouter:FindByAlias("unknown"))
end)
```

**Verify:** `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass.

**Commit:** `feat: add ServiceRouter module for nearest-service routing`

---

### Task 4: DestinationSearch Integration

Add "Services" section to the unified search dropdown.

**Files:**
- Modify: `QuickRoute/Modules/DestinationSearch.lua` — `CollectResults()` (~line 39-135) and `RefreshDropdown()` (~line 383-486)

**Implementation:**

In `CollectResults()`, add a `services` field to the results table (line 48):
```lua
local results = {
    waypoints = {},
    cities = {},
    dungeons = {},
    services = {},  -- NEW
}
```

After the dungeons section (~line 133, before `return results`), add service collection:

```lua
-- 4. Services (AH, Bank, Void Storage)
local SR = QR.ServiceRouter
if SR then
    local serviceTypes = SR:GetServiceTypes()
    for _, serviceType in ipairs(serviceTypes) do
        local serviceName = SR:GetServiceName(serviceType)
        -- Match if searching for service name
        if not isSearching or string_find(string_lower(serviceName), queryLower, 1, true) then
            local locations = SR:GetLocations(serviceType)
            if #locations > 0 then
                -- Add city names to each location for display
                local locs = {}
                for _, loc in ipairs(locations) do
                    table_insert(locs, {
                        name = SR:GetCityName(loc),
                        mapID = loc.mapID,
                        x = loc.x,
                        y = loc.y,
                        serviceType = serviceType,
                    })
                end
                table_sort(locs, function(a, b) return a.name < b.name end)
                table_insert(results.services, {
                    serviceType = serviceType,
                    serviceName = serviceName,
                    locations = locs,
                })
            end
        end
    end
end
```

In `RefreshDropdown()`, after the dungeons section (~line 466, before "No results" message), add:

```lua
-- 4. Services section
if #results.services > 0 then
    local sectionTitle = L and L["DEST_SEARCH_SERVICES"] or "Services"
    local _, newY = self:CreateSectionHeader("services", sectionTitle, yOffset)
    yOffset = newY
    totalRows = totalRows + 1

    if not self.collapsedSections["services"] then
        for _, svc in ipairs(results.services) do
            -- "Nearest X" auto-pick row
            local nearestEntry = {
                name = string_format(L and L["SERVICE_NEAREST"] or "Nearest %s", svc.serviceName),
                serviceType = svc.serviceType,
                isNearestService = true,
                tag = "",
            }
            local nearestRow = self:GetRow()
            nearestRow:SetPoint("TOPLEFT", self.frame.scrollChild, "TOPLEFT", 0, -yOffset)
            nearestRow:SetPoint("RIGHT", self.frame.scrollChild, "RIGHT", 0, 0)
            nearestRow.nameLabel:SetText("  " .. nearestEntry.name)
            nearestRow.nameLabel:SetTextColor(0.4, 0.8, 1)  -- Blue highlight for auto-pick
            nearestRow.tagLabel:SetText("")

            nearestRow:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                if QR.ServiceRouter then
                    QR.ServiceRouter:RouteToNearest(svc.serviceType)
                end
                DS:HideDropdown()
            end)
            nearestRow:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(nearestEntry.name, 1, 0.82, 0)
                GameTooltip:AddLine(L and L["DEST_SEARCH_ROUTE_TO_TT"] or "Click to calculate route", 0.5, 0.5, 0.5, true)
                QR.AddTooltipBranding(GameTooltip)
                GameTooltip:Show()
            end)
            nearestRow:SetScript("OnLeave", function() GameTooltip_Hide() end)
            table_insert(self.rows, nearestRow)
            yOffset = yOffset + ROW_HEIGHT
            totalRows = totalRows + 1

            -- Individual city locations
            for _, loc in ipairs(svc.locations) do
                loc.tag = ""
                local _, newY2 = self:CreateResultRow(loc, yOffset)
                yOffset = newY2
                totalRows = totalRows + 1
            end
        end
    end
end
```

**Tests** — add to `tests/test_destination_search.lua`:

```lua
T:run("DestSearch: CollectResults includes services section", function(t)
    resetState()
    local results = QR.DestinationSearch:CollectResults("")
    t:assertNotNil(results.services, "services field exists")
    t:assertTrue(#results.services > 0, "Has service entries")
end)

T:run("DestSearch: services filtered by search query", function(t)
    resetState()
    local results = QR.DestinationSearch:CollectResults("auction")
    t:assertTrue(#results.services > 0, "Auction matches")
    -- Check the matched service is AUCTION_HOUSE
    local foundAH = false
    for _, svc in ipairs(results.services) do
        if svc.serviceType == "AUCTION_HOUSE" then foundAH = true end
    end
    t:assertTrue(foundAH, "AUCTION_HOUSE found via search")

    -- Search for something that doesn't match
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
            t:assertTrue(loc.mapID ~= nil, "Location has mapID")
        end
    end
end)
```

**Verify:** `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass.

**Commit:** `feat: integrate services section into destination search dropdown`

---

### Task 5: Slash Commands and Init

Add `/qr ah|bank|void` commands and ServiceRouter to the init sequence.

**Files:**
- Modify: `QuickRoute/Modules/UI.lua` — `/qr` slash handler (~line 1894)
- Modify: `QuickRoute/QuickRoute.lua` — init steps (~line 198)
- Modify: `QuickRoute/QuickRoute.lua` — PrintHelp (~line 288-305)

**Implementation:**

In `UI.lua`, add to the `/qr` slash handler (after `elseif cmd == "minimap"` block, before `elseif cmd == "" then`):

```lua
elseif cmd == "ah" or cmd == "bank" or cmd == "void" or cmd == "craft" then
    if QR.ServiceRouter then
        local serviceType = QR.ServiceRouter:FindByAlias(cmd)
        if serviceType then
            QR.ServiceRouter:RouteToNearest(serviceType)
            -- Open the route tab to show results
            if QR.MainFrame then QR.MainFrame:Show("route") end
        end
    end
```

In `QuickRoute.lua`, add to the init steps array (after the DestinationSearch line):
```lua
{ "ServiceRouter",      function() QR.ServiceRouter:Initialize() end },
```

In `QuickRoute.lua`, add to `PrintHelp()`:
```lua
print("  /qr ah - Route to nearest Auction House")
print("  /qr bank - Route to nearest Bank")
print("  /qr void - Route to nearest Void Storage")
print("  /qr craft - Route to nearest Crafting Table")
```

Also add to the inline help block in the `/qr` slash handler (the `else` branch at end):
```lua
print("  /qr ah|bank|void - Route to nearest service")
```

**Tests** — add to `tests/test_service_router.lua`:

```lua
T:run("ServiceRouter: /qr ah slash command wiring", function(t)
    resetState()
    -- The SlashCmdList["QR"] handler should exist
    t:assertNotNil(SlashCmdList["QR"], "QR slash handler exists")
    -- Verify ServiceRouter init step is in the init sequence
    t:assertNotNil(QR.ServiceRouter, "ServiceRouter module loaded")
    t:assertNotNil(QR.ServiceRouter.Initialize, "Has Initialize method")
    t:assertNotNil(QR.ServiceRouter.RouteToNearest, "Has RouteToNearest method")
end)
```

**Verify:** `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass.

**Commit:** `feat: add /qr ah|bank|void slash commands for service routing`

---

### Task 6: Final Verification and Deploy

Run full test suite, verify luacheck (CI only), deploy to WoW addons folder.

**Steps:**

1. Run: `~/.local/bin/lua5.1 tests/run_tests.lua` — all tests pass
2. Deploy: `cp -r QuickRoute/* "/mnt/f/World of Warcraft/_retail_/Interface/AddOns/QuickRoute/"`
3. In-game verification checklist:
   - `/qr ah` routes to nearest AH
   - `/qr bank` routes to nearest Bank
   - `/qr void` routes to nearest Void Storage
   - Type "auction" in destination search → Services section appears with "Nearest Auction House" + city list
   - Type "bank" in destination search → Bank entries appear
   - Click "Nearest Auction House" → route calculates and displays
   - Click a specific city → routes to that city's AH
   - Services section is collapsible
   - All tooltips have branding
   - Sounds play on clicks

**No commit for this task** — it's verification only.
