# Dungeon & Raid Routing — Design

**Date:** 2026-02-14
**Status:** Approved

## Goal

Route players to any dungeon or raid entrance in the game. Three entry points: Route tab picker, Encounter Journal button, world map pin click.

## Data Layer

### Runtime scanning (primary)

On addon load (deferred via `C_Timer.After`), build a full instance catalog:

```lua
for tier = 1, EJ_GetNumTiers() do
    EJ_SelectTier(tier)
    for _, isRaid in ipairs({false, true}) do
        local index = 1
        while true do
            local instanceID, name = EJ_GetInstanceByIndex(index, isRaid)
            if not instanceID then break end
            -- Store: journalInstanceID -> { name, isRaid, tier }
            index = index + 1
        end
    end
end
```

Then for each zone in ZoneAdjacency data, call `C_EncounterJournal.GetDungeonEntrancesForMap(zoneMapID)` to get entrance coordinates (x, y, name, atlasName, journalInstanceID).

**Caveat:** Only returns discovered instances (ones the character has visited).

### Static fallback (Data/DungeonEntrances.lua)

Hardcoded entrance data for all expansions, covering undiscovered instances. Format:

```lua
QR.StaticDungeonEntrances = {
    -- [zoneMapID] = { { journalInstanceID, x, y, name, isRaid }, ... }
    [1116] = {  -- Shadowmoon Valley (WoD)
        { 476, 0.7720, 0.4190, "Shadowmoon Burial Grounds", false },
    },
}
```

Sourced from HandyNotes_DungeonLocations data + AreaPOI DBC database.

### Merged result

Runtime data takes priority (localized, accurate). Static fills gaps. Stored as:

```lua
QR.DungeonData = {
    instances = {},      -- journalInstanceID -> { name, zoneMapID, x, y, isRaid, tier, atlasName }
    byZone = {},         -- zoneMapID -> { journalInstanceID, ... }
    byTier = {},         -- tierIndex -> { journalInstanceID, ... }
}
```

## Graph Integration

During `PathCalculator:BuildGraph()`:

- Each dungeon entrance becomes a node: `"Dungeon: <name>"` with metadata `{ mapID, x, y, journalInstanceID, isRaid, isDungeon = true }`
- Walking edge from entrance to parent zone node (weight = estimated walk time from zone center)
- No new edge types — existing `"walk"` type suffices
- Routing works unchanged: `FindShortestPath(playerLocation, dungeonNode)`

## UI: Route Tab Dungeon Picker

### Location

Below the existing destination input in the Route tab.

### Layout

- Button labeled "Dungeons & Raids" opens a dropdown/popup panel
- Text search input at top (filter by name)
- Grouped by expansion tier (TWW, Dragonflight, ...) with collapsible headers
- Each tier split into Dungeons / Raids subsections
- Clicking an instance sets it as route destination, triggers path calculation

### Implementation

- Reuses ScrollFrame + row pool pattern from TeleportPanel
- Each row: instance icon (atlasName) + name + "Dungeon"/"Raid" tag
- Popup anchored below the button, same backdrop style as MiniTeleportPanel

## UI: Encounter Journal Button

### Approach

Hook into `EncounterJournalFrame` OnShow (same pattern as QuestTeleportButtons):

- Small QR button near instance title when viewing a specific instance
- Click routes to the dungeon entrance via `POIRouting:RouteToMapPosition()`
- Uses `QR.AddMicroIcon()` for consistent styling
- Tooltip: "Route to entrance" with branding
- Hidden when viewing boss encounters (only on instance overview)
- Hidden in combat (`InCombatLockdown()` check)

### Hook target

```lua
hooksecurefunc(EncounterJournal, "OnShow", function() ... end)
-- or hook the instance display update function
```

## UI: Map Pin Routing

### Approach

Extend POIRouting to handle dungeon entrance pins:

- Hook `DungeonEntrancePinMixin:OnMouseClickAction` or post-hook pin creation
- Ctrl+right-click on a dungeon map pin routes to that entrance
- Pin already has `position` and `journalInstanceID` — pass to `POIRouting:RouteToMapPosition()`
- Same UX pattern as existing Ctrl+right-click POI routing

## New Files

| File | Purpose |
|------|---------|
| `Data/DungeonEntrances.lua` | Static fallback entrance data (all expansions) |
| `Modules/DungeonData.lua` | Runtime scanner, merger, `QR.DungeonData` API |
| `Modules/DungeonPicker.lua` | Route tab dropdown for selecting dungeons |
| `Modules/EncounterJournalButton.lua` | QR button on Encounter Journal |
| `tests/test_dungeondata.lua` | Data layer + graph integration tests |
| `tests/test_dungeonpicker.lua` | Picker UI tests |

## Modified Files

| File | Changes |
|------|---------|
| `Core/PathCalculator.lua` | Add dungeon nodes during `BuildGraph()` |
| `Modules/POIRouting.lua` | Hook dungeon map pins for Ctrl+right-click |
| `Modules/UI.lua` | Mount DungeonPicker in Route tab content |
| `QuickRoute.toc` | Add new files to load order |
| `addon_loader.lua` | Add new files |
| `Localization.lua` | Add dungeon routing strings (10 languages) |
| `tests/mock_wow_api.lua` | Add EJ_* and C_EncounterJournal mocks |

## WoW APIs Used

- `C_EncounterJournal.GetDungeonEntrancesForMap(zoneMapID)` — entrance coordinates
- `EJ_GetInstanceInfo(journalInstanceID)` — instance metadata
- `EJ_GetInstanceByIndex(index, isRaid)` — enumerate instances
- `EJ_SelectTier(tier)` / `EJ_GetNumTiers()` — expansion tier selection
- `C_EncounterJournal.GetInstanceForGameMap(mapID)` — map-to-instance lookup

## Localization Keys

```
DUNGEON_PICKER_TITLE = "Dungeons & Raids"
DUNGEON_PICKER_SEARCH = "Search..."
DUNGEON_PICKER_NO_RESULTS = "No matching instances"
DUNGEON_ROUTE_TO = "Route to entrance"
DUNGEON_RAID_TAG = "Raid"
DUNGEON_TAG = "Dungeon"
TIER_1 through TIER_11 = expansion names (or use EJ_GetTierInfo)
```
