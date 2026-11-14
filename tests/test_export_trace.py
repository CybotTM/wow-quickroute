"""Tests for scripts/export_trace.py.

The SavedVariables files are produced by the addon itself: tests/make_trace_fixture.lua
loads it on the mock client of each flavor, turns the trace on and drives a short
session through the client's entry points. Nothing here is hand-written Lua data.
"""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import export_trace  # noqa: E402
from import_zone_survey import default_lua  # noqa: E402

LUA = default_lua()


def make_fixture(flavor, directory):
    path = os.path.join(directory, f"QuickRoute_{flavor}.lua")
    result = subprocess.run([LUA, os.path.join(HERE, "make_trace_fixture.lua"), flavor, path],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise AssertionError(f"fixture for {flavor} failed: {result.stderr}")
    return path


class ExportTraceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.retail = make_fixture("retail", cls.tmp.name)
        cls.forever = make_fixture("forever", cls.tmp.name)
        cls.out = os.path.join(cls.tmp.name, "trace.jsonl")
        report = io.StringIO()
        with contextlib.redirect_stdout(report):
            code = export_trace.main(["-o", cls.out, "--lua", LUA, cls.retail, cls.forever])
        cls.code = code
        cls.report = report.getvalue()
        with open(cls.out, encoding="utf-8") as handle:
            cls.records = [json.loads(line) for line in handle]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_record_names_its_client(self):
        self.assertEqual(0, self.code)
        by_source = {}
        for record in self.records:
            by_source.setdefault(record["source"], set()).add(record["flavor"])
        self.assertEqual({"retail"}, by_source[self.retail])
        self.assertEqual({"forever"}, by_source[self.forever])

    def test_records_are_in_order_with_their_fields(self):
        retail = [r for r in self.records if r["source"] == self.retail]
        self.assertEqual(list(range(1, len(retail) + 1)), [r["seq"] for r in retail])
        self.assertEqual("session", retail[0]["category"])
        times = [r["gameTime"] for r in retail]
        self.assertEqual(sorted(times), times)
        accepted = [r for r in retail if r.get("message") == "QUEST_ACCEPTED"]
        self.assertEqual(1, len(accepted))
        self.assertEqual(4711, accepted[0]["fields"]["a1"])

    def test_window_open_names_its_reason(self):
        opens = [r for r in self.records
                 if r["category"] == "window" and r["fields"].get("action") == "show"]
        self.assertEqual(2, len(opens), "one auto-show per client")
        for record in opens:
            self.assertEqual("waypoint-auto:SUPER_TRACKING_CHANGED", record["fields"]["reason"])
        self.assertEqual(2, self.report.count("reason=waypoint-auto:SUPER_TRACKING_CHANGED"))

    def test_summary_lists_the_two_seconds_before_an_open(self):
        records = [r for r in self.records if r["source"] == self.retail]
        opens = export_trace.window_opens(records)
        self.assertEqual(1, len(opens))
        _, before = opens[0]
        messages = [r.get("message") for r in before]
        self.assertIn("QUEST_ACCEPTED", messages)
        self.assertIn("GOSSIP_SHOW", messages)
        # Four seconds before the open: outside the window.
        self.assertNotIn("QUEST_DETAIL", messages)
        self.assertTrue(any(r["message"] == "QUEST_DETAIL" for r in records),
                        "the event is in the trace, only not in the window")

    def test_a_repeated_log_line_is_one_record_with_its_last_time(self):
        records = [r for r in self.records if r["source"] == self.retail]
        repeated = [r for r in records if r.get("message") == "fixture: repeated line"]
        self.assertEqual(1, len(repeated), "two occurrences, one record")
        record = repeated[0]
        self.assertEqual("log", record["category"])
        self.assertEqual(2, record["repeats"])
        self.assertAlmostEqual(3.5, record["lastGameTime"] - record["gameTime"], places=3)
        self.assertIn("lastTime", record)
        # Merged into the structured entries by write order, not appended.
        position = records.index(record)
        self.assertEqual("QUEST_DETAIL", records[position + 1].get("message"))
        folded = sum(r["repeats"] - 1 for r in records if r.get("repeats"))
        self.assertGreaterEqual(folded, 1)
        self.assertIn(f"retail, {len(records)} entries, 0 dropped by the cap, 0 log lines dropped by theirs, "
                      f"{folded} repeated log lines folded", self.report)

    def test_a_repeat_inside_the_look_back_is_listed_before_the_open(self):
        records = [r for r in self.records if r["source"] == self.retail]
        _, before = export_trace.window_opens(records)[0]
        messages = [r.get("message") for r in before]
        self.assertIn("fixture: repeated line", messages,
                      "first seen 4.5 s before the open, last seen 1 s before it")
        self.assertIn("log: fixture: repeated line (x2)", self.report)

    def test_summary_counts_per_flavor_and_category(self):
        self.assertIn("Entries per flavor and category:", self.report)
        self.assertRegex(self.report, r"retail\s+window\s+\d+")
        self.assertRegex(self.report, r"forever\s+window\s+\d+")

    def test_refuses_to_overwrite_its_input(self):
        with self.assertRaises(SystemExit):
            export_trace.main(["-o", self.retail, "--lua", LUA, self.retail])

    def test_file_without_trace_exports_nothing(self):
        path = os.path.join(self.tmp.name, "empty.lua")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write('QuickRouteDB = {\n\t["diagnosticTrace"] = false,\n}\n')
        records, headers = export_trace.load_records(LUA, [path])
        self.assertEqual([], records)
        self.assertEqual("unknown", headers[0]["flavor"])


if __name__ == "__main__":
    unittest.main()
