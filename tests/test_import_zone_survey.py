#!/usr/bin/env python3
"""End-to-end tests for scripts/import_zone_survey.py and the generator's apply step.

The retail case reads tests/fixtures/zone_survey_retail_excerpt.lua, three
zoneSurvey records copied verbatim from a retail SavedVariables file. The
Forever cases write a SavedVariables file shaped like the survey's own, with
Forever map IDs and coordinates read from QuickRoute/Data/Forever.

Run: python3 -m unittest discover -s tests -p 'test_*.py'
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")
sys.path.insert(0, SCRIPTS)
FIXTURE = os.path.join(HERE, "fixtures", "zone_survey_retail_excerpt.lua")
CAMELOT = os.path.join(HERE, "..", "QuickRoute", "QuickRoute_Camelot.toc")


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


imp = load("import_zone_survey")
gen = load("generate_forever_data")
LUA = imp.default_lua()


def forever_data():
    return imp.run_export(LUA, CAMELOT)


class ImportCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="quickroute-survey-test-")
        self.addCleanup(self.tmp.cleanup)
        self.observations = os.path.join(self.tmp.name, "observations.json")

    def run_import(self, saved_variables):
        result = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "import_zone_survey.py"), saved_variables,
             "--observations", self.observations, "--lua", LUA],
            capture_output=True, text=True, check=False)
        self.assertEqual(0, result.returncode, result.stderr)
        with open(self.observations, encoding="utf-8") as handle:
            return json.load(handle), result.stderr

    def survey_file(self, records):
        """A SavedVariables file in the survey's layout: [to] = { from = { [from] = {...} } }."""
        lines = ["QuickRouteDB = {", '["zoneSurvey"] = {']
        for to_map, record in records.items():
            lines.append(f"[{to_map}] = {{")
            lines.append(f'["x"] = {record["x"]},')
            lines.append(f'["y"] = {record["y"]},')
            lines.append('["from"] = {')
            for from_map, entry in record["from"].items():
                lines.append(f"[{from_map}] = {{")
                lines.append(f'["walked"] = {entry.get("walked", 0)},')
                lines.append(f'["loaded"] = {entry.get("loaded", 0)},')
                if entry.get("endpoints"):
                    lines.append('["endpoints"] = {')
                    for i, door in enumerate(entry["endpoints"]):
                        lines.append(f'["k{i}"] = {{ ["fromX"] = {door[0]}, ["fromY"] = {door[1]}, '
                                     f'["toX"] = {door[2]}, ["toY"] = {door[3]}, ["count"] = {door[4]} }},')
                    lines.append("},")
                lines.append("},")
            lines.append("},")
            lines.append("},")
        lines += ["},", "}"]
        path = os.path.join(self.tmp.name, "QuickRoute.lua")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        return path


class RetailFileTest(ImportCase):
    def test_retail_records_are_rejected(self):
        observations, report = self.run_import(FIXTURE)
        self.assertEqual([], observations["crossings"])
        # 32 <- 36, 2492 <- 2395, and five origins into 12: seven crossings.
        self.assertIn("rejected: not a Forever zone                : 7", report)
        self.assertNotIn("accepted", report)


class ForeverWalkTest(ImportCase):
    def riverglades_walk(self, walked):
        data = forever_data()
        point = data["FlightPoints"][2548]   # Riverglades flight master, Forever data
        return self.survey_file({2548: {"x": point["x"], "y": point["y"],
                                        "from": {1433: {"walked": walked}}}}), data

    def test_walk_replaces_a_map_bounds_edge(self):
        path, data = self.riverglades_walk(2)
        before = {e["zone"]: e for e in gen.as_list(data["ZoneAdjacencies"][2548])}
        self.assertEqual("map_bounds", before[1433].get("source"))
        observations, report = self.run_import(path)
        self.assertEqual([{"from": 1433, "to": 2548, "walked": 2, "loaded": 0, "endpoints": []}],
                         observations["crossings"])
        tally = gen.Tally()
        gen.apply_observed_walks(data, observations, tally)
        for source, target in ((2548, 1433), (1433, 2548)):
            edge = next(e for e in data["ZoneAdjacencies"][source] if e["zone"] == target)
            self.assertEqual("surveyed", edge["provenance"], (source, target))
            self.assertEqual("zone_survey", edge["source"], (source, target))
        # Both directions were map_bounds estimates.
        self.assertEqual(2, tally.counts["survey walks"]["applied: replaced a map_bounds edge"])

    def test_a_single_walk_is_not_applied(self):
        path, data = self.riverglades_walk(1)
        observations, _ = self.run_import(path)
        gen.apply_observed_walks(data, observations, gen.Tally())
        edge = next(e for e in data["ZoneAdjacencies"][2548] if e["zone"] == 1433)
        self.assertEqual("map_bounds", edge["source"])

    def test_importing_twice_changes_nothing(self):
        path, _ = self.riverglades_walk(2)
        self.run_import(path)
        with open(self.observations, "rb") as handle:
            first = handle.read()
        self.run_import(path)
        with open(self.observations, "rb") as handle:
            self.assertEqual(first, handle.read())


class ForeverLandingTest(ImportCase):
    def test_landing_refines_the_converted_tram(self):
        data = forever_data()
        stormwind = data["CAPITAL_CITIES"]["Stormwind City"]
        ironforge = data["CAPITAL_CITIES"]["Ironforge"]
        door = (stormwind["x"], stormwind["y"], ironforge["x"], ironforge["y"], 3)
        path = self.survey_file({1455: {"x": ironforge["x"], "y": ironforge["y"],
                                        "from": {1453: {"loaded": 3, "endpoints": [door]}}}})
        observations, _ = self.run_import(path)
        gen.apply_observed_landings(data, observations, gen.Tally())
        tram = next(p for p in data["StandalonePortals"] if p["type"] == "tram")
        self.assertEqual("surveyed", tram["provenance"])
        self.assertEqual((1453, stormwind["x"], stormwind["y"]),
                         (tram["from"]["mapID"], tram["from"]["x"], tram["from"]["y"]))
        self.assertEqual((1455, ironforge["x"], ironforge["y"]),
                         (tram["to"]["mapID"], tram["to"]["x"], tram["to"]["y"]))


if __name__ == "__main__":
    unittest.main()
