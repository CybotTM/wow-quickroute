# Flight network review — 2026-09-11

PR #82 and issue #33 now have reproducible route-level evidence. The network
change improves 262 of 6,156 calculated routes without making a route slower or
unreachable. These are estimated route costs, not measured client flight times.

## Reachability model

The generator computes strongly connected components over the directed
`TaxiPath` graph, separately for Alliance and Horde, using flight masters only.
This prevents an opposing-faction intermediate master from connecting neutral
endpoints and prevents a one-way connection from inventing a return flight.
Component IDs use the smallest taxi node ID and are independent of CSV ordering.

The runtime selects the character faction's component. Older data without the
field retains the previous world-map fallback. A cross-world pair also needs
the same named addon continent for pricing; neutral subregions such as Mechagon
remain compatible within their own world map.

One-way-only reachability is conservatively omitted because this layer writes
paired flights. Internal and scripted taxi nodes do not connect player networks.

## Route comparison

The checked-in `scripts/benchmark_flight_routes.lua` calls the real
`CalculatePath`, declares an unmounted character without flight capability,
scans the simulated inventory, and supplies discovery for the exact modeled
flight-master positions through `GetTaxiNodesForMap`. Graph-build errors fail
the run. The original author's all-nil harness failure was not reproduced on
the baseline; its cause remains unestablished.

The matrix covers 19 source/destination maps, including all five relevant Khaz
Algar maps, representative faction capitals, legacy continents and islands.
Every ordered pair runs for both factions, three Dornogal-teleport states
(absent, ready, one-hour cooldown) and three discovery states (none, Khaz Algar,
all): 6,156 scenarios.

The baseline is immutable commit `46eecb8`. The comparison snapshot overlays
only flight-network code/data, preserving the same loading-cost behavior,
movement state and other route data on both sides. The separate loading-cost
correction is excluded from these numbers.

| Outcome | Scenarios |
| --- | ---: |
| Faster estimated route | 262 |
| Unchanged reachable route | 5,291 |
| Slower route | 0 |
| Newly reachable / lost route | 0 / 0 |
| Unreachable in both versions | 603 |

The largest reduction is **6.120011 seconds**. For example, a ready Dornogal
teleport followed by the newly available Dornogal → Ringing Deeps flight changes
the estimate from **88.001 to 81.880989 seconds**. Returned route edges actually
contain that flight. Regression tests verify the benefit for both factions and
verify that forgetting the destination flight point removes it.

The 603 unchanged unreachable scenarios remain visible:

- 324 target the Vale without a supplied phase. A controlled probe obtains a
  route when the known past-phase art ID `402` is supplied.
- 162 Alliance scenarios target legacy Horde-only Silvermoon, map `110`.
- 51 start in legacy Silvermoon as Alliance without a personal escape ability.
- 66 start in Mechagon without a discovered local taxi or personal escape
  ability. Supplying taxi discovery restores a route in a controlled probe.

## Reproduction and input provenance

Run the same benchmark script against two immutable checkout directories:

```sh
lua5.1 scripts/benchmark_flight_routes.lua /path/to/baseline-checkout > before.tsv
lua5.1 scripts/benchmark_flight_routes.lua /path/to/network-only-checkout > after.tsv
```

For the exact comparison recorded here, both snapshots, complete TSV output,
comparison script and input CSVs are retained in the local evidence directory
`/home/cybot/projects/qr-completion-evidence-20260911`. The snapshot names are
`flight-baseline` and `flight-model`; `compare-flight-routes.py` compares the
complete keyed results and asserts that both scenario sets match.

```sh
lua5.1 scripts/benchmark_flight_routes.lua /home/cybot/projects/qr-completion-evidence-20260911/flight-baseline > /home/cybot/projects/qr-completion-evidence-20260911/flight-before.tsv
lua5.1 scripts/benchmark_flight_routes.lua /home/cybot/projects/qr-completion-evidence-20260911/flight-model > /home/cybot/projects/qr-completion-evidence-20260911/flight-after.tsv
python3 /home/cybot/projects/qr-completion-evidence-20260911/compare-flight-routes.py
```

The existing local CSV cache is dated September 9. It is preserved under
`flight-inputs/`, with SHA256 hashes in `flight-input-sha256.txt`. It is **not**
claimed to be a new September 11 live export. Wago CSV access was unavailable
through the web tool in this session. The source tables are
[TaxiNodes](https://wago.tools/db2/TaxiNodes),
[TaxiPath](https://wago.tools/db2/TaxiPath),
[UiMap](https://wago.tools/db2/UiMap) and
[UiMapAssignment](https://wago.tools/db2/UiMapAssignment).

The baseline generator reproduces the baseline data byte-for-byte from this
cache. The updated generator also reproduces its committed candidate
byte-for-byte, so the comparison does not depend on changed CSV inputs.

```sh
python3 scripts/generate_flight_points.py --csv-dir /path/to/export --out /tmp/FlightPoints.lua
cmp QuickRoute/Data/FlightPoints.lua /tmp/FlightPoints.lua
python3 -m unittest discover -s tests -p test_generate_flight_points.py
lua5.1 tests/run_tests.lua
QR_TEST_ORDER=reverse lua5.1 tests/run_tests.lua
./scripts/lint.sh
```

The generator suite has 48 passing tests, including regression failures first
observed against the original PR for one-way and hostile-faction bridges,
directed cycles, CSV ordering and emitted faction identities. An independent
directed transitive-closure calculation agrees with the generated component
relation on **680,969 faction/master pairs**; its script and output are retained
as `flight-network-audit.py` and `flight-network-audit.txt` in the evidence folder.

## Limits of the timing model

Flight cost remains a heuristic horizontal coordinate distance divided by
30 yards per second, plus 20 seconds of boarding/landing overhead. Sourced
`TaxiNodes` positions do not establish actual flight splines, altitude changes,
detours, intermediate stops or shared coordinate origins across different world
maps. A shared addon continent is a pricing safeguard, not proof of those facts.
The benchmark demonstrates an observable change to estimated routing; it does
not establish real-world seconds saved or guaranteed fastest live travel.

## Loading-cost consistency

The independent loading fix makes `TravelTime` own the configured loading
duration as a replacement for the type default. Ordinary teleports, cooldown
refresh, dungeon teleports, map-button estimates, portal hubs and conditional
portals use that single cost. Explicit transition costs remain complete
durations. Loading-free floor changes and instant travel with a zero loading
setting retain the graph's existing positive `0.001` epsilon.

Regression tests cover the ordinary and dungeon graph edges, the shared
estimate, cooldown changes, zero and absent settings, conditional portals,
loading-free floor changes, complete explicit costs and retained connectivity
for zero-cost graph edges.
