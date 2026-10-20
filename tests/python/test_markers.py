"""Unit tests for the rally corner boards' bend finder (tools/mapgen/markers.py)."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "mapgen"))
import markers  # noqa: E402
import shapes  # noqa: E402


def road(*segments):
    """A centre line heading +x from the origin (tools/mapgen/shapes.py), a point every 2 m."""
    return shapes.road(segments, step=2.0)[0]


class BendsTest(unittest.TestCase):
    def test_a_right_angle_left_is_one_bend_and_a_90_board(self):
        b = markers.bends(road(("S", 60), ("L", 30, 90), ("S", 60)))
        self.assertEqual(len(b), 1)
        self.assertAlmostEqual(b[0]["deg"], 90, delta=8)
        self.assertTrue(markers.board(b[0]["deg"]).endswith("s_corner_dir_left.dae"))

    def test_an_s_is_two_bends_with_their_own_boards(self):
        b = markers.bends(road(("S", 60), ("R", 40, 50), ("S", 20), ("L", 40, 50), ("S", 60)))
        self.assertEqual([round(x["deg"] / abs(x["deg"])) for x in b], [-1, 1])
        self.assertTrue(markers.board(b[0]["deg"]).endswith("dir45_right.dae"))

    def test_hairpins_and_gentle_curves(self):
        self.assertTrue(markers.board(175).endswith("dir225_left.dae"))
        self.assertTrue(markers.board(-130).endswith("dir135_right.dae"))
        self.assertEqual(markers.bends(road(("S", 60), ("L", 300, 15), ("S", 60))), [])  # too gentle for a board

    def test_the_board_stands_before_the_bend_on_its_outside(self):
        (x, y, heading, shape, b), = markers.placements(road(("S", 80), ("L", 30, 90), ("S", 60)), 8)
        self.assertLess(x, b["from"])  # before the bend (the road runs along +x first)
        self.assertGreater(x, b["from"] - 30)
        self.assertAlmostEqual(y, -7.0, delta=0.5)  # a left bend's outside is the right: 4 m half width + 3 m
        self.assertAlmostEqual(heading, 0.0, delta=2)


if __name__ == "__main__":
    unittest.main()
