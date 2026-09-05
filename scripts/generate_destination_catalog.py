#!/usr/bin/env python3
"""Extract a retail routing catalogue from a pinned MIT AllTheThings checkout.

This is a non-executing Lua data parser. Upstream Lua functions, dynamic
expressions and symlinks are never executed or guessed. Their descendants are
excluded when they could alter access. Run with --source /path/to/AllTheThings.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import re
import subprocess
from pathlib import Path

REVISION = "8809863ca3e6e4cb4bf8f2cae1d18d52fc209235"
SOURCE = "https://github.com/ATTWoWAddon/AllTheThings"
BUILD = 120100
ROOT = Path(__file__).resolve().parents[1]
UNKNOWN = object()
TOKEN = re.compile(r'''\s+|--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z_][\w]*|\.\.|==|~=|<=|>=|.''', re.S)


class LuaDataParser:
    """Read constructor/table literals; retain dynamic values as UNKNOWN."""

    def __init__(self, source: str):
        self.tokens = (m.group() for m in TOKEN.finditer(source)
                       if not m.group().isspace() and not m.group().startswith("--"))
        self.pending: list[str] = []

    def peek(self, offset=0):
        while len(self.pending) <= offset:
            self.pending.append(next(self.tokens, ""))
        return self.pending[offset]

    def pop(self):
        token = self.peek()
        del self.pending[0]
        return token

    def expect(self, expected):
        actual = self.pop()
        if actual != expected:
            raise ValueError(f"expected {expected!r}, received {actual!r}")

    def function(self):
        depth = 1
        while depth:
            token = self.pop()
            if not token:
                raise ValueError("unterminated Lua function")
            if token in ("function", "if", "for", "while", "repeat"):
                depth += 1
            elif token in ("end", "until"):
                depth -= 1
        return UNKNOWN

    def value(self):
        token = self.pop()
        if token == "{":
            result = self.table()
        elif token == "function":
            result = self.function()
        elif token == "(":
            result = self.value()
            self.expect(")")
        elif token == "-":
            number = self.value()
            result = -number if isinstance(number, (int, float)) else UNKNOWN
        elif token[:1] in ('"', "'"):
            result = re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m[1], m[1]), token[1:-1])
        elif token.startswith("["):
            result = re.sub(r"^\[=*\[|\]=*\]$", "", token)
        elif token == "true":
            result = True
        elif token == "false":
            result = False
        elif token == "nil":
            result = None
        elif re.fullmatch(r"\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+", token):
            result = float(token) if any(c in token for c in ".eE") else int(token)
        else:
            result = UNKNOWN
        # Constructors are represented, not invoked. Field/index expressions
        # and arbitrary callback wrappers cannot become executable code.
        while self.peek() in (".", ":", "[", "("):
            op = self.pop()
            if op in (".", ":"):
                self.pop()
                result = UNKNOWN
            elif op == "[":
                self.value()
                self.expect("]")
                result = UNKNOWN
            else:
                args = []
                while self.peek() != ")":
                    args.append(self.value())
                    if self.peek() != ",":
                        break
                    self.pop()
                self.expect(")")
                if re.fullmatch(r"[a-z]+", token) and args and isinstance(args[0], (int, float)):
                    fields = dict(args[-1]) if isinstance(args[-1], dict) else {}
                    fields["_kind"], fields["_id"] = token, args[0]
                    result = fields
                elif len(args) == 1 and isinstance(args[0], dict):
                    result = dict(args[0])
                    result["_unsafe"] = True
                else:
                    result = UNKNOWN
        if self.peek() in ("..", "+", "-", "*", "/", "and", "or", "==", "~=", ">", "<"):
            self.pop()
            self.value()
            return UNKNOWN
        return result

    def table(self):
        fields, index = {}, 1
        while self.peek() != "}":
            if not self.peek():
                raise ValueError("unterminated Lua table")
            if self.peek() == "[":
                self.pop()
                key = self.value()
                self.expect("]")
                self.expect("=")
            elif re.fullmatch(r"[A-Za-z_]\w*", self.peek()) and self.peek(1) == "=":
                key = self.pop()
                self.pop()
            else:
                key, index = index, index + 1
            value = self.value()
            if key is not UNKNOWN:
                fields[key] = value
            if self.peek() in (",", ";"):
                self.pop()
            elif self.peek() != "}":
                raise ValueError(f"unexpected table token {self.peek()!r}")
        self.pop()
        return fields


def values(table):
    return [table[key] for key in sorted(k for k in table if isinstance(k, int))] if isinstance(table, dict) else []


def coords(node):
    result = []
    coordinate_table = node.get("coords")
    if not isinstance(coordinate_table, dict):
        return result
    for map_id, points in coordinate_table.items():
        if not isinstance(map_id, int) or map_id <= 0:
            continue
        for point in values(points):
            pair = values(point)
            if len(pair) == 2 and all(isinstance(n, (int, float)) and math.isfinite(n) and 0 <= n <= 100 for n in pair):
                result.append((map_id, pair[0] / 100, pair[1] / 100))
    return result


def collect_names(source):
    names = {"q": {}, "n": {}, "o": {}}
    pattern = re.compile(r"\b([qno])\((\d+)\s*,\s*\{\s*--\s*([^\r\n]+)")
    for path in sorted((source / ".contrib/Parser/DATAS").rglob("*.lua")):
        for match in pattern.finditer(path.read_text(encoding="utf-8-sig")):
            name = match[3].strip()
            if name and not name.startswith("#"):
                names[match[1]].setdefault(int(match[2]), name[:160])
    return names


def requirements(node, inherited):
    result = dict(inherited)
    if node.get("_unsafe") or node.get("u") or node.get("rwp") or node.get("pb"):
        return None
    if node.get("awp", 0) is UNKNOWN or node.get("awp", 0) > BUILD:
        return None
    if any(node.get(key) is UNKNOWN for key in ("r", "c", "races", "lvl", "sourceQuests", "minReputation",
                                               "maxReputation", "minRenown", "requireSkill", "covenantID")):
        return None
    # Dynamic access callbacks, timed events and covenant-specific content need
    # their own state evaluator; omission is safer than silently losing a gate.
    if any(key in node for key in ("OnUpdate", "OnClick", "customCollect", "eventID", "e", "isWorldQuest", "isWeekly")):
        return None
    for key in ("r", "requireSkill", "covenantID"):
        if key in node:
            if key in result and result[key] != node[key]:
                return None
            result[key] = node[key]
    for key in ("minReputation", "maxReputation", "minRenown"):
        if key in node:
            rule = values(node[key])
            if len(rule) != 2 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in rule):
                return None
            result["reputationRules"] = result.get("reputationRules", []) + [{"kind": key, "values": rule}]
    for key in ("c", "races"):
        if key in node:
            allowed = set(values(node[key]))
            if key in result:
                allowed.intersection_update(result[key])
            if not allowed:
                return None
            result[key] = sorted(allowed)
    level = node.get("lvl", 0)
    if isinstance(level, dict):
        level = next(iter(values(level)), 0)
    if isinstance(level, (int, float)):
        result["lvl"] = max(result.get("lvl", 0), level)
    if node.get("sourceQuests"):
        group = values(node["sourceQuests"])
        if any(not isinstance(q, int) or q <= 0 for q in group):
            return None
        required = node.get("sqreq", len(group))
        if not isinstance(required, int) or not 0 <= required <= len(group):
            return None
        result["questGroups"] = result.get("questGroups", []) + [{"ids": group, "required": required}]
    return result


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'
    if isinstance(value, (int, float)):
        return format(value, ".10g")
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join((k if isinstance(k, str) and k.isidentifier() else "[" + lua(k) + "]") + "=" + lua(v)
                                 for k, v in sorted(value.items(), key=lambda item: str(item[0]))) + "}"
    raise ValueError("dynamic Lua value cannot be serialized")


def combine_requirements(left, right):
    """Join independent quest/NPC access conditions without dropping a gate."""
    result = dict(left)
    for key in ("r", "requireSkill", "covenantID"):
        if key in right:
            if key in result and result[key] != right[key]:
                return None
            result[key] = right[key]
    for key in ("c", "races"):
        if key in right:
            allowed = set(right[key])
            if key in result:
                allowed.intersection_update(result[key])
            if not allowed:
                return None
            result[key] = sorted(allowed)
    result["lvl"] = max(left.get("lvl", 0), right.get("lvl", 0))
    for key in ("questGroups", "reputationRules"):
        rules = left.get(key, []) + right.get(key, [])
        if rules:
            result[key] = rules
    return result


def generate(source, output):
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != REVISION:
        raise ValueError(f"expected pinned revision {REVISION}, got {actual}")
    dirty = subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=all", "--",
                                     "LICENSE", "db/Standard/Categories", ".contrib/Parser/DATAS"], text=True).strip()
    if dirty:
        raise ValueError("catalogue source inputs differ from the pinned revision")
    if "MIT License" not in (source / "LICENSE").read_text():
        raise ValueError("upstream license changed")
    names = collect_names(source)
    npcs, quests, vendors, quest_sources = {}, {}, {}, {}
    provenance, skipped = [], 0

    def walk(node, inherited, parent_npc=None, vendor_section=False):
        nonlocal skipped
        if not isinstance(node, dict):
            return
        req = requirements(node, inherited)
        if req is None:
            skipped += 1
            return
        kind, identity = node.get("_kind"), node.get("_id")
        vendor_section = vendor_section or (kind == "h" and identity == -58)
        points = coords(node)
        npc = parent_npc
        if kind == "n" and isinstance(identity, int) and identity > 0:
            npc = {"npcID": identity, "name": names["n"].get(identity, "NPC " + str(identity)), "points": points}
            for map_id, x, y in points:
                record = {"npcID": identity, "name": npc["name"], "mapID": map_id, "x": x, "y": y, "requirements": req}
                npcs[lua(record)] = record
        if kind == "q" and isinstance(identity, int) and identity > 0:
            quest_source = {"questID": identity, "name": names["q"].get(identity, "Quest " + str(identity)),
                            "requirements": req, "qgs": values(node.get("qgs"))}
            if node.get("isDaily") or node.get("repeatable"):
                quest_source["repeatable"] = True
            quest_sources[lua(quest_source)] = quest_source
            for map_id, x, y in points:
                record = {"questID": identity, "name": names["q"].get(identity, "Quest " + str(identity)),
                          "mapID": map_id, "x": x, "y": y, "requirements": req,
                          "role": "reference"}
                if node.get("isDaily") or node.get("repeatable"):
                    record["repeatable"] = True
                quests[lua(record)] = record
        if vendor_section and npc and npc["points"] and kind in ("i", "s", "r", "de", "en", "ens", "toy", "mnt", "p", "cu"):
            for cost in values(node.get("cost")):
                cost_values = values(cost)
                if len(cost_values) >= 3 and cost_values[0] == "c" and isinstance(cost_values[1], int) and cost_values[1] > 0:
                    for map_id, x, y in npc["points"]:
                        record = {"npcID": npc["npcID"], "name": npc["name"], "mapID": map_id,
                                  "x": x, "y": y, "currencyID": cost_values[1], "requirements": req}
                        vendors[lua(record)] = record
        for child in values(node) + values(node.get("g")):
            walk(child, req, npc, vendor_section)

    excluded = {"NeverImplemented", "Unsorted", "HiddenQuestTriggers", "HiddenAchievementTriggers"}
    for path in sorted((source / "db/Standard/Categories").glob("*.lua")):
        if path.stem in excluded:
            continue
        raw = path.read_bytes()
        text = raw.decode("utf-8-sig")
        match = re.search(r"categories\.\w+\s*=", text)
        if not match:
            continue
        try:
            tree = LuaDataParser(text[match.end():]).value()
        except ValueError as error:
            raise ValueError(f"{path.name}: {error}") from error
        walk(tree, {})
        provenance.append((str(path.relative_to(source)), hashlib.sha256(raw).hexdigest()))
        print(path.name, "vendors", len(vendors), "quests", len(quests), "npcs", len(npcs), flush=True)
    # Quest coordinates have no universal endpoint-role contract. Givers use
    # the independently documented NPC positions joined through qgs instead.
    npc_points = {}
    for npc in npcs.values():
        npc_points.setdefault(npc["npcID"], []).append(npc)
    for quest in quest_sources.values():
        for npc_id in quest["qgs"]:
            if not isinstance(npc_id, int) or npc_id <= 0:
                continue
            for npc in npc_points.get(npc_id, []):
                combined = combine_requirements(quest["requirements"], npc["requirements"])
                if combined is None:
                    continue
                record = {"questID": quest["questID"], "name": quest["name"], "npcID": npc_id,
                          "mapID": npc["mapID"], "x": npc["x"], "y": npc["y"], "role": "giver", "requirements": combined}
                if quest.get("repeatable"):
                    record["repeatable"] = True
                quests[lua(record)] = record
    requirement_keys = sorted({lua(row["requirements"]) for entries in (vendors, quests, npcs) for row in entries.values()})
    requirement_ids = {key: index for index, key in enumerate(requirement_keys, 1)}
    lines = ["-- Generated by scripts/generate_destination_catalog.py. Do not edit.",
             "-- MIT data: AllTheThings WoW Addon; see Licenses/AllTheThings-MIT.txt.",
             "local ADDON_NAME, QR = ...", "local R = {"]
    lines.extend(key + "," for key in requirement_keys)
    lines.extend(["}", "QR.DestinationCatalog = {", f"source={lua(SOURCE)},revision={lua(REVISION)},build={BUILD},"])
    for category, entries in (("vendors", vendors), ("quests", quests), ("npcs", npcs)):
        lines.append(category + "={")
        for entry in sorted(entries.values(), key=lambda row: (row["name"].lower(), row.get("questID", row.get("npcID")), row["mapID"], row["x"], row["y"], lua(row["requirements"]))):
            req = entry.pop("requirements")
            lines.append(lua(entry)[:-1] + f",requirements=R[{requirement_ids[lua(req)]}]" + "},")
        lines.append("},")
    lines.append("}")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    license_path = output.parent.parent / "Licenses/AllTheThings-MIT.txt"
    license_path.parent.mkdir(exist_ok=True)
    license_path.write_text((source / "LICENSE").read_text(), encoding="utf-8")
    manifest = output.with_suffix(".sources.txt")
    names_tree = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD:.contrib/Parser/DATAS"], text=True).strip()
    manifest.write_text(f"Source: {SOURCE}\nRevision: {REVISION}\nName source tree: .contrib/Parser/DATAS {names_tree}\nBuild: {BUILD}\nExcluded dynamic/unavailable branches: {skipped}\n"
                        + "\n".join(f"{digest}  {path}" for path, digest in provenance) + "\n", encoding="utf-8")
    print("Wrote", output, output.stat().st_size, "bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "QuickRoute/Data/DestinationCatalog.lua")
    options = parser.parse_args()
    generate(options.source, options.output)
