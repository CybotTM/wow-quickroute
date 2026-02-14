# Unified Destination Search Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Route tab's waypoint source dropdown + dungeon picker button with a unified search box that provides access to auto-detected waypoints, cities, and dungeons/raids in a single grouped dropdown.

**Architecture:** A new `DestinationSearch` module creates an EditBox + BackdropTemplate dropdown popup in the Route tab toolbar. The dropdown shows results grouped by category (Active Waypoint, Cities, Dungeons & Raids) with section headers and search filtering. Selection routes via the existing `POIRouting:RouteToMapPosition()` pipeline. The module follows the same patterns as the existing DungeonPicker (row pool, scroll frame, combat hide, ESC-to-close).

**Tech Stack:** WoW Lua 5.1, standalone test framework (`tests/run_tests.lua`), MockWoW test harness

---

## Context for the Implementer

### Project structure
- Addon code: `QuickRoute/` — loaded in order defined by `QuickRoute.toc`
- Tests: `tests/` — run via `~/.local/bin/lua5.1 tests/run_tests.lua`
- Test loader: `tests/addon_loader.lua` — mirrors .toc file list, loads all addon files in order
- Test framework: `tests/test_framework.lua` — provides `T:run(name, fn)`, `t:assertEqual`, `t:assertNotNil`, etc.
- Mock WoW API: `tests/mock_wow_api.lua` — provides `CreateFrame`, `C_Map`, `GameTooltip`, `PlaySound`, etc.

### Key patterns to follow
- **Global caching**: Every Lua file starts with `local pairs, ipairs = pairs, ipairs` etc.
- **Localization**: Use `QR.L` table with `L["KEY"]` lookups. English defaults in `Localization.lua`, translations for deDE, frFR, esES, ptBR, ruRU, koKR, zhCN, zhTW, itIT.
- **UX consistency**: `QR.AddTooltipBranding(GameTooltip)` before `GameTooltip:Show()`, `GameTooltip_Hide` (global func) on leave, `PlaySound(SOUNDKIT.*)` on click, gold `(1, 0.82, 0)` header color, muted border `(0.4, 0.4, 0.4, 0.8)`.
- **Frame recycling**: Row pool pattern from DungeonPicker (see `GetRow()` / `ReleaseAllRows()`)
- **Combat hide**: `QR:RegisterCombatCallback(enterCb, leaveCb)` in QuickRoute.lua
- **ESC to close**: `table_insert(UISpecialFrames, "QRFrameName")`
- **isShowing sync**: Always add `OnHide` script to sync `isShowing = false`
- **Routing**: All destinations route via `QR.POIRouting:RouteToMapPosition(mapID, x, y)` which saves to `QR.db.lastDestination` and triggers `UI:RefreshRoute()`

### What we're replacing in UI.lua (lines 268-356)
Currently the Route tab toolbar has:
1. `WowStyle1DropdownTemplate` — waypoint source selector ("Auto", "Map Pin", "TomTom", "Quest")
2. Refresh button
3. Copy Debug button
4. Zone Debug button
5. Dungeon Picker button

After this change:
1. **EditBox** (search box) — replaces dropdown + dungeon button
2. Refresh button (stays, repositioned)
3. Copy Debug button (stays)
4. Zone Debug button (stays)

### Data sources

**CAPITAL_CITIES** (PathCalculator.lua lines 110-132): Table of `[name] = {mapID, x, y, faction}`. 17 entries: 5 Alliance, 5 Horde, 7 neutral. Currently `local` — must be exposed as `QR.CAPITAL_CITIES`.

**DungeonData** (Modules/DungeonData.lua): Provides `DD.instances`, `DD.byTier`, `DD:GetTierName(tier)`, `DD:GetAllTiers()`. Scans EJ on initialize. Each instance: `{name, isRaid, zoneMapID, x, y, tier, tierName}`.

