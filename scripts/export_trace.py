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

A log line the addon saw again within a few minutes is stored once; its record
carries `repeats` (occurrences, the first included), `lastTime` and
`lastGameTime` (the last occurrence). It sits at the position of its first
occurrence, and it is also listed before a window open when its last
occurrence falls into the two seconds before it.

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
# How far back a repeated log line can have started: Diagnostics.TRACE_REPEAT_SECONDS.
REPEAT_SECONDS = 300.0
FIELDS = (("t", "time"), ("g", "gameTime"), ("l", "level"), ("c", "category"),
          ("m", "message"), ("map", "mapID"), ("x", "x"), ("y", "y"),
          ("r", "repeats"), ("rt", "lastTime"), ("rg", "lastGameTime"))


def read_trace(lua, path):
    """(client header, dropped counts, entries) of one SavedVariables file.

    The dropped counts are those of the structured ring and of the log ring.
    """
    data = run_export(lua, "--trace", path)
    dropped = (data.get("dropped", 0), data.get("logDropped", 0))
    return data.get("client") or {}, dropped, gfd.as_list(data.get("entries", {}))


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
        client, (dropped, log_dropped), entries = read_trace(lua, path)
        flavor = client.get("flavor") or "unknown"
        headers.append({"source": path, "flavor": flavor, "client": client,
                        "entries": len(entries), "dropped": dropped, "logDropped": log_dropped,
                        "repeats": sum(max(0, e.get("r", 1) - 1) for e in entries)})
        for seq, entry in enumerate(entries, 1):
            records.append(to_record(entry, flavor, seq, path))
    return records, headers


def describe(record):
    text = f"{record.get('category')}: {record.get('message')}"
    if record.get("repeats"):
        text += f" (x{record['repeats']})"
    fields = record.get("fields") or {}
    for key in ("trigger", "outcome", "a1", "npc", "questID", "reason"):
        if key in fields:
            text += f" {key}={fields[key]}"
    return text


def offset(at, prior):
    """When a prior entry happened relative to `at`: "-0.500s", or for a
    repeated line the span of its occurrences, "-4.500s..+1.000s"."""
    first = at - prior["gameTime"]
    text = f"-{first:.3f}s"
    if prior.get("repeats") and "lastGameTime" in prior:
        last = prior["lastGameTime"] - at
        text += f"..{'+' if last > 0 else '-'}{abs(last):.3f}s"
    return text


def window_opens(records):
    """Every traced window open with the entries of the WINDOW_SECONDS before it.

    gameTime restarts with the client, so the look-back stays within one file
    and within one session (it stops at the session's start entry). A repeated
    log line counts when its last occurrence is in the window, although its
    record sits where it first occurred (at most REPEAT_SECONDS earlier).
    """
    opens = []
    for i, record in enumerate(records):
        fields = record.get("fields") or {}
        if record.get("category") != "window" or fields.get("action") != "show":
            continue
        at = record.get("gameTime")
        before = []
        j = i - 1
        while j >= 0 and at is not None:
            prior = records[j]
            if prior["source"] != record["source"] or prior.get("category") == "session":
                break
            started = prior.get("gameTime")
            if started is None or at - started > REPEAT_SECONDS + WINDOW_SECONDS:
                break
            last = prior.get("lastGameTime", started)
            # A repeated line spans first..last occurrence; it counts when that
            # span reaches into the window, also when it goes on past the open.
            if at - started <= WINDOW_SECONDS or (prior.get("repeats") and last >= at - WINDOW_SECONDS):
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
                     f"{header['dropped']} dropped by the cap, {header['logDropped']} log lines dropped "
                     f"by theirs, {header['repeats']} repeated log lines folded, "
                     f"interface {client.get('interface', '?')}, "
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
            lines.append(f"    {offset(record['gameTime'], prior)} {describe(prior)}")
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
