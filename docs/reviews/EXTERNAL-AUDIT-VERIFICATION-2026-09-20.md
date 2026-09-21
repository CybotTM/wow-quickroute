# Verification of the external QuickRoute audit (2026-09-20)

Tree checked: `/home/cybot/projects/wow-quickroute/main` at `f91963e`, the same commit the audit names.
Reproduction runtime: `~/.local/bin/lua5.1`, the version the addon runs on. The audit ran Lua 5.4.

## Code findings

| Audit item | Verdict | Evidence |
| --- | --- | --- |
| A / QR-A01 waypoint parser too narrow | Holds | `QuickRoute/Modules/MultiRoute.lua:35-41`. Pattern `^%s*/way%s+#?(%d+)%s+([%d%.]+)%s+([%d%.]+)`. Reproduced on Lua 5.1: documented form accepted; comma pair, zone name, current-map form, heading line and semicolon-in-label all rejected, and line 41 returns `nil` for the **whole** import, not just the offending line. `;` is also a line separator in the `gmatch` at line 35. |
| B / QR-A02 Silvermoon hidden from Alliance | Holds | `Core/PathCalculator.lua:207` sets `faction = "Horde"` for map 2393. `Modules/DestinationSearch.lua:282` admits a city only on `== "both"` or `== playerFaction`. The comment at 204-206 defends the **mapID** choice, not the faction. |
| C / QR-A03 failure reason dropped | Holds; the audit's description of where is imprecise | `Core/Graph.lua:372` produces `"search_limit"`, inside `FindShortestPathWithState` (declared at `Graph.lua:340`). `Modules/TravelRequirements.lua:393` tail-returns all four values. `Core/PathCalculator.lua:852` captures three. The earlier `return nil` exits at `TravelRequirements.lua:294` and `:375` run before the stateful search, so they cannot drop a `search_limit`; they lose their own distinct reasons. The only lossy hop for `search_limit` is `PathCalculator.lua:852`. |
| D / QR-A04 remote legs priced as ground | Holds, with a nuance | `Core/TravelTime.lua:148`: `if not here ... then return ground end`. `ground` is mounted-ground speed when a usable mount exists (lines 144-147), not bare run speed. The skyriding branch (153-158) needs `gliding == true` and also sits behind `here`. |
| E / QR-A05 collapsing drops anchors | Holds, and is not pinned by a test | `Core/PathCalculator.lua:1911` merges consecutive `walk`/`travel` steps with no map or anchor check; 1919-1924 copies the **last** step and keeps only the first step's `from`. Invoked in the normal flow at line 880. The seven tests at `tests/test_route_features.lua:36-132` use node names only, never map IDs, so cross-map merging is neither asserted nor forbidden. |
| F / QR-A06 search is synchronous | Holds, and is already recorded | `grep coroutine QuickRoute/Core/*.lua` returns nothing; the only coroutine use is `Modules/MultiRoute.lua:9`, the per-route scheduler. `docs/REVIEW-2026-09-05.md:101` already states it: "Complex phase searches reached about 57 ms per query: yielding between comparisons reduces sustained blocking but does not guarantee a sub-16-ms frame." |
| G / QR-A07 tour matrix drops all teleports | Holds as code, but it is a documented decision | `Core/PathCalculator.lua:917-926` strips every edge with `edgeType == "teleport"` under `excludeCooldowns`; `Modules/MultiRoute.lua:133` sets that flag for the tour matrix, and `tests/test_multiroute.lua:113` pins it. `docs/REVIEW-2026-09-05.md:38` states the intent: "The matrix excludes personal teleports ... its optimum is an estimate, not a claim of globally optimal cooldown/phase scheduling." Introduced in `c0222c0`. The audit's point survives: the exclusion is by edge type, so a cooldown-free reusable teleport is removed together with the consumables. |

## Cross-checks the audit did not run

- Issues on `CybotTM/wow-quickroute`: **0 open, 24 closed**. No closed issue covers A, B, C, D, E or G. #66 covers F's symptom and is closed.
- PR #86 "Resolve known hearthstone inns before first use": OPEN, not a draft. Both statuses match the audit.
- `docs/PLAYER-WORKFLOW-REVIEW-2026-09-05.md:31` already records the shared-district vs Horde-enclave distinction for Silvermoon and applies it in `Data/ServicePOIs.lua:30,34`. A surveyed shared coordinate is already in the tree: map 2393, x 0.5028, y 0.7486, `faction = "both"`. Finding B is that distinction missing from `CAPITAL_CITIES`.
- A concept grep over `docs/*.md` for collapse, stutter, yield, skyriding, ground speed, paste and comma found the two F and G paragraphs quoted above, and nothing on A, B, C, D or E.

## Not verified

Everything outside the seven code claims: the competitor comparison table, the player-report table, the CurseForge description claim, and every acceptance criterion. The audit's own scope note already limits those to reading rather than measurement.
