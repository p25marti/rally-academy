"""Unit tests for road centre lines from straights and arcs (tools/mapgen/shapes.py)."""
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "mapgen"))
import shapes  # noqa: E402


class RoadTest(unittest.TestCase):
    def test_a_quarter_circle_left_ends_a_radius_across_and_ahead(self):
        pts, _, _ = shapes.road([("L", 30, 90)], heading_deg=0, step=1.0)
        self.assertAlmostEqual(pts[-1][0], 30, delta=0.05)
        self.assertAlmostEqual(pts[-1][1], 30, delta=0.05)

    def test_attributes_apply_per_segment(self):
        pts, bank, zs = shapes.road([("S", 20), ("R", 20, 45, {"bank": 0.1, "z": (0, 2)}), ("S", 20)], step=4.0)
        self.assertEqual(len(pts), len(bank))
        self.assertEqual(bank[1], 0.0)
        self.assertIn(0.1, bank)
        self.assertEqual(zs[-1], 2.0)  # a height is carried on past its segment
        self.assertLess(pts[-1][1], 0)  # a right turn heading +x ends below the x axis

    def test_heading_rotates_the_whole_road(self):
        pts, _, _ = shapes.road([("S", 10)], heading_deg=90, step=5.0)
        self.assertAlmostEqual(pts[-1][0], 0, delta=0.01)
        self.assertAlmostEqual(pts[-1][1], 10, delta=0.01)
        self.assertTrue(all(math.isfinite(c) for p in pts for c in p))


if __name__ == "__main__":
    unittest.main()
