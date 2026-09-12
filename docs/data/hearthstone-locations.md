# Hearthstone inn catalog

Checked on 2026-09-12 against retail build **12.1.0.69587**. The data contains **59 distinct approximate inn destinations on 44 maps** and **59 ambiguity/phase blockers** (119 records). There are 60 positioned records because two localized area-name aliases explicitly use the same modern Morgenluft default. A runtime locale can have fewer usable names: translated aliases deliberately block otherwise unique English names.

This is an initial catalog, not a complete list of WoW inns. Fifty-eight destinations come from explicit hearth-binding steps with numeric UI map IDs in retail guides. The modern Morgenluft default uses the current innkeeper's mapped position, described below. Names in guide instructions and NPC names are not interchangeable. Runtime matching uses the client's localized `C_Map.GetAreaInfo(areaID)` and the exact `GetBindLocation()` string; no English alias or NPC-name matching is required.

## Position accuracy

The coordinates locate the inn/binding interaction described by the guide. They are **not an observation of a character's saved hearthstone landing position** and must retain `isApproximate = true`. Observed binding/arrival data takes priority. A match can be useful for long-distance travel estimates without claiming that the character lands at the innkeeper's exact feet. Guide point precision is retained to four normalized decimals; this is serialization precision, not an accuracy guarantee.

## Reproducible sources and selection

