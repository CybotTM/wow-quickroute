#!/usr/bin/env python3
"""Import WoW Forever zone-survey observations into scripts/data/forever_zone_survey.json.

The zone survey (QuickRoute/Modules/ZoneSurvey.lua) records, per map the player
arrives on, where they came from: `walked` counts arrivals without a loading
screen, `afoot` the part of those made while the client said the player was not
on a taxi, `flown` those made on a taxi, `loaded` arrivals with a loading
screen, and `endpoints` the departure and arrival
positions of loading-screen crossings. This script reads that table from a
SavedVariables file and merges the crossings between Forever zones into the
checked-in observations file. scripts/generate_forever_data.py applies the
file when it writes QuickRoute/Data/Forever/, so a regeneration keeps them.

Only crossings whose both maps are Forever zones are kept; everything else is
counted as rejected. Retail map IDs are not Forever zones, so a retail
SavedVariables file adds nothing.

Walks are split by what the recording build could tell. An entry with `afoot`
comes from a build that checks the taxi: `afoot` is stored as `walked` (on foot),
the rest of its `walked` as `unverifiedWalks`. An entry without `afoot` comes
from an older build that counted taxi flights as walks: all of its `walked` is
`unverifiedWalks`. The generator applies `walked` only.

Merging takes the larger count per crossing and per endpoint, never the sum:
the survey's counts only grow, so importing the same or a later file again
gives the same result, and running the import twice changes nothing.

Usage:
    python3 scripts/import_zone_survey.py \\
        "/mnt/f/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/QuickRoute.lua"
    python3 scripts/generate_forever_data.py --forever-csv-dir DIR --retail-csv-dir DIR

The SavedVariables file is only read.
"""

import argparse
import collections
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import generate_forever_data as gfd  # noqa: E402

DEFAULT_OBSERVATIONS = os.path.join(HERE, "data", "forever_zone_survey.json")
DEFAULT_TOC = os.path.join(HERE, "..", "QuickRoute", "QuickRoute_Camelot.toc")
ENDPOINT_BUCKETS = 200   # ZoneSurvey.lua's ENDPOINT_BUCKETS


def default_lua():
    """QR_LUA, else ~/.local/bin/lua5.1, else lua5.1 or lua on PATH (CI)."""
    local = os.path.expanduser("~/.local/bin/lua5.1")
    return (os.environ.get("QR_LUA") or (local if os.path.exists(local) else None)
            or shutil.which("lua5.1") or shutil.which("lua") or local)


def run_export(lua, *args):
    result = subprocess.run([lua, os.path.join(HERE, "export_data_json.lua"), *args],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        sys.exit(f"export failed: {result.stderr.strip()}")
    return gfd.decode_export(result.stdout)


def forever_zones(lua, toc):
    """Forever zone uiMap IDs, from the continent zone lists of the Forever data."""
    data = run_export(lua, toc)
    zones = set()
    for continent in data["Continents"].values():
        zones.update(gfd.as_list(continent.get("zones", {})))
    return zones


def endpoint_key(endpoint):
    return ":".join(str(int(endpoint[field] * ENDPOINT_BUCKETS))
                    for field in ("fromX", "fromY", "toX", "toY"))


def empty_observations():
    return {
        "about": "Zone-survey crossings between WoW Forever zones, merged by "
                 "scripts/import_zone_survey.py and applied by "
                 "scripts/generate_forever_data.py. Counts are the largest seen.",
        "crossings": [],
    }


def load_observations(path):
    if not os.path.exists(path):
        return empty_observations()
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def write_observations(path, observations):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    text = json.dumps(observations, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def merge(observations, survey, zones, tally):
    """Fold survey crossings between Forever zones into observations (in place)."""
    by_pair = {(c["from"], c["to"]): c for c in observations["crossings"]}
    for to_map, record in sorted(survey.items(), key=lambda kv: str(kv[0])):
        origins = record.get("from") if isinstance(record, dict) else None
        if not isinstance(origins, dict):
            continue
        for from_map, entry in sorted(origins.items(), key=lambda kv: str(kv[0])):
            if not isinstance(entry, dict):
                tally["rejected: malformed"] += 1
                continue
            if to_map not in zones or from_map not in zones:
                tally["rejected: not a Forever zone"] += 1
                continue
            crossing = by_pair.setdefault((from_map, to_map), {
                "from": from_map, "to": to_map, "walked": 0, "unverifiedWalks": 0,
                "flown": 0, "loaded": 0, "endpoints": []})
            walked = int(entry.get("walked") or 0)
            if "afoot" in entry:
                afoot = int(entry.get("afoot") or 0)
                counts = {"walked": afoot, "unverifiedWalks": max(0, walked - afoot)}
            else:
                counts = {"walked": 0, "unverifiedWalks": walked}
            counts["flown"] = int(entry.get("flown") or 0)
            counts["loaded"] = int(entry.get("loaded") or 0)
            for field, value in counts.items():
                crossing[field] = max(crossing.get(field, 0), value)
            known = {endpoint_key(e): e for e in crossing["endpoints"]}
            for door in (entry.get("endpoints") or {}).values():
                if not all(isinstance(door.get(f), (int, float))
                           for f in ("fromX", "fromY", "toX", "toY")):
                    tally["rejected: malformed endpoint"] += 1
                    continue
                point = {f: door[f] for f in ("fromX", "fromY", "toX", "toY")}
                point["count"] = int(door.get("count") or 0)
                key = endpoint_key(point)
                if key in known:
                    known[key]["count"] = max(known[key]["count"], point["count"])
                else:
                    known[key] = point
            crossing["endpoints"] = [known[k] for k in sorted(known)]
            tally["accepted: crossing between Forever zones"] += 1
    observations["crossings"] = [by_pair[k] for k in sorted(by_pair)]
    return observations


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("saved_variables", help="SavedVariables/QuickRoute.lua (read only)")
    parser.add_argument("--observations", default=DEFAULT_OBSERVATIONS)
    parser.add_argument("--toc", default=DEFAULT_TOC)
    parser.add_argument("--lua", default=default_lua())
    args = parser.parse_args()

    survey = run_export(args.lua, "--zone-survey", args.saved_variables)
    zones = forever_zones(args.lua, args.toc)
    tally = collections.Counter()
    observations = merge(load_observations(args.observations), survey, zones, tally)
    write_observations(args.observations, observations)
    print(f"{'survey records (maps)':<44}: {len(survey)}", file=sys.stderr)
    for key in sorted(tally):
        print(f"{key:<44}: {tally[key]}", file=sys.stderr)
    print(f"{'crossings in the observations file':<44}: {len(observations['crossings'])}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
