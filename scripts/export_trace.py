#!/usr/bin/env python3
"""Export QuickRoute's diagnostic trace from SavedVariables files as JSONL.

The trace (setting "Diagnostic trace", QuickRoute/Modules/Diagnostics.lua) is a
ring buffer in QuickRouteDB.trace. This script reads it through
scripts/export_data_json.lua --trace, so no Lua is parsed in Python, and writes
one JSON object per entry, oldest first. Several files may be given -- the
retail and the Forever SavedVariables -- and every record carries the
`flavor` of the client that wrote it, taken from the client header the addon
stores with the trace ("retail" or "forever").

Then it prints a summary: entries per flavor and category, and for every
window open its reason and the trace entries of the two seconds before it.

Usage:
    python3 scripts/export_trace.py -o trace.jsonl \\
        "/mnt/f/World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/QuickRoute.lua" \\
        "/mnt/f/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/QuickRoute.lua"

Without -o the JSONL goes to stdout and the summary to stderr. The
SavedVariables files are only read; nothing is written next to them.
"""

import argparse
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import generate_forever_data as gfd  # noqa: E402
from import_zone_survey import default_lua, run_export  # noqa: E402

WINDOW_SECONDS = 2.0
FIELDS = (("t", "time"), ("g", "gameTime"), ("l", "level"), ("c", "category"),
          ("m", "message"), ("map", "mapID"), ("x", "x"), ("y", "y"))


def read_trace(lua, path):
    """(client header, dropped count, entries) of one SavedVariables file."""
    data = run_export(lua, "--trace", path)
    return data.get("client") or {}, data.get("dropped", 0), gfd.as_list(data.get("entries", {}))


def to_record(entry, flavor, seq, source):
    record = {"flavor": flavor, "seq": seq, "source": source}
    for short, name in FIELDS:
        if short in entry:
            record[name] = entry[short]
    record["combat"] = bool(entry.get("cb"))
    fields = entry.get("f")
    if fields:
        record["fields"] = {str(k): v for k, v in fields.items()}
    return record


def load_records(lua, paths):
    records, headers = [], []
    for path in paths:
        client, dropped, entries = read_trace(lua, path)
        flavor = client.get("flavor") or "unknown"
        headers.append({"source": path, "flavor": flavor, "client": client,
                        "entries": len(entries), "dropped": dropped})
        for seq, entry in enumerate(entries, 1):
            records.append(to_record(entry, flavor, seq, path))
    return records, headers


def describe(record):
    text = f"{record.get('category')}: {record.get('message')}"
    fields = record.get("fields") or {}
    for key in ("trigger", "outcome", "a1", "npc", "questID", "reason"):
        if key in fields:
            text += f" {key}={fields[key]}"
    return text


def window_opens(records):
    """Every traced window open with the entries of the WINDOW_SECONDS before it.

    gameTime restarts with the client, so the look-back stays within one file
    and within one session (it stops at the session's start entry).
    """
    opens = []
    for i, record in enumerate(records):
        fields = record.get("fields") or {}
        if record.get("category") != "window" or fields.get("action") != "show":
            continue
        at = record.get("gameTime")
        before = []
        j = i - 1
        while j >= 0:
            prior = records[j]
            if prior["source"] != record["source"] or prior.get("category") == "session":
                break
            if at is None or prior.get("gameTime") is None or at - prior["gameTime"] > WINDOW_SECONDS:
                break
            before.append(prior)
            j -= 1
        before.reverse()
        opens.append((record, before))
    return opens


def summary(records, headers):
    lines = []
    for header in headers:
        client = header["client"]
        lines.append(f"{header['source']}: {header['flavor']}, {header['entries']} entries, "
                     f"{header['dropped']} dropped by the cap, interface {client.get('interface', '?')}, "
                     f"build {client.get('build', '?')}, addon {client.get('addonVersion', '?')}")
    counts = collections.Counter((r["flavor"], r.get("category")) for r in records)
    lines.append("")
    lines.append("Entries per flavor and category:")
    for (flavor, category), n in sorted(counts.items(), key=lambda kv: (kv[0][0], -kv[1], str(kv[0][1]))):
        lines.append(f"  {flavor:8} {str(category):12} {n}")
    opens = window_opens(records)
    lines.append("")
    lines.append(f"Window opens: {len(opens)}")
    for record, before in opens:
        fields = record.get("fields") or {}
        lines.append(f"- [{record['flavor']} #{record['seq']} t={record.get('time')} "
                     f"g={record.get('gameTime')}] reason={fields.get('reason')} tab={fields.get('tab')}")
        if fields.get("stack"):
            lines.append(f"    stack: {fields['stack']}")
        if not before:
            lines.append(f"    (nothing in the {WINDOW_SECONDS:g} s before)")
        for prior in before:
            delta = record["gameTime"] - prior["gameTime"]
            lines.append(f"    -{delta:.3f}s {describe(prior)}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("savedvariables", nargs="+", help="SavedVariables/QuickRoute.lua file(s)")
    parser.add_argument("-o", "--output", help="JSONL output file (default: stdout)")
    parser.add_argument("--lua", default=default_lua(), help="Lua 5.1 interpreter")
    args = parser.parse_args(argv)

    for path in args.savedvariables:
        if args.output and os.path.abspath(path) == os.path.abspath(args.output):
            sys.exit("refusing to overwrite the input file")
    records, headers = load_records(args.lua, args.savedvariables)
    text = "".join(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n" for r in records)
    report = summary(records, headers)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(f"wrote {len(records)} records to {args.output}")
        print(report)
    else:
        sys.stdout.write(text)
        print(report, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
