# Unified Destination Search - Design

## Goal

Replace the current waypoint source dropdown + separate dungeon picker button in the Route tab with a single search box that provides unified access to all destination types: auto-detected waypoints, cities, and dungeons/raids.

## Problem

Currently, routing to different destination types requires different UI paths:
- **Waypoints:** Dropdown selector in Route tab (auto/map pin/TomTom/quest)
- **Dungeons:** Separate DungeonPicker popup via toolbar button
- **Cities:** No UI at all (only available as teleport destinations, not as routing targets)

This fragments the UX and makes city routing impossible.

## Architecture

A new `DestinationSearch` module provides an EditBox + dropdown popup in the Route tab toolbar. The dropdown shows grouped results from three data sources, filtered by free-text search.

### Data Sources

| Category | Source | Items |
|----------|--------|-------|
| Active Waypoint | `WaypointIntegration:GetActiveWaypoint()` + super-tracked quest | 0-2 |
| Cities | `CAPITAL_CITIES` table (PathCalculator.lua), filtered by faction | ~12 |
| Dungeons & Raids | `DungeonData` instances by tier | ~100+ |

### UI Layout

**Route tab toolbar:**
```
[  Search destinations...  ] [Refresh] [Debug] [Zone]
```

- EditBox with placeholder text replaces the old dropdown + dungeon button
- Dropdown popup (BackdropTemplate, DIALOG strata) anchored below search box
- Opens on focus/click, closes on ESC/click-away/selection

**Dropdown structure:**
```
+-----------------------------------------+
| > Active Waypoint          (gold header) |
|   Valdrakken (Map Pin)                   |
|   Some Quest (Quest)                     |
|                                          |
| > Cities                   (gold header) |
|   Stormwind City                         |
|   Ironforge                              |
|   Dalaran (Northrend)                    |
|   ...                                    |
|                                          |
| > Dungeons & Raids         (gold header) |
|   The War Within           (tier header) |
|     Ara-Kara, City of Echoes             |
|     The Stonevault                       |
|   Dragonflight              (tier header)|
|     ...                                  |
+-----------------------------------------+
```

### Search Behavior

- **Empty search:** All categories expanded
- **Typing:** Case-insensitive substring match, only matching items + headers shown
- **Selection:** Routes via `POIRouting:RouteToMapPosition()`, closes dropdown, shows name in search box
- **Auto-detected waypoint:** Appears as highlighted suggestion in Active Waypoint section (search box stays empty)

### Module: `Modules/DestinationSearch.lua`

Follows DungeonPicker pattern:
- Row pool for frame recycling
- ScrollFrame for long lists
- Grouped display with section headers
- Reuses `QR.CAPITAL_CITIES`, `DungeonData` API, `WaypointIntegration`

### Files Modified

| File | Change |
|------|--------|
| `Modules/DestinationSearch.lua` | **New** — search box + dropdown popup module |
| `Modules/UI.lua` | Replace sourceDropdown + dungeonButton with EditBox tied to DestinationSearch |
| `Core/PathCalculator.lua` | Expose `CAPITAL_CITIES` as `QR.CAPITAL_CITIES` |
| `Localization.lua` | Search placeholder, category header keys, city name keys |
| `QuickRoute.toc` | Add DestinationSearch.lua to load order |
| `QuickRoute.lua` | Initialize DestinationSearch in boot sequence |

### What Gets Removed

- `WowStyle1DropdownTemplate` waypoint source dropdown
- `QR.db.selectedWaypointSource` setting
- Dungeon picker button from Route tab toolbar (DungeonPicker module stays for Encounter Journal)

### What Stays

- Refresh, Debug, Zone buttons in toolbar
- DungeonPicker module (still used by EncounterJournalButton)
- All existing routing logic (POIRouting, PathCalculator, WaypointIntegration)
