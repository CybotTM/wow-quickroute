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


def load(csv_dir, name):
    path = os.path.join(csv_dir, name)
    if not os.path.exists(path):
        sys.exit(f"missing input: {path}")
    with open(path, encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def norm(text):
    return re.sub(r"[^a-z]", "", text.lower())


def related(a, b):
    """One name is an abbreviation or expansion of the other."""
    a, b = norm(a), norm(b)
    return bool(a) and bool(b) and (a.startswith(b) or b.startswith(a))


def build(csv_dir):
    nodes = load(csv_dir, "TaxiNodes.csv")
    paths = load(csv_dir, "TaxiPath.csv")
    uimaps = load(csv_dir, "UiMap.csv")
    assignments = load(csv_dir, "UiMapAssignment.csv")

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

        nx = (px - x0) / (x1 - x0) if x1 != x0 else 0.0
        ny = (py - y0) / (y1 - y0) if y1 != y0 else 0.0
        kept.append({
            "uid": uid,
            "zone": uimap[str(uid)]["Name_lang"].strip(),
            "x": a0 + nx * (a1 - a0),
            "y": b0 + ny * (b1 - b0),
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
    present = {entry["uid"] for entry in kept}
    corroborated = []
    for entry in kept:
        name = entry["name"]
        if "," not in name:
            # A bare name has to BE the zone. Without this the client's
            # comma-less internal rows walk straight through: "Dalaran" was
            # representing Broken Shore, 1332 yards from its real flight
            # master, and "Grand Rampart" was representing Nerub-ar Palace.
            if related(entry["zone"], name):
                corroborated.append(entry)
            else:
                tally["dropped: bare name is not the zone"] += 1
            continue
        place, stated = (part.strip() for part in name.rsplit(",", 1))
        stated = re.sub(r"\[.*?\]", "", stated).strip()
        if related(entry["zone"], stated):
            corroborated.append(entry)
            continue
        # The city-inside-a-zone case: "Ironforge, Dun Morogh" is in the
        # Ironforge zone, and the place part says so. Only accept it when the
        # stated zone is not itself represented -- otherwise "Trueshot Lodge,
        # Highmountain" would claim a zone that Highmountain already holds.
        stated_present = any(
            norm(uimap[str(u)]["Name_lang"].strip()) == norm(stated) for u in present
        )
        if related(entry["zone"], place) and not stated_present:
            corroborated.append(entry)
        else:
            tally["dropped: name contradicts geometry"] += 1

    # One entry per zone: the most connected node wins, lowest node ID breaks
    # ties so regeneration is stable.
    best_per_zone = {}
    for entry in corroborated:
        current = best_per_zone.get(entry["uid"])
        if current is None or (-entry["degree"], entry["id"]) < (-current["degree"], current["id"]):
            best_per_zone[entry["uid"]] = entry

    final = {
        uid: entry for uid, entry in best_per_zone.items()
        if 0.0 < entry["x"] < 1.0 and 0.0 < entry["y"] < 1.0
    }
    tally["dropped: coordinates outside the zone"] = len(best_per_zone) - len(final)

    for key in sorted(tally):
        print(f"{key:<38}: {tally[key]}", file=sys.stderr)
    print(f"{'zones with a flight master':<38}: {len(final)}", file=sys.stderr)
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
-- Four filters, because TaxiNodes holds far more than flight masters. A node
-- is kept only when it has at least two TaxiPath neighbours (a flight master
-- connects to many nodes; a scripted quest flight to one, and the boat and
-- zeppelin nodes to none), is not tagged internal or disabled, sits inside
-- some zone-type UiMap box, and has a name that corroborates that zone.
--
-- The rule is deliberately conservative: a node whose name cannot corroborate
-- the geometry is dropped, not guessed at. That costs real entries, and it is
-- the right trade -- a wrong entry makes the addon assert a flight master that
-- is not there and hand out a route nobody can fly.
--
-- One entry per zone: the most connected node wins, lowest node ID breaks ties.
-- The graph is zone-level, and from any flight master the game auto-routes
-- multi-hop to every point you have discovered on that world map.
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
