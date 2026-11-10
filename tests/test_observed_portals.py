"""Tests for the hand-curated observed portals in scripts/generate_forever_data.py.

A curated portal is added to the Forever StandalonePortals only while the zone
survey holds a loading-screen crossing in the same direction with both ends
within MAX_LANDING_SHIFT_YARDS of the portal's.
"""

import copy
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gen = load("generate_forever_data")

# Yards per whole map along the normalized x and y axes, from Forever's
# UiMapAssignment boxes: Alterac Mountains 1416 and Stormwind City 1453.
MAP_YARDS = {1416: (783.33 + 2016.67, 1500 + 366.67),
             1453: (1722.92 + 14.58, 9154.17 - 7995.83)}

# The crossing as the survey recorded it (scripts/data/forever_zone_survey.json).
CROSSING = {"from": 1416, "to": 1453, "loaded": 1, "walked": 0, "flown": 0, "unverifiedWalks": 0,
            "endpoints": [{"fromX": 0.1209, "fromY": 0.5641, "toX": 0.4987, "toY": 0.8667, "count": 1}]}
PORTAL = {"name": "Portal to Stormwind (Dalaran)",
          "from": {"mapID": 1416, "x": 0.1209, "y": 0.5641},
          "to": {"mapID": 1453, "x": 0.4987, "y": 0.8667},
          "faction": "Alliance", "bidirectional": False, "travelTime": 5, "source": "test"}


def apply(crossings, portals=(PORTAL,)):
    tables = {"StandalonePortals": []}
    tally = gen.Tally()
    gen.apply_observed_portals(tables, {"portals": list(portals)}, {"crossings": crossings},
                               tally, MAP_YARDS)
    return tables["StandalonePortals"], tally


class ObservedPortalTest(unittest.TestCase):
    def test_a_backed_portal_is_added_one_way_for_its_faction(self):
        added, tally = apply([CROSSING])
        self.assertEqual(1, len(added))
        portal = added[0]
        self.assertEqual("portal", portal["type"])
        self.assertEqual("Alliance", portal["faction"])
        self.assertIs(False, portal["bidirectional"])
        self.assertEqual("surveyed", portal["provenance"])
        self.assertEqual("observed_portal", portal["source"])
        self.assertEqual(5, portal["travelTime"])
        self.assertEqual((1416, 0.1209, 0.5641), (portal["from"]["mapID"], portal["from"]["x"], portal["from"]["y"]))
        self.assertEqual((1453, 0.4987, 0.8667), (portal["to"]["mapID"], portal["to"]["x"], portal["to"]["y"]))
        self.assertEqual(1, tally.counts["observed portals"]["added"])

    def test_without_a_crossing_nothing_is_added(self):
        added, tally = apply([])
        self.assertEqual([], added)
        self.assertEqual(1, tally.counts["observed portals"][
            "not added: no matching loading-screen crossing in the survey"])

    def test_a_crossing_the_other_way_does_not_back_it(self):
        reverse = copy.deepcopy(CROSSING)
        reverse["from"], reverse["to"] = 1453, 1416
        added, _ = apply([reverse])
        self.assertEqual([], added)

    def test_a_walk_does_not_back_it(self):
        walk = copy.deepcopy(CROSSING)
        walk["loaded"], walk["walked"] = 0, 1
        added, _ = apply([walk])
        self.assertEqual([], added)

    def test_an_endpoint_too_far_away_does_not_back_it(self):
        # 0.05 of Alterac Mountains along x is 140 yd.
        far = copy.deepcopy(CROSSING)
        far["endpoints"][0]["fromX"] = 0.1209 + 0.05
        added, _ = apply([far])
        self.assertEqual([], added)
        far = copy.deepcopy(CROSSING)
        far["endpoints"][0]["toY"] = 0.8667 - 0.05
        added, _ = apply([far])
        self.assertEqual([], added, "the arrival end is checked too")

    def test_the_checked_in_files_add_the_dalaran_portal(self):
        curated = gen.load_observed_portals(gen.OBSERVED_PORTALS)
        observations = gen.load_observations(gen.OBSERVATIONS)
        tables = {"StandalonePortals": []}
        gen.apply_observed_portals(tables, curated, observations, gen.Tally(), MAP_YARDS)
        names = [p["name"] for p in tables["StandalonePortals"]]
        self.assertEqual(["Portal to Stormwind (Dalaran)"], names)


class CheckedInDataTest(unittest.TestCase):
    """The curated file and the generated Data/Forever/Portals.lua agree.

    Editing scripts/data/forever_observed_portals.json without regenerating
    leaves the addon on the old portal; this fails until both say the same.
    """

    def test_every_curated_portal_is_in_the_generated_data_as_curated(self):
        imp = load("import_zone_survey")
        lua = imp.default_lua()
        camelot = os.path.join(HERE, "..", "QuickRoute", "QuickRoute_Camelot.toc")
        generated = {p["name"]: p for p in gen.as_list(imp.run_export(lua, camelot)["StandalonePortals"])}
        curated = gen.load_observed_portals(gen.OBSERVED_PORTALS)["portals"]
        self.assertGreater(len(curated), 0)
        for entry in curated:
            portal = generated.get(entry["name"])
            self.assertIsNotNone(portal, f"{entry['name']} is in Data/Forever/Portals.lua")
            for end in ("from", "to"):
                self.assertEqual((entry[end]["mapID"], entry[end]["x"], entry[end]["y"]),
                                 (portal[end]["mapID"], portal[end]["x"], portal[end]["y"]), end)
            self.assertEqual(entry["faction"], portal["faction"])
            self.assertEqual(bool(entry.get("bidirectional")), portal["bidirectional"])
            self.assertEqual(entry["travelTime"], portal["travelTime"])
            self.assertEqual("portal", portal["type"])
            self.assertEqual("surveyed", portal["provenance"])


if __name__ == "__main__":
    unittest.main()
