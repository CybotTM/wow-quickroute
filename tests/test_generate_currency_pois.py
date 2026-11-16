"""Tests for scripts/generate_currency_pois.py."""
import csv
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("generate_currency_pois", ROOT / "scripts/generate_currency_pois.py")
gen = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gen)


def write(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def assignment(ui_map, region, wmo="0"):
    row = {"UiMin_0": 0, "UiMin_1": 0, "UiMax_0": 1, "UiMax_1": 1, "UiMapID": ui_map, "MapID": "0",
           "WMOGroupID": wmo, "WMODoodadPlacementID": "0"}
    for i, value in enumerate(region):
        row["Region_%d" % i] = value
    return row


class ProjectTest(unittest.TestCase):
    def test_world_position_maps_to_east_and_south(self):
        # Region x (north) 0..100, y (west) 0..200. The point lies 10 below the
        # north edge (map y 0.1) and 50 west of the east edge (map x 0.25).
        rows = [assignment("84", (0, 0, -10, 100, 200, 10))]
        poi = {"ID": "1", "Pos_0": "90", "Pos_1": "150", "Pos_2": "0", "ContinentID": "0"}
        self.assertEqual(gen.project(poi, rows, 84), (0.25, 0.1))

    def test_point_outside_the_named_map_fails(self):
        rows = [assignment("84", (0, 0, -10, 100, 200, 10))]
        poi = {"ID": "1", "Pos_0": "500", "Pos_1": "150", "Pos_2": "0", "ContinentID": "0"}
        with self.assertRaises(ValueError):
            gen.project(poi, rows, 84)

    def test_building_interiors_are_not_used(self):
        rows = [assignment("84", (0, 0, -10, 100, 200, 10), wmo="17")]
        poi = {"ID": "1", "Pos_0": "75", "Pos_1": "150", "Pos_2": "0", "ContinentID": "0"}
        with self.assertRaises(ValueError):
            gen.project(poi, rows, 84)

    def test_generate_writes_one_row_per_spec_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            pois = [{"ID": str(entry[0]), "Name_lang": "Post %d" % entry[0], "Pos_0": "75", "Pos_1": "150",
                     "Pos_2": "0", "ContinentID": "0"} for entry in gen.SPEC]
            write(directory / "AreaPOI.csv", pois)
            write(directory / "UiMapAssignment.csv",
                  [assignment(str(entry[1]), (0, 0, -10, 100, 200, 10)) for entry in gen.SPEC])
            write(directory / "UiMap.csv", [{"ID": str(entry[1]), "Name_lang": "Map"} for entry in gen.SPEC])
            text = gen.generate("1.2.3", directory)
        self.assertEqual(len(gen.SPEC), text.count("areaPoiID = "))
        self.assertIn("build 1.2.3", text)


if __name__ == "__main__":
    unittest.main()
