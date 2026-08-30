# Changelog

## [Unreleased]

### Fixed
- Interface bumped to 120100 for WoW 12.1.0; the addon was flagged out of date and skipped at load
- Spell teleports reported as permanently off cooldown on 12.x
- SecureButtons failed to load, raising a Lua error on every login
- Twelve dungeon entrances bound to the wrong Encounter Journal instance
- Twelve zone graph nodes carrying the uiMapID of a dungeon, raid or continent
- The Veiled Stair modelled as an island reached by boat, from carrying Isle of Thunder's map ID
- Crucible of Storms registered on the Kul Tiras continent map instead of Stormsong Valley
- Routes computed after a zone change started in the zone the player had just left
- Teleports vanishing from routes after a single step, their graph edge overwritten by a walking estimate
- North-south distances priced by the map's east-west extent
- Secure buttons never returned when a window closed, draining the pool
- Releases published without having been linted, and store uploads that failed silently

### Added
- The Coiled Isle, Vaults of Atal'Utek, Val, Naigtal and the two housing zones
- Nine dungeon and raid entrances from patches 11.1 through 12.1.0
- Delve-O-Bot 7001

## [1.10.1] - 2026-03-08

### Added
- detect Homestead teleport via C_Spell.IsSpellUsable

### Fixed
- show Homestead teleport in MiniTeleportPanel and TeleportPanel
- add spell diagnostics to /qrextract header and fix teleport extract
- scan GeneralTeleportSpells and add teleport verification to /qrextract

### Other
- bump version to 1.10.1

## [1.10.0] - 2026-03-08

### Added
- improve TomTom waypoints, portal-through routing, and data extraction

### Fixed
- restore StandalonePortals after portal-through tests
- restore TomTom "from" option for waypoint source display
- update TOC version to 1.9.0
- TomTom "from" field shows "QuickRoute" instead of player zone
- use zone name instead of generic "Map Pin" for waypoint titles
- correct Harandar mapID from 2576 to 2413

### Other
- persist git hooks in repo and remove unused TomTom "from" opt

## [1.9.0] - 2026-03-05

### Added
- add Personal Key to the Arcantina teleport toy

## [1.8.1] - 2026-03-05

### Added
- improve quest coordinate resolution with header→zone and broad scan fallbacks

## [1.8.0] - 2026-03-05

### Added
- track and clean up TomTom waypoints set by QuickRoute

### Fixed
- add debug trace for quest negative cache hits

## [1.7.0] - 2026-03-04

### Added
- add tracked quests to destination search dropdown

### Fixed
- quest waypoint beats TomTom when quest is super-tracked
- add Docker fallback to lint.sh and enable pre-commit luacheck
- add Enum to luacheckrc globals
- make release workflow failsafe when release already exists

## [1.6.0] - 2026-03-04

### Added
- improve quest-to-dungeon routing with Blizzard API enhancements

### Fixed
- prevent stale saved destination when quest has no coordinates

### Other
- bump version to 1.6.0
- use named zone constants in DungeonEntrances and include Textures in release

## [1.5.0] - 2026-02-17

### Added
- add screenshot tooling and clean up unused library dependencies
- export localization to CurseForge on release

### Fixed
- align Use button vertically with Nav button in step cards
- step card button alignment and updated screenshots
- remove green brand accent border from all windows
- add Screenshot and SLASH_QRSCREENSHOT1 to luacheckrc globals
- show all 3 screenshots in single row, remove broken image
- add Screenshot() mock and tests for /qrscreenshot command
- add /qrscreenshot to help listing and README
- use lua_additive_table format for CurseForge localization import

### Other
- bump version to 1.5.0
- add cropped screenshots for README and addon listings
- add manual localization upload workflow

## [1.4.0] - 2026-02-16

### Added
- show zone and continent on step detail line
- Nav button as 28x28 icon and destination in step action line
- localized city region tags in destination search
- card-style route step rendering with two-line layout
- destination locking via _pendingPOIRoute pattern
- absorb redundant walk steps after transport to same map
- add ServiceRouter module, localization, search integration, and dropdown close fix
- add /qr ah|bank|void|craft slash commands for service routing
- add static service POI data for AH, Bank, Void Storage, Crafting Table

### Fixed
- Use button as 28x28 icon and replace unprintable arrow char
- correct continent mapIDs and enable BFA cross-continent routing
- robust suppress-refresh for POI routing, city zone labels, select-all search
- use per-service nearest keys for gender-correct translations
- suppress waypoint event re-trigger and fix gendered translations
- search/dropdown selection routes to selected target instead of mappin
- localize all user-visible strings and improve test coverage

### Other
- add config/ to gitignore
- bump version to 1.4.0
- add crafting table as 4th service type to plan
- add service POI routing design and implementation plan

## [1.3.0] - 2026-02-15

### Added
- integrate destination search into Route tab toolbar
- add DestinationSearch dropdown popup UI
- add DestinationSearch module with data collection
- expose CAPITAL_CITIES and add destination search localization keys

### Fixed
- address code review findings for destination search

### Other
- bump version to 1.3.0
- add unified destination search design and implementation plan

## [1.2.0] - 2026-02-14

### Added
- persist selected route destination across close/reopen
- add ConnectIslandNodes to fix all dungeon routing failures
- add missing zones to pathfinding graph, add routability debug
- add Midnight expansion zones to pathfinding graph
- add Midnight expansion dungeon data, filter continent entries
- add Dungeon Data section to /qrdebug output
- add Route button on Encounter Journal
- add Ctrl+Right-click routing on dungeon map pins
- add dungeon/raid picker dropdown in Route tab
- integrate dungeon entrance nodes into pathfinding graph
- add DungeonData module with runtime scanning and static fallback

### Fixed
- remove unused variable flagged by luacheck
- add Encounter Journal globals to luacheck whitelist
- correct systematic uiMapID mislabeling in ZoneAdjacency.lua
- change Kalimdor Alliance hub to Exodar, add missing adjacencies
- always connect destinations via continent routing
- connect remaining 5 unreachable dungeon zones
- cache table.sort in UI.lua to fix debug output error
- log dungeon instances missing coordinates in debug output
- hide EJ route button on boss encounter view, fix addon_loader order

### Other
- bump version to 1.2.0
- i18n: add dungeon/raid routing localization keys (10 languages)
- data: add static dungeon/raid entrance coordinates for all expansions
- add Encounter Journal API mocks for dungeon routing
- add dungeon/raid routing implementation plan
- add dungeon & raid routing design

## [1.1.0] - 2026-02-13

### Added
- add missing zones, fix route guidance for portal-connected zones
- use custom logo for addon portrait, minimap, and tooltips

### Fixed
- CI badge URL (lint.yml → ci.yml)

### Other
- bump version to 1.1.0
- add project logo to README

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
