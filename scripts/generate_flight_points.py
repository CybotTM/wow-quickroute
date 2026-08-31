#!/usr/bin/env python3
"""Generate QuickRoute/Data/FlightPoints.lua from the client's DB2 tables.

The addon needs one thing per zone: does it have a flight master, and where is
it. TaxiNodes holds far more than flight masters -- scripted quest flights,
boat and zeppelin stops, internal hubs, filming rigs -- so most of this script
is deciding what to throw away.

Inputs (CSV exports, e.g. from wago.tools):
    TaxiNodes.csv  TaxiPath.csv  UiMap.csv  UiMapAssignment.csv

Usage:
    python3 scripts/generate_flight_points.py --csv-dir DIR \\
        [--out QuickRoute/Data/FlightPoints.lua]

Writes the Lua file and prints the filter tally to stderr, so a regeneration
that silently loses half the zones is visible rather than quiet.
"""

import argparse
import collections
import csv
import os
import re
import sys

ZONE_TYPE = "3"          # UiMap.Type 3 is a zone
MIN_NEIGHBOURS = 2       # a flight master connects to more than one node

# Rows the client keeps for its own purposes. The degree filter removes most of
# them, but the travel-network hubs are highly connected and would survive it:
# "[Hidden] 10.0 Travel Network - Destination Input" has ten neighbours and sits
# 2101 yards from the real Ohn'ahran Plains flight master.
INTERNAL_NAME = re.compile(r"\[(hidden|disabled|ph|temp|internal)\b", re.IGNORECASE)

# TaxiNodes.Flags. The low two bits are the factions the node is shown to, so a
# node with neither is shown to nobody. Bit 0x400 marks the client's own
# scripted and internal nodes: every row this generator was getting wrong
# carried it ("Grand Rampart" = 1027, the Exile's Reach troll bat = 1024) and
# no real flight master does -- Stormwind is 1, Orgrimmar 2, Maruukai 3.
FLAG_FACTIONS = 0x3
FLAG_INTERNAL = 0x400


MIN_ZONES = 100   # a healthy run yields ~134; far below that means bad input