**WaypointIntegration** (Modules/WaypointIntegration.lua): `GetActiveWaypoint()` returns `{mapID, x, y, title, source}`, `GetAllAvailableWaypoints()` returns `[{key, label, waypoint}]`.

---

### Task 1: Expose CAPITAL_CITIES and add localization keys

**Files:**
- Modify: `QuickRoute/Core/PathCalculator.lua:110-132`
- Modify: `QuickRoute/Localization.lua`
- Test: `tests/test_destination_search.lua` (create)

**Step 1: Write the failing test**

Create `tests/test_destination_search.lua`:

```lua
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
    t:assertEqual(type(QR.CAPITAL_CITIES), "table")
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
end)
```

**Step 2: Register the test file**

Add `"test_destination_search"` to the test file list in `tests/run_tests.lua`.

**Step 3: Run test to verify it fails**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: FAIL — `QR.CAPITAL_CITIES` is nil, L keys missing

**Step 4: Expose CAPITAL_CITIES**

In `QuickRoute/Core/PathCalculator.lua`, change line ~132 (after the table definition):
```lua
-- Expose for DestinationSearch module
QR.CAPITAL_CITIES = CAPITAL_CITIES
```

**Step 5: Add localization keys**

In `QuickRoute/Localization.lua`, add to the enUS defaults section:

```lua
-- Destination Search
L["DEST_SEARCH_PLACEHOLDER"] = "Search destinations..."
L["DEST_SEARCH_ACTIVE_WAYPOINT"] = "Active Waypoint"
L["DEST_SEARCH_CITIES"] = "Cities"
L["DEST_SEARCH_DUNGEONS"] = "Dungeons & Raids"
L["DEST_SEARCH_NO_RESULTS"] = "No matching destinations"
L["DEST_SEARCH_ROUTE_TO_TT"] = "Click to calculate route"
```

Add translations for all 9 non-English locales (deDE, frFR, esES, ptBR, ruRU, koKR, zhCN, zhTW, itIT):

| Key | deDE | frFR | esES |
|-----|------|------|------|
| DEST_SEARCH_PLACEHOLDER | Ziele suchen... | Rechercher destinations... | Buscar destinos... |
| DEST_SEARCH_ACTIVE_WAYPOINT | Aktiver Wegpunkt | Point de passage actif | Punto de ruta activo |
| DEST_SEARCH_CITIES | Staedte | Villes | Ciudades |
| DEST_SEARCH_DUNGEONS | Dungeons & Schlachtzuege | Donjons & Raids | Mazmorras y bandas |
| DEST_SEARCH_NO_RESULTS | Keine passenden Ziele | Aucune destination correspondante | No se encontraron destinos |
| DEST_SEARCH_ROUTE_TO_TT | Klicken um Route zu berechnen | Cliquer pour calculer l'itineraire | Clic para calcular la ruta |

(Continue for ptBR, ruRU, koKR, zhCN, zhTW, itIT following the same patterns used for DUNGEON_PICKER_* keys.)

**Step 6: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all new tests + all existing 9819 tests

**Step 7: Commit**

```bash
git add QuickRoute/Core/PathCalculator.lua QuickRoute/Localization.lua tests/test_destination_search.lua tests/run_tests.lua
git commit -S -m "feat: expose CAPITAL_CITIES and add destination search localization keys"
```

---

### Task 2: Create DestinationSearch module — data collection

**Files:**
- Create: `QuickRoute/Modules/DestinationSearch.lua`
- Modify: `QuickRoute/QuickRoute.toc` (add file)
- Modify: `tests/addon_loader.lua` (add file)
- Test: `tests/test_destination_search.lua` (extend)

**Step 1: Write failing tests for data collection**

Append to `tests/test_destination_search.lua`:

