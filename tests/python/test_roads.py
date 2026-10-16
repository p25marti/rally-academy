"""Unit tests for tools/ingame/roads.py on synthetic road networks (no game needed)."""
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "ingame"))
import roads  # noqa: E402


def polyline(points, radius=4.0, drivability=1.0, prefix="n"):
    """A road through `points` [(x, y, z), ...]: nodes and links."""
    nodes = {f"{prefix}{i}": (x, y, z, radius) for i, (x, y, z) in enumerate(points)}
    links = [(f"{prefix}{i}", f"{prefix}{i + 1}", drivability, 20.0) for i in range(len(points) - 1)]
    return nodes, links


def arc(cx, cy, r, a0, a1, steps, z=0.0):
    return [(cx + r * math.cos(a0 + (a1 - a0) * k / steps), cy + r * math.sin(a0 + (a1 - a0) * k / steps), z)
            for k in range(steps + 1)]


class Straights(unittest.TestCase):
    def test_a_long_straight_is_found_with_its_length_and_width(self):
        nodes, links = polyline([(0, 10 * k, 0) for k in range(21)])  # 200 m north
        s = roads.straights(nodes, roads.build(nodes, links), min_length=100)
        self.assertEqual(len(s), 1)
        self.assertAlmostEqual(s[0]["length"], 200, places=0)
        self.assertEqual(s[0]["width"], 8.0)
        self.assertAlmostEqual(s[0]["dir"]["y"], 1.0)

    def test_a_short_or_wavy_road_is_not_a_straight(self):
        nodes, links = polyline([(0, 10 * k, 0) for k in range(6)])  # 50 m
        self.assertEqual(roads.straights(nodes, roads.build(nodes, links), min_length=100), [])
        nodes, links = polyline([(5 * (k % 2), 10 * k, 0) for k in range(21)])  # zig-zag 5 m
        self.assertEqual(roads.straights(nodes, roads.build(nodes, links), min_length=100), [])

    def test_grade_is_reported(self):
        nodes, links = polyline([(0, 10 * k, 0.5 * k) for k in range(21)])  # 5% climb
        s = roads.straights(nodes, roads.build(nodes, links), min_length=100)
        self.assertAlmostEqual(s[0]["gradePct"], 5.0, places=1)


class Corners(unittest.TestCase):
    def test_a_constant_radius_bend_is_found_with_radius_turn_and_direction(self):
        pts = [(0, -60 + 10 * k, 0) for k in range(6)] + arc(30, -10, 30, math.pi, math.pi / 2, 9)[1:]
        nodes, links = polyline(pts)
        c = roads.corners(nodes, roads.build(nodes, links), max_radius=80)
        self.assertEqual(len(c), 1)
        self.assertAlmostEqual(c[0]["minRadius"], 30, delta=1)
        self.assertEqual(c[0]["shape"], "constant")
        self.assertEqual(c[0]["direction"], "right")
        self.assertAlmostEqual(abs(c[0]["turnDeg"]), 90, delta=15)

    def test_a_tightening_bend_is_decreasing_radius_and_a_u_turn_is_a_hairpin(self):
        pts = arc(0, 0, 60, 0, 0.6, 6) + arc(60 * math.cos(0.6) - 25 * math.cos(0.6), 60 * math.sin(0.6) - 25 * math.sin(0.6),
                                             25, 0.6, 1.4, 6)[1:]
        nodes, links = polyline(pts)
        c = roads.corners(nodes, roads.build(nodes, links), max_radius=80)
        self.assertEqual(c[0]["shape"], "decreasing")
        nodes, links = polyline(arc(0, 0, 15, 0, math.pi, 12))
        self.assertEqual(roads.corners(nodes, roads.build(nodes, links))[0]["shape"], "hairpin")


class Hills(unittest.TestCase):
    def test_climbs_descents_and_crests(self):
        up = [(0, 10 * k, 0.8 * k) for k in range(11)]               # 8% for 100 m
        down = [(0, 100 + 10 * k, 8 - 0.8 * k) for k in range(1, 11)]  # then 8% down
        nodes, links = polyline(up + down)
        adj = roads.build(nodes, links)
        h = roads.hills(nodes, adj, min_grade_pct=6, min_length=60)
        self.assertEqual({x["kind"] for x in h}, {"uphill", "downhill"})
        self.assertTrue(roads.crests(nodes, adj))


class Network(unittest.TestCase):
    def test_chains_split_at_junctions(self):
        a, la = polyline([(0, 10 * k, 0) for k in range(5)], prefix="a")
        b, lb = polyline([(0, 40, 0), (10, 40, 0), (20, 40, 0)], prefix="b")
        nodes = {**a, **b}
        links = la + lb + [("a4", "b1", 1.0, 20.0)]
        nodes.pop("b0")
        chains = roads.chains(nodes, roads.build(nodes, links))
        self.assertEqual(sum(len(c) - 1 for c in chains), len(links) - 1)  # every valid edge once

    def test_dedupe_keeps_the_first_of_nearby_sections(self):
        s = [{"pos": {"x": 0, "y": 0}}, {"pos": {"x": 10, "y": 0}}, {"pos": {"x": 100, "y": 0}}]
        self.assertEqual(len(roads.dedupe(s, radius=25)), 2)


if __name__ == "__main__":
    unittest.main()
