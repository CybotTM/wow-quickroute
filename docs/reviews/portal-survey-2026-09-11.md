# Portal survey and return-route review — 2026-09-11

## Results

Issue #21's original assertion that Pandaria and Draenor have no modeled return
portals is outdated. `TravelTransitions.lua` already contains faction-specific
returns from Paw'Don/Honeydew Village and Stormshield/Warspear. The remaining
reproducible gap was the two outdoor garrison maps: Lunarfall (582) had no
connection to Shadowmoon Valley (539), and Frostwall (590) had no connection to
Frostfire Ridge (525). Both ordinary entrances now work in both directions.
Their 60-second local cost is an estimate, matching this table's coarse zone
travel model; it is not a measured gate duration or a level-3 garrison portal.

With no personal teleport abilities and all modeled flight masters discovered,
the full routing engine reaches the faction capital from all 24 explicitly
named Pandaria/Draenor maps for both factions: **48/48 complete routes**. The same
fixture on main `46eecb8` reaches 44/48; its four failures are the two garrisons
for both factions. The regression names every origin and checks actual route
steps, so deleting a map from the production catalog cannot weaken coverage.

A completely flightless character with no discovered taxis and no personal
teleport still has no modeled mainland exit from Timeless Isle or nine Draenor
maps. Those cases require discovering an available flight, another verified
travel ability, or a separately modeled transport; they are not evidence of
unconditional return portals. The test does not bypass discovery gates to make
these cases green.

Issue #40's premise that the four covenant realms share an ordinary return
portal with Oribos was wrong. The existing sourced transition data correctly
uses taxi flights and the Ring of Transference (1671), with an explicit
translocation pad connecting the Ring of Fates (1670). All four realms are
reachable in both directions for both factions when their flight points are
known: **16/16 routes**. At matched flight-master coordinates the modeled times
are symmetric: Bastion 228.857s, Maldraxxus 214.512s, Ardenweald 169.113s,
Revendreth 169.967s. These are distance/speed estimates, not measured taxi times.
Without discovered flight points, the same realm crossings remain unavailable;
no portal or overland edge substitutes for them. The Maw is separate transport
(a one-way descent), not a fifth ordinary realm flight or a reversible portal.

## Survey evidence and recorder correction

The existing client SavedVariables file was read as literal data without
executing Lua or changing the file. Only aggregate survey fields and endpoint
coordinates were exported: 56 maps, 71 map pairs, 49 crossings without an
observed load, 30 with a load, and one endpoint pair:

| From map | x | y | Into map | x | y | Count |
|---|---|---|---|---|---|---|
| 2405 | 0.5159 | 0.7027 | 2537 | 0.2517 | 0.3816 | 1 |

The client map table identifies 2405 as Voidstorm and 2537 as the Quel'Thalas
continent map. This is a single observation into a coarse parent map. It does
not identify a portal, its transport method, or a Pandaria/Oribos return point.
No routing coordinate was invented from it.

PR #83's recorder now reads and freezes the departure on
`LOADING_SCREEN_ENABLED`, before map APIs change, and retains the first available
arrival position instead of movement observed by the delayed capture. Its
sample fallback expires after two seconds. Combat, disabling, clearing and
ambiguous multiple loads invalidate stale state and queued captures. Both ends
participate in endpoint bucket keys; legacy keys migrate without losing counts.

Saved-state validation rejects nonfinite/out-of-range coordinates, invalid map
IDs and secret API values, normalizes counters, removes unknown nested data, and
applies caps on load and recording: 3,000 maps, 64 origins per map, six endpoint
pairs per origin, plus global budgets of 6,000 origins and 6,000 endpoint pairs.
Global counts are maintained per active store, so revisits do not rescan the
whole survey. Clearing or replacing the store resets/rebuilds the counts.
Reinitialization reuses its event frame. The report explicitly
says that loading screens, repeat counts, and the legacy `walked` counter cannot
prove a portal or geographic adjacency. This fixes the evidence collection
mechanism; it does not claim a newly observed live-client journey.

## Sources and verification

- Blizzard client [UiMap, build 12.1.0.69587](https://wago.tools/db2/UiMap/csv?build=12.1.0.69587): 582's parent is 539; 590's parent is 525. Acherus floor maps 647/648 both have parent 619 and are now included in the Broken Isles continent list, without invented overland connections.
- Blizzard's [Frostfire Ridge preview](https://worldofwarcraft.blizzard.com/en-us/news/14645686/warlords-of-draenor-zone-preview-frostfire-ridge) identifies Frostwall as the garrison established in Frostfire Ridge.
- Blizzard client [TaxiPath, build 12.1.0.69587](https://wago.tools/db2/TaxiPath/csv?build=12.1.0.69587): Oribos node 2395 connects in both directions with Pridefall 2514 (7916/7917), Aspirant's Rest 2519 (8013/8012), Theater of Pain 2564 (8318/8319), and Tirna Vaal 2585 (8431/8432). TaxiPath `Cost` is a monetary fare, not duration.
- [Mapzeroth authored edges](https://github.com/tr0tsky0/Mapzeroth/blob/676241e234cbeab5e2066b869b52c235d675a9e0/Data/Mapzeroth_Data_Edges.lua) and [Pandaria nodes](https://github.com/tr0tsky0/Mapzeroth/blob/676241e234cbeab5e2066b869b52c235d675a9e0/Data/Mapzeroth_Data_Nodes_Pandaria.lua) provide the existing return-portal evidence. Attribution and independent Oribos coordinate checks remain in `QuickRoute/ThirdParty/Mapzeroth-NOTICE.md`.
- Blizzard's [generated loading-screen API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/LoadingScreenDocumentation.lua) declares `LOADING_SCREEN_ENABLED` as a synchronous event.

`tests/test_portal_return_routes.lua` exercises the public `CalculatePath` with
the complete addon graph. `tests/test_zonesurvey.lua` covers load ordering,
pre-load timer cancellation, first-arrival retention, stale/combat samples,
secret/NaN/infinite API data, both-endpoint bucketing, saved-state migration,
load/live bounds, and repeated initialization. Full-suite discovery/reverse
runs and lint are recorded with the overall completion evidence.

Local evidence directory: `/home/cybot/projects/qr-completion-evidence-20260911`.
Run `lua5.1 scripts/benchmark_portal_routes.lua /path/to/checkout > routes.tsv`
for the public full-graph sweep. Run the same script against an immutable
baseline checkout and the changed checkout. The corresponding local main
and changed-tree results are `portal-routes-main.tsv` and
`portal-routes-after.tsv`. The literal-only reader and aggregate export are
`read_survey_data.py` and `survey-live-evidence.txt`. The saved file itself was
not copied into the repository or published.