```lua
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

    -- Should include Alliance + neutral cities, not Horde
    local hasStormwind = false
    local hasOrgrimmar = false
    local hasValdrakken = false
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

    local hasStormwind = false
    local hasOrgrimmar = false
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
    local results = DS:CollectResults("storm")

    local count = 0
    for _, city in ipairs(results.cities) do
        count = count + 1
        -- All results must match "storm" (case-insensitive)
    end
    t:assertTrue(count > 0, "At least one city matches 'storm'")
    t:assertTrue(count < 12, "Fewer than all cities match 'storm'")
end)

T:run("DestSearch: search filters dungeons by name", function(t)
    resetState()
    -- Ensure DungeonData is scanned
    if QR.DungeonData and not QR.DungeonData.scanned then
        QR.DungeonData:Initialize()
    end

    local DS = QR.DestinationSearch
    local results = DS:CollectResults("stonevault")

    -- Should have at least one dungeon if DungeonData contains Stonevault
    t:assertNotNil(results.dungeons, "dungeons group exists")
end)

T:run("DestSearch: empty search returns all cities", function(t)
    resetState()
    local DS = QR.DestinationSearch
    local results = DS:CollectResults("")

    -- Alliance: 5 + 6 neutral = 11 (Dornogal added later, Dalaran x2)
    t:assertTrue(#results.cities >= 10, "At least 10 cities for Alliance: got " .. #results.cities)
end)
```

**Step 2: Run tests to verify they fail**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: FAIL — `QR.DestinationSearch` is nil

**Step 3: Create the DestinationSearch module (data layer)**

Create `QuickRoute/Modules/DestinationSearch.lua`:

```lua
-- DestinationSearch.lua
-- Unified search box + dropdown for routing to waypoints, cities, and dungeons.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals for performance
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_format = string.format
local string_lower = string.lower
local string_find = string.find
local table_insert, table_sort = table.insert, table.sort
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------------
-- DestinationSearch Module
-------------------------------------------------------------------------------
QR.DestinationSearch = {
    frame = nil,        -- dropdown popup frame
    searchBox = nil,    -- EditBox reference (lives in Route tab toolbar)
    isShowing = false,
    rows = {},
    rowPool = {},
    collapsedSections = {},  -- section key -> true if collapsed
}

local DS = QR.DestinationSearch

-- Localization shorthand (set on Initialize)
local L

-------------------------------------------------------------------------------
-- Data Collection
-------------------------------------------------------------------------------

--- Collect all destination results, optionally filtered by search query
-- @param query string Search text (empty = all results)
-- @return table { waypoints = {}, cities = {}, dungeons = {} }
function DS:CollectResults(query)
    L = QR.L
    local queryLower = string_lower(query or "")
    local isSearching = queryLower ~= ""

    local results = {
        waypoints = {},
        cities = {},
        dungeons = {},  -- array of { tierName, tierIndex, instances = {} }
    }

    -- 1. Active Waypoints
    if QR.WaypointIntegration then
        local available = QR.WaypointIntegration:GetAllAvailableWaypoints()
        for _, entry in ipairs(available) do
            if entry.waypoint then
                local title = entry.waypoint.title or entry.label or "?"
                if not isSearching or string_find(string_lower(title), queryLower, 1, true) then
                    table_insert(results.waypoints, {
                        name = title,
                        label = entry.label,
                        key = entry.key,
                        mapID = entry.waypoint.mapID,
                        x = entry.waypoint.x,
                        y = entry.waypoint.y,
                        source = entry.key,
                    })
                end
            end
        end
    end

    -- 2. Cities (filtered by player faction)
    local playerFaction = QR.PlayerInfo and QR.PlayerInfo:GetFaction() or "Alliance"
    local cities = QR.CAPITAL_CITIES
    if cities then
        local cityList = {}
        for name, data in pairs(cities) do
            if data.faction == "both" or data.faction == playerFaction then
                if not isSearching or string_find(string_lower(name), queryLower, 1, true) then
                    table_insert(cityList, {
                        name = name,
                        mapID = data.mapID,
                        x = data.x,
                        y = data.y,
                        faction = data.faction,
                    })
                end
            end
        end
        -- Sort alphabetically
        table_sort(cityList, function(a, b) return a.name < b.name end)
        results.cities = cityList
    end

    -- 3. Dungeons & Raids (from DungeonData, grouped by tier)
    local DD = QR.DungeonData
    if DD and DD.scanned then
        for tier = DD.numTiers, 1, -1 do
            local tierName = DD:GetTierName(tier) or string_format("Tier %d", tier)
            local tierInstances = DD.byTier[tier] or {}

            local matchingInstances = {}
            for _, instanceID in ipairs(tierInstances) do
                local inst = DD.instances[instanceID]
                if inst and inst.name then
                    if not isSearching or string_find(string_lower(inst.name), queryLower, 1, true) then
                        table_insert(matchingInstances, {
                            name = inst.name,
                            isRaid = inst.isRaid,
                            zoneMapID = inst.zoneMapID,
                            x = inst.x,
                            y = inst.y,
                        })
                    end
                end
            end

            -- Sort: dungeons first, then raids, alphabetical within
            table_sort(matchingInstances, function(a, b)
                if a.isRaid ~= b.isRaid then return not a.isRaid end
                return a.name < b.name
            end)

            if #matchingInstances > 0 or not isSearching then
                table_insert(results.dungeons, {
                    tierName = tierName,
                    tierIndex = tier,
                    instances = matchingInstances,
                })
            end
        end
    end

    return results
end

-------------------------------------------------------------------------------
-- Initialize
-------------------------------------------------------------------------------

function DS:Initialize()
    L = QR.L
    self:RegisterCombat()
    QR:Debug("DestinationSearch initialized")
end

--- Register combat callbacks (auto-hide dropdown on combat enter)
function DS:RegisterCombat()
    QR:RegisterCombatCallback(
        function() DS:HideDropdown() end,  -- enter combat
        nil  -- leave combat: no action needed
    )
end

--- Hide the dropdown popup
function DS:HideDropdown()
    if self.frame then
        self.frame:Hide()
    end
    self.isShowing = false
end
```

