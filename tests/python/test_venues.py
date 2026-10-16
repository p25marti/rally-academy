"""Unit tests for tools/ingame/venues.py: does a candidate place suit a drill's venueNeeds?"""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "ingame"))
import venues  # noqa: E402

BRAKING = {"kind": "straight", "lengthM": 150, "widthM": 8, "maxGradePct": 3, "surfaces": ["GRAVEL", "ASPHALT"]}
HAIRPIN = {"kind": "corner", "shape": "hairpin", "radiusM": [8, 30], "turnDeg": 150, "widthM": 8}
SKIDPAD = {"kind": "open", "areaM": 50, "maxSlopeDeg": 3}


def straight(**kw):
    return {"kind": "straight", "length": 200, "width": 9, "gradePct": 1.0, "measured": {"surfaces": ["GRAVEL"]}, **kw}


class Sections(unittest.TestCase):
    def test_a_long_wide_flat_gravel_straight_fits_a_braking_drill(self):
        self.assertEqual(venues.check(BRAKING, straight()), ([], []))

    def test_each_shortfall_is_named(self):
        problems, _ = venues.check(BRAKING, straight(length=90, width=5, gradePct=6, measured={"surfaces": ["GRASS"]}))
        self.assertIn("needs 150 m long, has 90 m", problems)
        self.assertIn("needs 8 m wide, is 5 m", problems)
        self.assertIn("needs flatter than 3%, is 6%", problems)
        self.assertIn("surface GRASS isn't allowed", problems)

    def test_unmeasured_surfaces_become_a_by_eye_check(self):
        problems, by_eye = venues.check(BRAKING, straight(measured=None))
        self.assertEqual(problems, [])
        self.assertIn("surface: GRAVEL/ASPHALT", by_eye)

    def test_corners_check_radius_turn_and_shape(self):
        c = {"kind": "corner", "length": 60, "width": 8, "minRadius": 14, "turnDeg": -170, "shape": "hairpin"}
        self.assertEqual(venues.check(HAIRPIN, c)[0], [])
        problems, _ = venues.check(HAIRPIN, {**c, "minRadius": 45, "turnDeg": 95, "shape": "constant"})
        self.assertEqual(len(problems), 3)

    def test_a_straight_is_not_a_corner(self):
        problems, _ = venues.check(HAIRPIN, straight())
        self.assertIn("is a straight, needs a corner", problems)

    def test_features_are_always_left_to_a_person(self):
        _, by_eye = venues.check({**BRAKING, "features": ["surface change: tarmac to gravel"]}, straight())
        self.assertEqual(by_eye, ["surface change: tarmac to gravel"])


class Ranking(unittest.TestCase):
    def test_surfaces_listed_first_are_preferred(self):
        needs = {**BRAKING, "surfaces": ["GRAVEL", "DIRT", "ASPHALT"]}
        gravel, tarmac = straight(), straight(measured={"surfaces": ["ASPHALT", "GRAVEL"]})
        self.assertLess(venues.surface_rank(needs, gravel), venues.surface_rank(needs, tarmac))


class Spots(unittest.TestCase):
    def spot(self, room=(160, 30, 30, 30, 160, 30, 30, 30), **kw):
        return {"id": 3, "level": "x", "room": list(room), "slopeDeg": 1.0,
                "road": {"width": 9, "dist": 1}, "surfaces": {"FL": "GRAVEL", "FR": "GRAVEL"}, **kw}

    def test_a_spot_with_room_ahead_on_a_wide_road_fits_a_braking_drill(self):
        self.assertEqual(venues.check(BRAKING, self.spot())[0], [])

    def test_room_ahead_is_the_usable_length(self):
        problems, _ = venues.check(BRAKING, self.spot(room=(57, 8, 8, 8, 150, 8, 6, 8)))
        self.assertIn("needs 150 m long, has 57 m", problems)

    def test_open_ground_comes_from_room_side_to_side_and_end_to_end(self):
        self.assertEqual(venues.check(SKIDPAD, self.spot())[0], [])
        problems, _ = venues.check(SKIDPAD, self.spot(room=(30, 10, 10, 10, 30, 10, 10, 10)))
        self.assertIn("needs 50 m of open ground, has 20 m", problems)

    def test_a_spot_cant_prove_a_corner_so_it_asks(self):
        problems, by_eye = venues.check(HAIRPIN, self.spot())
        self.assertNotIn("is a", " ".join(problems))
        self.assertIn("a corner here", by_eye)


class Suits(unittest.TestCase):
    def test_fits_and_near_misses_and_parked_drills_are_skipped(self):
        drills = [{"id": "B01", "environment": {"venueNeeds": BRAKING}},
                  {"id": "A04", "environment": {"venueNeeds": {**BRAKING, "lengthM": 300}}},
                  {"id": "C04", "environment": {"venueNeeds": HAIRPIN}},
                  {"id": "C03", "parked": "RWD", "environment": {"venueNeeds": BRAKING}}]
        fits, maybe, near = venues.suits(drills, straight())
        self.assertEqual([f[0] for f in fits], ["B01"])
        self.assertEqual(maybe, [])
        self.assertEqual(near, [("A04", ["needs 300 m long, has 200 m"])])

    def test_a_saved_spot_only_maybe_fits_a_corner_drill(self):
        drills = [{"id": "C04", "environment": {"venueNeeds": HAIRPIN}}]
        spot = {"id": 1, "room": [100] * 8, "road": {"width": 9, "dist": 1}}
        fits, maybe, _ = venues.suits(drills, spot)
        self.assertEqual((fits, [m[0] for m in maybe]), ([], ["C04"]))

    def test_every_drill_has_valid_venue_needs(self):
        data = json.loads((ROOT / "mod/gameplay/rallyAcademy/exercises.json").read_text(encoding="utf-8"))
        for d in data["exercises"]:
            self.assertEqual(venues.validate(d["environment"].get("venueNeeds")), [], d["id"])


if __name__ == "__main__":
    unittest.main()
