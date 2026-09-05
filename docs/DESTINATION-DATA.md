# Retail destination catalogue

QuickRoute ships a reproducible reference catalogue from [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings), pinned at [`8809863ca3e6e4cb4bf8f2cae1d18d52fc209235`](https://github.com/ATTWoWAddon/AllTheThings/tree/8809863ca3e6e4cb4bf8f2cae1d18d52fc209235). The source is MIT licensed; its complete notice is distributed at `QuickRoute/Licenses/AllTheThings-MIT.txt`.

The snapshot contains 1,042 vendor currency/location variants across 76 accepted currency IDs, 25,183 quest reference coordinates, 1,496 independently located quest-giver entries, and 8,076 NPC coordinate entries. These cover 22,211 distinct quests and 5,726 distinct NPCs. Variants retain their own access conditions; counts describe source coverage, not simultaneous character availability.

## Reproduce and verify

Use Python 3.10 or newer and Git. No Lua from the source checkout is executed.

```sh
git clone https://github.com/ATTWoWAddon/AllTheThings.git /tmp/quickroute-att

git -C /tmp/quickroute-att checkout 8809863ca3e6e4cb4bf8f2cae1d18d52fc209235
python3 scripts/generate_destination_catalog.py --source /tmp/quickroute-att
python3 -m unittest discover -s tests -p 'test_*.py'
```

The generator rejects a different commit and modified or additional input files. `QuickRoute/Data/DestinationCatalog.sources.txt` records SHA-256 hashes of the compiled retail source files, the pinned original-source name tree, and the target interface build. Names come from the original source comments; live localized quest titles and NPC tooltip names take precedence when loaded by the client. Numeric IDs remain searchable regardless of locale.

## Interpretation and access

Currency vendors are identified within explicit vendor sections. Only currency entries in an item's purchase `cost` establish accepted currency. A vendor selling a currency does not establish that it accepts that currency. Independently observed merchant data uses Blizzard's `GetMerchantCurrencies` API and supersedes reference coordinates for the same NPC on that map, for the observing character and faction.

Quest coordinates remain **reference** locations because the source does not define a universal giver/objective/turn-in role for them. **Quest giver** entries join the quest's `qgs` relationship to a separately documented NPC position and combine both records' requirements. No NPC location is inferred from a generic quest coordinate. Active quest objectives and turn-ins come from Blizzard's live quest waypoint/POI APIs and are never replaced with giver coordinates when unavailable.

The evaluator preserves faction, class, race, minimum level, profession skill-line, covenant, reputation and renown gates. Inherited quest prerequisites retain their original required-completion count (`sqreq`, default all). Missing required API data denies access. The completion check is conservative: ATT's collection UI can additionally relax breadcrumbs and active prerequisite quests; QuickRoute does not grant access based on those collection heuristics. Completed one-time quests are hidden from general search; an explicit quest-ID giver request can still retrieve the reference.

Removed, future, timed/event, weekly/world-quest and dynamic callback branches are excluded when their runtime access cannot be determined safely. A historical static reference cannot guarantee that an NPC is present in the character's current personal story phase. The graph separately checks supported map-phase transitions. The visible provenance description allows the player to distinguish catalogue locations from personally visited merchants. Blizzard's current waypoint and map POI data remain the authority for live targets.

## Performance and interaction

The catalogue is indexed once when first used. Empty search reads only the current/viewed map's entries. Global reference search starts at two characters, returns at most 40 rows, and narrows previous matches when a text query grows; exact numeric-ID searches use the full index so typing additional digits cannot discard a valid ID. Currency choices list the fastest eligible vendor action and individual known vendors, with source labels and a back control. Long vendor lists render at most 100 locations and prompt for a narrower name/zone search.

On the development machine, standalone Lua 5.1 loaded the generated 4.70 MB file in approximately 88 ms (22.5 MiB retained data), built its indexes in 29 ms (8.2 MiB additional), and searched a broad initial `th` query in 8.5 ms. Refining through `the` to `the lost` took 2.8 ms down to 0.013 ms; a current-map query took 0.26 ms. These are development measurements, not in-client frame-time guarantees.

Fastest currency selection calculates one route per frame. A map change or movement exceeding 0.1% of a map axis discards all prior estimates and restarts from the new origin. At most two restarts are allowed; sustained movement produces an explanatory retry message. Cancellation prevents an earlier comparison from publishing over a newer destination selection.
