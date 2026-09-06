# Movement performance, memory and quest-button continuity

The user supplied [r0s0j's CurseForge report](https://www.curseforge.com/wow/addons/quickroute/comments) of reduced FPS during movement or camera rotation, then reported high memory use and repeatedly flickering quest-tracker buttons. This investigation compares the immutable `v1.17.0` code with the corrections in this PR.

## Reproduction and CPU work

`scripts/benchmark_movement.lua` loads actual addon data and routing code with the existing WoW API mock. It tracks 25 quests, keeps the QuickRoute window closed and advances a 60-frame-per-second fixture. Its timer queue schedules callbacks on later simulated frames. Both versions use the same mock, positions and quest events.

| Ten-second workload | v1.17.0 CPU | Initial fix `a49f277` CPU | Route calculations |
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

The reference catalogue itself still accounts for about 22.5 MiB. Before the follow-up below, the travel graph/index accounted for about 11.75 MiB in this fixture. Repeated route batches with a stable graph stabilized after collection; the separate graph-retention issue above required replacing the graph and changing which quests filled the button pool. The phase optimization mainly reduces CPU time, with only about 4.8 KiB fewer temporary allocations per route. These Lua heap figures are not the WoW process's total RAM usage.

## Follow-up to the 168 MB client screenshot

The player reported 168 MB and 2% average CPU in the native addon tooltip after reloading the initial fix `a49f277`. A subsequent in-client measurement, confirmed by a screenshot and explicitly updating addon memory counters before and after one manual collection, returned **150.05 MiB before and 51.10 MiB after**. Approximately 99 MiB was therefore collectable in that sample. This supports transient allocation as the main contributor to the high reading; it does not prove that every live workflow is free of retention issues.

An independent rich-character fixture with 227 scanned teleports, expanded flight knowledge, UI refreshes and repeated graph rebuilds did not reproduce another retained-graph leak. A 20-stop tour reached approximately 176 MiB before collection and 76.5 MiB afterward; canceling returned it to approximately 70 MiB. This is additional synthetic evidence of temporary churn, not a measurement of the player's tour. No automatic garbage collection is added to the addon.

Allocation profiling identified redundant containers around single graph edges and full index rebuilds that connection code no longer reads. Single methods now use the existing direct-edge representation; parallel alternatives, tie rules, stateful filtering and previously returned route snapshots retain their behavior. Connections read current graph nodes without rebuilding the unused index.

| Standalone heap measurement | Initial fix `a49f277` | Follow-up |
| --- | ---: | ---: |
| Temporary allocation per stationary route | 267.7 KiB | 140.0 KiB |
| Temporary allocation per moving route | 491.3 KiB | 254.3 KiB |
| Temporary allocation per hypothetical-origin route | 6,928 KiB | 4,585 KiB |
| Retained graph/index in the fixture | 12,028 KiB | 7,489 KiB |

Ordinary `BAG_UPDATE` events also rebuilt the entire graph even when the rescan found identical teleport options. Comparing the scan snapshots now skips that invalidation for unchanged bag-only batches. Acquiring/removing a teleport, changes in source/usability and coalesced skill, spell, toy or equipment events still invalidate routes, with the existing combat deferral.

The real-code loot fixture performs ten inventory scans and ten routes. Graph rebuilds fell from ten to zero; temporary allocations fell from 176,523 KiB to 1,413 KiB. This sample pauses GC to count allocations and does not predict a native tooltip value. A separate structural-sharing experiment saved only about 758 KiB in catalogue requirements, so no generated data or generator changes were included.

## Flight-button follow-up (2026-09-07)

The player clarified that they have not noticed an FPS drop themselves; that symptom remains the separate third-party report. They still see occasional quest-button flicker, mostly while flying. Their latest screenshot confirms **210.13 MiB before collection and 44.37 MiB afterward** on `b0f9e928`, compared with the earlier 51.10 MiB after collection. These are different live samples, not a controlled comparison of peak memory. The current retained reading is lower, while temporary peaks remain possible.

The follow-up reproduces and addresses these distinct behaviors:

- A missing player position, unavailable quest coordinate or failed route query previously retired an existing button immediately. A known usable action's icon now remains in place for at most two seconds, with its secure action, housing attributes and equipment/click callbacks cleared immediately. Its tooltip says it is being recalculated. A one-second retry can recover while stationary and bypasses only that pending quest's negative coordinate cache. Repeated failures do not extend the deadline; known cooldown/ownership changes, confirmed direct routes, untracking and disabling still retire the button.
- Flight speed can cross a nearly equal direct/teleport comparison on adjacent samples. A synthetic 800-yard target with a 20-second teleport changes from teleport to direct travel when gliding speed changes from 39 to 40 yards/second. Direct travel still removes the teleport immediately. After that withdrawal during flight, the same teleport/source must win another fresh query at least one second later before reappearing. Initial and ground recommendations are immediate. Candidate confirmation bypasses cached routes, and cancelled calculations cannot repopulate the invalidated cache. This is a display confirmation policy; route costs and the shortest-path algorithm are unchanged.
- Real player origins now use the existing verified coordinate projection, as destinations already did. A parent-zone → microzone → parent-zone fixture no longer loses its route in the middle. Missing transforms preserve the original map/coordinates, missing positions never become guessed midpoints, and measured flight speed remains local to the verified current zone with indoor restrictions preserved.
- Native achievement and recipe blocks use independent numeric IDs. They could overwrite a quest block with the same number during tracker collection. Tagged quest modules now have priority, explicit nonquest tags are excluded, and supported untagged legacy/custom layouts remain compatible.
- The global cooldown of another ability made an otherwise ready teleport spell appear unavailable for 1.5 seconds. Spell queries now request `C_Spell.GetSpellCooldownDuration(spellID, true)` and read the documented duration-object accessors with public-value guards. Genuine short and overlapping personal cooldowns remain active; failed or unreadable duration queries fall back to public numeric metadata. Unreadable timing is never advertised as readiness. The observer keeps unknown/unavailable state distinct from ready without inventing an expiry timer. The boundary fixture confirms the defect, but does not establish which flight abilities triggered it in the player's session.

An independent stable-block probe produced zero hide/show/reparent operations over 100 positioning ticks and 20 zone refreshes. Ordinary synchronous tracker layout alone did not reproduce flicker, so no tracker-layout delay was introduced. The reproduced gaps and speed threshold explain possible triggers; the corrected behavior still needs confirmation during the player's actual flight.

The movement benchmark with the flight follow-up still performs 226 routes over ten simulated seconds (226 ms in this run), with no graph builds. The settled stationary phase performs zero routes. Ten ordinary loot batches retain all ten inventory scans, perform zero graph builds and allocate about 1,416 KiB. Timing varies by host/load; these checks establish that the flight corrections preserve the earlier workload reductions.

## Repeating the measurements

Run from the repository root with Lua 5.1:

```sh
lua5.1 scripts/benchmark_movement.lua
lua5.1 scripts/benchmark_memory.lua QuickRoute/ currency
lua5.1 scripts/benchmark_memory.lua QuickRoute/ quest
lua5.1 scripts/benchmark_memory.lua QuickRoute/ search
lua5.1 scripts/benchmark_loot.lua
```

To compare a previous version, extract its `QuickRoute/` directory into an isolated temporary directory and pass that directory, including its trailing slash, as the first argument. The memory script pauses GC during allocation samples and resumes it after collection. Neither benchmark reads the player's SavedVariables or runs inside the game.

The flight follow-up passes all **15,825 assertions in each Lua test order**, with zero lint warnings/errors across **117 files**. Independent checks cover pending icons, flight candidate changes/cancellation, pool bounds, combat, projected origins, tracker identity and GCD/unknown cooldown notifications. The prior allocation fix also passed the Python generator CI gate; no generator code changes are part of this follow-up. In-client confirmation remains necessary for the third-party FPS/camera report, the appearance of the quest tracker during actual flight, and the follow-up's reduction in allocation churn.
