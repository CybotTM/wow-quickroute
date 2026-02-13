# Changelog

## [1.0.1] - 2026-02-13

### Improved
- Debug output is now markdown-formatted for direct pasting into GitHub issues
- Debug info header includes WoW version, build number, locale, and date
- Teleport list and module status use collapsible sections to keep pastes compact
- Errors and warnings promoted to their own visible section in debug output

### Added
- `/qrdebug copy` subcommand to open the Copy Debug popup directly
- "Debug info" field in bug report issue template with paste instructions
- Wago.io automated publishing in release workflow
- GitHub issue templates (bug report, feature request, new teleport)
- Pull request template
- CHANGELOG.md

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
