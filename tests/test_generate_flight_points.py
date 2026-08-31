#!/usr/bin/env python3
"""Tests for scripts/generate_flight_points.py.

The generator decides which taxi nodes are flight masters, which zone each one
belongs to and where in that zone it sits. None of that was reachable from the
Lua suite, which only validates the shape of the file the generator produced --
so a filter could be inverted, the ranking dropped or the projection transposed
and the only signal would be that the committed data looked slightly different.

Run: python3 -m unittest discover -s tests -p 'test_*.py'
"""

import csv
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "generate_flight_points.py")

spec = importlib.util.spec_from_file_location("generate_flight_points", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


class ProjectionTest(unittest.TestCase):
    """The UI axes are the transpose of the world axes and both run backwards."""

    # One zone box: world x 0..100, world y 0..200, filling the whole ui square.
    BOX = dict(x0=0.0, y0=0.0, x1=100.0, y1=200.0, a0=0.0, b0=0.0, a1=1.0, b1=1.0)

    def project(self, px, py):
        return gen.project(px, py, **self.BOX)

    def test_ui_x_comes_from_world_y_and_runs_backwards(self):
        # Moving in world Y must move ui x, and increasing Y must lower it.
        low = self.project(50.0, 0.0)[0]
        high = self.project(50.0, 200.0)[0]
        self.assertAlmostEqual(low, 1.0)
        self.assertAlmostEqual(high, 0.0)

    def test_ui_y_comes_from_world_x_and_runs_backwards(self):
        low = self.project(0.0, 100.0)[1]
        high = self.project(100.0, 100.0)[1]
        self.assertAlmostEqual(low, 1.0)
        self.assertAlmostEqual(high, 0.0)

    def test_world_x_does_not_move_ui_x(self):
        # The defect that shipped: reading the axes straight through. If ui x
        # tracked world X this would differ.
        self.assertAlmostEqual(self.project(0.0, 100.0)[0], self.project(100.0, 100.0)[0])

    def test_a_transposition_is_visible_off_the_diagonal(self):
        # A point away from the diagonal, so swapping x and y actually moves it.
        x, y = self.project(25.0, 20.0)
        self.assertNotAlmostEqual(x, y, places=2)

    def test_degenerate_span_does_not_divide_by_zero(self):
        box = dict(self.BOX, x1=0.0)
        self.assertEqual(gen.project(0.0, 100.0, **box)[1], box["b0"])


class NameRuleTest(unittest.TestCase):
    def test_related_accepts_an_abbreviation(self):
        self.assertTrue(gen.related("Elwynn Forest", "Elwynn"))
        self.assertTrue(gen.related("Arathi", "Arathi Highlands"))

    def test_related_accepts_a_leading_or_trailing_qualifier(self):
        # The client and UiMap disagree about articles and qualifiers far more
        # often than about the place. A prefix test rejected all of these and
        # shipped the zones with no flight master at all.
        for zone, stated in (
            ("The Azure Span", "Azure Span"),
            ("Emerald Dream", "The Emerald Dream"),
            ("The Jade Forest", "Jade Forest"),
            ("Mount Hyjal", "Hyjal"),
            ("Ruins of Gilneas", "Gilneas"),
            ("Northern Stranglethorn", "Stranglethorn"),
            ("The Cape of Stranglethorn", "Stranglethorn"),
        ):
            self.assertTrue(gen.related(zone, stated), f"{zone} vs {stated}")

    def test_related_rejects_a_different_zone(self):
        # The border cases the rule exists for. Loosening to substring must not
        # cost any of these.
        for zone, stated in (
            ("Searing Gorge", "Badlands"),
            ("Broken Shore", "Dalaran"),
            ("Deadwind Pass", "Duskwood"),
            ("Mulgore", "Southern Barrens"),
            ("Durotar", "Northern Barrens"),
            ("Swamp of Sorrows", "Blasted Lands"),
        ):
            self.assertFalse(gen.related(zone, stated), f"{zone} vs {stated}")


class FixtureMixin:
    """A minimal but complete input set, one world map, two zones."""

    ZONE_A, ZONE_B, ZONE_C = 100, 200, 300

    def build_inputs(self, taxi_rows, path_rows=None):
        directory = tempfile.mkdtemp()
        write_csv(
            os.path.join(directory, "TaxiNodes.csv"),
            ["Name_lang", "Pos_0", "Pos_1", "ID", "ContinentID", "Flags"],
            taxi_rows,
        )
        if path_rows is None:
            # Give every node enough neighbours to survive the degree filter.
            ids = [r["ID"] for r in taxi_rows]
            path_rows = []
            for i, node in enumerate(ids):
                for other in ids:
                    if other != node:
                        path_rows.append({"FromTaxiNode": node, "ToTaxiNode": other})
        write_csv(
            os.path.join(directory, "TaxiPath.csv"),
            ["FromTaxiNode", "ToTaxiNode"], path_rows,
        )
        write_csv(
            os.path.join(directory, "UiMap.csv"),
            ["Name_lang", "ID", "Type"],
            [
                {"Name_lang": "Alpha Vale", "ID": str(self.ZONE_A), "Type": "3"},
                {"Name_lang": "Beta Reach", "ID": str(self.ZONE_B), "Type": "3"},
                {"Name_lang": "Gamma Hold", "ID": str(self.ZONE_C), "Type": "3"},
            ],
        )
        write_csv(
            os.path.join(directory, "UiMapAssignment.csv"),
            ["UiMapID", "MapID", "Region_0", "Region_1", "Region_3", "Region_4",
             "UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"],
            [
                {"UiMapID": str(self.ZONE_A), "MapID": "1",
                 "Region_0": "0", "Region_1": "0", "Region_3": "100", "Region_4": "100",
                 "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1"},
                {"UiMapID": str(self.ZONE_B), "MapID": "1",
                 "Region_0": "200", "Region_1": "200", "Region_3": "300", "Region_4": "300",
                 "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1"},
                # A small zone nested inside Beta Reach. Zone boxes really do
                # overlap -- a city sits inside the zone around it -- so the
                # fixture has to contain a case where "smallest wins" decides,
                # or that rule and the containment test are both invisible.
                {"UiMapID": str(self.ZONE_C), "MapID": "1",
                 "Region_0": "240", "Region_1": "240", "Region_3": "260", "Region_4": "260",
                 "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1"},
                # Alpha Vale again, on a SECOND world map. Real zones do this
                # -- UiMap 376 is assigned to MapID 870 and 1157 -- and it is
                # the only shape that can tell the alternate's own continentID
                # apart from the primary's.
                {"UiMapID": str(self.ZONE_A), "MapID": "2",
                 "Region_0": "0", "Region_1": "0", "Region_3": "100", "Region_4": "100",
                 "UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1"},
            ],
        )
        return directory

    @staticmethod
    def node(node_id, name, x, y, flags="3", continent="1"):
        return {"Name_lang": name, "Pos_0": str(x), "Pos_1": str(y),
                "ID": str(node_id), "ContinentID": continent, "Flags": flags}


class FilterTest(FixtureMixin, unittest.TestCase):
    def resolve(self, taxi_rows, path_rows=None):
        directory = self.build_inputs(taxi_rows, path_rows)
        gen.MIN_ZONES = 0          # the fixture is deliberately tiny
        return gen.build(directory)

    def test_a_flight_master_is_kept(self):
        # Three nodes, so each has the two neighbours a flight master needs.
        result = self.resolve([
            self.node(1, "Havenhold, Alpha Vale", 50, 50),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertIn(self.ZONE_A, result)
        self.assertEqual(result[self.ZONE_A]["name"], "Havenhold, Alpha Vale")

    def test_an_internal_flagged_node_is_dropped(self):
        result = self.resolve([
            self.node(1, "Havenhold, Alpha Vale", 50, 50, flags="1027"),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertNotIn(self.ZONE_A, result)

    def test_a_node_shown_to_no_faction_is_dropped(self):
        result = self.resolve([
            self.node(1, "Havenhold, Alpha Vale", 50, 50, flags="0"),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertNotIn(self.ZONE_A, result)

    def test_a_bracketed_internal_name_is_dropped(self):
        result = self.resolve([
            self.node(1, "[Hidden] Travel Network, Alpha Vale", 50, 50),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertNotIn(self.ZONE_A, result)

    def test_a_lone_node_is_dropped(self):
        # One neighbour is a scripted flight, not a flight master.
        result = self.resolve(
            [self.node(1, "Havenhold, Alpha Vale", 50, 50),
             self.node(2, "Farpost, Beta Reach", 250, 250)],
            path_rows=[{"FromTaxiNode": "1", "ToTaxiNode": "2"}],
        )
        self.assertEqual(result, {})

    def test_a_name_naming_another_zone_is_dropped(self):
        # The New Kargath case: geometry says Alpha Vale, the name says Beta
        # Reach, so the row is thrown away rather than guessed at.
        result = self.resolve([
            self.node(1, "Outpost, Beta Reach", 50, 50),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertNotIn(self.ZONE_A, result)

    def test_a_corroborating_name_outranks_a_bare_one(self):
        # The Broken Shore case: the bare name has more neighbours, and still
        # loses to the one that names the zone.
        rows = [
            self.node(1, "Elsewhere", 50, 50),
            self.node(2, "Havenhold, Alpha Vale", 60, 60),
            self.node(3, "Farpost, Beta Reach", 250, 250),
            self.node(4, "Waypost, Beta Reach", 260, 260),
        ]
        paths = [{"FromTaxiNode": "1", "ToTaxiNode": t} for t in ("2", "3", "4")]
        paths += [{"FromTaxiNode": "2", "ToTaxiNode": "3"}]
        paths += [{"FromTaxiNode": "3", "ToTaxiNode": "4"}]
        result = self.resolve(rows, paths)
        self.assertEqual(result[self.ZONE_A]["name"], "Havenhold, Alpha Vale")


    def test_the_smallest_containing_zone_wins(self):
        # (250, 250) is inside Beta Reach and inside the smaller Gamma Hold
        # nested in it. The smaller box is the answer; taking the larger one
        # would file every city flight master under the zone around it.
        result = self.resolve([
            self.node(1, "Keep, Gamma Hold", 250, 250),
            self.node(2, "Havenhold, Alpha Vale", 50, 50),
            self.node(3, "Outpost, Alpha Vale", 60, 60),
        ])
        self.assertIn(self.ZONE_C, result)
        self.assertNotIn(self.ZONE_B, result)

    def test_a_node_outside_every_zone_is_dropped(self):
        result = self.resolve([
            self.node(1, "Nowhere, Alpha Vale", 5000, 5000),
            self.node(2, "Havenhold, Alpha Vale", 50, 50),
            self.node(3, "Outpost, Alpha Vale", 60, 60),
        ])
        self.assertEqual(len(result), 1)
        self.assertIn(self.ZONE_A, result)

    def test_the_most_connected_node_represents_its_zone(self):
        # Both names corroborate, so the corroboration tier cannot decide and
        # the degree has to. Reversing the direction picks Quietpost, which is
        # what shipped for 84 of 134 zones under an untested ranking.
        rows = [
            self.node(1, "Busypost, Alpha Vale", 50, 50),
            self.node(2, "Quietpost, Alpha Vale", 60, 60),
            self.node(3, "Farpost, Beta Reach", 250, 250),
            self.node(4, "Waypost, Beta Reach", 260, 260),
        ]
        # Busypost: 3 neighbours. Quietpost: 2.
        paths = [{"FromTaxiNode": "1", "ToTaxiNode": t} for t in ("2", "3", "4")]
        paths += [{"FromTaxiNode": "2", "ToTaxiNode": "3"}]
        paths += [{"FromTaxiNode": "3", "ToTaxiNode": "4"}]
        result = self.resolve(rows, paths)
        self.assertEqual(result[self.ZONE_A]["name"], "Busypost, Alpha Vale")

    def test_equal_candidates_are_broken_by_the_lowest_node_id(self):
        # Same name shape, same degree: the tie-break is the only thing left,
        # and it has to be stable or regeneration churns the data file.
        rows = [
            self.node(7, "Sevenpost, Alpha Vale", 50, 50),
            self.node(3, "Threepost, Alpha Vale", 60, 60),
            self.node(9, "Farpost, Beta Reach", 250, 250),
        ]
        paths = []
        for a in ("7", "3", "9"):
            for b in ("7", "3", "9"):
                if a != b:
                    paths.append({"FromTaxiNode": a, "ToTaxiNode": b})
        result = self.resolve(rows, paths)
        self.assertEqual(result[self.ZONE_A]["name"], "Threepost, Alpha Vale")


    def test_a_single_faction_node_is_kept(self):
        # flags 2 is Horde-only. Narrowing the mask to 0x1 keeps every fixture
        # node here green while dropping ten real zones, so the mask's VALUE
        # needs a node that only one faction can see.
        result = self.resolve([
            self.node(1, "Warpost, Alpha Vale", 50, 50, flags="2"),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        self.assertIn(self.ZONE_A, result)

    def test_a_city_named_for_the_zone_around_it_is_kept(self):
        # "Ironforge, Dun Morogh" is in the Ironforge zone: the place part
        # names the zone, the stated part names the zone around it. Dropping
        # this branch costs seven capitals and both suites stay green, because
        # the Lua capitals guard reads the committed file rather than the
        # generator.
        result = self.resolve([
            self.node(1, "Gamma Hold, Beta Reach", 250, 250),
            self.node(2, "Havenhold, Alpha Vale", 50, 50),
            self.node(3, "Outpost, Alpha Vale", 60, 60),
        ])
        self.assertIn(self.ZONE_C, result)
        self.assertEqual(result[self.ZONE_C]["name"], "Gamma Hold, Beta Reach")


    def test_each_faction_keeps_its_own_flight_master(self):
        # The Hinterlands case: two masters in one zone, one per faction, in
        # different places. Collapsing to one entry lost the other side's in 45
        # of 141 real zones.
        result = self.resolve([
            self.node(1, "Alliancepost, Alpha Vale", 50, 50, flags="1"),
            self.node(2, "Hordepost, Alpha Vale", 60, 60, flags="2"),
            self.node(3, "Farpost, Beta Reach", 250, 250),
        ])
        entry = result[self.ZONE_A]
        self.assertIn(entry["faction"], ("Alliance", "Horde"))
        self.assertIsNotNone(entry["alt"], "the other faction's master survives")
        self.assertNotEqual(entry["faction"], entry["alt"]["faction"])
        self.assertNotEqual(entry["name"], entry["alt"]["name"])

    def test_a_node_both_factions_use_needs_no_alternate(self):
        result = self.resolve([
            self.node(1, "Havenhold, Alpha Vale", 50, 50, flags="3"),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        entry = result[self.ZONE_A]
        self.assertEqual("both", entry["faction"])
        self.assertIsNone(entry["alt"])

    def test_a_one_faction_zone_stays_one_faction(self):
        result = self.resolve([
            self.node(1, "Hordepost, Alpha Vale", 50, 50, flags="2"),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        entry = result[self.ZONE_A]
        self.assertEqual("Horde", entry["faction"])
        self.assertIsNone(entry["alt"], "there is no Alliance master to record")


class EmitTest(FixtureMixin, unittest.TestCase):
    """What build() decides has to survive being written out.

    Nothing covered emit() before: deleting the whole alt tail -- all 45
    alternates, the entire payload of the faction work -- or stamping
    faction = "both" on every row left both suites green, because the Python
    tests only exercised build() and the Lua tests read a committed file that
    no job regenerates.
    """

    def render(self, taxi_rows, path_rows=None):
        directory = self.build_inputs(taxi_rows, path_rows)
        gen.MIN_ZONES = 0
        final = gen.build(directory)
        out = os.path.join(directory, "out.lua")
        gen.emit(final, out)
        with open(out, encoding="utf-8") as handle:
            return handle.read()

    def two_faction_zone(self):
        return [
            self.node(1, "Alliancepost, Alpha Vale", 50, 50, flags="1"),
            self.node(2, "Hordepost, Alpha Vale", 60, 60, flags="2"),
            self.node(3, "Farpost, Beta Reach", 250, 250),
        ]

    def test_the_alternate_reaches_the_file(self):
        text = self.render(self.two_faction_zone())
        self.assertIn("alt = {", text)
        self.assertIn("Alliancepost, Alpha Vale", text)
        self.assertIn("Hordepost, Alpha Vale", text)

    def test_every_entry_states_a_faction(self):
        text = self.render(self.two_faction_zone())
        entries = [line for line in text.splitlines() if line.startswith("    [")]
        self.assertTrue(entries)
        for line in entries:
            self.assertIn("faction = ", line, line)
        self.assertNotIn('faction = "both", alt', text)

    def test_the_alternate_states_the_other_faction(self):
        text = self.render(self.two_faction_zone())
        line = next(l for l in text.splitlines() if "alt = {" in l)
        primary = line.split("faction = ")[1].split(",")[0].strip()
        alternate = line.split("alt = {")[1].split('faction = ')[1].split("}")[0].strip()
        self.assertNotEqual(primary, alternate)
        self.assertIn(primary, ('"Alliance"', '"Horde"'))

    def test_the_alternate_carries_its_own_world_map(self):
        # The two sides on DIFFERENT world maps. Writing the primary's
        # continentID onto the alternate would invert SameFlightNetwork for
        # that player -- every zone on one world map offered, every zone on the
        # other denied. No shipped zone has this shape, so only a fixture can
        # tell the two apart.
        text = self.render([
            self.node(1, "Alliancepost, Alpha Vale", 50, 50, flags="1", continent="1"),
            self.node(2, "Hordepost, Alpha Vale", 60, 60, flags="2", continent="2"),
            self.node(3, "Farpost, Beta Reach", 250, 250),
        ])
        line = next(l for l in text.splitlines() if "alt = {" in l)
        self.assertEqual(2, line.count("continentID = "),
                         "the alternate is self-contained")
        primary, alternate = line.split("continentID = ")[1:3]
        self.assertNotEqual(primary.split(",")[0].strip(),
                            alternate.split(",")[0].strip(),
                            "and it is the alternate's own world map, not the primary's")

    def test_the_header_describes_the_shape_the_file_actually_has(self):
        # The header is prose and reverted silently once already: it kept
        # saying "one entry per zone" for a commit after the collapse became
        # per-faction. Nothing regenerates the committed file in CI, so a stale
        # header is invisible unless asserted here.
        text = self.render(self.two_faction_zone())
        header = text.split("QR.FlightPoints = {")[0]
        self.assertIn("faction", header,
                      "the header names the faction field the rows carry")
        self.assertIn("alt", header,
                      "and the alternate entry")
        self.assertNotIn("One entry per zone:", header,
                         "and no longer claims one entry per zone")

    def test_the_file_still_parses_as_a_lua_table(self):
        text = self.render(self.two_faction_zone())
        self.assertTrue(text.startswith("-- FlightPoints.lua"))
        self.assertIn("QR.FlightPoints = {", text)
        self.assertEqual(text.count("{"), text.count("}"))


class InputGuardTest(FixtureMixin, unittest.TestCase):
    """Broken input must fail loudly. Exit status is what a script reads."""

    def run_generator(self, directory):
        out = os.path.join(directory, "out.lua")
        completed = subprocess.run(
            [sys.executable, SCRIPT, "--csv-dir", directory, "--out", out],
            capture_output=True, text=True,
        )
        return completed, out

    def test_too_few_zones_writes_nothing(self):
        directory = self.build_inputs([
            self.node(1, "Havenhold, Alpha Vale", 50, 50),
            self.node(2, "Farpost, Beta Reach", 250, 250),
            self.node(3, "Waypost, Beta Reach", 260, 260),
        ])
        completed, out = self.run_generator(directory)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("expected at least", completed.stderr)
        self.assertFalse(os.path.exists(out))

    def test_a_missing_column_is_named(self):
        directory = self.build_inputs([self.node(1, "Havenhold, Alpha Vale", 50, 50)])
        write_csv(os.path.join(directory, "TaxiNodes.csv"),
                  ["Name_lang", "Pos_0", "Pos_1", "ID", "ContinentID"],
                  [{"Name_lang": "x", "Pos_0": "0", "Pos_1": "0", "ID": "1", "ContinentID": "1"}])
        completed, _ = self.run_generator(directory)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("Flags", completed.stderr)

    def test_a_ragged_row_is_rejected_not_miscounted(self):
        directory = self.build_inputs([self.node(1, "Havenhold, Alpha Vale", 50, 50)])
        path = os.path.join(directory, "TaxiNodes.csv")
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("Truncated, Alpha Vale,10\n")
        completed, _ = self.run_generator(directory)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("wrong number of fields", completed.stderr)

    def test_a_missing_file_is_named(self):
        directory = self.build_inputs([self.node(1, "Havenhold, Alpha Vale", 50, 50)])
        os.remove(os.path.join(directory, "TaxiPath.csv"))
        completed, _ = self.run_generator(directory)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("missing input", completed.stderr)


if __name__ == "__main__":
    unittest.main()