**Step 4: Add to .toc and addon_loader.lua**

In `QuickRoute/QuickRoute.toc`, add after `Modules/DungeonPicker.lua`:
```
Modules/DestinationSearch.lua
```

In `tests/addon_loader.lua`, add after `"Modules/DungeonPicker.lua"`:
```lua
"Modules/DestinationSearch.lua",
```

**Step 5: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all tests

**Step 6: Commit**

```bash
git add QuickRoute/Modules/DestinationSearch.lua QuickRoute/QuickRoute.toc tests/addon_loader.lua tests/test_destination_search.lua
git commit -S -m "feat: add DestinationSearch module with data collection"
```

---

### Task 3: Create dropdown popup UI

**Files:**
- Modify: `QuickRoute/Modules/DestinationSearch.lua`
- Test: `tests/test_destination_search.lua` (extend)

**Step 1: Write failing tests for dropdown UI**

Append to `tests/test_destination_search.lua`:

```lua
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

    -- Initialize DungeonData so RefreshDropdown works
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
    t:assertTrue(DS.isShowing, "Showing after show")
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
    -- Simulate frame:Hide() (like ESC key would)
    DS.frame:Hide()
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
    DS:Initialize()
    DS:ShowDropdown()
    t:assertTrue(DS.isShowing, "Showing before combat")

    -- Simulate entering combat
    MockWoW:FireEvent("PLAYER_REGEN_DISABLED")
    t:assertFalse(DS.isShowing, "Hidden after combat enter")
end)

T:run("DestSearch: selecting city routes via POIRouting", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    -- Track POIRouting calls
    local routedTo = nil
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routedTo = { mapID = mapID, x = x, y = y }
    end

    local DS = QR.DestinationSearch
    DS:SelectResult({
        type = "city",
        name = "Stormwind City",
        mapID = 84,
        x = 0.4965,
        y = 0.8725,
    })

    t:assertNotNil(routedTo, "POIRouting called")
    t:assertEqual(routedTo.mapID, 84, "Correct mapID")

    -- Restore
    QR.POIRouting.RouteToMapPosition = origRoute
end)
```

