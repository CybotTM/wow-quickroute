# ATT acquisition guidance and routing

The player's screenshots exposed gaps in acquisition guidance: QuickRoute did not explain ATT's removed-source status for Path of the Watcher's Legacy, source routing depended on bundled NPC positions, and an item's purchase reputation could prevent visiting its vendor. The follow-up adds acquisition labels, direct ATT source routing and item/NPC destination search, including the Broker Translocation Matrix and Vilo.

## Verified installed data

The installed ALL THE THINGS 5.3.8 database identifies spell **393222** with two removed sources: achievement 16639 in Dragonflight seasons 2 and 4. Both spell records carry `u=2`. Spell **393256** provides a mixed-source counterexample: two removed records and one unmarked record. It must not receive a blanket unavailable label.

Toy **190237**, Broker Translocation Matrix, is recorded under vendor **182257**, Vilo. His own coordinates are `coords = { [1970] = {{34.8, 64.1}} }`. The item's `minReputation = {2478, 42000}` is a purchase condition. Vilo's parent vendor header and the zone's level/patch ancestry remain distinct from that condition.

The integration follows these installed ATT contracts:

- `SearchForField(field, id)` and `GetRawFieldContainer(field)` expose existing flat indexes. The integration does not call the recursive index-building convenience API.
- `NPCNameFromID` is read directly without triggering its tooltip-backed name fallback. Item scans read only data that `C_Item.IsItemDataCachedByID` confirms is cached.
- `PhaseConstants.NEVER_IMPLEMENTED` and `REMOVED_FROM_GAME` identify explicit removal. The existing character filter excludes removed entries, so classification reads the raw indexed alternatives separately.
- ATT identifies vendors through `HeaderConstants.VENDORS` on the NPC's immediate parent. Generic NPCs and quest rewards are not assumed to be vendors.

## Behavior and limits

Missing entries with complete removal evidence show **Currently unobtainable** in QuickRoute help, an unavailable label in the list and a native red-X texture on grouped icons. The Obtainable filter excludes those acquisitions; Show All retains them. Already owned or learned teleports keep their usage status.

Classification requires complete evidence across at most 32 sources and 16 ancestors per source. An unmarked alternative, unknown flag, malformed/cyclic ancestry or truncated result remains unknown. Removed unbound/BoE items can still have tradeable copies, so item labels require explicit bind-on-pickup evidence. No removal calendar or permanent seasonal assumption is invented when ATT is absent.

Source routes use the coordinates of the identified NPC itself. A quest reward can follow explicit giver IDs to independently indexed NPC positions. Generic item or quest reference coordinates never become a guessed vendor position. Source ancestry and supported character-access conditions are checked again when a result is selected.

For an item beneath a confirmed vendor, its own reputation/renown requirement is shown as a purchase condition. It does not prevent visiting the vendor. Conditions on the NPC or its ancestors, and other item access gates, still apply. The help window names the source, shows its coordinates and states the purchase requirement before offering the route.

The destination search accepts item links, numeric item/NPC IDs, cached exact item names and partial cached-name queries. ATT results follow existing catalogue results, with duplicate NPC destinations suppressed. Each item result offers a verified recorded source; this is not an exhaustive search for the globally fastest vendor among all ATT alternatives. Route calculation to the selected point uses QuickRoute's existing travel graph.

Search work is limited to 200 index keys per frame, 40,000 per query, 80 source checks and 20 results, with an additional elapsed-time budget. Results explicitly say when a search is partial or only cached names are available. Closing the window, entering combat or changing the query cancels pending work. A click rechecks the current query, ATT provider, requested item/NPC and original source identity. No new SavedVariables, whole-database copy, bulk item-data loading or background search loop is introduced.

## Validation

Both Lua test orders pass **15,962 assertions**. Luacheck reports zero warnings/errors across **120 files**, and all **47 Python generator/packaging tests** pass. Independent review covers removal alternatives, owned/BoE preservation, pooled labels, source identity, purchase/access distinctions, stale clicks and bounded searches.

A standalone fixture containing 200,000 item IDs and 20,001 cached NPC names stops an unmatched search at 40,000 keys. It used 17.4 ms total CPU, 0.137 ms maximum callback time, about 854 KiB temporary allocation and 2.2 KiB retained heap. Twenty cancelled keystrokes performed no cache/source reads. These measurements cover the Lua search worker, not native game FPS or all dropdown-rendering cost.

The existing combined wow-ui-sim build renders the actual QuickRoute controls with explicit ATT boundary fixtures. Native simulator names can remain English; the German QuickRoute labels are loaded from the addon. These renders verify layout and the native texture badge, not live ATT initialization or native-client routing acceptance.

- [Unavailable list](../screenshots/att-unobtainable-list.webp)
- [Grouped native badge](../screenshots/att-unobtainable-grid.webp)
- [Unavailable help](../screenshots/att-unobtainable-help.webp)
- [Vilo source and purchase requirements](../screenshots/att-vilo-help.webp)
- [Vendor search at the route input](../screenshots/att-search-vilo.webp)
- [Item search at the route input](../screenshots/att-search-item.webp)

Repeat the visual fixtures with `python3 scripts/render_att_review.py --sim-root <combined-wow-ui-sim-checkout> --wow-install <WoW-directory> --output <review-directory>`. In-game confirmation should search for Vilo or item 190237, select its source, and confirm that the route ends at Zereth Mortis 34.8 / 64.1.