def load(csv_dir, name, required_columns=()):
    path = os.path.join(csv_dir, name)
    if not os.path.exists(path):
        sys.exit(f"missing input: {path}")
    with open(path, encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        sys.exit(f"{name} has no data rows")
    missing = [c for c in required_columns if c not in rows[0]]
    if missing:
        sys.exit(f"{name} is missing column(s): {', '.join(missing)}")
    # A ragged row makes DictReader yield None keys, which every lookup below
    # would silently read as absent and blame on the wrong filter.
    ragged = sum(1 for row in rows if None in row or any(v is None for v in row.values()))
    if ragged:
        sys.exit(f"{name} has {ragged} row(s) with the wrong number of fields")
    return rows


def norm(text):
    return re.sub(r"[^a-z]", "", text.lower())


def related(a, b):
    """One name is an abbreviation or expansion of the other."""
    a, b = norm(a), norm(b)
    return bool(a) and bool(b) and (a.startswith(b) or b.startswith(a))


def project(px, py, x0, y0, x1, y1, a0, b0, a1, b1):
    """World position -> normalized zone coordinates.

    The UI axes are the transpose of the world axes, and both run backwards:
    the map's x comes from world Y and its y from world X, each decreasing as
    the world coordinate grows. This is not folklore -- UiMapAssignment states
    it. On uiMap 13 two rows share the world-Y span [-1400,-800] and carry an
    identical UiMin_0/UiMax_0 of [0.4657,0.4804] while differing in world X and
    in UiMin_1/UiMax_1, which is only possible if ui_0 is a function of world Y.
    The two rows are adjacent in X and meet at ui_1 = 0.6842 where X = -7400,
    with the larger X on the smaller ui_1, which is what fixes the direction.

    Getting this backwards put Stormwind's flight master at (0.2703, 0.2902),
    918 yards from where it stands.
    """
    ux = a0 + (y1 - py) / (y1 - y0) * (a1 - a0) if y1 != y0 else a0
    uy = b0 + (x1 - px) / (x1 - x0) * (b1 - b0) if x1 != x0 else b0
    return ux, uy


def build(csv_dir):
    nodes = load(csv_dir, "TaxiNodes.csv",
                 ("Name_lang", "Pos_0", "Pos_1", "ID", "ContinentID", "Flags"))
    paths = load(csv_dir, "TaxiPath.csv", ("FromTaxiNode", "ToTaxiNode"))
    uimaps = load(csv_dir, "UiMap.csv", ("Name_lang", "ID", "Type"))
    assignments = load(csv_dir, "UiMapAssignment.csv",
                       ("UiMapID", "MapID", "Region_0", "Region_1", "Region_3",
                        "Region_4", "UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))

    neighbours = collections.defaultdict(set)
    for row in paths:
        neighbours[row["FromTaxiNode"]].add(row["ToTaxiNode"])
        neighbours[row["ToTaxiNode"]].add(row["FromTaxiNode"])
    degree = {k: len(v - {k}) for k, v in neighbours.items()}

    uimap = {r["ID"]: r for r in uimaps}
    boxes = collections.defaultdict(list)
    for row in assignments:
        entry = uimap.get(row["UiMapID"])
        if not entry or entry["Type"] != ZONE_TYPE:
            continue
        try:
            x0, y0 = float(row["Region_0"]), float(row["Region_1"])
            x1, y1 = float(row["Region_3"]), float(row["Region_4"])
            a0, b0 = float(row["UiMin_0"]), float(row["UiMin_1"])
            a1, b1 = float(row["UiMax_0"]), float(row["UiMax_1"])
        except ValueError:
            continue
        box = (min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1))
        boxes[row["MapID"]].append((box, (x0, y0, x1, y1, a0, b0, a1, b1), int(row["UiMapID"])))

    tally = collections.Counter()
    kept = []
    for node in nodes:
        name = node["Name_lang"]
        if degree.get(node["ID"], 0) < MIN_NEIGHBOURS:
            tally["dropped: fewer than two neighbours"] += 1
            continue
        if INTERNAL_NAME.search(name):
            tally["dropped: internal or disabled node"] += 1
            continue
        try:
            flags = int(node["Flags"])
        except (KeyError, ValueError):
            flags = 0
        # The faction half drops nothing on the current tables -- every
        # faction-less survivor of the filters above already carries 0x400, so
        # removing it regenerates a byte-identical file. It is kept because
        # "shown to nobody" and "internal" are different claims and a future
        # table could separate them, and it is covered by a test of its own
        # rather than left as an untested assertion.
        if flags & FLAG_INTERNAL or not flags & FLAG_FACTIONS:
            tally["dropped: not shown to players"] += 1
            continue

        px, py = float(node["Pos_0"]), float(node["Pos_1"])
        best = None
        for box, projection, uid in boxes.get(node["ContinentID"], ()):
            if box[0] <= px <= box[1] and box[2] <= py <= box[3]:
                area = (box[1] - box[0]) * (box[3] - box[2])
                if best is None or area < best[0]:
                    best = (area, uid, projection)
        if best is None:
            tally["dropped: no zone box contains it"] += 1
            continue
        _, uid, (x0, y0, x1, y1, a0, b0, a1, b1) = best

        ux, uy = project(px, py, x0, y0, x1, y1, a0, b0, a1, b1)
        kept.append({
            "uid": uid,
            "zone": uimap[str(uid)]["Name_lang"].strip(),
            "x": ux,
            "y": uy,
            "wx": px, "wy": py,
            "continent": int(node["ContinentID"]),
            "name": name,
            "degree": degree.get(node["ID"], 0),
            "id": int(node["ID"]),
        })

    # Rule 3 needs to know which zones are represented at all, so it runs after
    # the geometric pass. A node named "Place, Zone" states where it is; the
    # geometry has to agree, because zone boxes overlap at borders and without
    # this "New Kargath, Badlands" lands in Searing Gorge 1103 yards away.
    corroborated = []
    for entry in kept:
        name = entry["name"]
        if "," not in name:
            # A bare name neither confirms nor contradicts the zone. Keep it --
            # "The Great Seal" is the Dazar'alor flight master and says nothing
            # about Dazar'alor -- but rank it below a name that does confirm,
            # so Broken Shore picks "Vengeance Point, Broken Shore" over the
            # bare "Dalaran" sitting 1332 yards away rather than by degree.
            entry["corroborated"] = related(entry["zone"], name)
            corroborated.append(entry)
            continue
        entry["corroborated"] = True
        place, stated = (part.strip() for part in name.rsplit(",", 1))
        stated = re.sub(r"\[.*?\]", "", stated).strip()
        if related(entry["zone"], stated):
            corroborated.append(entry)
            continue
        # The city-inside-a-zone case: "Ironforge, Dun Morogh" is in the
        # Ironforge zone, and the place part says so.
        #
        # There is deliberately no "unless the stated zone is also represented"
        # test here. One was tried and destroyed six capitals: an entry always
        # claims the zone the GEOMETRY put it in, never the zone its name
        # mentions, so "Orgrimmar, Durotar" claiming uid 85 takes nothing away
        # from Durotar. Worse, whether it fired depended on whether the client
        # abbreviated the suffix -- "Stormwind, Elwynn" survived because
        # "Elwynn" is not a zone name, "Orgrimmar, Durotar" did not.
        if related(entry["zone"], place):
            corroborated.append(entry)
        else:
            tally["dropped: name contradicts geometry"] += 1

    # One entry per zone: the most connected node wins, lowest node ID breaks
    # ties so regeneration is stable.
    best_per_zone = {}
    for entry in corroborated:
        current = best_per_zone.get(entry["uid"])
        def key(item):
            return (0 if item.get("corroborated") else 1, -item["degree"], item["id"])
        if current is None or key(entry) < key(current):
            best_per_zone[entry["uid"]] = entry

    final = {
        uid: entry for uid, entry in best_per_zone.items()
        if 0.0 < entry["x"] < 1.0 and 0.0 < entry["y"] < 1.0
    }
    tally["dropped: coordinates outside the zone"] = len(best_per_zone) - len(final)

    for key in sorted(tally):
        print(f"{key:<38}: {tally[key]}", file=sys.stderr)
    print(f"{'zones with a flight master':<38}: {len(final)}", file=sys.stderr)
    # Exit status is what a script or CI reads, and a truncated TaxiPath.csv
    # makes every degree 0 -- which produced an empty data file and exit 0.
    if len(final) < MIN_ZONES:
        sys.exit(f"only {len(final)} zones resolved, expected at least {MIN_ZONES}; "
                 "the inputs look truncated -- nothing was written")
    return final


HEADER = '''-- FlightPoints.lua
-- Zones with a flight master, and the position of one of their flight points
-- in both zone and world coordinates.
--
-- GENERATED by scripts/generate_flight_points.py -- do not edit by hand.
--
-- Derived from the client's own tables, not surveyed. TaxiNodes gives every
-- taxi node with a world position and the world map it sits on, TaxiPath gives
-- the network between them, and UiMapAssignment converts a world position into
-- a zone with normalized coordinates.
--
-- Five filters, because TaxiNodes holds far more than flight masters. A node
-- is kept only when it has at least two TaxiPath neighbours (a flight master
-- connects to many nodes; a scripted quest flight to one, and the boat and
-- zeppelin nodes to none), is not tagged internal or disabled, is shown to
-- players by its Flags, sits inside some zone-type UiMap box, and -- if its
-- name states a zone at all -- states the zone the geometry put it in.
--
-- A name of the form "Place, Zone" has to agree with the geometry: zone boxes
-- overlap at borders, and without that test "New Kargath, Badlands" lands in
-- Searing Gorge 1103 yards away. A name with no comma states no zone, so it
-- neither confirms nor contradicts: those are kept, but rank below a name that
-- does confirm. That is what makes Broken Shore pick "Vengeance Point, Broken
-- Shore" over the bare "Dalaran" sitting 1332 yards from it.
--
-- One entry per zone: a corroborating name first, then the most connected
-- node, then the lowest node ID so regeneration is stable. The graph is
-- zone-level, and from any flight master the game auto-routes multi-hop to
-- every point you have discovered on that world map.
--
-- x and y are normalized ZONE coordinates, and the UI axes are the transpose
-- of the world axes with both running backwards -- see project() in the
-- generator for the evidence. Getting that backwards put Stormwind's flight
-- master 918 yards from where it stands, and the "inside the unit square"
-- check could not see it, because a swapped and mirrored unit square is still
-- the unit square.
--
-- worldX/worldY are what edge weights are computed from: the distance is
-- exact, and only the speed it is divided by is an estimate. continentID is
-- the world map from TaxiNodes, NOT a uiMapID. It is necessary for two zones
-- to be connected by flight but not sufficient -- world map 530 holds Outland
-- AND the Burning Crusade starting zones, which are not one taxi network, so
-- PathCalculator requires the addon's own continent to agree as well.
local ADDON_NAME, QR = ...

QR.FlightPoints = {'''


def emit(final, out_path):
    lines = [HEADER]
    current = None
    for uid, entry in sorted(final.items(), key=lambda kv: (kv[1]["continent"], kv[0])):
        if entry["continent"] != current:
            current = entry["continent"]
            lines.append(f"    -- world map {current}")
        node = entry["name"].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(
            f'    [{uid}] = {{ x = {entry["x"]:.4f}, y = {entry["y"]:.4f}, '
            f'worldX = {entry["wx"]:.1f}, worldY = {entry["wy"]:.1f}, '
            f'continentID = {current}, node = "{node}" }},'
        )
    lines.append("}")
    lines.append("")
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {out_path} with {len(final)} entries", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv-dir", required=True,
                        help="directory holding TaxiNodes.csv, TaxiPath.csv, "
                             "UiMap.csv and UiMapAssignment.csv")
    parser.add_argument("--out", default="QuickRoute/Data/FlightPoints.lua",
                        help="path to write (default: %(default)s)")
    args = parser.parse_args()
    emit(build(args.csv_dir), args.out)


if __name__ == "__main__":
    main()