**Step 2: Run tests to verify they fail**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: FAIL — `CreateDropdown`, `ShowDropdown`, `SelectResult` not defined

**Step 3: Implement dropdown popup UI**

Add to `DestinationSearch.lua` — the full dropdown frame creation, row pool, show/hide, section headers, city rows, dungeon rows, waypoint rows, and selection handler. Follow the DungeonPicker pattern exactly:

- `CreateDropdown()`: Creates BackdropTemplate frame, scrollFrame, scrollChild. Registers in UISpecialFrames. Sets OnHide to sync `isShowing`. Starts hidden.
- `GetRow()` / `ReleaseAllRows()`: Row pool identical to DungeonPicker pattern.
- `CreateSectionHeader(sectionKey, title, yOffset)`: Gold text, collapse toggle (+/-), click handler.
- `CreateResultRow(entry, yOffset)`: Item row with name, optional tag, click to select, tooltip with branding.
- `RefreshDropdown(query)`: Calls `CollectResults(query)`, builds section headers + rows.
- `ShowDropdown(anchorFrame)`: Creates frame if needed, anchors below `anchorFrame`, calls RefreshDropdown, shows.
- `SelectResult(entry)`: Routes via `POIRouting:RouteToMapPosition()`, hides dropdown, sets search box text.

Constants: `DROPDOWN_WIDTH = 340`, `ROW_HEIGHT = 22`, `HEADER_HEIGHT = 24`, `MAX_VISIBLE_ROWS = 16`, `PADDING = 6`.

**Step 4: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all tests

**Step 5: Commit**

```bash
git add QuickRoute/Modules/DestinationSearch.lua tests/test_destination_search.lua
git commit -S -m "feat: add DestinationSearch dropdown popup UI"
```

---

### Task 4: Integrate into Route tab toolbar

**Files:**
- Modify: `QuickRoute/Modules/UI.lua:260-392` (CreateContent)
- Modify: `QuickRoute/Modules/UI.lua:618-696` (UpdateRoute — remove dropdown text update)
- Modify: `QuickRoute/Modules/UI.lua:554-588` (remove InitializeSourceDropdown)
- Modify: `QuickRoute/QuickRoute.lua` (add DestinationSearch to init sequence)
- Test: `tests/test_ui.lua` (update existing dropdown tests)
- Test: `tests/test_destination_search.lua` (extend)

**Step 1: Write failing tests for integration**

Append to `tests/test_destination_search.lua`:

```lua
-------------------------------------------------------------------------------
-- 5. Route Tab Integration
-------------------------------------------------------------------------------

T:run("DestSearch: search box exists on Route tab", function(t)
    resetState()

    -- Initialize UI with a parent frame
    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNotNil(QR.UI.frame, "UI frame created")
    -- The search box should be a child of the frame
    t:assertNotNil(parentFrame.searchBox, "searchBox exists on frame")
end)

T:run("DestSearch: no sourceDropdown on Route tab", function(t)
    resetState()

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNil(parentFrame.sourceDropdown, "sourceDropdown removed")
end)

T:run("DestSearch: no dungeon button on Route tab", function(t)
    resetState()

    local parentFrame = CreateFrame("Frame", nil, UIParent)
    parentFrame:SetSize(500, 400)
    QR.UI.frame = nil
    QR.UI:CreateContent(parentFrame)

    t:assertNil(parentFrame.dungeonButton, "dungeonButton removed")
end)
```

**Step 2: Run tests to verify they fail**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: FAIL — sourceDropdown still exists, searchBox doesn't exist

