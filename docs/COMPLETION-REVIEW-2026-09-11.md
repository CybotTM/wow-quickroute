# Routing completion and review, 2026-09-11

Work starts from `46eecb8a646751a1d3d70a67a4178f4a25cd2dde` (main,
after release 1.18.5). The installed client initially matches PR #83, whose
version string is still 1.18.5. Four uncommitted files from the earlier
1.18.1-based routing investigation are preserved separately before integration.

## Scope and acceptance

The user requested completion of the outstanding QuickRoute work, followed by
several review rounds covering resource consumption, performance, accuracy,
data trustworthiness and reliability. Existing authorization covers repository
work, merging verified QuickRoute changes and installing the resulting addon.

| Deliverable | Acceptance evidence | State |
| --- | --- | --- |
| Existing hearthstone binding | Successful arrival records only the observed character's current bind; canceled/unrelated arrivals do not | Verified in event and complete-route tests |
| Death Gate destination | No guaranteed EPL landing; confirmed Legion destination and return/diversion guards | Verified in initialized data and complete-route tests |
| Quest recommendations and performance (#66, #71, #72) | Fresh destination/cooldown choices, bounded API work, before/after resource measurements | Verified, including one bounded repair batch after a mid-refresh rebind |
| Flight network correctness (#82, #33) | Directed, faction-correct data and complete-route comparisons | Verified; 6,156 scenarios |
| Portal observations (#83) | Valid departure/arrival pairs, bounded storage, corrupt-data and combat handling | Verified, including global 6,000-origin and 6,000-endpoint budgets |
| Claimed stranded zones / Oribos returns (#21, #40) | Real full-graph routes, verified transport data; no invented return portals | Verified with discovery-dependent fixtures |
| Review rounds | Functional/source review, independent adversarial review, integrated verification | Complete; findings repaired and rechecked |
| Delivery | Exact reviewed commits, green CI, scoped merges, verified installation and explicit remaining live limits | Local gates passed; GitHub PR and release gates follow |

## Risks considered before integration

- Overwriting newer performance fixes with the old working copy: separate
  worktree, saved patches, surgical integration by file owner.
- Reporting static data instead of initialized data: test actual loaded
  destination candidates and full `CalculatePath` results.
- Guessing a remote hearth binding from its name: require observed binding or
  successful arrival; never substitute a map midpoint.
- Treating Death Gate as a single fixed location: verify class-hall state;
  exclude unresolved return travel and quest diversions.
- Conflating availability with the global cooldown: preserve the current batch
  and GCD protections while handling real expiry and combat transitions.
- Hiding real quest progress with longer caches: preserve explicit event
  invalidation and test destination changes within a zone and delayed POIs.
- Counting undirected or opposite-faction taxi connections as usable: inspect
  client graph direction and permitted flight masters.
- Pricing a transport twice: verify the owner of cast and loading durations.
- Treating a movement sample as a measured portal: freeze actual endpoints;
  retain observations as candidates, not automatically trusted routes.
- Corrupt, secret or unbounded saved data: validate both endpoints and cap
  stores; never execute SavedVariables to inspect them.
- Misleading performance comparisons: identical harness and capability profile,
  separate semantic changes, report call counts and retained heap as well as time.
- Claiming live verification from mocks: distinguish harness, client source,
  observed saved data and direct game evidence.
- Parallel edits or loss of task context: assigned file ownership and this
  persistent deliverable register; resolve disagreements before accepting claims.
- Premature completion: review every deliverable and issue against evidence,
  not just a green build; retain any genuinely missing client observation.

The independent plan review additionally required delayed quest-data tests,
real cooldown expiry without events, global-cooldown bursts and combat callback
coverage. The implementation uses normal bounded execution and reviewers;
no recurring automation or separate goal was requested.

## Evidence and review results

Evidence from this working session is kept under
`/home/cybot/projects/qr-completion-evidence-20260911`.
Final reproducible commands, measurements and review outcomes are recorded below
when each change has passed integration checks.

### Review rounds and repairs

1. **Implementation and source review.** Compared initialized data, player API
   state and complete routes. Removed Death Gate's false Eastern Plaguelands
   landing; learned hearth arrivals without guessing remote coordinates;
   corrected cooldown expiry; replaced undirected/opposing-faction taxi
   components; corrected departure/arrival capture and loading counted twice.
   The transport data changes were checked against Blizzard client tables.
2. **Independent cross-review.** Reviewers inspected other contributors' code.
   Found city-named binds hidden by inn subzone names, cooldowns first seen in
   their final second, a survey rounding-boundary migration error, and legacy
   test settings that leaked between file orders. Removed claims that taxi
   coordinate distance was an exact flight length. A separate transitive-closure
   calculation agrees with generated components for 680,969 faction/master pairs.
3. **Integration and resource review.** Exercised live bind changes between
   queued quest callbacks, revealing an earlier button retaining its obsolete
   hearth after a later callback rebuilt the graph. Also challenged the product
   of survey limits: per-table caps alone could admit more than one million
   endpoint records. Both findings are fixed and have regression coverage: one
   replacement quest batch repairs earlier buttons, and global budgets apply on
   saved-data loading and live recording with constant-time counter updates.
   Security checks cover secret/nonfinite API values, malformed
   saved tables, bounded observation growth and protected-frame writes in combat.

### Routing accuracy and data limits

The full routing test uses an Alliance death knight with a ready Stormwind
cloak, Death Gate and a normal hearthstone. From Dalaran, the cloak wins for
Stormwind and for the modeled Twilight Crypts entrance while the bind is
unknown. Adding an observed nearer inn makes the hearth win on total route
cost. The inn in this test is an explicit fixture; it is not a claimed measured
coordinate for the user's Morgenluft binding.

An old binding becomes known after a successful observed hearth arrival or
binding at an inn. It is scoped to character and current bind name. The tooltip
explains this requirement. Death Gate is only an automatic route option for a
confirmed unlocked Legion hall outside Acherus, excluding the known Icecrown
artifact diversion. Unresolved legacy/return destinations are omitted and
explained; they are not substituted with Eastern Plaguelands coordinates.

The flight comparison isolates network changes from loading-price changes:
**262 faster modeled routes, zero slower routes, and 603 unreachable in both
versions across 6,156 scenarios**. Faction, teleport readiness and taxi discovery
are explicit inputs. One-way-only taxi components are conservatively omitted
by the paired-flight model. Flight, overland and loading times are estimates;
the graph does not contain terrain navigation meshes or measured taxi splines.
This is the fastest modeled route among available, known options, not proof of
the fastest physical path over every obstacle or quest phase in WoW.

[The portal and return-route review](reviews/portal-survey-2026-09-11.md)
records 48/48 capital returns from the named Pandaria/Draenor maps with discovered
taxis, and 16/16 symmetric Oribos realm routes. Undiscovered taxis remain gated.
The user's saved survey contains new travel observations, including one coarse
endpoint pair; those observations are evidence candidates and are not promoted
to verified portals automatically.

### Resource measurements

The controlled quest-refresh workload reduces map-wide API reads from 42,750
to 1,710 (96%) and allocation from 8,294 to 3,360 KiB (59.5%). Quest events still
invalidate stale answers, including projection-only destinations. The
quest-specific worst-case projection scan remains necessary and is stated in
[the performance review](reviews/quest-performance-2026-09-11.md).
The final integrated dataset includes two additional maps: the same cold
workload makes 1,730 map reads and allocates 3,361 KiB. The 1,710 figure above
isolates the scan implementation on an identical map catalog.

The integrated standalone workload retains about 35 MiB after initialization
and 43 MiB after building the complete catalog indexes and graph. About
22.5 MiB comes from the bundled destination data alone. Three settled batches
of 100 route queries stabilize rather than growing retained heap. Temporary
allocation is still about 139 KiB per ordinary settled route. These figures
include the Lua harness and exclude native client allocations; they must not be
presented as WoW's addon-memory display or live FPS measurements.

The memory benchmark labels one-shot hypothetical graph copies separately from
MultiRoute's actual reused private context. The movement benchmark observes no
route calculation or graph rebuild while settled, 25 routes and no rebuilds
over ten simulated seconds of movement, and no reroutes for unchanged quest
events. CPU timings are machine-specific; API counts and graph/cache behavior
are the stronger regression evidence.
The tested cross-continent tour context costs about 1.1 MiB to create. Its
settled queries still allocate about 2.2 MiB per leg and take roughly 10 ms in
this harness, with only 3.5 KiB retained across a repeated 25-leg batch. This
user-requested, queued optimization is heavier than ordinary cached routing;
the change does not claim to eliminate its transient allocation.

### Reproduction and final gates

```sh
~/.local/bin/lua5.1 tests/run_tests.lua
QR_TEST_ORDER=reverse ~/.local/bin/lua5.1 tests/run_tests.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
./scripts/lint.sh
~/.local/bin/lua5.1 scripts/benchmark_quest_refresh.lua QuickRoute/
~/.local/bin/lua5.1 scripts/benchmark_memory.lua QuickRoute/ full
~/.local/bin/lua5.1 scripts/benchmark_movement.lua QuickRoute/
~/.local/bin/lua5.1 scripts/benchmark_flight_routes.lua .
~/.local/bin/lua5.1 scripts/benchmark_portal_routes.lua .
```

The final frozen source passed **16,977 Lua assertions in each file order**, all
**56 Python tests**, and pinned luacheck **with zero warnings/errors across 126
files**. The actual inventory was rendered through the existing patched
wow-ui-sim checkout: icons, header and frame corners were visually inspected.
The German hearth tooltip handler was executed and its content asserted; the
headless renderer dismisses the popup before capture, so that image proves the
inventory layout, not the popup's final appearance. No simulator PR was merged.

Direct game control was unavailable:
the Windows/WSL tool bridge rejected its sandbox working-directory URI before
executing any game action. No in-game FPS or live gameplay acceptance is claimed.
