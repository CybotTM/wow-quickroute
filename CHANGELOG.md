# Changelog

## [1.0.0] - 2026-02-13

### Added
- Smart pathfinding using Dijkstra's algorithm
- Route step collapsing (merges consecutive walk/fly steps)
- Teleport detection: inventory items, toys, spells, racials, class abilities
- Cooldown tracking with route-aware scheduling
- Portal hub knowledge (all major hubs, boats, zeppelins, trams, Dreamway)
- Faction-aware routing (Alliance/Horde restrictions)
- Class-aware teleports (Mage, Druid, Monk, DK, Shaman, DH)
- TomTom waypoint integration
- Auto-destination from super-tracked quests/waypoints
- World map teleport button overlay
- Quest tracker teleport buttons
- Destination-centric teleport grouping (grid + list views)
- POI click routing (Ctrl+Right-click on world map)
- Player Housing "Teleport Home" spell support
- Minimap button with addon compartment support
- Settings panel (max cooldown filter, loading screen time, window scale)
- Availability filter (all / available / ready) with three-state cycling
- Icon button mode toggle
- Localization for 10 languages (en, de, fr, es, pt, ru, ko, zh-CN, zh-TW, it)
- Full test suite (7754 assertions, 27 test files)
- CI pipeline (luacheck + tests)
- CurseForge + Wago automated publishing