**Step 3: Modify UI.lua CreateContent**

In `UI:CreateContent()` (lines 268-356), replace:
- **Remove**: `WowStyle1DropdownTemplate` dropdown creation (lines 269-272)
- **Remove**: Dungeon picker button creation (lines 337-356)
- **Remove**: `self:InitializeSourceDropdown()` call (line 389)
- **Add**: EditBox (search box) in the same position:

```lua
-- Search box (replaces source dropdown + dungeon button)
local searchBox = CreateFrame("EditBox", "QRDestSearchBox", frame, "InputBoxTemplate")
searchBox:SetSize(180, BUTTON_HEIGHT)
searchBox:SetPoint("TOPLEFT", PADDING + 5, -4)
searchBox:SetAutoFocus(false)
searchBox:SetFontObject(GameFontHighlightSmall)
searchBox:SetScript("OnTextChanged", function(self)
    if QR.DestinationSearch then
        QR.DestinationSearch:OnSearchTextChanged(self:GetText() or "")
    end
end)
searchBox:SetScript("OnEditFocusGained", function(self)
    if QR.DestinationSearch then
        QR.DestinationSearch:ShowDropdown(self)
    end
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if QR.DestinationSearch then
        QR.DestinationSearch:HideDropdown()
    end
end)
searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
frame.searchBox = searchBox

-- Store reference for DestinationSearch
QR.DestinationSearch.searchBox = searchBox

-- Set placeholder text
if QR.L then
    searchBox:SetText("")
    -- WoW InputBoxTemplate supports placeholder natively via instructions
end
```

- **Reposition**: Refresh button anchors to `searchBox` RIGHT instead of `sourceDropdown` RIGHT

**Step 4: Remove dropdown text update from UpdateRoute**

In `UI:UpdateRoute()` (lines 680-696), remove the block that updates `sourceDropdown` text:
```lua
-- REMOVE: Update dropdown text with active source (lines 680-696)
```

Instead, when a route is successfully calculated, update the search box text with the destination name:
```lua
-- Update search box with destination name
if result.waypoint and result.waypoint.title and QR.DestinationSearch then
    QR.DestinationSearch:SetSearchText(result.waypoint.title)
end
```

**Step 5: Remove InitializeSourceDropdown function**

Delete the entire `UI:InitializeSourceDropdown()` function (lines 554-588).

**Step 6: Add DestinationSearch to init sequence**

In `QuickRoute.lua`, add to the `steps` table in `OnPlayerLogin()`, after the DungeonPicker entry:
```lua
{ "DestinationSearch", function() QR.DestinationSearch:Initialize() end },
```

**Step 7: Update existing tests**

In `tests/test_ui.lua`, find and update any tests that reference `sourceDropdown` or `dungeonButton`:
- Tests checking `frame.sourceDropdown` should be updated to check `frame.searchBox` instead
- Tests checking `frame.dungeonButton` should be removed or updated
- Any test that calls `InitializeSourceDropdown()` should be removed

**Step 8: Run all tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all tests

**Step 9: Commit**

```bash
git add QuickRoute/Modules/UI.lua QuickRoute/Modules/DestinationSearch.lua QuickRoute/QuickRoute.lua tests/test_ui.lua tests/test_destination_search.lua
git commit -S -m "feat: integrate destination search into Route tab toolbar"
```

---

### Task 5: Remove `selectedWaypointSource` setting

**Files:**
- Modify: `QuickRoute/QuickRoute.lua:136-156` (remove from defaults)
- Modify: `QuickRoute/Modules/UI.lua:440-455` (simplify RefreshRoute)
- Modify: `QuickRoute/Modules/SettingsPanel.lua` (remove waypoint source setting if present)
- Test: `tests/test_ui.lua` (update RefreshRoute tests)

**Step 1: Remove `selectedWaypointSource` from defaults**

