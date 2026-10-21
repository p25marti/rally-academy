"""Unit tests for the drill roads the map builder writes for the mod's racing lines (tools/mapgen/racingline.py)."""
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "mapgen"))
import racingline as RL  # noqa: E402
import shapes  # noqa: E402


def road(*segments):
    """A centre line heading +x from the origin (tools/mapgen/shapes.py), a point every 2 m."""
    return shapes.road(segments, step=2.0)[0]


class DrillRoadsTest(unittest.TestCase):
    def test_points_every_step_with_the_ground_height_width_and_grip(self):
        r = RL.road_samples({"id": "r", "width": 8, "material": "Asphalt"}, road(("S", 99)), lambda x, y: 100 + x / 10)
        self.assertEqual((r["id"], r["width"], r["grip"]), ("r", 8, 1.0))
        self.assertEqual(len(r["points"]), 34)  # 0 to 99 m every 3 m
        x, y, z, tilt = r["points"][10]
        self.assertAlmostEqual(x, 30, places=6)
        self.assertAlmostEqual(z, 103, places=6)
        self.assertAlmostEqual(tilt, 0, places=6)

    def test_tilt_is_the_right_side_above_the_left(self):
        # heading +x, the left is +y: ground rising towards -y is higher on the right
        r = RL.road_samples({"id": "r", "width": 8, "material": "gravel"}, road(("S", 30)), lambda x, y: 100 - 0.12 * y)
        self.assertAlmostEqual(r["points"][3][3], 0.12, places=3)
        self.assertEqual(r["grip"], RL.GRIP["gravel"])

    def test_banked_corner_tilts_into_the_turn(self):
        centre = road(("S", 30), ("L", 30, 90), ("S", 30))

        def banked(x, y):  # higher away from the left turn's centre at (30, 30)
            return 100 + 0.15 * math.hypot(x - 30, y - 30)
        r = RL.road_samples({"id": "r", "width": 8, "material": "gravel"}, centre, banked)
        mid = r["points"][len(r["points"]) // 2]
        self.assertGreater(mid[3], 0.1, "the outside (right) of a left turn is higher")


if __name__ == "__main__":
    unittest.main()
