# Changelog

## [Unreleased]

## [1.16.0] - 2026-09-03

### Added
- `/qrsurvey` records what the client says about each map you stand on, and `/qrdiag` records Lua errors and teleport-list rebuilds. Both keep their results across sessions, for the questions that can only be answered from a running game.
- The settings page opens with the header from the design ("C2"): the logo, the addon's name, a subtitle, a line with version and author and the site below it, drawn over a travel network with one route in gold; below it a status bar that says whether TomTom was found (and which version), how many teleports the character has, and a button that opens the route window. The settings themselves are unchanged, and Blizzard's own Defaults button stays where it is.

### Changed
- The teleport cards picture the destination, not the teleport: the banner shows the middle of the destination's zone map (its two centre tiles, side by side), a little darker and less saturated so the name on it and the icons under it stand out. Destinations without a map of their own get the map that stands for them: the garrison and the housing plot their faction's map, a random location on a continent that continent, a random delve Khaz Algar, a random location worldwide the Azeroth map. Only the bound location and the camp keep the icon of their first teleport as the picture.
- The teleport cards are the picture cards of the design ("K2"): a 68px banner carrying the group's icon, scaled to the card's width and cut to the banner rather than squashed, with the destination and its continent at the banner's foot; below it the teleport icons and a round status dot. The window opens at the 820px the cards were designed for, three columns of them; at the former 500px they fell into a single column.

### Fixed
- Labels that do not fit are shortened rather than cut mid-word. The teleport inventory's filter button carries the chosen filter and the grouping setting together, so "Usable Now, Group by Destination" reached it as "Usable Now, Gr"; it is now as wide as the longest label its menu can produce, in every language. In the quick-teleport list the name and destination columns were a fixed 100px whatever the panel's width, which is narrower than the row they sit in: they follow the row now, the panel is 380px wide, and a name still too long for its column ends in an ellipsis. The full name was always in the row's tooltip.
- The Kirin Tor Beacon, the Sunreaver Beacon and the Mobile Telemancy Beacon no longer count as ready everywhere. The game accepts the first two only on Isle of Thunder and in the Throne of Thunder, the third only in Suramar; away from there they read NOT HERE in the teleport inventory, the "usable" filter hides them, and the quick-teleport list and the map sidebar leave them out. The data carries the maps as `usableOnMaps`, next to the free-text `restriction` that was already there.
- The map sidebar's rows show their names and destinations again, and so do the list rows of the teleport inventory. Each text was set and then cleared by a `SetTextToFit()` call without a text, which the client reads as an empty string. The test double had made that call a no-op, which is why no test saw it; it now behaves like the client.
- "Teleport Home" works. The button cast it through the spellbook, and the housing teleport is granted rather than learned, so clicking it did nothing at all — no cast, no error. Spells you can use without having learned them are now cast by name.
- The teleport list no longer empties itself after a teleport. The bag rescan a teleport triggers lands during the loading screen that follows it, where the game answers "no bags" rather than declining, and the scan wrote that down as an empty inventory. With the availability filter on "usable" the list then had nothing left to show, until the window was closed and reopened. A scan that cannot read the bags at all now keeps the previous one.
- Teleport cloaks and rings no longer report that the item was not found. The button always tried to equip first, which searches the bags only, so aiming it at something already on the character failed on that line and never reached the teleport. An item already in its slot is now used straight from the slot. One you are not wearing takes two clicks — equipping and using cannot happen in the same one, because the item reaches the slot only after the server answers — so the first click equips and says so.
- `/qrverifymap` answered "nothing in the addon's data points at this map" for zones that have a flight master, because it never looked at flight points or portals. Its service check could not report anything for any map at all.
- Six zones had a flight master in the data and no flight edge in the graph. The client ships a second set of zone maps that repeats zones under different IDs, and the flight-point generator was filing masters under those: Azsuna as 1187 rather than 630, Isle of Dorn as 2271 rather than 2248, and the same for Bastion, The Ringing Deeps, Hallowfall and Harandar. Five of those IDs are ones the addon's zone tables do not know at all. Azj-Kahet had two entries and keeps the right one. No route changes as a result — 0 of 1824 measured routes into those zones and 0 of 306 to the faction capitals — but the graph gains 18 flight edges that were previously attached to nothing.
- Teleport items you are wearing work again. Eleven of them sit in slots the inventory scan never looked at — the six guild cloaks and Mountebank's Colorful Cloak on the back, three pairs of slippers on the feet, and the Blessed Medallion of Karabor on the neck — so while worn they counted as not owned and the panel drew a plain icon with nothing behind it. The slot list is now taken from the item data instead of being kept by hand.
- Zen Pilgrimage sends Monks to Kun-Lai Summit, where it actually lands. It pointed at a Karazhan instance floor on another continent, and now carries the landing position rather than the middle of the zone.
- Dalaran is one place in the route graph again. Three teleports and a mage portal called their destination "Dalaran (Legion)" while the rest of the addon called the same spot "Dalaran (Broken Isles)", so anyone holding a Dalaran teleport got two nodes at identical coordinates with the portals attached to one and the teleport to the other.
- No more routes to a bank or auction house in Darnassus or Undercity. Both cities were destroyed in Battle for Azeroth, and the maps the client still ships are the pre-destruction versions a character only reaches by asking Zidormi to send them back — so the five services the addon listed there are not standing in the present day. Both cities keep their graph nodes, because standing on those maps is possible and a character who is there needs a way out; no route changes as a result.