- Guide facts: [WoW-Pro-Guides commit f7c84c7ef4bcc3af20ff33cb5a497dd639b45851](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/commit/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851). Only normalized location facts are included; guide prose and implementation are not copied.
- Area identities, hierarchy and localized collision checks: Blizzard client DB2 data exposed by [Wago AreaTable, build 12.1.0.69587](https://wago.tools/db2/AreaTable?build=12.1.0.69587). The CSV endpoint is `https://wago.tools/db2/AreaTable/csv?build=12.1.0.69587&locale=LOCALE`.
- Numeric UI map identities: [Wago UiMap, same build](https://wago.tools/db2/UiMap?build=12.1.0.69587). All selected map IDs occur in this build.

The source scan found 162 retail `h` steps with numeric coordinates. Of these, 88 also include an explicit numeric `Z` (UI map), representing 80 distinct trimmed binding labels. All 80 labels have exact AreaTable matches. Sixty-four have a single English area ID; the other 16 have multiple IDs. Those remain blocked except for the explicitly selected modern Morgenluft default. Six additional labels are withheld for known city/phase or conflicting-coordinate concerns. Repeated steps at the same inn use one sourced point; no coordinates are averaged or invented.

All **10,002 AreaTable rows** were checked for duplicate localized labels in **enUS, deDE, frFR, esES, esMX, ptBR, ruRU, koKR, zhCN, zhTW and itIT**. Ten additional area IDs are included as blockers for collisions outside the original guide labels. This prevents the incomplete catalog from making a translated name appear unique. AreaTable duplicates include scenarios/dungeon copies that may not contain usable inns; they are intentionally withheld until a source proves that the other copy cannot be a hearth binding. Faction and level do not remove ambiguity.

The offline audit found all 119 catalog area IDs present and nonempty in every locale. It resolves 59 binding names in enUS, deDE, frFR, esES, esMX, ptBR and zhTW, and 58 in ruRU, koKR, zhCN and itIT. Portuguese has separate legacy and modern Fairbreeze labels that both resolve to the same modern inn; its extra alias offsets another localized collision. The test fixture `tests/fixtures/hearthstone_area_names.lua` contains all 119 EN/DE labels extracted directly from these snapshots; `tests/test_hearthstone_catalog.lua` exercises the shipped catalog through the real resolver.

At runtime, one unavailable, empty or protected area name makes the entire inferred index incomplete; it cannot establish uniqueness safely. The resolver retries after entering the world. The client snapshots establish that the IDs exist in this build, but they do not guarantee that every API lookup is available during login.

Rows without explicit numeric map IDs were left for a subsequent source pass instead of guessing from a guide filename. Further coverage should resolve those guide map declarations against current UiMap, verify binding labels against AreaTable, review duplicate locations and world-state changes, then rerun the full locale collision scan. Broader ATT merchant data is a supplementary cross-check, not proof of a binding label or a complete inn database: the locally installed ATT and QR DestinationCatalog describe collectible-related NPC/vendor positions and omit some ordinary innkeepers.

The checked-in `scripts/audit_hearthstone_catalog.py` validates these facts without executing source Lua. Place the eleven AreaTable CSV exports above in a source directory as `AreaTable-<locale>.csv`, the same-build UiMap export as `UiMap.csv`, the [pinned guide archive](https://codeload.github.com/Ludovicus-Maior/WoW-Pro-Guides/tar.gz/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851) as `WoW-Pro-Guides-f7c84c7.tar.gz`, and the [Sylmara Dawnpetal NPC page](https://www.wowhead.com/npc=242949/sylmara-dawnpetal) as `wowhead-sylmara-242949.html`. From the repository root, run:

```sh
python3 scripts/audit_hearthstone_catalog.py --root . --sources /path/to/source-directory
```

The audit checks guide coordinates against explicit binding steps and the two modern default aliases against the NPC page's embedded mapper data. It verifies every UI map and area ID, checks translated collisions against the complete AreaTable, and prints source checksums. `--fixture tests/fixtures/hearthstone_area_names.lua` regenerates the EN/DE test fixture from the same client data. The ordinary Lua suite uses that fixture without requiring network access or the complete snapshots.

## Selected and withheld guide labels

Coordinates below are percentages on the listed UI map and remain approximate. Each source links to the exact hearth-binding step at the pinned commit. A blocked label has no executable route coordinate.

| Binding label (enUS, audit only) | Area ID(s) | UI map and guide point | Status | Source |
| --- | --- | --- | --- | --- |
| Amberpine Lodge | 4204 | 116: 31.97, 60.22 | Approximate inn | [WOTLK_Grizzly_Hills.lua:17](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Grizzly_Hills.lua#L17) |
| Aspirant's Rest | 11473 | 1533: 48.07, 73.00 | Approximate inn | [SL_Bastion.lua:123](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/SL_Bastion.lua#L123) |
| Astranaar | 415 | 63: 37.00, 49.17 | Approximate inn | [CATA_Ashenvale.lua:80](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Ashenvale.lua#L80) |
| Bilgewater Harbor | 4821 | 76: 57.02, 50.29 | Approximate inn | [CATA_Azshara.lua:179](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Azshara.lua#L179) |
| Blood Watch | 3584 | 106: 55.84, 59.80 | Approximate inn | [CATA_Bloodmyst.lua:28](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Bloodmyst.lua#L28) |
| Bogpaddle | 5458 | 51: 71.75, 13.98 | Approximate inn | [CATA_Swamp_of_Sorrows.lua:10](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Swamp_of_Sorrows.lua#L10) |
| Darkshire | 42 | 47: 73.87, 44.40 | Approximate inn | [CATA_Duskwood.lua:12](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Duskwood.lua#L12) |
| Deepmist Grotto | 5058 | 201: 63.90, 59.90 | Approximate inn | [CATA_Vashjir.lua:134](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Vashjir.lua#L134), [CATA_Vashjir.lua:128](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Vashjir.lua#L128) |
| Deepwater Tavern | 2104 | 56: 10.66, 61.02 | Approximate inn | [CATA_Wetlands.lua:70](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Wetlands.lua#L70) |
| Dolanaar | 186 | 57: 55.40, 52.24 | Teldrassil world-state/phase must be observed. | [INTRO_Night_Elf.lua:55](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/INTRO_Night_Elf.lua#L55) |
| Dornogal | 14771 | 2339: 44.82, 46.49 | Approximate inn | [Aes_Versatile_TWW_speed.lua:83](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Archive/WoWPro_Leveling/Retail/Aes_Versatile_TWW_speed.lua#L83), [TWW_Dorn.lua:64](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/TWW_Dorn.lua#L64) |
| Dragon's Mouth | 5564 | 15: 20.69, 56.08 | Approximate inn | [CATA_Badlands.lua:106](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Badlands.lua#L106) |
| Dreamer's Rest | 5024 | 69: 51.02, 17.97 | Approximate inn | [CATA_Feralas.lua:10](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Feralas.lua#L10) |
| Evergrove | 3951 | 105: 62.85, 38.30 | Approximate inn | [BC_Blades_Edge_Mountains.lua:149](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Blades_Edge_Mountains.lua#L149) |
| Everlook | 2255 | 83: 59.84, 51.17 | Approximate inn | [CATA_Winterspring.lua:72](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/CATA_Winterspring.lua#L72) |
| Fairbreeze Village | 3462, 15995 | 2395: 46.20, 46.00 | Both bind-name aliases default to the modern inn; observation overrides. | [Sylmara Dawnpetal, NPC 242949](https://www.wowhead.com/npc=242949/sylmara-dawnpetal) |
| Falconwing Inn | 5728 | 94: 48.10, 47.70 | Approximate inn | [INTRO_Blood_Elf.lua:60](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/INTRO_Blood_Elf.lua#L60) |
| Fallowmere Inn | 5073 | 65: 59.00, 56.40 | Approximate inn | [CATA_Stonetalon_Mountains.lua:67](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Stonetalon_Mountains.lua#L67) |
| Farwatcher's Glen | 4939 | 65: 31.50, 60.62 | Approximate inn | [CATA_Stonetalon_Mountains.lua:215](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Stonetalon_Mountains.lua#L215) |
| Feathermoon Stronghold | 5072 | 69: 46.14, 45.24 | Approximate inn | [CATA_Feralas.lua:40](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Feralas.lua#L40) |
| Firefly Tavern | 8612 | 102: 78.50, 63.00 | Approximate inn | [BC_Zangarmarsh.lua:17](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Zangarmarsh.lua#L17) |
| Fizzcrank Airstrip | 4108 | 114: 57.12, 18.72 | Approximate inn | [WOTLK_Borean_Tundra.lua:247](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Borean_Tundra.lua#L247) |
| Fort Livingston | 5320 | 50: 53.21, 66.92 | Approximate inn | [CATA_Northern_Stranglethorn.lua:125](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Northern_Stranglethorn.lua#L125) |
| Fuselight | 5496 | 15: 65.88, 35.85 | Approximate inn | [CATA_Badlands.lua:16](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Badlands.lua#L16) |
| Grol'dom Farm | 1704 | 10: 56.27, 40.04 | Approximate inn | [CATA_Northern_Barrens.lua:37](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Northern_Barrens.lua#L37) |
| Gundargaz | 14796 | 2214: 47.94, 32.16 | Approximate inn | [Aes_Versatile_TWW_speed.lua:400](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Archive/WoWPro_Leveling/Retail/Aes_Versatile_TWW_speed.lua#L400), [Aes_Versatile_TWW_speed.lua:437](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Archive/WoWPro_Leveling/Retail/Aes_Versatile_TWW_speed.lua#L437) |
| Heart of the Forest | 12858, 12923, 13388 | 1701: 54.59, 55.49 | AreaTable name has multiple area IDs. | [SL_Covenant.lua:88](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/SL_Covenant.lua#L88) |
| Hero's Rest | 11381 | 1533: 53.15, 46.88 | Approximate inn | [SL_Bastion.lua:406](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/SL_Bastion.lua#L406) |
| Honor Hold | 3538 | 100: 54.20, 63.60 | Approximate inn | [BC_Hellfire.lua:21](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Hellfire.lua#L21) |
| Iron Summit | 5628 | 32: 39.21, 66.02 | Approximate inn | [CATA_Searing_Gorge.lua:116](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/CATA_Searing_Gorge.lua#L116) |
| Karnum's Glade | 4805 | 66: 56.68, 50.01 | Approximate inn | [CATA_Desolace.lua:112](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Desolace.lua#L112) |
| Lakeshire | 69, 12953 | 49: 26.39, 41.42 | AreaTable name has multiple area IDs. | [CATA_Redridge_Mountains.lua:31](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Redridge_Mountains.lua#L31) |
| Light's Hope Chapel | 2268, 4361, 8357 | 24: 43.99, 89.42 | AreaTable name has multiple area IDs. | [CATA_Eastern_Plaguelands.lua:156](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/CATA_Eastern_Plaguelands.lua#L156) |
| Lion's Pride Inn | 5637 | 37: 43.77, 65.80 | Approximate inn | [INTRO_Human.lua:173](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/INTRO_Human.lua#L173) |
| Lor'danel | 4659, 10067, 10230, 10237, 10310 | 62: 50.98, 18.61 | AreaTable name has multiple area IDs. | [CATA_Darkshore.lua:15](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Darkshore.lua#L15) |
| Marshal's Stand | 4882 | 78: 55.31, 62.26 | Approximate inn | [CATA_UnGoro.lua:55](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/CATA_UnGoro.lua#L55) |
| Maruukai | 13764, 14476 | 2023: 62.80, 40.66 | AreaTable name has multiple area IDs. | [DF_Ohnahran_Plains.lua:117](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/DF_Ohnahran_Plains.lua#L117) |
| Mereldar | 14917, 15149, 15545 | 2215: 42.76, 55.81 | AreaTable name has multiple area IDs. | [Aes_Versatile_TWW_speed.lua:875](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Archive/WoWPro_Leveling/Retail/Aes_Versatile_TWW_speed.lua#L875) |
| Nethergarde Keep | 1438 | 17: 60.72, 14.13 | Destroyed/phased Blasted Lands inn; no verified bind-phase mapping. | [CATA_Blasted_Lands.lua:13](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Blasted_Lands.lua#L13) |
| Nijel's Point | 608 | 66: 66.26, 6.64 | Approximate inn | [CATA_Desolace.lua:15](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Desolace.lua#L15) |
| Nozzlepot's Outpost | 5117 | 10: 62.52, 16.65 | Approximate inn | [CATA_Northern_Barrens.lua:213](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Northern_Barrens.lua#L213) |
| Orebor Harborage | 3766 | 102: 41.85, 26.20 | Approximate inn | [BC_Zangarmarsh.lua:240](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Zangarmarsh.lua#L240) |
| Ratchet | 392, 8756 | 10: 67.29, 74.68 | AreaTable name has multiple area IDs. | [CATA_Northern_Barrens.lua:145](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Northern_Barrens.lua#L145) |
| Razor Hill | 362 | 1: 51.61, 41.65 | Approximate inn | [INTRO_Orc_Troll_Part2.lua:37](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/INTRO_Orc_Troll_Part2.lua#L37) |
| Refuge Pointe | 320, 9747, 15073, 15733, 16445 | 14: 39.91, 49.04 | AreaTable name has multiple area IDs. | [CATA_Arathi_Highlands.lua:11](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Arathi_Highlands.lua#L11) |
| Ruby Lifeshrine | 13727, 14448 | 2022: 61.89, 73.84 | AreaTable name has multiple area IDs. | [DF_Waking_Shores.lua:180](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/DF_Waking_Shores.lua#L180) |
| Rusty Rocket Tavern | 8613 | 109: 32.01, 64.39 | Approximate inn | [BC_Netherstorm.lua:15](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/BC_Netherstorm.lua#L15) |
| Scryer's Tier | 3898 | 111: 56.35, 81.55 | Approximate inn | [BC_Terokkar.lua:24](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Terokkar.lua#L24) |
| Seat of the Primus | 12876, 13187 | 1698: 47.02, 29.95 | AreaTable name has multiple area IDs. | [SL_Covenant.lua:1599](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/SL_Covenant.lua#L1599) |
| Sentinel Hill | 108 | 52: 52.86, 53.71 | Approximate inn | [CATA_Westfall.lua:71](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Westfall.lua#L71) |
| Shal'Aran | 7928 | 680: 36.56, 46.93 | Approximate inn | [LEGION_Suramar.lua:49](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/LEGION_Suramar.lua#L49) |
| Shattrath City | 3703, 6980, 7420 | 111: 28.00, 49.00 | AreaTable name has multiple area IDs. | [BC_Terokkar.lua:20](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Terokkar.lua#L20), [BC_Terokkar_Forest.lua:20](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/BC_Terokkar_Forest.lua#L20), [BC_Terokkar_Forest.lua:23](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/BC_Terokkar_Forest.lua#L23) |
| Silver Tide Hollow | 5005 | 205: 49.13, 41.95 | Approximate inn | [CATA_Vashjir.lua:180](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Vashjir.lua#L180), [CATA_Vashjir.lua:172](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Vashjir.lua#L172) |
| Speedbarge Bar | 5049 | 64: 76.52, 74.74 | Approximate inn | [CATA_Thousand_Needles.lua:23](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Thousand_Needles.lua#L23) |
| Stoutlager Inn | 2101 | 48: 35.48, 48.44 | Approximate inn | [CATA_Loch_Modan.lua:45](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Loch_Modan.lua#L45) |
| Surwich | 5084 | 17: 44.42, 87.70 | Phased Blasted Lands inn; no verified bind-phase mapping. | [CATA_Blasted_Lands.lua:135](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Blasted_Lands.lua#L135) |
| Sylvanaar | 3772 | 105: 35.80, 63.90 | Approximate inn | [BC_Blades_Edge_Mountains.lua:24](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Blades_Edge_Mountains.lua#L24) |
| Temple of Telhamat | 3552 | 100: 23.23, 36.50 | Approximate inn | [BC_Hellfire.lua:294](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Hellfire.lua#L294) |
| The Briny Cutter | 5012 | 201: 45.20, 23.40 | Approximate inn | [CATA_Vashjir.lua:16](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Vashjir.lua#L16) |
| The Conjured Biscuit Inn | 14434 | 2024: 37.37, 62.43 | Approximate inn | [DF_Azure_Span.lua:150](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/DF_Azure_Span.lua#L150) |
| The Crossroads | 380, 7477, 8762 | 10: 49.60, 57.95 | AreaTable name has multiple area IDs. | [CATA_Northern_Barrens.lua:70](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Northern_Barrens.lua#L70) |
| The Farstrider Lodge | 147 | 48: 81.91, 64.60 | Approximate inn | [CATA_Loch_Modan.lua:150](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Loch_Modan.lua#L150) |
| The Great Seal | 9598 | 1163: 50.91, 74.43 | Guide coordinates disagree; indoor inn point needs verification. | [BFA_Intro.lua:45](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/BFA_Intro.lua#L45), [BFA_Zuldazar.lua:22](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/BFA_Zuldazar.lua#L22) |
| The Harborage | 657 | 51: 29.00, 32.60 | Approximate inn | [CATA_Swamp_of_Sorrows.lua:123](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Swamp_of_Sorrows.lua#L123) |
| The Immortal Coil | 5056 | 201: 38.83, 31.62 | Approximate inn | [CATA_Vashjir.lua:14](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/CATA_Vashjir.lua#L14) |
| The Oasis Inn | 8611 | 81: 55.51, 36.72 | Silithus world-state/phase must be observed. | [CATA_Silithus.lua:16](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/CATA_Silithus.lua#L16) |
| The Road Warrior | 8610 | 71: 52.59, 27.00 | Approximate inn | [CATA_Tanaris.lua:16](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Tanaris.lua#L16) |
| The Salty Sailor Tavern | 8615 | 210: 40.93, 73.79 | Approximate inn | [CATA_Cape_of_Stranglethorn.lua:78](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Cape_of_Stranglethorn.lua#L78) |
| The Weaver's Lair | 14755 | 2255: 56.98, 38.83 | Approximate inn | [Aes_Versatile_TWW_speed.lua:1075](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Archive/WoWPro_Leveling/Retail/Aes_Versatile_TWW_speed.lua#L1075) |
| Theramore Isle | 513, 6042, 6502, 8839 | 70: 66.57, 45.26 | AreaTable name has multiple area IDs. | [CATA_Dustwallow_Marsh.lua:23](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Dustwallow_Marsh.lua#L23) |
| Thunderbrew Distillery | 2102 | 27: 54.47, 50.81 | Approximate inn | [INTRO_Dwarf_Gnome_Part2.lua:13](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/INTRO_Dwarf_Gnome_Part2.lua#L13) |
| Toshley's Station | 3918 | 105: 61.00, 68.10 | Approximate inn | [BC_Blades_Edge_Mountains.lua:85](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Blades_Edge_Mountains.lua#L85) |
| Valdrakken | 13862 | 2112: 47.26, 46.47 | Multiple Valdrakken inns; city label does not identify one inn. | [DF_Thaldraszus.lua:81](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/DF_Thaldraszus.lua#L81) |
| Valgarde | 3981, 4379 | 117: 58.39, 62.46 | AreaTable name has multiple area IDs. | [WOTLK_Howling_Fjord.lua:15](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Howling_Fjord.lua#L15) |
| Wayfarer's Rest | 16645 | 2393: 56.29, 70.35 | Approximate inn | [MN_Eversong_Woods.lua:77](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Neutral/MN_Eversong_Woods.lua#L77) |
| Westguard Inn | 4380 | 117: 30.86, 41.45 | Approximate inn | [WOTLK_Howling_Fjord.lua:156](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Howling_Fjord.lua#L156) |
| Whisperwind Grove | 5645 | 77: 44.75, 29.17 | Approximate inn | [CATA_Felwood.lua:123](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Felwood.lua#L123) |
| Wildhammer Stronghold | 3745, 5776 | 104: 37.06, 58.17 | AreaTable name has multiple area IDs. | [BC_Shadowmoon.lua:30](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/BC_Shadowmoon.lua#L30) |
| Wildheart Point | 5649 | 77: 43.98, 61.94 | Approximate inn | [CATA_Felwood.lua:59](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/CATA_Felwood.lua#L59) |
| Wintergarde Keep | 4177 | 115: 77.50, 51.50 | Approximate inn | [WOTLK_Dragonblight.lua:31](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Dragonblight.lua#L31), [WOTLK_Dragonblight.lua:232](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Alliance/WOTLK_Dragonblight.lua#L232) |

## Additional translated-name blockers

These have different English labels from the matching guide area. The runtime must retain them so that the collision exists in the affected client locale.

| Extra area ID | English label | Colliding catalog area | Locale(s) |
| --- | --- | --- | --- |
| 1598 | Grol'dom Farm UNUSED | 1704 | itIT |
| 5633 | Terrace of the Augurs | 3898 | ptBR |
| 5836 | Forest Heart | 12858, 12923, 13388 | deDE, frFR, esES, esMX, ptBR, ruRU, zhTW, itIT |
| 7659 | Heroes' Rest | 11381 | koKR, zhCN |
| 8065 | The Retreat | 657 | ruRU |
| 8409 | Heroes' Rest | 11381 | koKR, zhCN |
| 13632 | Haven | 320, 9747, 15073, 15733, 16445 | deDE |
| 16094 | Augurs' Terrace | 3898 | ptBR |
| 16179 | Augurs' Terrace | 3898 | ptBR |
| 16326 | Augurs' Terrace | 3898 | ptBR |

## Morgenluft / Fairbreeze Village

The current AreaTable contains **two different areas named `Morgenluft` in deDE**, both `Fairbreeze Village` in enUS:

| Area ID | Parent area | World map instance ID | UI map | Meaning |
| --- | --- | --- | --- | --- |
| 3462 | 3430 | 530 | 94 | Legacy Eversong Woods |
| 15995 | 15968 | 0 | 2395 | Midnight Eversong Woods |

The legacy binding step at [INTRO_Blood_Elf.lua:122](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/blob/f7c84c7ef4bcc3af20ff33cb5a497dd639b45851/WoWPro_Leveling/Retail/Horde/INTRO_Blood_Elf.lua#L122) locates the inn at **43.7, 71.2** on map **94**, with Marniel Amberlight. ATT independently associates NPC **15397** with **43.6, 71.3** in legacy Eversong: [ATT Eversong Woods.lua:1595–1597](https://github.com/ATTWoWAddon/AllTheThings/blob/afc150328d8a4c9abb68f5dc7f47948ee00e09e1/.contrib/Parser/DATAS/02%20-%20Outdoor%20Zones/02%20Eastern%20Kingdoms/Eversong%20Woods.lua#L1595). The slight difference is another reason to describe these as inn locations.

The current [Sylmara Dawnpetal NPC dataset](https://www.wowhead.com/npc=242949/sylmara-dawnpetal), NPC **242949**, embeds mapper data for area **15968**, UI map **2395**, at **46.2, 46.0**. This sourced innkeeper point supplies the modern default. The earlier [Dragon Army travel notes](http://dragonarmyguild.net/viewthread.php?p=1&threadid=4847) describe a beta visit and a nearby **46.3, 46.0** point; the current NPC map data is used instead.

Both AreaTable IDs deliberately act as localized **bind-name aliases** for the modern position and carry `isDefault = true`. In particular, record 3462 does not claim that the legacy area physically moved to map 2395. This is an explicit product default, not evidence that the character is actually bound in the modern area. The tooltip explains the choice. In ptBR the old and new labels differ, so both names remain aliases for this same destination.

The existing observer continues running while the default is in use. A valid saved observation matching the character and bind name always wins; a successful observed arrival or a new binding replaces the default, including a destination on legacy map 94. Defaults are never written as observed SavedVariables. Other name collisions remain unresolved, and a third conflicting candidate would still block inference.

## Deliberate limits

- Valdrakken's city label does not identify one inn; it is blocked pending precise inn-name evidence.
- The Great Seal has materially different guide points at two binding steps; it is blocked pending an indoor coordinate check.
- Nethergarde Keep, Surwich, Dolanaar and The Oasis Inn are withheld because their world state/phase cannot be derived reliably from the binding label alone.
- The catalog does not infer that every inn is represented, that every character can bind there, or that an AreaTable row itself proves an inn exists.
- All catalog results remain fallbacks. Unknown/ambiguous labels without an explicit default continue to require stronger evidence; observed character data is never overwritten by this catalog.
