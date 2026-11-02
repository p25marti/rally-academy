"""Unit tests for the driver's attempt and tuning helpers that don't need the game (tools/driver, docs/DRIVER.md)."""
import json
import random
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "driver"))
sys.path.insert(0, str(ROOT / "tools" / "ingame"))
import attempt as AT  # noqa: E402
import tune  # noqa: E402

CARD = AT.card("scandinavian_flick")


class ScoreTest(unittest.TestCase):
    def test_a_medal_outweighs_any_margin(self):
        miss = AT.score({"passed": False}, {"maxSlip": 30, "exitKmh": 60})
        bronze = AT.score({"passed": True, "tier": "bronze"}, {"maxSlip": 0, "exitKmh": 0})
        self.assertLess(miss, bronze)
        best_silver = AT.score({"passed": True, "tier": "silver"}, {"maxSlip": 20, "exitKmh": 50})
        self.assertLess(best_silver, AT.score({"passed": True, "tier": "gold"}, {"maxSlip": 0, "exitKmh": 0}))

    def test_margins_and_a_spin(self):
        self.assertEqual(AT.score({"passed": True, "tier": "gold"}, {"maxSlip": 10, "exitKmh": 25}), 3.45)
        self.assertEqual(AT.score({"passed": False}, {"maxSlip": 20, "exitKmh": 50, "spun": True}), -0.1)


class DialsTest(unittest.TestCase):
    def test_every_start_value_is_within_its_range(self):
        for name, (lo, hi, start) in AT.dial_specs(CARD).items():
            self.assertTrue(lo <= start <= hi, name)

    def test_surface_then_tuned_then_overrides(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(AT, "DIALS", Path(d)):
            self.assertEqual(AT.dials(CARD, "asphalt")["approachKmh"], 72)  # the card's asphalt adjustment
            AT.tuned_path(CARD, "asphalt").write_text(json.dumps({"dials": {"approachKmh": 70.5}}))
            self.assertEqual(AT.dials(CARD, "asphalt")["approachKmh"], 70.5)
            self.assertEqual(AT.dials(CARD, "asphalt", tuned=False)["approachKmh"], 72)
            self.assertEqual(AT.dials(CARD, "asphalt", {"approachKmh": 60})["approachKmh"], 60)

    def test_unit_scaling_round_trips(self):
        names = tune.tunable(CARD)
        start = AT.dials(CARD, "gravel", tuned=False)
        x = tune.to_unit(CARD, names, start)
        self.assertTrue(all(0 <= v <= 1 for v in x))
        self.assertEqual(tune.from_unit(CARD, names, x), {n: round(start[n], 3) for n in names})

    def test_the_safety_net_time_limits_are_not_tuned(self):
        self.assertFalse(set(tune.FIXED) & set(tune.tunable(CARD)))
        self.assertTrue(set(tune.FIXED) <= set(AT.dial_specs(CARD)))


class SelectionTest(unittest.TestCase):
    def test_the_shortlist_takes_the_fittest_of_the_second_half(self):
        cands = [{"gen": g, "k": k, "fitness": f, "dials": {}} for g, k, f in
                 [(0, 0, 3.9), (5, 0, 3.0), (6, 0, 3.5), (8, 1, 3.9), (11, 2, 3.9), (10, 0, 2.0)]]
        short = tune.shortlist(cands, 12, k=3)
        self.assertEqual([(c["gen"], c["fitness"]) for c in short], [(11, 3.9), (8, 3.9), (6, 3.5)])

    def test_pick_prefers_passes_then_the_mean_score(self):
        results = [{"k": 0, "passes": 9, "meanScore": 3.8}, {"k": 1, "passes": 10, "meanScore": 3.1},
                   {"k": 2, "passes": 10, "meanScore": 3.4}]
        self.assertEqual(tune.pick(results)["k"], 2)


class StartsTest(unittest.TestCase):
    def test_varied_starts_stay_within_the_spread_and_repeat_with_a_seed(self):
        a = [AT.varied_start(random.Random(5)) for _ in range(3)]
        b = [AT.varied_start(random.Random(5)) for _ in range(3)]
        self.assertEqual(a, b)
        rng = random.Random(1)
        for _ in range(200):
            s = AT.varied_start(rng)
            self.assertLessEqual(abs(s["kmh"]), AT.VARY["kmh"])
            self.assertLessEqual(abs(s["side"]), AT.VARY["side"])


class LuaLiteralTest(unittest.TestCase):
    def test_values(self):
        self.assertEqual(AT.lua_literal({"a": [1, 2.5, True], "b": "x"}), '{["a"]={1,2.5,true},["b"]="x"}')


if __name__ == "__main__":
    unittest.main()
