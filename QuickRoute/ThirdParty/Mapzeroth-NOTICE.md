# Mapzeroth data attribution

QuickRoute's `Data/TravelShortcuts.lua` and `Data/TravelTransitions.lua` adapt
static travel ability, destination and transition data from
[Mapzeroth](https://github.com/tr0tsky0/Mapzeroth), revision
`676241e234cbeab5e2066b869b52c235d675a9e0` (reviewed 2026-09-05).

Copyright (c) 2026 tr0tsky0. Used under the MIT License; the complete license is
included in [Mapzeroth-LICENSE.txt](Mapzeroth-LICENSE.txt).

The source data was reviewed and converted independently. QuickRoute does not
load or execute Mapzeroth at runtime. QuickRoute adds ownership, unlock, phase,
coordinate validation and protected-action handling. Random landings and known
zone-centre placeholders are excluded from guaranteed destination candidates.

Mole Machine unlock quest identifiers were cross-checked with the client-facing
unlock flag catalogue published by the InteractiveWormholes author at
<https://www.wowhead.com/spell=265225/mole-machine>. The three initial destinations
need no discovery flag; the remaining destinations require their individual flag.

The Northrend generator's additional Icecrown option (65, 31) is corroborated by
the [player guide on Blizzard's forum](https://us.forums.blizzard.com/en/wow/t/vanity-items-more-toys-for-your-toy-box/1759386/1).
The Draenor generator remains excluded from deterministic routes because each
zone choice has several random landing points, documented by players at
<https://www.wowhead.com/item=112059/wormhole-centrifuge>.

Housing and movement API shapes follow Blizzard's generated API documentation
in the [live WoW UI source mirror](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated),
including `HousingUIDocumentation.lua`, `HousingUISharedDocumentation.lua`,
`HousingNeighborhoodUIDocumentation.lua`, `PlayerInfoDocumentation.lua` and
`MountJournalDocumentation.lua`.

Additional flight connections were verified against the client
[TaxiNodes](https://wago.tools/db2/TaxiNodes/csv?build=12.1.0.69587) and
[TaxiPath](https://wago.tools/db2/TaxiPath/csv?build=12.1.0.69587) tables for build
`12.1.0.69587`: Amani'Zar Village (3127) to Tokka's Landing (3168), and Oribos
(2395) to Pridefall Hamlet (2514), Aspirant's Rest (2519), Theater of Pain
(2564), and Tirna Vaal (2585). Travel times use horizontal world distance divided
by QuickRoute's flight speed, plus its boarding overhead; these are estimates.
The database's `TaxiPath.Cost` field is a monetary fare, not a duration.

Oribos floor-pad and portal position facts were cross-checked against the
[HandyNotes: TravelGuide author's observations](https://github.com/Dathwada/handynotes-travelguide/blob/7f6477ac3825777fa55d1835e92e70edadff886d/Retail/data/DB.lua#L425),
revision `7f6477ac3825777fa55d1835e92e70edadff886d`. That project reserves its
rights; QuickRoute copies no code or structured records from it. The lower
transport pad is independently corroborated by the
[firsthand quest walkthrough](https://www.wowhead.com/quest=61475/the-heart-of-the-forest#comments).
