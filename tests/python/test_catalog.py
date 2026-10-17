"""Unit tests for tools/ingame/catalog.py: surface families and the generated catalogue page."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "ingame"))
import catalog  # noqa: E402


def spot(kind, fam, **kw):
    s = {"kind": kind, "family": fam, "pos": {"x": 1.0, "y": 2.0, "z": 3.0}, "dir": {"x": 0.0, "y": 1.0},
         "metrics": {"length": 120.0, "width": 8.0, "spanM": "96 x 80", "turnDeg": -160, "minRadius": 12,
                     "direction": "right", "shape": "hairpin", "gradePct": 8.0},
         "surfaces": [], "room": [50] * 8, "slopeDeg": 1.0}
    s.update(kw)
    return s


class FamilyTest(unittest.TestCase):
    def test_majority_of_the_wheels_decides(self):
        self.assertEqual(catalog.family(["DIRT_DUSTY", "DIRT", "GRASS", "DIRT_DUSTY"]), "dirt")
        self.assertEqual(catalog.family(["ASPHALT", "ASPHALT_WET", "ASPHALT", "GRAVEL"]), "tarmac")
        self.assertEqual(catalog.family(["SNOW"] * 4), "snow")

    def test_a_tie_is_mixed_and_wheels_in_the_air_are_ignored(self):
        self.assertEqual(catalog.family(["ASPHALT", "ASPHALT", "GRAVEL", "GRAVEL"]), "mixed")
        self.assertEqual(catalog.family(["-1", "-1", "ICE", "ICE"]), "ice")
        self.assertEqual(catalog.family(["-1"] * 4), "other")
        self.assertEqual(catalog.family(["METAL"] * 4), "other")


class ClearTest(unittest.TestCase):
    def test_room_along_each_axis_counts_both_ways(self):
        # Near the fence of a 64 m arena: short behind, long ahead (measured at the BMP dirt arena).
        self.assertTrue(catalog.is_clear([150, 150, 32, 16, 10, 15, 43, 85]))
        # In a forest lane: long ahead and behind, trees close on both sides.
        self.assertFalse(catalog.is_clear([150, 8, 5, 8, 150, 6, 4, 9]))


class RenderTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.old = catalog.CATALOG, catalog.DOC
        catalog.CATALOG = Path(self.dir.name) / "venue-catalog.json"
        catalog.DOC = Path(self.dir.name) / "VENUE_CATALOG.md"

    def tearDown(self):
        catalog.CATALOG, catalog.DOC = self.old
        self.dir.cleanup()

    def write(self, maps):
        catalog.CATALOG.write_text(json.dumps({"schemaVersion": 1, "maps": maps}), encoding="utf-8")

    def test_page_groups_by_surface_and_kind_and_hides_cluttered_ground(self):
        self.write({"test_map": {"level": "test_map", "community": False, "surveyed": "2026-10-16", "game": "0.39.4",
                                 "spots": [spot("hairpin", "snow", fit={"drill": "C04", "fits": True, "problems": [], "notes": []}),
                                           spot("open", "tarmac", clear=True),
                                           spot("open", "dirt", clear=False)]}})
        catalog.render()
        page = catalog.DOC.read_text(encoding="utf-8")
        self.assertIn("## Snow", page)
        self.assertIn("### Hairpins", page)
        self.assertIn("**C04 fits**", page)
        self.assertIn("160° right, r 12 m, hairpin", page)
        self.assertIn("## Tarmac", page)
        self.assertNotIn("## Dirt", page)  # the only dirt spot is cluttered open ground
        self.assertIn("| snow | – | – | – | `test_map` |", page)

    def test_community_maps_are_labelled(self):
        self.write({"forest": {"level": "forest", "community": True, "surveyed": "2026-10-16", "game": "0.39.4",
                               "spots": [spot("corner", "dirt")]}})
        catalog.render()
        self.assertIn("community map: needs installing", catalog.DOC.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
