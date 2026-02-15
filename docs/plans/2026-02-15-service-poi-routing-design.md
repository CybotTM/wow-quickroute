# Service POI Routing Design

## Goal

Route the player to the nearest Auction House, Bank, Void Storage, or Crafting Table across all capital cities, using Dijkstra-optimal travel time (not geographic distance).

## User Stories

- "I need an AH urgently" → type "auction" in search or `/qr ah` → instant route to nearest AH considering teleports
- "Where's the closest bank?" → type "bank" in search or `/qr bank` → route to nearest bank

## Architecture

### Data Layer: `Data/ServicePOIs.lua`

Static coordinate table for service locations across all 17 capital cities. Structure:

```lua
QR.ServicePOIs = {
    AUCTION_HOUSE = {
        { mapID = 84,  x = 0.61, y = 0.70, faction = "Alliance" },  -- Stormwind
        { mapID = 85,  x = 0.54, y = 0.63, faction = "Horde" },     -- Orgrimmar
        { mapID = 2112, x = 0.47, y = 0.57, faction = "both" },     -- Valdrakken
        -- ...
    },
    BANK = { ... },
    VOID_STORAGE = { ... },
    CRAFTING_TABLE = { ... },
}
```

Each entry: `mapID`, `x`, `y`, `faction`. City name resolved at runtime via `C_Map.GetMapInfo(mapID).name`.

### Logic Layer: `Modules/ServiceRouter.lua`

- `ServiceRouter:GetServiceTypes()` — returns available service type keys
- `ServiceRouter:GetLocations(serviceType)` — returns faction-filtered locations for a service type
- `ServiceRouter:FindNearest(serviceType)` — calculates Dijkstra route to each candidate, returns the one with shortest travel time
- `ServiceRouter:RouteToNearest(serviceType)` — calls FindNearest, then `POIRouting:RouteToMapPosition()`

FindNearest leverages PathCalculator which already builds a full Dijkstra graph. For each candidate location, calculate path cost and pick the minimum.

### DestinationSearch Integration

Add "Services" section to `CollectResults()`:
- New section header "Services" (gold, collapsible)
- For each service type with matching locations:
  - "Nearest Auction House" auto-pick row (routes to best one)
  - Individual city locations below (indented)
- Search filtering: "auction", "bank", "void" match the appropriate service types

### Slash Commands

Added to `QuickRoute.lua`:
- `/qr ah` → `ServiceRouter:RouteToNearest("AUCTION_HOUSE")`
- `/qr bank` → `ServiceRouter:RouteToNearest("BANK")`
- `/qr void` → `ServiceRouter:RouteToNearest("VOID_STORAGE")`
- `/qr craft` → `ServiceRouter:RouteToNearest("CRAFTING_TABLE")`

### Localization

New keys in all 10 languages (enUS, deDE, frFR, esES, ptBR, ruRU, koKR, zhCN, zhTW, itIT):
- `SERVICE_AUCTION_HOUSE` — "Auction House"
- `SERVICE_BANK` — "Bank"
- `SERVICE_VOID_STORAGE` — "Void Storage"
- `SERVICE_CRAFTING_TABLE` — "Crafting Table"
- `SERVICE_NEAREST` — "Nearest %s"
- `DEST_SEARCH_SERVICES` — "Services"

## Files

| File | Change |
|------|--------|
| `Data/ServicePOIs.lua` | NEW — static service coordinates |
| `Modules/ServiceRouter.lua` | NEW — nearest-service routing logic |
| `Modules/DestinationSearch.lua` | Add services section to CollectResults + RefreshDropdown |
| `QuickRoute.lua` | Add `/qr ah/bank/void` slash commands, init ServiceRouter |
| `QuickRoute.toc` | Add new files |
| `Localization.lua` | Add SERVICE_* keys in 10 languages |
| `tests/addon_loader.lua` | Add new files |
| `tests/test_service_router.lua` | NEW — tests for data, filtering, nearest routing |
| `tests/test_destination_search.lua` | Add tests for services section |
