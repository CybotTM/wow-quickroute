# Quest refresh performance and correctness review

Compared against main commit `46eecb8` with identical Lua 5.1 fixtures. To isolate
these changes from the parallel flight and portal updates, the after snapshot
replaced only `QuestTeleportButtons.lua`, `WaypointIntegration.lua`, and
`CooldownTracker.lua` in a copy of that commit's addon directory. Three
alternating baseline/after runs produced these results:

| Workload / metric | Baseline | After |
| --- | ---: | ---: |
| 10 cold refreshes × 25 transit quests: map API reads | 42,750 | 1,710 |
| Same workload: world-map child discovery calls | 500 | 10 |
| Same workload: allocated Lua heap | 8,293.8 KiB | 3,359.9 KiB |
| Same workload: median CPU | 13.35 ms | 10.13 ms |
| All coordinates missing: map API reads | 42,750 | 1,710 |
| All coordinates missing: quest-specific projection reads | 42,750 | 42,750 |
| All coordinates missing: allocated Lua heap | 8,000.7 KiB | 3,134.2 KiB |
| All coordinates missing: median CPU | 13.95 ms | 9.87 ms |
| Stationary quest events: route calculations / graph builds | 0 / 0 | 0 / 0 |
| Stationary quest events: median CPU | 25.63 ms | 13.32 ms |
| Settled stationary refresh: route calculations / graph builds | 0 / 0 | 0 / 0 |
| Moving refresh: route calculations / graph builds | 25 / 0 | 25 / 0 |
| Loot: scans / graph builds / allocated heap | 10 / 1 / 13,020 KiB | 10 / 1 / 13,020 KiB |
| Settled route allocation | 139.3 KiB | 139.3 KiB |
| Retained Lua heap after initialization | 35,712.1 KiB | 35,715.8 KiB |

The map-read reduction is 96%; cold allocation drops 59.5% for transit quests
and 60.8% when all coordinates are missing. CPU improvement in the cold and
quest-event workloads exceeds the measured three-run ranges. Moving and loot
timings overlap normal variation; no CPU improvement is claimed for them.
These numbers describe standalone Lua CPU/heap and mocked native API call counts,
not live WoW FPS, native memory, or client API execution cost.

## Reproduce

Run from the repository root with Lua 5.1 available. All scripts accept an addon
directory override, so a historical addon can be tested with the current harness.
The checked-out mock and benchmark harness must remain the same for both sides.

```bash
lua5.1 scripts/benchmark_quest_refresh.lua
lua5.1 scripts/benchmark_movement.lua
lua5.1 scripts/benchmark_memory.lua
lua5.1 scripts/benchmark_loot.lua
```

For the controlled three-module comparison:

```bash
baseline_dir=$(mktemp -d)
after_dir=$(mktemp -d)
git archive 46eecb8 QuickRoute | tar -x -C "$baseline_dir"
cp -a "$baseline_dir/QuickRoute" "$after_dir/QuickRoute"
cp QuickRoute/Modules/QuestTeleportButtons.lua \
   QuickRoute/Modules/WaypointIntegration.lua \
   QuickRoute/Modules/CooldownTracker.lua "$after_dir/QuickRoute/Modules/"
for repeat in 1 2 3; do
    for addon_dir in "$baseline_dir/QuickRoute/" "$after_dir/QuickRoute/"; do
        lua5.1 scripts/benchmark_quest_refresh.lua "$addon_dir"
        lua5.1 scripts/benchmark_movement.lua "$addon_dir"
        lua5.1 scripts/benchmark_memory.lua "$addon_dir"
        lua5.1 scripts/benchmark_loot.lua "$addon_dir"
    done
done
```

The later repair for a graph changed between queued callbacks adds no map API
reads and is covered by the same benchmark harness; its cold-call counts remain
identical. Absolute timings and minor heap totals vary by runtime and checkout.

## Freshness and bounded work

Map-wide answers and metadata are shared only inside one asynchronous quest
refresh. Each quest keeps its own visited-map set, so later quests still inspect
objectives on previously fetched maps. A new refresh starts fresh. Quest events
invalidate the context even when they arrive between queued callbacks.

One cold quest can still call `GetNextWaypointForMap` for every known zone. A
3–5 second negative backoff was considered and rejected: that quest-specific
API can be the only coordinate source that becomes available after
`QUEST_LOG_UPDATE`. Preserving a negative answer across the event would hide the
new destination; clearing it on each event provides no reduction. Objective
counters cannot prove a moving or phase-dependent destination unchanged.
`test_quest_scan_performance.lua` covers this projection-only case explicitly.

Cooldown deadlines use the existing one-second observer. Known personal
cooldowns remain unavailable through their final 1.5 seconds, including ones
first observed in that window. The modern ignoreGCD duration API supplies
personal-cooldown evidence; legacy fallback clears that evidence, preserving
the existing global-cooldown protection and batch memo behavior. Item cooldown
events, stationary expiry, and combat-exit availability changes update choices.

An independent integrated review found a further stale-button case: rebinding
between queued quest callbacks rebuilt the graph for later quests but left an
earlier button pointing at the old hearth destination. The refresh now replaces
its generation once when an already-used graph changes. The real-pathfinder
regression verifies both quests choose the cloak after the bind changes, with
exactly one replacement batch, three route calculations, and no repeated idle
repair. The normal initial dirty build does not restart the batch. Callbacks
hold no extra graph reference after pool release or cancellation.

## Verification

`test_questbutton_async.lua`, `test_quest_scan_performance.lua`, and
`test_spell_global_cooldown.lua` contain the new regression coverage. The focused
suite passed 741 assertions in both orders after the integrated repair. Existing
tests continue to cover protected writes in combat, asynchronous cancellation,
frame-pool bounds, cache retention, no icon flicker, and issue #72's memo/gap fix.

Final release gates use the full repository checks:

```bash
lua5.1 tests/run_tests.lua
QR_TEST_ORDER=reverse lua5.1 tests/run_tests.lua
./scripts/lint.sh
```
