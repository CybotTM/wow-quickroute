#!/usr/bin/env python3
"""Tests for the coordinate conversion in scripts/generate_forever_data.py.

Every converted point in QuickRoute/Data/Forever/ goes retail uiMap + (x, y) ->
world position -> the Forever zone that contains it. The rows below are real:
UiMapAssignment and UiMap rows from retail build 12.1.0.69587 and Forever build
1.60.1.70862 (wago.tools), cut down to the columns the generator reads.

Run: python3 -m unittest discover -s tests -p 'test_*.py'
"""

import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")
sys.path.insert(0, SCRIPTS)

spec = importlib.util.spec_from_file_location(
    "generate_forever_data", os.path.join(SCRIPTS, "generate_forever_data.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def assignment(uimap, map_id, area, x0, y0, x1, y1, row_id):
    return {"UiMin_0": "0", "UiMin_1": "0", "UiMax_0": "1", "UiMax_1": "1",
            "Region_0": x0, "Region_1": y0, "Region_3": x1, "Region_4": y1,
            "ID": row_id, "UiMapID": uimap, "MapID": map_id, "AreaID": area,
            "WMODoodadPlacementID": "0", "WMOGroupID": "0"}


def uimap(uid, name, kind):
    return {"ID": uid, "Name_lang": name, "Type": kind, "System": "0"}


RETAIL_UIMAP = [uimap("13", "Eastern Kingdoms", "2"), uimap("37", "Elwynn Forest", "3"),
                uimap("84", "Stormwind City", "3"), uimap("241", "Twilight Highlands", "3")]
RETAIL_ASSIGNMENTS = [
    assignment("37", "0", "12", "-10254.200195312", "-1935.4200439453",
               "-7939.580078125", "1535.4200439453", "39462"),
    assignment("84", "0", "1519", "-9154.166015625", "-14.583984375",
               "-7995.833984375", "1722.9169921875", "39844"),
    assignment("241", "0", "4922", "-5670.830078125", "-7708.330078125",
               "-2156.25", "-2437.5", "40875"),
]
FOREVER_UIMAP = [uimap("1415", "Eastern Kingdoms", "2"), uimap("1429", "Elwynn Forest", "3"),
                 uimap("1437", "Wetlands", "3"), uimap("1453", "Stormwind City", "3")]
FOREVER_ASSIGNMENTS = [
    assignment("1415", "0", "0", "-16000", "-19199.900390625",
               "7466.6000976562", "16000", "46725"),
    assignment("1429", "0", "12", "-10254.166015625", "-1935.4166259766",
               "-7939.5830078125", "1535.4166259766", "46739"),
    assignment("1437", "0", "11", "-4904.1665039062", "-4525",
               "-2147.9165039062", "-389.58331298828", "46747"),
    assignment("1453", "0", "1519", "-9154.169921875", "-14.58399963379",
               "-7995.830078125", "1722.9200439453", "46763"),
]


def geometry():
    return gen.Geometry(RETAIL_UIMAP, RETAIL_ASSIGNMENTS, FOREVER_UIMAP, FOREVER_ASSIGNMENTS)


class ConversionTest(unittest.TestCase):

    def test_stormwind_flight_master_converts_into_forever_stormwind(self):
        # QuickRoute/Data/FlightPoints.lua, retail [84]: the Stormwind flight
        # master at (0.7098, 0.7297), world (-8841.1, 489.7). Its world position
        # is inside Elwynn Forest's box as well; it belongs to Stormwind City.
        geo = geometry()
        world = geo.to_world(84, 0.7098, 0.7297)
        self.assertEqual("0", world[0])
        self.assertAlmostEqual(-8841.1, world[1], delta=1.0)
        self.assertAlmostEqual(489.7, world[2], delta=1.0)
        fuid, fx, fy = geo.convert(84, 0.7098, 0.7297)
        self.assertEqual(1453, fuid)
        # Classic Stormwind's map frame is the same as retail's.
        self.assertAlmostEqual(0.7098, fx, places=3)
        self.assertAlmostEqual(0.7297, fy, places=3)

    def test_point_of_the_surrounding_zone_stays_in_that_zone(self):
        # The same world position, stated in retail Elwynn Forest coordinates,
        # converts into Forever Elwynn Forest rather than the smaller Stormwind
        # box that also contains it.
        geo = geometry()
        x0, y0, x1, y1, a0, b0, a1, b1 = gen.assignment_geometry(RETAIL_ASSIGNMENTS[0])
        ex, ey = gen.fp.project(-8841.1, 489.7, x0, y0, x1, y1, a0, b0, a1, b1)
        self.assertEqual(1429, geo.convert(37, ex, ey)[0])

    def test_unproject_inverts_project(self):
        x0, y0, x1, y1, a0, b0, a1, b1 = gen.assignment_geometry(FOREVER_ASSIGNMENTS[3])
        for wx, wy in ((-8841.1, 489.7), (-9000.0, 0.0), (-8000.0, 1700.0)):
            ux, uy = gen.fp.project(wx, wy, x0, y0, x1, y1, a0, b0, a1, b1)
            back = gen.unproject(ux, uy, x0, y0, x1, y1, a0, b0, a1, b1)
            self.assertAlmostEqual(wx, back[0], places=6)
            self.assertAlmostEqual(wy, back[1], places=6)

    def test_zone_that_is_not_on_forever_converts_to_nothing(self):
        # Twilight Highlands (Cataclysm) partly lies under Forever Wetlands' box.
        # A point there must not be filed under Wetlands.
        geo = geometry()
        x0, y0, x1, y1, a0, b0, a1, b1 = gen.assignment_geometry(RETAIL_ASSIGNMENTS[2])
        tx, ty = gen.fp.project(-3000.0, -3000.0, x0, y0, x1, y1, a0, b0, a1, b1)
        self.assertIsNotNone(geo.to_forever("0", -3000.0, -3000.0))
        self.assertIsNone(geo.zone(241))
        self.assertIsNone(geo.convert(241, tx, ty))

    def test_zone_mapping_prefers_the_same_area(self):
        geo = geometry()
        self.assertEqual(1453, geo.zone(84))
        self.assertEqual(1429, geo.zone(37))


class InstanceNameTest(unittest.TestCase):

    def test_wings_and_articles_match_the_dungeon_map(self):
        self.assertEqual(gen.instance_key("Dire Maul"), gen.instance_key("Dire Maul - Warpwood Quarter"))
        self.assertEqual(gen.instance_key("Deadmines"), gen.instance_key("The Deadmines"))
        self.assertNotEqual(gen.instance_key("Uldaman"), gen.instance_key("Uldaman: Legacy of Tyr"))


class RequirementTest(unittest.TestCase):
    PHASES = {62: {1: {"artID": 67, "name": "Zidormi (Past Darkshore)"},
                   2: {"artID": 1176, "name": "Zidormi (Present Darkshore)"}}}

    def test_past_phase_requirement_is_dropped_and_present_phase_excluded(self):
        past = {"mapArtID": {"artID": 67, "mapID": 62}, "faction": "Alliance"}
        present = {"mapArtID": {"artID": 1176, "mapID": 62}}
        self.assertEqual({"faction": "Alliance"}, gen.forever_requirements(past, self.PHASES))
        self.assertIsNone(gen.forever_requirements(present, self.PHASES))


if __name__ == "__main__":
    unittest.main()
