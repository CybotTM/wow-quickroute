#!/usr/bin/env python3
"""Audit local inn facts against pinned guide text and full client DB2 snapshots.

No source Lua is executed. Run:
  python3 audit_hearthstone_catalog.py --root /path/to/quickroute --sources /path/to/snapshots
Add --fixture /path/to/hearthstone_area_names.lua to regenerate the EN/DE test fixture.
"""
import argparse
import csv
import hashlib
import re
import tarfile
from collections import defaultdict
from pathlib import Path

BUILD = "12.1.0.69587"
SHA = "f7c84c7ef4bcc3af20ff33cb5a497dd639b45851"
LOCALES = ("enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT")


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def quote_lua(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--fixture", type=Path)
    args = parser.parse_args()
    catalog_path = args.root / "QuickRoute/Data/HearthstoneLocations.lua"
    source = catalog_path.read_text()
    records = {}
    pattern = re.compile(r"^    \{ areaID = (\d+), (ambiguous = true|mapID = (\d+), x = ([\d.]+), y = ([\d.]+)) \},", re.M)
    for match in pattern.finditer(source):
        area = int(match[1])
        assert area not in records, ("duplicate areaID", area)
        record = {"areaID": area, "ambiguous": match[2] == "ambiguous = true"}
        if not record["ambiguous"]:
            record.update(mapID=int(match[3]), x=float(match[4]), y=float(match[5]))
            assert record["mapID"] > 0 and 0 <= record["x"] <= 1 and 0 <= record["y"] <= 1
        records[area] = record
    assert len(records) == 119, ("reviewed snapshot record count", len(records))
    maps = {int(row["ID"]) for row in rows(args.sources / "UiMap.csv")}
    locations = [record for record in records.values() if not record["ambiguous"]]
    assert len(locations) == 58
    assert len({record["mapID"] for record in locations}) == 43
    assert all(record["mapID"] in maps for record in locations)

    guides = []
    with tarfile.open(args.sources / "WoW-Pro-Guides-f7c84c7.tar.gz") as archive:
        assert all(member.name.startswith("WoW-Pro-Guides-" + SHA) for member in archive.getmembers())
        for member in archive.getmembers():
            if "/WoWPro_Leveling/Retail/" not in member.name or not member.name.endswith(".lua"):
                continue
            text = archive.extractfile(member).read().decode("utf-8")
            for line_number, line in enumerate(text.splitlines(), 1):
                if not line.startswith("h "):
                    continue
                coords = re.search(r"\|M\|([0-9.]+),([0-9.]+)\|", line)
                map_id = re.search(r"\|Z\|(\d+)(?:;|\|)", line)
                if coords and map_id:
                    guides.append((line.split("|")[0][2:].strip(), int(map_id[1]),
                                   round(float(coords[1]) / 100, 4), round(float(coords[2]) / 100, 4),
                                   member.name.split("/", 1)[1], line_number))
    assert len(guides) == 88
    assert len({guide[0] for guide in guides}) == 80
    snapshots = {}
    print("locale\tAreaTable_rows\tmissing_catalog_IDs\tusable_bind_names")
    for locale in LOCALES:
        table = rows(args.sources / ("AreaTable-" + locale + ".csv"))
        assert len(table) == 10002
        names = {int(row["ID"]): row["AreaName_lang"] for row in table}
        snapshots[locale] = names
        missing = set(records) - names.keys()
        assert not missing, (locale, "missing catalog area IDs", missing)
        assert all(names[area] for area in records)
        by_name = defaultdict(set)
        for area, name in names.items():
            by_name[name].add(area)
        index = {}
        for area, record in records.items():
            name = names[area]
            if record["ambiguous"]:
                index[name] = None
            elif name not in index:
                index[name] = record
            elif index[name] is not None:
                previous = index[name]
                if any(previous[key] != record[key] for key in ("mapID", "x", "y")):
                    index[name] = None
        # Every physical candidate's translated aliases must be represented.
        # Unknown copies cannot disappear just because the guide omitted them.
        for record in locations:
            name = names[record["areaID"]]
            aliases = by_name[name] - {record["areaID"]}
            assert aliases <= records.keys(), (locale, record["areaID"], "missing collision blocker", aliases - records.keys())
            if aliases:
                assert index[name] is None, (locale, "collision incorrectly routable", name)
        usable = sum(record is not None for record in index.values())
        print(f"{locale}\t{len(table)}\t{len(missing)}\t{usable}")
    en = snapshots["enUS"]
    for record in locations:
        key = (en[record["areaID"]], record["mapID"], record["x"], record["y"])
        assert any(guide[:4] == key for guide in guides), ("unsourced or averaged coordinates", key)
    assert snapshots["deDE"][3462] == snapshots["deDE"][15995] == "Morgenluft"
    assert records[3462]["ambiguous"] and records[15995]["ambiguous"]
    if args.fixture:
        content = [
            "-- Client AreaTable names, extracted without manual translation.",
            "-- Source: https://wago.tools/db2/AreaTable/csv?build=" + BUILD + "&locale=LOCALE",
            "-- Snapshot: 2026-09-12; all 119 catalog area IDs; EN/DE only for integration tests.",
            "return {",
        ]
        for locale in ("enUS", "deDE"):
            content.append("    " + locale + " = {")
            for area in sorted(records):
                content.append("        [" + str(area) + "] = " + quote_lua(snapshots[locale][area]) + ",")
            content.append("    },")
        content.append("}")
        args.fixture.parent.mkdir(parents=True, exist_ok=True)
        args.fixture.write_text("\n".join(content) + "\n")
        print("fixture\t" + str(args.fixture))
    print("source_file\tsha256")
    for path in sorted(args.sources.glob("*.csv")):
        print(path.name + "\t" + hashlib.sha256(path.read_bytes()).hexdigest())
    guide_path = args.sources / "WoW-Pro-Guides-f7c84c7.tar.gz"
    print(guide_path.name + "\t" + hashlib.sha256(guide_path.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