## [1.15.0] - 2026-08-31

### Fixed
- A pandaren who picks a faction is routed as that faction straight away. The addon read the faction once and kept the answer, so a character who chose Horde was routed as neutral until the next reload.
- Flight masters are filed under the zone their own name states. Zone boxes overlap, and picking the smallest containing one put 185 of them in a neighbouring zone — Darkshire under Deadwind Pass, New Kargath under Searing Gorge, Ratchet under Valley of Trials. Six more zones have a flight master as a result, nine gain a faction's access, and none loses any.

## [1.14.0] - 2026-08-31

### Fixed
- Flight routes use your own faction's flight masters. 74 of the 141 flight zones were represented by a node only one side can reach, and 45 of those had a master for the other faction that the data was discarding — The Hinterlands sent Horde players to Aerie Peak, Ashenvale to Astranaar. Zones with no master for your faction no longer get a flight edge at all.

## [1.13.0] - 2026-08-31

### Added
- Flight paths are part of the travel graph. 141 zones with a flight master, positioned from the client's own tables and connected where the player has discovered them. A flight step's waypoint is the flight master itself. Measured for a character with no teleports routing to Stormwind: 18 zones get a faster route and none get a slower one; Silithus drops from 855 to 542 seconds and Mount Hyjal from 705 to 418.

## [1.12.0] - 2026-08-31

### Fixed
- Two test files left shared state behind, so the suite passed in one file order and failed in others: a mock frame method deleted rather than restored, and two saved-variables keys. CI now runs both orders.
- The last-resort node connection in continent routing took whichever candidate Lua's hash order yielded, behind variables named as if it searched for the cheapest. It is deterministic now.
- A character with no teleports had no route at all from anywhere the graph has no other node for -- Thunder Bluff, Darnassus, Ashran and 26 other zones. The player node was only connected by the teleports they owned, and by nothing else until they moved.

### Added
- `/qrdungeons` opens the dungeon and raid picker. The module shipped in every release but nothing ever initialized it or opened it, so it was unreachable.
- A teleport step rendered during combat is dimmed. It gets no Use button under lockdown, so it used to look identical to a step whose teleport is unavailable.
- `/qrverifymap [mapID]` reports what the client says about a map and what the addon believes about it, side by side, in the copyable window. For the questions that cannot be answered from the data — which map a teleport actually lands on, whether a service is still there.
- Dungeon and raid teleports the player knows are now routes. A character with the Mythic+ teleport for a dungeon was sent there on foot: the addon knew the entrance and knew the spell, and nothing connected the two.

## [1.11.0] - 2026-08-31

### Fixed
- Interface bumped to 120100 for WoW 12.1.0; the addon was flagged out of date and skipped at load
- Spell teleports reported as permanently off cooldown on 12.x
- SecureButtons failed to load, raising a Lua error on every login
- Twelve dungeon entrances bound to the wrong Encounter Journal instance
- Twelve dungeon-entrance zone constants pointing at the wrong map
- Nine maps that are not walkable zones -- dungeons, raids, continents and an orphan duplicate -- used as if they were
- The Veiled Stair modelled as an island reached by boat, its adjacency block holding Isle of Thunder's neighbours
- Crucible of Storms registered on the Kul Tiras continent map instead of Stormsong Valley
- Four Tol Barad teleports pointing at a map with no continent and no neighbours
- Silvermoon services and portals on the map the city left behind when Midnight revamped it
- Teleport entries the live client contradicts
- Routes computed after a zone change started in the zone the player had just left
- Continent routing erasing the measured walk edges inside a city
- Teleport edge weights frozen at graph-build time, so cooldowns stopped being considered
- Walking distances priced by one hard-coded scale for every map in the game instead of the map's real size
- Quest teleport buttons hidden whenever the objective tracker had a shape this code did not know
- Use buttons missing from a route rendered during combat, with nothing to restore them
- Quest waypoints: the native map pin QuickRoute set was never taken back, so it kept outranking the player's tracked quest; the transit-hub fallback ran before the dungeon-entrance lookup and hid it; and both confirmations printed English regardless of locale
- The minimap teleport panel left one separator frame behind on every refresh
- Secure buttons never returned when a window closed, and the minimap teleport panel keeping its buttons on screen for the whole fight
- An unguarded call to GetSpellInfo, removed in 11.0.2, in the teleport panel's icon lookup -- reached whenever spell data is not cached yet, which is the state right after login
- Dead branches left behind by two API changes that were guarded: the GetQuestLogIndexByID rename, and SetPortraitToTexture's removal in 12.0.0, whose fallback had been drawing a square portrait ever since
- Item and icon lookups moved to the C_Item and C_Spell namespaces
- Releases published without having been linted, and store uploads that failed silently

### Added
- The Coiled Isle, Vaults of Atal'Utek, Val, Naigtal and the two housing zones
- Eight dungeon and raid entrances from patches 11.1 through 12.1.0
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
