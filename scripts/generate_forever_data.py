#!/usr/bin/env python3
"""Generate QuickRoute/Data/Forever/*.lua, the data set QuickRoute_Camelot.toc loads.

WoW Forever runs on the modern client with Vanilla-era content: two continents,
the Classic UiMap IDs (Stormwind 1453, not 84) and a handful of new zones. The
addon's code is the same; only the data differs. Each file written here defines
the same QR tables, in the same shape, as its retail counterpart, so no consumer
has to know which client it is on.

Two kinds of source, and the files say which one each record comes from:

  authoritative  Forever's own DB2 tables: flight masters (TaxiNodes, TaxiPath),
                 boats and zeppelins (TaxiPath, TaxiPathNode), continents and
                 zone lists (UiMap, UiMapAssignment), and which spells, items
                 and inn areas exist at all (SpellName, ItemSparse, AreaTable).
  derived        Adjacency for zones the conversion left with no edge, from
                 touching UiMapAssignment rectangles; marked as such.
  surveyed       Crossings the zone survey saw on the Forever client, from
                 scripts/data/forever_zone_survey.json (written by
                 scripts/import_zone_survey.py): walks become adjacency,
                 loading-screen endpoints refine converted transports.
  converted      Retail coordinates carried over through world space: retail
                 uiMap + (x, y) -> world position via retail UiMapAssignment ->
                 the Forever zone whose UiMapAssignment box contains it. Both
                 clients share the world maps 0 and 1, so the position is the same
                 place; the terrain is not always the same (Cataclysm reshaped
                 Darkshore, Thousand Needles, the Barrens and Azshara). A
                 converted point is a starting estimate and is marked ESTIMATED
                 wherever the schema has a provenance field. A point that lands
                 in no Forever zone is dropped.

Inputs:
  --forever-csv-dir  TaxiNodes TaxiPath TaxiPathNode UiMap UiMapAssignment
                     SpellName ItemSparse AreaTable Map  (wago.tools, build
                     1.60.1.70862)
  --retail-csv-dir   UiMap UiMapAssignment JournalInstance  (wago.tools, build
                     12.1.0.69587, the build the retail data files were
                     checked against)
  The retail Lua data is read by running scripts/export_data_json.lua against
  QuickRoute/QuickRoute.toc, not by parsing Lua here.

Usage:
    python3 scripts/generate_forever_data.py \\
        --forever-csv-dir DIR --retail-csv-dir DIR \\
        [--lua ~/.local/bin/lua5.1] [--out-dir QuickRoute/Data/Forever]

Prints kept/dropped counts per file to stderr.
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_flight_points as fp  # noqa: E402

FOREVER_BUILD = "1.60.1.70862"
RETAIL_BUILD = "12.1.0.69587"
CONTINENT_TYPE = "2"
ESTIMATED = "estimated"   # QR.Provenance.ESTIMATED
EPSILON = 1e-6
MIN_ZONE_OVERLAP = 0.5  # share of a retail zone a Forever zone must cover to be it

# Services that did not exist before Cataclysm (void storage) or Dragonflight
# (crafting tables). The retail points sit inside Stormwind and Orgrimmar and
# would convert cleanly into buildings that have no such NPC on Forever.
SERVICES_NOT_ON_FOREVER = {"VOID_STORAGE", "CRAFTING_TABLE"}

# Zone adjacency derived from map bounds, for zones the retail conversion left
# with no edge at all. Rectangles that touch or overlap on the same world map
# are candidate neighbours: a guess from geometry, not an observed crossing.
# The time is the one most retail adjacency entries carry.
DERIVED_ADJACENCY_TIME = 60
DERIVED_ADJACENCY_SOURCE = "map_bounds"

# Transports come from Forever's own TaxiPath / TaxiPathNode: a ship or
# zeppelin path is a TaxiPath whose nodes stop (Delay > 0) in two or more
# zones. A stop is placed in the zone of the nearest flight master when that
# zone's box contains it (or that flight master's name states one that does),
# otherwise in the smallest containing box.
STOP_ANCHOR_YARDS = 1500

# Zone-survey observations (scripts/import_zone_survey.py). A walk is applied
# when the pair was crossed without a loading screen at least this often, both
# directions together: one crossing can be a taxi flight passing over the
# border, which the survey records the same way (see commit 800438b).
OBSERVATIONS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "data", "forever_zone_survey.json")
MIN_OBSERVED_WALKS = 2
SURVEYED = "surveyed"            # QR.Provenance.SURVEYED
# How far an observed loading-screen endpoint may lie from the converted end of
# a transport and still be taken for it. The survey buckets endpoints to 1/200
# of a map (8.7 yd on Stormwind City, the larger of the tram's two maps), samples
# every 0.5 s (about 7 yd on a ground mount) and the conversion is good to 0.42
# yd: under 20 yd together. The nearest other landing on those maps is the mage
# teleport, 408 yd from the tram's Ironforge end and 949 yd from its Stormwind
# end, so 50 yd keeps the tram and rejects a teleport with room to spare.
MAX_LANDING_SHIFT_YARDS = 50
SURVEY_SOURCE = "zone_survey"
ZEPPELIN_MIN_HEIGHT = 20     # median path height; ships run at sea level (0)
DEFAULT_TRANSPORT_TIME = {"boat": 180, "zeppelin": 120}

# Continent keys for the world maps Forever's zones sit on. The keys match the
# retail ones where the continent is the same, because code and tests use them.
CONTINENT_KEY_BY_MAP = {"0": "EASTERN_KINGDOMS", "1": "KALIMDOR"}


def lua_json_key(key):
    kind, _, text = key.partition(":")
    if kind == "n":
        number = float(text)
        return int(number) if number.is_integer() else number
    if kind == "s":
        return text
    raise ValueError(f"unexpected key {key!r}")


def decode_export(text):
    """JSON from export_data_json.lua -> Python, with Lua key types restored."""
    return json.loads(text, object_pairs_hook=lambda pairs: {lua_json_key(k): v for k, v in pairs})


def export_retail(lua, toc):
    result = subprocess.run([lua, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                               "export_data_json.lua"), toc],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"exporting the retail data failed: {result.stderr.strip()}")
    return decode_export(result.stdout)


def is_array(table):
    return isinstance(table, dict) and all(isinstance(k, int) for k in table) \
        and sorted(table) == list(range(1, len(table) + 1))


def as_list(table):
    """A Lua array exported as {1: a, 2: b} -> [a, b]. Empty tables are lists."""
    if isinstance(table, list):
        return table
    if not table:
        return []
    if not is_array(table):
        raise ValueError("expected a Lua array")
    return [table[i] for i in range(1, len(table) + 1)]


def unproject(ux, uy, x0, y0, x1, y1, a0, b0, a1, b1):
    """Normalized zone coordinates -> world position. Inverse of fp.project()."""
    py = y1 - (ux - a0) / (a1 - a0) * (y1 - y0) if a1 != a0 else y1
    px = x1 - (uy - b0) / (b1 - b0) * (x1 - x0) if b1 != b0 else x1
    return px, py


def assignment_geometry(row):
    x0, y0 = float(row["Region_0"]), float(row["Region_1"])
    x1, y1 = float(row["Region_3"]), float(row["Region_4"])
    a0, b0 = float(row["UiMin_0"]), float(row["UiMin_1"])
    a1, b1 = float(row["UiMax_0"]), float(row["UiMax_1"])
    return (x0, y0, x1, y1, a0, b0, a1, b1)


class Geometry:
    """Retail zone coordinates -> Forever zone coordinates, through world space."""

    def __init__(self, retail_uimaps, retail_assignments, forever_uimaps, forever_assignments):
        self.retail_uimap = {r["ID"]: r for r in retail_uimaps}
        self.forever_uimap = {r["ID"]: r for r in forever_uimaps}

        # The world maps both clients share: the maps Forever's continents are
        # drawn on. Retail points on any other map cannot exist on Forever.
        self.continent_of_map = {}
        for row in forever_assignments:
            entry = self.forever_uimap.get(row["UiMapID"])
            if entry and entry["Type"] == CONTINENT_TYPE and entry["System"] == fp.RETAIL_MAP_SYSTEM:
                self.continent_of_map[row["MapID"]] = int(row["UiMapID"])
        self.shared_maps = set(self.continent_of_map)

        self.retail_rows = collections.defaultdict(list)
        for row in retail_assignments:
            if row["MapID"] not in self.shared_maps:
                continue
            geo = assignment_geometry(row)
            ui_area = abs((geo[6] - geo[4]) * (geo[7] - geo[5]))
            # Rows for a WMO group or doodad are interiors; prefer the plain
            # zone row, then the most specific UI rectangle.
            interior = row["WMOGroupID"] != "0" or row["WMODoodadPlacementID"] != "0"
            self.retail_rows[int(row["UiMapID"])].append(
                ((interior, ui_area), row["MapID"], geo, row["AreaID"]))

        self._zone_cache = {}
        self.forever_zones = {}
        self.forever_boxes = collections.defaultdict(list)
        for row in forever_assignments:
            entry = self.forever_uimap.get(row["UiMapID"])
            if not entry or entry["Type"] != fp.ZONE_TYPE or entry["System"] != fp.RETAIL_MAP_SYSTEM:
                continue
            geo = assignment_geometry(row)
            box = (min(geo[0], geo[2]), max(geo[0], geo[2]), min(geo[1], geo[3]), max(geo[1], geo[3]))
            uid = int(row["UiMapID"])
            self.forever_zones[uid] = {"name": entry["Name_lang"].strip(), "map": row["MapID"],
                                       "area": row["AreaID"]}
            self.forever_boxes[row["MapID"]].append((box, geo, uid, row["AreaID"]))

    def retail_name(self, uid):
        entry = self.retail_uimap.get(str(uid))
        return entry["Name_lang"].strip() if entry else ""

    def retail_area(self, uid):
        rows = sorted(self.retail_rows.get(uid, ()), key=lambda r: r[0])
        return rows[0][3] if rows else None

    def to_world(self, uid, x, y):
        """Retail uiMap + normalized (x, y) -> (world map, wx, wy), or None."""
        for _, map_id, geo, _ in sorted(self.retail_rows.get(uid, ()), key=lambda r: r[0]):
            _, _, _, _, a0, b0, a1, b1 = geo
            if min(a0, a1) - EPSILON <= x <= max(a0, a1) + EPSILON \
                    and min(b0, b1) - EPSILON <= y <= max(b0, b1) + EPSILON:
                wx, wy = unproject(x, y, *geo)
                return map_id, wx, wy
        return None

    def to_forever(self, map_id, wx, wy, prefer=None):
        """World position -> (Forever uiMap, x, y), or None.

        Zone boxes are rectangles and overlap at borders, so a position is in
        several. Take the zone the retail zone maps to (prefer) when its box
        contains the position, otherwise the smallest containing box: a point
        in retail Orgrimmar outside Classic Orgrimmar's smaller map is in
        Durotar.
        """
        candidates = []
        for box, geo, uid, _ in self.forever_boxes.get(map_id, ()):
            if box[0] <= wx <= box[1] and box[2] <= wy <= box[3]:
                rank = (0 if uid == prefer else 1, (box[1] - box[0]) * (box[3] - box[2]), uid)
                candidates.append((rank, uid, geo))
        if not candidates:
            return None
        _, uid, geo = min(candidates)
        ux, uy = fp.project(wx, wy, *geo)
        return uid, ux, uy

    def convert(self, uid, x, y):
        """Retail uiMap + (x, y) -> (Forever uiMap, x, y), or None.

        None when the retail zone is not on Forever at all (zone() below) or
        the position is in no Forever zone. The first test is what keeps a
        point in Twilight Highlands from landing in whichever Forever zone's
        rectangle happens to reach over it.
        """
        preferred = self.zone(uid)
        if preferred is None:
            return None
        world = self.to_world(uid, x, y)
        if world is None:
            return None
        result = self.to_forever(world[0], world[1], world[2], prefer=preferred)
        if result is None:
            return None
        fuid, fx, fy = result
        return fuid, round(fx, 4), round(fy, 4)

    def zone(self, uid):
        """Retail zone -> the Forever zone it is, or None when it is not on Forever.

        Same AreaID first (Northern Barrens is area 17, The Barrens), then the
        same name, then the Forever zone whose box covers at least half of the
        retail zone's box (Southern Barrens, area 4709, is mostly The Barrens).
        Below half, the retail zone is taken as not existing on Forever.
        """
        if uid in self._zone_cache:
            return self._zone_cache[uid]
        result = None
        area = self.retail_area(uid)
        name = self.retail_name(uid)
        for fuid, info in sorted(self.forever_zones.items()):
            if area not in (None, "0") and info["area"] == area:
                result = fuid
                break
        if result is None:
            for fuid, info in sorted(self.forever_zones.items()):
                if name and fp.norm(info["name"]) == fp.norm(name):
                    result = fuid
                    break
        rows = sorted(self.retail_rows.get(uid, ()), key=lambda r: r[0])
        if result is None and rows:
            map_id, geo = rows[0][1], rows[0][2]
            rx0, rx1 = sorted((geo[0], geo[2]))
            ry0, ry1 = sorted((geo[1], geo[3]))
            size = (rx1 - rx0) * (ry1 - ry0)
            best, best_overlap = None, 0.0
            for box, _, fuid, _ in self.forever_boxes.get(map_id, ()):
                overlap = max(0.0, min(rx1, box[1]) - max(rx0, box[0])) \
                    * max(0.0, min(ry1, box[3]) - max(ry0, box[2]))
                if overlap > best_overlap:
                    best, best_overlap = fuid, overlap
            if size > 0 and best_overlap >= MIN_ZONE_OVERLAP * size:
                result = best
        self._zone_cache[uid] = result
        return result


class Tally:
    def __init__(self):
        self.counts = collections.OrderedDict()

    def add(self, what, outcome, amount=1):
        self.counts.setdefault(what, collections.Counter())[outcome] += amount

    def report(self):
        for what, counter in self.counts.items():
            parts = ", ".join(f"{k} {v}" for k, v in sorted(counter.items()))
            print(f"{what:<34}: {parts}", file=sys.stderr)


def converted_point(geo, tally, what, entry, map_key="mapID"):
    """Copy of entry with mapID/x/y converted, or None when it lands nowhere."""
    uid = entry.get(map_key)
    if uid is None:
        return dict(entry)
    if "x" in entry and "y" in entry:
        result = geo.convert(uid, entry["x"], entry["y"])
    else:
        fuid = geo.zone(uid)
        result = (fuid, None, None) if fuid else None
    if result is None:
        tally.add(what, "dropped: lands in no Forever zone")
        return None
    out = dict(entry)
    out[map_key] = result[0]
    if result[1] is not None:
        out["x"], out["y"] = result[1], result[2]
    return out


# ---------------------------------------------------------------------------
# Builders, one per output file
# ---------------------------------------------------------------------------

def build_zones(geo, retail, tally):
    continents = {}
    zone_to_continent = {}
    by_map = collections.defaultdict(list)
    for fuid, info in geo.forever_zones.items():
        by_map[info["map"]].append(fuid)

    retail_continents = retail["Continents"]
    for map_id, zones in sorted(by_map.items(), key=lambda kv: int(kv[0])):
        key = CONTINENT_KEY_BY_MAP.get(map_id)
        continent_uid = geo.continent_of_map.get(map_id)
        if key is None:
            # A world map of its own with no continent UiMap (Zephras Isle,
            # map 2991): its own key, named after its only zone.
            names = sorted({geo.forever_zones[z]["name"] for z in zones})
            key = re.sub(r"[^A-Z]+", "_", names[0].upper()).strip("_")
            name = names[0]
        else:
            name = geo.forever_uimap[str(continent_uid)]["Name_lang"].strip()
        entry = {"name": name, "zones": sorted(zones)}
        if continent_uid:
            entry["continentMapID"] = int(continent_uid)
        source = retail_continents.get(key, {})
        for field in ("hub", "hubHorde", "hubAlliance"):
            if field in source:
                fuid = geo.zone(source[field])
                if fuid and geo.forever_zones[fuid]["map"] == map_id:
                    entry[field] = fuid
                    tally.add("continent hubs", "kept")
                else:
                    tally.add("continent hubs", f"dropped: {field} {source[field]} not on Forever")
        continents[key] = entry
        for z in zones:
            zone_to_continent[z] = key
        if continent_uid:
            zone_to_continent[int(continent_uid)] = key
    name_map_ids = {k: v["continentMapID"] for k, v in continents.items() if "continentMapID" in v}

    # Zone adjacency: retail zones mapped onto Forever zones. Several retail
    # zones can fold into one (Northern and Southern Barrens are The Barrens);
    # the edge between them disappears, duplicates keep the shorter time.
    adjacency = collections.defaultdict(dict)
    zone_map = {}
    for retail_uid, edges in retail["ZoneAdjacencies"].items():
        source = zone_map.setdefault(retail_uid, geo.zone(retail_uid))
        for edge in as_list(edges):
            target = zone_map.setdefault(edge["zone"], geo.zone(edge["zone"]))
            if source is None or target is None:
                tally.add("zone adjacency edges", "dropped: a side is not on Forever")
                continue
            if source == target:
                tally.add("zone adjacency edges", "dropped: both sides fold into one zone")
                continue
            if geo.forever_zones[source]["map"] != geo.forever_zones[target]["map"]:
                tally.add("zone adjacency edges", "dropped: crosses world maps")
                continue
            previous = adjacency[source].get(target)
            if previous is None:
                tally.add("zone adjacency edges", "kept")
            else:
                tally.add("zone adjacency edges", "merged into an existing edge")
            adjacency[source][target] = min(previous or edge["travelTime"], edge["travelTime"])
    derived = derive_bounds_adjacency(geo, adjacency, tally)
    adjacencies = {}
    for source, targets in sorted(adjacency.items()):
        edges = []
        for target, time in sorted(targets.items()):
            edge = {"zone": target, "travelTime": time}
            if (source, target) in derived:
                edge["provenance"] = ESTIMATED
                edge["source"] = DERIVED_ADJACENCY_SOURCE
            edges.append(edge)
        adjacencies[source] = edges

    cross = {}
    for a, row in retail["CrossContinentTravel"].items():
        if a in continents:
            kept = {b: t for b, t in row.items() if b in continents}
            if kept:
                cross[a] = kept
    tally.add("continents", "kept", len(continents))
    return {
        "Continents": continents,
        "ZoneToContinent": zone_to_continent,
        "ContinentNameMapIDs": name_map_ids,
        "ZoneAdjacencies": adjacencies,
        "CrossContinentTravel": cross,
    }, zone_map


def load_observations(path):
    if not path or not os.path.exists(path):
        return {"crossings": []}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def apply_observed_walks(tables, observations, tally):
    """Walks the zone survey saw on foot become surveyed adjacency, both directions.

    Only `walked`, which the importer fills from the survey's taxi-checked
    `afoot` count; walks from builds without the taxi check (`unverifiedWalks`)
    and taxi crossings (`flown`) are counted and never applied.

    A walk replaces any edge for the pair, a map_bounds estimate included,
    keeping its travel time; a pair with no edge gets one with the derived
    default time. Walks on different continents and pairs below
    MIN_OBSERVED_WALKS are counted and left out.
    """
    adjacency = tables["ZoneAdjacencies"]
    for source in list(adjacency):
        adjacency[source] = as_list(adjacency[source])
    continent_of = tables["ZoneToContinent"]
    walks = collections.Counter()
    for crossing in observations.get("crossings", []):
        if crossing.get("walked"):
            walks[frozenset((crossing["from"], crossing["to"]))] += crossing["walked"]
        # Recorded by a build that counted taxi flights as walks, or flown.
        if crossing.get("unverifiedWalks"):
            tally.add("survey walks", "not applied: recorded before the taxi check")
        if crossing.get("flown"):
            tally.add("survey walks", "not applied: flown on a taxi")
    for pair, count in sorted(walks.items(), key=lambda kv: sorted(kv[0])):
        a, b = sorted(pair)
        if continent_of.get(a) != continent_of.get(b):
            tally.add("survey walks", "not applied: different continents")
            continue
        if count < MIN_OBSERVED_WALKS:
            tally.add("survey walks", "not applied: seen once")
            continue
        for source, target in ((a, b), (b, a)):
            edges = adjacency.setdefault(source, [])
            edge = next((e for e in edges if e["zone"] == target), None)
            if edge is None:
                edge = {"zone": target, "travelTime": DERIVED_ADJACENCY_TIME}
                edges.append(edge)
                edges.sort(key=lambda e: e["zone"])
                tally.add("survey walks", "applied: new edge")
            elif edge.get("source") == DERIVED_ADJACENCY_SOURCE:
                tally.add("survey walks", "applied: replaced a map_bounds edge")
            else:
                tally.add("survey walks", "applied: confirmed an edge")
            edge["provenance"] = SURVEYED
            edge["source"] = SURVEY_SOURCE
            edge["observedWalks"] = count
    return tables


def map_yards_from_boxes(geo):
    """uiMap -> (yards per unit of map x, yards per unit of map y).

    Map x runs along world Y and map y along world X (see fp.project).
    """
    return {uid: (box[3] - box[2], box[1] - box[0])
            for boxes in geo.forever_boxes.values() for box, _, uid, _ in boxes}


def yards_between(map_yards, uid, ax, ay, bx, by):
    span = map_yards.get(uid)
    if not span:
        return None
    return (((ax - bx) * span[0]) ** 2 + ((ay - by) * span[1]) ** 2) ** 0.5


def apply_observed_landings(tables, observations, tally, map_yards):
    """Loading-screen crossings refine the ends of converted transports.

    Only entries converted from retail (provenance estimated) are touched; the
    TaxiPath ones carry the client's own positions. The most often seen
    endpoint of a crossing between the same two zones replaces both ends, but
    only when each end lies within MAX_LANDING_SHIFT_YARDS of the converted one:
    a mage teleport between the same two cities is the same kind of record.
    """
    portals = as_list(tables["StandalonePortals"])
    tables["StandalonePortals"] = portals
    for crossing in observations.get("crossings", []):
        endpoints = crossing.get("endpoints") or []
        if not endpoints:
            continue
        best = sorted(endpoints, key=lambda e: (-e["count"], e["fromX"], e["fromY"],
                                                e["toX"], e["toY"]))[0]
        applied = False
        for portal in portals:
            if portal.get("provenance") != ESTIMATED:
                continue
            ends = (portal["from"]["mapID"], portal["to"]["mapID"])
            if ends == (crossing["from"], crossing["to"]):
                start, end = portal["from"], portal["to"]
            elif ends == (crossing["to"], crossing["from"]):
                start, end = portal["to"], portal["from"]
            else:
                continue
            shifts = [yards_between(map_yards, start["mapID"], start["x"], start["y"],
                                    best["fromX"], best["fromY"]),
                      yards_between(map_yards, end["mapID"], end["x"], end["y"],
                                    best["toX"], best["toY"])]
            if any(d is None or d > MAX_LANDING_SHIFT_YARDS for d in shifts):
                tally.add("survey landings",
                          f"not applied: farther than {MAX_LANDING_SHIFT_YARDS} yd from the converted end")
                applied = None
                continue
            start["x"], start["y"] = best["fromX"], best["fromY"]
            end["x"], end["y"] = best["toX"], best["toY"]
            portal["provenance"] = SURVEYED
            applied = True
        if applied is True:
            tally.add("survey landings", "applied to a converted transport")
        elif applied is False:
            tally.add("survey landings", "not applied: no converted transport between the zones")
    return tables


def boxes_touch(a, b):
    """Two (xmin, xmax, ymin, ymax) rectangles overlap or share an edge."""
    return a[0] <= b[1] and b[0] <= a[1] and a[2] <= b[3] and b[2] <= a[3]


def derive_bounds_adjacency(geo, adjacency, tally):
    """Edges for Forever zones that have none, from touching zone rectangles.

    Only zones with zero edges after the retail conversion get them, in both
    directions, marked so a surveyed crossing can replace them later. Returns
    the set of (from, to) pairs added; geo.derived_report lists them with the
    rectangles they came from.
    """
    connected = set(adjacency) | {t for targets in adjacency.values() for t in targets}
    isolated = sorted(uid for uid in geo.forever_zones if uid not in connected)
    derived = set()
    geo.derived_report = []
    for uid in isolated:
        info = geo.forever_zones[uid]
        boxes = geo.forever_boxes.get(info["map"], ())
        mine = next(box for box, _, other, _ in boxes if other == uid)
        found = False
        for box, _, other, _ in sorted(boxes, key=lambda b: b[2]):
            if other == uid or not boxes_touch(mine, box):
                continue
            found = True
            for a, b in ((uid, other), (other, uid)):
                if b not in adjacency[a]:
                    adjacency[a][b] = DERIVED_ADJACENCY_TIME
                    derived.add((a, b))
            geo.derived_report.append((uid, other, mine, box))
            tally.add("zone adjacency edges", "derived from map bounds (pairs)")
        if not found:
            tally.add("zones with no edge", f"{info['name']} ({uid}, world map {info['map']})")
    return derived


def teleport_exists(kind, ident, spells, items):
    return ident in spells if kind == "spell" else ident in items


def forever_requirements(requirements, phases):
    """Requirements as they apply on Forever, or None when they cannot be met.

    A mapArtID requirement names a retail Zidormi phase. Forever is the world
    before those changes and has no phase switch, so a destination gated on the
    "Past" art is simply there (the requirement goes) and one gated on the
    "Present" art does not exist (None). Other requirements are copied.
    """
    if not requirements or "mapArtID" not in requirements:
        return requirements
    gate = requirements["mapArtID"]
    names = {p.get("artID"): p.get("name", "") for p in as_list(phases.get(gate["mapID"], {}))}
    if "(Past " not in names.get(gate["artID"], ""):
        return None
    rest = {k: v for k, v in requirements.items() if k != "mapArtID"}
    return rest


def with_forever_requirements(entry, phases, tally, what):
    if "requirements" not in entry:
        return entry
    requirements = forever_requirements(entry["requirements"], phases)
    if requirements is None:
        tally.add(what, "dropped: exists only in a present-day phase")
        return None
    out = dict(entry)
    if requirements:
        out["requirements"] = requirements
    else:
        del out["requirements"]
    return out


def build_teleports(geo, retail, spells, items, tally):
    out = {"TeleportTypes": dict(retail["TeleportTypes"])}
    phases = retail["TravelPhaseGroups"]

    tdd = {}
    for key, entry in sorted(retail["TeleportDestinationData"].items()):
        kind, _, ident = key.partition(":")
        if not teleport_exists("spell" if kind == "spell" else "item", int(ident), spells, items):
            tally.add("TeleportDestinationData", "dropped: spell/item not in Forever tables")
            continue
        retail_destinations = as_list(entry.get("destinations", {}))
        destinations = []
        for dest in retail_destinations:
            dest = with_forever_requirements(dest, phases, tally,
                                             "TeleportDestinationData destinations")
            converted = dest and converted_point(geo, tally,
                                                 "TeleportDestinationData destinations", dest)
            if converted is not None:
                destinations.append(converted)
                tally.add("TeleportDestinationData destinations", "kept")
        if retail_destinations and not destinations:
            tally.add("TeleportDestinationData", "dropped: no destination on Forever")
            continue
        copy = dict(entry)
        copy["destinations"] = destinations
        tdd[key] = copy
        tally.add("TeleportDestinationData", "kept")
    out["TeleportDestinationData"] = tdd

    def filter_table(name, table):
        kept = {}
        for ident, entry in sorted(table.items()):
            kind = "spell" if entry.get("type") == "spell" else "item"
            if not teleport_exists(kind, ident, spells, items):
                tally.add(name, "dropped: spell/item not in Forever tables")
                continue
            key = entry.get("travelDestinationKey")
            if key and key not in tdd:
                tally.add(name, "dropped: its destinations are not on Forever")
                continue
            entry = with_forever_requirements(entry, phases, tally, name)
            converted = entry and converted_point(geo, tally, name, entry)
            if converted is None:
                continue
            if converted.get("multiDestination") and len(tdd[key]["destinations"]) == 1:
                # The retail choice between phases is gone: one destination left.
                # Shape it the way TravelShortcuts.lua shapes a single-destination
                # entry, so it routes like one.
                only = tdd[key]["destinations"][0]
                only.pop("choiceText", None)
                del converted["multiDestination"]
                for field in ("mapID", "x", "y", "requirements"):
                    converted.pop(field, None)
                    if field in only:
                        converted[field] = only[field]
                converted["isDynamic"] = converted.get("requiresDestinationResolution", False)
                tally.add(name, "note: phase choice collapsed to one destination")
            kept[ident] = converted
            tally.add(name, "kept")
        return kept

    for name in ("TeleportItemsData", "ClassTeleportSpells", "RacialTeleportSpells",
                 "GeneralTeleportSpells"):
        out[name] = filter_table(name, retail[name])
    out["MageTeleports"] = {group: filter_table(f"MageTeleports.{group}", table)
                            for group, table in sorted(retail["MageTeleports"].items())}

    # Mythic+ and attunement teleports name a journal instance. The spell has
    # to exist and the instance has to be one Forever ships (instance_on_forever).
    dungeon = {}
    for ident, entry in sorted(retail["DungeonTeleportSpells"].items()):
        if ident not in spells:
            tally.add("DungeonTeleportSpells", "dropped: spell not in Forever SpellName")
        elif not instance_on_forever(retail, entry["journalInstanceID"], entry["destination"]):
            tally.add("DungeonTeleportSpells", "dropped: no such instance map on Forever")
        else:
            dungeon[ident] = dict(entry)
            tally.add("DungeonTeleportSpells", "kept")
    out["DungeonTeleportSpells"] = dungeon
    return out


def instance_key(name):
    """Dungeon name -> comparison key. Wing names share their dungeon's map
    ("Dire Maul - Warpwood Quarter" is Dire Maul), and a leading "The" is not
    part of the name ("The Deadmines" is the Deadmines map)."""
    base = re.split(r"\s+-\s+", name)[0]
    return fp.norm(re.sub(r"^the\s+", "", base, flags=re.IGNORECASE))


def instance_on_forever(retail, journal_id, name):
    """Does Forever ship this dungeon? Forever has no JournalInstance table.

    Either the retail journal instance's map ID is an instance map in Forever's
    Map table (The Stockade is map 34 there as "Stormwind Stockade"), or the
    names match (retail Scarlet Monastery is the remade map 1004; Forever has
    the original, 189, under the same name).
    """
    map_id = retail["_journal_map"].get(journal_id)
    return map_id in retail["_forever_instance_ids"] \
        or instance_key(name) in retail["_forever_instances"]


def mark_estimated(entry):
    entry["provenance"] = ESTIMATED
    return entry


def stop_zone(geo, anchors, map_id, wx, wy):
    """A transport stop -> (Forever uiMap, x, y, label), or None."""
    containing = sorted(((box[1] - box[0]) * (box[3] - box[2]), uid, box_geo)
                        for box, box_geo, uid, _ in geo.forever_boxes.get(map_id, ())
                        if box[0] <= wx <= box[1] and box[2] <= wy <= box[3])
    if not containing:
        return None
    by_uid = {uid: g for _, uid, g in containing}
    chosen, label = containing[0][1], None
    near = sorted(((((a["wx"] - wx) ** 2 + (a["wy"] - wy) ** 2) ** 0.5, i)
                   for i, a in enumerate(anchors) if str(a["continent"]) == map_id))
    if near and near[0][0] <= STOP_ANCHOR_YARDS:
        anchor = anchors[near[0][1]]
        place, _, stated = anchor["name"].partition(",")
        if anchor["uid"] in by_uid:
            chosen, label = anchor["uid"], place.strip()
        else:
            for _, uid, _ in containing:
                if stated and fp.related(geo.forever_zones[uid]["name"], stated.strip()):
                    chosen = uid
                    break
    ux, uy = fp.project(wx, wy, *by_uid[chosen])
    return chosen, round(ux, 4), round(uy, 4), label or geo.forever_zones[chosen]["name"]


def build_transports(geo, fdir, flight_final, retail, tally):
    """Boats and zeppelins whose paths are in Forever's TaxiPath tables."""
    anchors = []
    for uid, entry in flight_final.items():
        for point in (entry, entry.get("alt")):
            if point:
                anchors.append({"uid": uid, "name": point["name"], "continent": point["continent"],
                                "wx": point["wx"], "wy": point["wy"]})
    path_nodes = collections.defaultdict(list)
    for row in fp.load(fdir, "TaxiPathNode.csv",
                       ("PathID", "NodeIndex", "ContinentID", "Loc_0", "Loc_1", "Loc_2", "Delay")):
        path_nodes[row["PathID"]].append(row)

    # Retail time and faction for the same pair of Forever zones, where retail
    # has that connection; the route itself is Forever's.
    retail_pairs = {}
    for portal in as_list(retail["StandalonePortals"]):
        a, b = geo.zone(portal["from"]["mapID"]), geo.zone(portal["to"]["mapID"])
        if a and b:
            retail_pairs.setdefault((frozenset((a, b)), portal["type"]), portal)

    seen = {}
    transports = []
    geo.transport_report = []
    for path_id in sorted(path_nodes, key=int):
        rows = sorted(path_nodes[path_id], key=lambda r: int(r["NodeIndex"]))
        stops = []
        for row in rows:
            if int(row["Delay"] or 0) <= 0:
                continue
            place = stop_zone(geo, anchors, row["ContinentID"], float(row["Loc_0"]), float(row["Loc_1"]))
            if place is None:
                tally.add("transport paths", "stop in no Forever zone")
                continue
            if not stops or stops[-1][0] != place[0]:
                stops.append(place)
        if len(stops) > 2 and stops[0][0] == stops[-1][0]:
            stops.pop()
        if len({stop[0] for stop in stops}) < 2:
            continue
        heights = sorted(float(r["Loc_2"]) for r in rows)
        kind = "zeppelin" if heights[len(heights) // 2] > ZEPPELIN_MIN_HEIGHT else "boat"
        legs = list(zip(stops, stops[1:]))
        if len(stops) > 2:
            legs.append((stops[-1], stops[0]))
        for a, b in legs:
            key = (frozenset((a[0], b[0])), kind)
            if key in seen:
                seen[key]["taxiPathIDs"].append(int(path_id))
                tally.add("transports", "same leg on another path")
                continue
            match = retail_pairs.get(key)
            entry = {
                "name": f"{a[3]} to {b[3]}",
                "from": {"mapID": a[0], "x": a[1], "y": a[2]},
                "to": {"mapID": b[0], "x": b[1], "y": b[2]},
                "travelTime": match["travelTime"] if match else DEFAULT_TRANSPORT_TIME[kind],
                "faction": match["faction"] if match else "both",
                "type": kind,
                "bidirectional": True,
                "taxiPathIDs": [int(path_id)],
            }
            seen[key] = entry
            transports.append(entry)
            geo.transport_report.append((path_id, entry["name"], kind, a[0], b[0],
                                         "retail" if match else "default"))
            tally.add("transports", "kept (from TaxiPath)")
    return transports


def build_portals(geo, retail, tally, fdir=None, flight_final=None, maps=()):
    capitals = {}
    for name, city in sorted(retail["CAPITAL_CITIES"].items()):
        converted = converted_point(geo, tally, "CAPITAL_CITIES", city)
        if converted is not None:
            capitals[name] = mark_estimated(converted)
            tally.add("CAPITAL_CITIES", "kept")

    # No portal hubs. Converting them kept the Stormwind and Orgrimmar portal
    # rooms with four portals (Ironforge, Thunder Bluff, and Caverns of Time
    # twice) and the router then sent a Westfall-to-Ashenvale trip through
    # "Take portal to Tanaris". City portal rooms came with Cataclysm and later;
    # the Vanilla-era world has none. Forever's client tables neither confirm
    # nor rule that out (its GameObjects table lists no portal objects, and
    # neither does retail's), so this is the one judgement in this file.
    hubs = {}
    tally.add("PortalHubs", "dropped: city portal rooms are post-Vanilla", len(retail["PortalHubs"]))

    # Boats and zeppelins: only what Forever's TaxiPath tables prove. The
    # tram has no taxi path; Forever's Map table has its map ("Deeprun Tram",
    # 369), so the retail tram is converted. Every other retail transport is
    # replaced by the Forever paths.
    standalone = build_transports(geo, fdir, flight_final, retail, tally)
    for portal in as_list(retail["StandalonePortals"]):
        if portal["type"] != "tram" or "Deeprun Tram" not in maps:
            tally.add("StandalonePortals (retail)", "dropped: replaced by Forever TaxiPath")
            continue
        source = converted_point(geo, tally, "StandalonePortals", portal["from"])
        target = converted_point(geo, tally, "StandalonePortals", portal["to"]) if source else None
        if source is None or target is None:
            continue
        copy = dict(portal)
        copy["from"], copy["to"] = source, target
        standalone.append(mark_estimated(copy))
        tally.add("StandalonePortals (retail)", "kept: tram, converted")
    return {"CAPITAL_CITIES": capitals, "PortalHubs": hubs, "StandalonePortals": standalone}


def build_dungeons(geo, retail, tally):
    out = collections.defaultdict(list)
    for zone, entries in sorted(retail["StaticDungeonEntrances"].items()):
        for entry in as_list(entries):
            jid, x, y, name, is_raid = as_list(entry)
            if not instance_on_forever(retail, jid, name):
                tally.add("StaticDungeonEntrances", "dropped: no such instance map on Forever")
                continue
            result = geo.convert(zone, x, y)
            if result is None:
                tally.add("StaticDungeonEntrances", "dropped: lands in no Forever zone")
                continue
            out[result[0]].append([jid, result[1], result[2], name, is_raid])
            tally.add("StaticDungeonEntrances", "kept")
    return {"StaticDungeonEntrances": dict(sorted(out.items()))}


def build_services(geo, retail, tally):
    pois = {}
    for service, points in sorted(retail["ServicePOIs"].items()):
        if service in SERVICES_NOT_ON_FOREVER:
            tally.add("ServicePOIs", "dropped: service type not on Forever", len(as_list(points)))
            continue
        kept = []
        for point in as_list(points):
            converted = converted_point(geo, tally, "ServicePOIs", point)
            if converted is not None:
                kept.append(mark_estimated(converted))
                tally.add("ServicePOIs", "kept")
        if kept:
            pois[service] = kept
    types = {k: v for k, v in retail["ServiceTypes"].items() if k in pois}
    return {"ServicePOIs": pois, "ServiceTypes": types}


def build_hearthstones(geo, retail, areas, tally):
    kept = []
    for entry in as_list(retail["HearthstoneLocations"]):
        if entry["areaID"] not in areas:
            tally.add("HearthstoneLocations", "dropped: area not in Forever AreaTable")
            continue
        if entry.get("ambiguous"):
            kept.append(dict(entry))
            tally.add("HearthstoneLocations", "kept (ambiguous, no point)")
            continue
        converted = converted_point(geo, tally, "HearthstoneLocations", entry)
        if converted is not None:
            kept.append(converted)
            tally.add("HearthstoneLocations", "kept")
    return {"HearthstoneLocations": kept}


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------

LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else repr(value)
    if isinstance(value, str):
        return lua_string(value)
    raise TypeError(f"cannot write {type(value).__name__}")


def lua_key(key):
    if isinstance(key, str) and IDENT.match(key) and key not in LUA_KEYWORDS:
        return key
    return f"[{lua_scalar(key)}]"


def sort_key(key):
    return (0, key, "") if isinstance(key, (int, float)) else (1, 0, key)


def lua_value(value, indent):
    if isinstance(value, list) or is_array(value) and value:
        items = as_list(value) if isinstance(value, dict) else value
        if not items:
            return "{}"
        rendered = [lua_value(v, indent + 1) for v in items]
        if all("\n" not in r for r in rendered) and sum(len(r) for r in rendered) < 100:
            return "{ " + ", ".join(rendered) + " }"
        pad = "    " * (indent + 1)
        return "{\n" + "".join(f"{pad}{r},\n" for r in rendered) + "    " * indent + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        keys = sorted(value, key=sort_key)
        rendered = [(lua_key(k), lua_value(value[k], indent + 1)) for k in keys]
        flat = all("\n" not in r for _, r in rendered)
        if flat and sum(len(k) + len(r) + 5 for k, r in rendered) < 110:
            return "{ " + ", ".join(f"{k} = {r}" for k, r in rendered) + " }"
        pad = "    " * (indent + 1)
        return "{\n" + "".join(f"{pad}{k} = {r},\n" for k, r in rendered) + "    " * indent + "}"
    return lua_scalar(value)


def write_lua(path, header, tables):
    lines = [header.rstrip("\n"), "local ADDON_NAME, QR = ...", ""]
    for name, value in tables.items():
        lines.append(f"QR.{name} = {lua_value(value, 0)}")
        lines.append("")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def header(file_name, body):
    return (f"-- {file_name}\n"
            "-- WoW Forever data. GENERATED by scripts/generate_forever_data.py -- do not\n"
            "-- edit by hand. Loaded by QuickRoute_Camelot.toc instead of the retail file\n"
            "-- of the same name; defines the same QR tables in the same shape.\n"
            f"-- Forever tables: build {FOREVER_BUILD}. Retail geometry: build {RETAIL_BUILD}.\n"
            "--\n" + "".join(f"-- {line}\n" if line else "--\n" for line in body))


CONVERTED_NOTE = [
    "Positions are retail coordinates converted through world space into the",
    "Forever zone that contains them, and are estimates: Cataclysm changed the",
    "terrain in places. provenance = \"estimated\" marks them where the schema has",
    "that field. A point that lands in no Forever zone was dropped.",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--forever-csv-dir", required=True)
    parser.add_argument("--retail-csv-dir", required=True)
    parser.add_argument("--lua", default=os.path.expanduser("~/.local/bin/lua5.1"))
    parser.add_argument("--toc", default="QuickRoute/QuickRoute.toc",
                        help="retail TOC whose Data\\ files are converted (default: %(default)s)")
    parser.add_argument("--out-dir", default="QuickRoute/Data/Forever")
    parser.add_argument("--observations", default=OBSERVATIONS,
                        help="zone-survey observations to apply (default: %(default)s)")
    args = parser.parse_args()
    generate(args)


def generate(args):
    fdir, rdir = args.forever_csv_dir, args.retail_csv_dir
    geo_columns = ("UiMapID", "MapID", "AreaID", "Region_0", "Region_1", "Region_3", "Region_4",
                   "UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1", "WMOGroupID", "WMODoodadPlacementID")
    geo = Geometry(
        fp.load(rdir, "UiMap.csv", ("ID", "Name_lang", "Type", "System")),
        fp.load(rdir, "UiMapAssignment.csv", geo_columns),
        fp.load(fdir, "UiMap.csv", ("ID", "Name_lang", "Type", "System")),
        fp.load(fdir, "UiMapAssignment.csv", geo_columns),
    )
    spells = {int(r["ID"]) for r in fp.load(fdir, "SpellName.csv", ("ID",))}
    items = {int(r["ID"]) for r in fp.load(fdir, "ItemSparse.csv", ("ID",))}
    areas = {int(r["ID"]) for r in fp.load(fdir, "AreaTable.csv", ("ID",))}
    forever_instances = [r for r in fp.load(fdir, "Map.csv", ("ID", "MapName_lang", "InstanceType"))
                         if r["InstanceType"] in ("1", "2")]
    journal = fp.load(rdir, "JournalInstance.csv", ("ID", "MapID"))

    retail = export_retail(args.lua, args.toc)
    retail["_forever_instances"] = {instance_key(r["MapName_lang"]) for r in forever_instances}
    retail["_forever_instance_ids"] = {r["ID"] for r in forever_instances}
    retail["_journal_map"] = {int(r["ID"]): r["MapID"] for r in journal}
    tally = Tally()
    os.makedirs(args.out_dir, exist_ok=True)

    def out(name):
        return os.path.join(args.out_dir, name)

    flight_final = fp.build(fdir, min_zones=30, internal_flag=0)
    world_maps = {r["MapName_lang"] for r in fp.load(fdir, "Map.csv", ("ID", "MapName_lang"))}
    zones, zone_map = build_zones(geo, retail, tally)
    observations = load_observations(args.observations)
    apply_observed_walks(zones, observations, tally)
    write_lua(out("ZoneAdjacency.lua"), header("ZoneAdjacency.lua", [
        "Continents and their zone lists come from Forever's UiMap and",
        "UiMapAssignment: every zone-type map, grouped by the world map it is drawn",
        "on. Zone adjacency is the retail graph with each retail zone mapped onto",
        "the Forever zone of the same area, the same name, or the one containing",
        "its centre; edges inside one Forever zone and duplicates were folded.",
        "A zone left with no edge at all gets edges to every zone whose",
        "UiMapAssignment rectangle touches or overlaps its own on the same world",
        "map, both ways, marked provenance = \"estimated\", source = \"map_bounds\":",
        "derived from bounds, never observed, for a surveyed crossing to replace.",
        "Walks the zone survey saw (scripts/data/forever_zone_survey.json, at least",
        "twice) are provenance = \"surveyed\", source = \"zone_survey\", both ways.",
    ]), zones)

    flight_header = header("FlightPoints.lua", [
        "Authoritative: Forever's own TaxiNodes and TaxiPath, filtered and placed",
        "by scripts/generate_flight_points.py. That generator's notes on the",
        "filters, the per-faction entries and the axis order apply here. One",
        "difference: Forever sets the 0x400 flag on almost every node, flight",
        "masters included, so only the faction bits decide who a node is shown to.",
    ]) + "local ADDON_NAME, QR = ...\n\nQR.FlightPoints = {"
    fp.emit(flight_final, out("FlightPoints.lua"), header=flight_header)
    tally.add("FlightPoints", "zones", len(flight_final))

    write_lua(out("Teleports.lua"), header("Teleports.lua", [
        "Teleport items, toys and spells: a retail entry is kept only when its",
        "spell is in Forever's SpellName or its item in Forever's ItemSparse, and",
        "its destination converts into a Forever zone. Entries whose destination",
        "depends on the character (hearthstones and other dynamic ones) keep",
        "mapID nil. Dungeon teleports also need their instance map to exist.",
        "",
    ] + CONVERTED_NOTE), build_teleports(geo, retail, spells, items, tally))

    write_lua(out("Portals.lua"), header("Portals.lua", [
        "Capital cities from the retail table, converted. No portal hubs: the",
        "converted Stormwind and Orgrimmar portal rooms are post-Vanilla and",
        "routed trips through a portal to Tanaris.",
        "",
        "Boats and zeppelins come from Forever's TaxiPath and TaxiPathNode: a",
        "path whose nodes stop in two or more zones, one entry per leg between",
        "consecutive stops, stop positions as the table states them. Type by",
        "path height (ships at sea level). taxiPathIDs names the paths. Travel",
        "time and faction come from the retail connection between the same two",
        "zones where there is one, otherwise 180 s (boat) / 120 s (zeppelin) and",
        "both. The Deeprun Tram has no taxi path; Forever's Map table has its",
        "map, and the retail tram is converted.",
        "",
        "Loading-screen crossings the zone survey saw replace both ends of a",
        "converted transport between the same zones (provenance = \"surveyed\")",
        "when each end lies within 50 yd of the converted one.",
        "",
    ] + CONVERTED_NOTE), apply_observed_landings(
        build_portals(geo, retail, tally, fdir, flight_final, world_maps), observations, tally,
        map_yards_from_boxes(geo)))

    write_lua(out("DungeonEntrances.lua"), header("DungeonEntrances.lua", [
        "Format as in the retail file: [zoneMapID] = { { journalInstanceID, x, y,",
        "\"English Name\", isRaid }, ... }. Kept only when Forever's Map table has an",
        "instance of that name (wings match their dungeon). The journal instance",
        "IDs are retail ones; Forever has no JournalInstance table.",
        "",
    ] + CONVERTED_NOTE), build_dungeons(geo, retail, tally))

    write_lua(out("ServicePOIs.lua"), header("ServicePOIs.lua", [
        "Auction houses and banks from the retail table, converted. Void storage",
        "(Cataclysm) and crafting tables (Dragonflight) are left out: their retail",
        "points would convert into cities that have no such service on Forever.",
        "",
    ] + CONVERTED_NOTE), build_services(geo, retail, tally))

    write_lua(out("HearthstoneLocations.lua"), header("HearthstoneLocations.lua", [
        "Inn positions by area ID. An entry is kept only when its area exists in",
        "Forever's AreaTable. Ambiguous entries stay ambiguous: Forever having fewer",
        "areas has not been measured to make any name unique.",
        "",
    ] + CONVERTED_NOTE), build_hearthstones(geo, retail, areas, tally))

    write_lua(out("DestinationCatalog.lua"), header("DestinationCatalog.lua", [
        "Empty. The retail catalogue lists retail quests, NPCs and vendors from",
        "AllTheThings; none of it is valid on Forever.",
    ]), {"DestinationCatalog": {"source": "", "revision": "", "build": 0,
                                "npcs": [], "quests": [], "vendors": []}})

    write_lua(out("TravelTransitions.lua"), header("TravelTransitions.lua", [
        "Empty. The retail transitions are fixed portals between retail-only",
        "places and Zidormi phase switches; Forever has neither. Boats, zeppelins",
        "and the Deeprun Tram are a later change.",
    ]), {"TravelTransitions": {"nodes": {}, "edges": []}, "TravelPhaseGroups": {},
         "TravelHolidayIcons": {}})

    print("retail zone -> Forever zone (adjacency):", file=sys.stderr)
    unmapped = sorted(uid for uid, f in zone_map.items() if f is None)
    print(f"  mapped {sum(1 for f in zone_map.values() if f)}, unmapped {len(unmapped)}",
          file=sys.stderr)
    print("derived adjacency (zone, neighbour, boxes as xmin xmax ymin ymax):", file=sys.stderr)
    for uid, other, mine, box in geo.derived_report:
        print(f"  {uid} {geo.forever_zones[uid]['name']} <-> {other} "
              f"{geo.forever_zones[other]['name']}: {tuple(round(v) for v in mine)} "
              f"{tuple(round(v) for v in box)}", file=sys.stderr)
    print("transports (taxi path, name, type, from, to, time/faction source):", file=sys.stderr)
    for row in geo.transport_report:
        print(f"  {row}", file=sys.stderr)
    tally.report()


if __name__ == "__main__":
    main()
