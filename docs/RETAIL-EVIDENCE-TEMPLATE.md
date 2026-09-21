# Retail evidence: how a run is recorded

`RETAIL-ACCEPTANCE.md` lists what to check. This file says what a result has to
contain before it counts, and in what order a comparison against another routing
addon is judged.

Publishing a checklist is not evidence that it was run. A recorded run without
the state it ran under is not evidence either: a route that works on an
all-unlocked main says nothing about the character who installed the addon
yesterday.

## One record per run

Copy this block, fill every field, and keep it with the tested commit.

```
QuickRoute commit:      <sha>            (the exact ZIP or commit installed)
Client build:           <build>          (from wago.tools/api/builds, not the wiki)
Locale:                 <enUS|deDE|...>
Character:              <faction> <class> <level>
Access state:           <flying unlocks, expansion unlocks, professions,
                         reusable class travel, hearth bindings, cooldowns held>
Loading-screen profile: <SSD/HDD, measured seconds for one portal>
Scenario:               <number from RETAIL-ACCEPTANCE.md, or a description>
Origin:                 map <id> (<x>, <y>)
Destination:            map <id> (<x>, <y>), role <objective|reference|...>
Expected path:          <the constraint that matters, e.g. "must use the
                         Silvermoon shared district, not the enclave">
Observed:               <what happened, in one or two sentences>
Every step usable:      <yes|no, and which step was not>
Arrived where intended: <yes|no>
Wall clock:             <seconds, door to door>
Frame time:             <median and worst frame during calculation, measured
                         with a frame-time addon; QuickRoute does not report it>
Result:                 <pass|fail|blocked>
```

`Blocked` is a real result. A scenario that could not be run because the
character lacks an unlock is recorded as blocked, with what is missing, not left
out of the list.

## The order a comparison is judged in

A lower estimate is not a faster journey, and an invalid two-minute route is
worse than a valid three-minute one. Judge in this order and stop at the first
failure.

1. **Feasibility.** Can this character execute every step? A route through a
   portal they have not unlocked fails here, whatever its estimate says.
2. **Destination correctness.** Does the last coordinate reach the intended
   entrance, objective or service, on the right floor? Being near it is not
   reaching it.
3. **Recovery.** Refuse a step with "Cannot use". Does the route come back with
   an alternative to the same destination, or an explanation of why there is
   none?
4. **Efficiency.** Only now compare wall clock and how many interactions the
   journey cost.
5. **Responsiveness.** Median and worst frame time during calculation, and
   whether a superseded calculation ever replaced a newer route.

When comparing against another routing addon, hold origin, destination, faction,
class, level, unlocks, phase assumptions, cooldown state and loading-screen
profile identical across both. A run where the two addons had different
characters measures the characters.

Record an unreachable or unknown case as its own outcome. Counting it as a route
of infinite cost turns a coverage gap into an efficiency number.

## Negative scenarios are first-class

These belong in the run list, not in a section of things that would be nice to
try.

- A portal that is missing from the client at the coordinate the catalogue holds.
- A remote phase the client cannot report.
- A player position that is unavailable, during and just after a loading screen.
- An objective that moves within the same zone while the route is displayed.
- Two items that share one cooldown, both offered in a multi-stop trip.
- The player replacing QuickRoute's pin with their own.
- A rare alert firing while a manually chosen trip is locked.
- Combat, a battleground entry and a death during an active route.
- Cancelling a large vendor comparison midway.

## What the numbers are for

The measurements worth keeping are completed journeys, suggestions that turned
out to contain an unusable step, failures that produced an actionable
explanation, recoveries that found an alternative, and frame-time tails.

Assertion counts and catalogue size support engineering work. They do not
establish any of the five.