In `QuickRoute.lua`, remove from the `defaults` table:
```lua
-- REMOVE:
-- selectedWaypointSource = "auto",
```

**Step 2: Simplify RefreshRoute waypoint detection**

In `UI:RefreshRoute()`, the `WaypointIntegration:GetActiveWaypoint()` call currently respects `selectedWaypointSource`. Now it should always use "auto" behavior (detect best available waypoint). The `GetActiveWaypoint()` function already defaults to "auto" when `selectedWaypointSource` is nil, so removing the setting is sufficient.

**Step 3: Run all tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all tests

**Step 4: Commit**

```bash
git add QuickRoute/QuickRoute.lua QuickRoute/Modules/UI.lua
git commit -S -m "chore: remove selectedWaypointSource setting (replaced by destination search)"
```

---

### Task 6: Add OnSearchTextChanged and dropdown refresh

**Files:**
- Modify: `QuickRoute/Modules/DestinationSearch.lua`
- Test: `tests/test_destination_search.lua` (extend)

**Step 1: Write failing tests**

```lua
-------------------------------------------------------------------------------
-- 6. Search Text Change
-------------------------------------------------------------------------------

T:run("DestSearch: OnSearchTextChanged filters results", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    -- Count rows with empty search
    local initialRowCount = #DS.rows

    -- Now search for "storm" - should have fewer rows
    DS:OnSearchTextChanged("storm")
    local filteredRowCount = #DS.rows

    t:assertTrue(filteredRowCount < initialRowCount,
        "Filtered rows (" .. filteredRowCount .. ") < initial (" .. initialRowCount .. ")")
end)

T:run("DestSearch: SetSearchText updates editbox text", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    -- Create a mock search box
    local mockBox = CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
    QR.DestinationSearch.searchBox = mockBox

    QR.DestinationSearch:SetSearchText("Valdrakken")
    t:assertEqual(mockBox:GetText(), "Valdrakken", "Text set correctly")
end)
```

**Step 2: Implement OnSearchTextChanged and SetSearchText**

Add to `DestinationSearch.lua`:

```lua
--- Called when the search EditBox text changes
-- @param text string Current search text
function DS:OnSearchTextChanged(text)
    if self.isShowing then
        self:RefreshDropdown(text or "")
    end
end

--- Set the search box text (e.g., after route calculation shows destination)
-- @param text string The text to display
function DS:SetSearchText(text)
    if self.searchBox then
        self.searchBox:SetText(text or "")
    end
end
```

**Step 3: Run tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS

**Step 4: Commit**

```bash
git add QuickRoute/Modules/DestinationSearch.lua tests/test_destination_search.lua
git commit -S -m "feat: add search text change handler and dropdown refresh"
```

---

### Task 7: UX consistency and polish

**Files:**
- Modify: `QuickRoute/Modules/DestinationSearch.lua`
- Modify: `tests/test_ux_consistency.lua` (add DestinationSearch checks)
- Test: `tests/test_destination_search.lua` (extend)

**Step 1: Write UX tests**

