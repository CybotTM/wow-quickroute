# Movement performance, memory and quest-button continuity

The user supplied [r0s0j's CurseForge report](https://www.curseforge.com/wow/addons/quickroute/comments) of reduced FPS during movement or camera rotation, then reported high memory use and repeatedly flickering quest-tracker buttons. This investigation compares the immutable `v1.17.0` code with the corrections in this PR.

## Reproduction and CPU work

`scripts/benchmark_movement.lua` loads actual addon data and routing code with the existing WoW API mock. It tracks 25 quests, keeps the QuickRoute window closed and advances a 60-frame-per-second fixture. Its timer queue schedules callbacks on later simulated frames. Both versions use the same mock, positions and quest events.

| Ten-second workload | v1.17.0 CPU | Corrected CPU | Route calculations |
| --- | ---: | ---: | ---: |
| Moving, QR closed | 1,692 ms | 371 ms | 226 in both |
| Stationary, one quest-log event/second | 1,718 ms | 276 ms | 249 in both |
| Stationary after the initial batch | 0.20 ms | 0.23 ms | 0 in both |

These are standalone Lua CPU measurements, not measured game FPS. Native API cost, rendering, other addons and real client GC interactions are not represented. Timing varies by host/load. No camera-specific listener or independent camera-only reproduction was found.

The dominant repeated work was collecting phase metadata from all 506 graph nodes and 15,350 edges for each quest route. The existing optimistic shortest path now checks only its own complete phase dependencies first. When that path is rejected, the existing stateful fallback still receives all graph phase dependencies and live access checks. No destination data or transport alternatives are removed. Independent comparison over 3,000 generated phase graphs, including 133 reachable cases, found matching reachability and route costs.

An unresolved intermediate quest also scanned the same maps twice in one synchronous lookup. Reusing map results within that lookup reduced `GetQuestsOnMap` calls for 25 such quests from 8,525 to 4,275. No result is shared across separate lookups by this optimization.

## Button continuity

Each movement refresh previously released the entire secure-button pool before calculating replacement routes over subsequent frames. The replacement reuses buttons belonging to still-tracked quests, releases obsolete choices individually, and preserves the eight-button limit when a new higher-priority quest arrives. Generation cancellation and combat guards remain active. An unavailable icon for a changed action uses a neutral placeholder instead of the previous teleport's icon.

Regression tests observe visibility, anchors, button identity, secure actions and pool bounds across partial refreshes, reordering and changed route results. Earlier batching tests checked one route per callback but did not cover the visible gap caused by releasing unchanged buttons.

## Memory

Fresh Lua 5.1 processes with the same generated catalogue produced these incremental retained-heap measurements after collection:

| First catalogue operation | v1.17.0 | Corrected |
| --- | ---: | ---: |
| Currency lookup | 8,410 KiB | 32 KiB |
| Quest lookup | 8,410 KiB | 3,093 KiB |
| Broad search, including query cache | 8,987 KiB | 5,044 KiB |
| Explicit full initialization | 8,410 KiB | 8,410 KiB |

Indexes are now built for the operation requesting them. Later operations can add the remaining indexes; these savings do not mean a fully used catalogue stays at the currency-only size. Source replacement resets all partitions, and explicit full initialization keeps its prior behavior.

The coordinate cache previously retained every distinct requested quest ID until a quest event cleared it; TTL only controlled reuse. It now has a 256-entry FIFO limit for both found and unavailable targets, preserving the 30-second TTL and explicit retry behavior. A synthetic 10,000-request quiet-session probe retained approximately 105 KiB instead of 1,720 KiB and stopped growing after reaching the limit. Unwatched quest-button cache entries are also removed.

An additional reproduction found obsolete graphs retained by quest-button cache entries below the eight-button cutoff: those quests were still watched, but their expired entries were never queried again. The correction prunes expired and obsolete-graph entries during refresh and the lightweight idle probe, and clears graph references when disabling the feature. Weak-reference regression tests verify that replaced graphs can be collected without calculating more routes.

The reference catalogue itself still accounts for about 22.5 MiB, and the current travel graph/index about 11.75 MiB in this fixture. Repeated route batches with a stable graph stabilized after collection; the separate graph-retention issue above required replacing the graph and changing which quests filled the button pool. The phase optimization mainly reduces CPU time, with only about 4.8 KiB fewer temporary allocations per route. These Lua heap figures are not the WoW process's total RAM usage.

## Repeating the measurements

Run from the repository root with Lua 5.1:

```sh
lua5.1 scripts/benchmark_movement.lua
lua5.1 scripts/benchmark_memory.lua QuickRoute/ currency
lua5.1 scripts/benchmark_memory.lua QuickRoute/ quest
lua5.1 scripts/benchmark_memory.lua QuickRoute/ search
```

To compare a previous version, extract its `QuickRoute/` directory into an isolated temporary directory and pass that directory, including its trailing slash, as the first argument. The memory script pauses GC during allocation samples and resumes it after collection. Neither benchmark reads the player's SavedVariables or runs inside the game.

The final suite passed all 15,658 assertions in both Lua test orders, lint reported zero warnings/errors in 112 files, and all 47 Python tests passed. In-client confirmation remains necessary for the reported FPS/camera symptom and the appearance of the quest tracker during actual play.
