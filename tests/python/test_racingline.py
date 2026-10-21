"""Unit tests for the racing lines the map builder writes (tools/mapgen/racingline.py)."""
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


def flat(_x, _y):
    return 100.0


def corner_kmh(line):
    """The slowest target speed where the corner's limit holds it (not the standing start)."""
    return min(p[3] for p in line if p[4] == 0)


def offsets(centre, line):
    """Each line point's distance left of the centre line (both resampled the same way)."""
    pts = RL.resample(centre, RL.STEP)
    return [(p[0] - c[0]) * n[0] + (p[1] - c[1]) * n[1] for p, c, n in zip(line, pts, RL.normals(pts))]


class RacingLineTest(unittest.TestCase):
    def test_a_straight_road_keeps_to_the_middle(self):
        centre = road(("S", 200))
        line = RL.line_for({"width": 8, "material": "gravel"}, centre, flat)
        self.assertLess(max(abs(o) for o in offsets(centre, line)), 0.01)
        self.assertTrue(all(p[4] == 1 for p in line[:-1]), "accelerating all the way")

    def test_a_corner_goes_outside_inside_outside_and_stays_on_the_road(self):
        centre = road(("S", 100), ("L", 30, 90), ("S", 100))
        line = RL.line_for({"width": 10, "material": "gravel"}, centre, flat)
        off = offsets(centre, line)
        limit = 5 - RL.CAR_MARGIN
        self.assertLessEqual(max(abs(o) for o in off), limit + 1e-6, "on the road")
        apex = min((i for i in range(len(line)) if line[i][4] == 0), key=lambda i: line[i][3])  # slowest in the corner
        self.assertGreater(off[apex], limit - 0.5, "inside (left) at the apex")
        self.assertLess(min(off[:apex]), -(limit - 0.5), "outside (right) on the way in")
        self.assertLess(min(off[apex:]), -(limit - 0.5), "outside on the way out")
        phases = "".join({-1: "B", 0: "-", 1: "a"}[p[4]] for p in line)
        self.assertRegex(phases, r"^a+B+-*a+$", "accelerate, brake, hold, accelerate")

    def test_grip_and_banking_set_the_corner_speed(self):
        centre = road(("S", 100), ("L", 30, 90), ("S", 100))
        slowest = {m: corner_kmh(RL.line_for({"width": 10, "material": m}, centre, flat)) for m in ("snow", "gravel", "Asphalt")}
        self.assertLess(slowest["snow"], slowest["gravel"])
        self.assertLess(slowest["gravel"], slowest["Asphalt"])

        def banked(x, y):  # higher towards the outside of the left turn (away from its centre at (100, 30))
            return 100.0 + 0.15 * math.hypot(x - 100, y - 30)
        self.assertGreater(corner_kmh(RL.line_for({"width": 10, "material": "gravel"}, centre, banked)),
                           slowest["gravel"] + 3, "a banked corner is faster")


if __name__ == "__main__":
    unittest.main()