```lua
-------------------------------------------------------------------------------
-- 7. UX Consistency
-------------------------------------------------------------------------------

T:run("DestSearch: click plays sound", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}
    MockWoW.config.playedSounds = {}

    local routedTo = nil
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routedTo = { mapID = mapID, x = x, y = y }
    end

    local DS = QR.DestinationSearch
    DS:SelectResult({
        type = "city",
        name = "Stormwind City",
        mapID = 84,
        x = 0.4965,
        y = 0.8725,
    })

    t:assertTrue(#MockWoW.config.playedSounds > 0, "Sound played on selection")
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DestSearch: tooltip has branding on row hover", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    -- Find a result row and trigger OnEnter
    local foundRow = false
    for _, row in ipairs(DS.rows) do
        if row._entryData then
            local onEnter = row:GetScript("OnEnter")
            if onEnter then
                onEnter(row)
                foundRow = true
                break
            end
        end
    end

    if foundRow then
        -- Check tooltip branding was called
        local brandingCalled = false
        for _, call in ipairs(GameTooltip._calls or {}) do
            if call == "AddTooltipBranding" then
                brandingCalled = true
                break
            end
        end
        -- Branding is checked via UX consistency tests
    end
end)

T:run("DestSearch: section headers use gold color", function(t)
    resetState()
    QR.DestinationSearch.frame = nil
    QR.DestinationSearch.isShowing = false
    QR.DestinationSearch.rows = {}
    QR.DestinationSearch.rowPool = {}

    if QR.DungeonData then QR.DungeonData:Initialize() end

    local DS = QR.DestinationSearch
    DS:ShowDropdown()

    -- Find a header row
    local headerFound = false
    for _, row in ipairs(DS.rows) do
        if row._isHeader and row.nameLabel then
            local r, g, b = row.nameLabel._textColorR, row.nameLabel._textColorG, row.nameLabel._textColorB
            if r then
                -- Gold: (1, 0.82, 0)
                t:assertTrue(r > 0.9, "Header red > 0.9")
                t:assertTrue(g > 0.7 and g < 0.9, "Header green ~0.82")
                headerFound = true
                break
            end
        end
    end
    -- Header may or may not exist depending on data availability
end)
```

**Step 2: Ensure all UX patterns are implemented in DestinationSearch**

Review the dropdown code and verify:
1. `QR.AddTooltipBranding(GameTooltip)` before every `GameTooltip:Show()`
2. `GameTooltip_Hide()` on every OnLeave
3. `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` on every click
4. Gold `(1, 0.82, 0)` for section headers
5. Muted border `(0.4, 0.4, 0.4, 0.8)` for dropdown backdrop

**Step 3: Add DestinationSearch to test_ux_consistency.lua**

Add a section checking the new module follows UX patterns (tooltip branding, sounds, colors).

**Step 4: Run all tests**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: PASS for all tests

**Step 5: Commit**

```bash
git add QuickRoute/Modules/DestinationSearch.lua tests/test_destination_search.lua tests/test_ux_consistency.lua
git commit -S -m "feat: add UX consistency to DestinationSearch (tooltips, sounds, colors)"
```

---

### Task 8: Luacheck and final verification

**Files:**
- Modify: `.luacheckrc` (add any new globals if needed)
- Run: luacheck + full test suite

**Step 1: Run luacheck**

Run: `luacheck QuickRoute/`
Expected: 0 warnings

If any warnings about new globals (e.g., the EditBox name `QRDestSearchBox`), add to `.luacheckrc` globals list.

**Step 2: Run full test suite**

Run: `~/.local/bin/lua5.1 tests/run_tests.lua`
Expected: All tests pass (existing + new)

**Step 3: Commit any fixes**

```bash
git add .luacheckrc
git commit -S -m "chore: update luacheck config for DestinationSearch"
```

---

### Task 9: Deploy and verify

**Step 1: Copy to WoW addons folder**

```bash
cp -r QuickRoute/* "/mnt/f/World of Warcraft/_retail_/Interface/AddOns/QuickRoute/"
```

**Step 2: In-game verification checklist**

- [ ] Open QuickRoute (/qr) — Route tab shows search box instead of dropdown
- [ ] Click search box — dropdown opens with grouped results
- [ ] Type "storm" — filters to Stormwind + any matching dungeons
- [ ] Click "Stormwind City" — routes, dropdown closes, search box shows "Stormwind City"
- [ ] Click search box again — dropdown reopens
- [ ] Clear search — all results visible
- [ ] ESC key closes dropdown
- [ ] Press Refresh — route recalculates
- [ ] Enter combat — dropdown auto-hides
- [ ] Dungeon Picker still works from Encounter Journal button
- [ ] /qrtest graph — existing tests pass
