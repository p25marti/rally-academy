"""Unit tests for the dial optimiser (tools/driver/es.py): it finds the minimum of standard test functions."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "driver"))
import es  # noqa: E402


def minimise(f, x0, generations, seed=1, **kw):
    opt = es.SepCMA(x0, seed=seed, **kw)
    best = (float("inf"), None)
    for _ in range(generations):
        xs = opt.ask()
        costs = [f(x) for x in xs]
        opt.tell(xs, costs)
        best = min(best, min(zip(costs, xs)))
    return best, opt


class SepCMATest(unittest.TestCase):
    def test_finds_the_centre_of_a_sphere(self):
        target = [0.3, 0.7, 0.5, 0.2, 0.9, 0.6, 0.4, 0.8, 0.1, 0.5, 0.65]
        (cost, x), _ = minimise(lambda x: sum((a - b) ** 2 for a, b in zip(x, target)), [0.5] * 11, 60)
        self.assertLess(cost, 1e-4)
        for a, b in zip(x, target):
            self.assertAlmostEqual(a, b, delta=0.02)

    def test_learns_a_step_size_per_dial(self):
        # one dial matters 1000 times more than another: its step size shrinks further
        scale = [1000, 1, 1, 1, 1, 1]
        f = lambda x: sum(s * (v - 0.5) ** 2 for s, v in zip(scale, x))  # noqa: E731
        _, opt = minimise(f, [0.2] * 6, 50)
        spread = opt.spread()  # midway, the step sizes differ by dial
        self.assertLess(spread[0], min(spread[1:]) / 5)
        (cost, _), _ = minimise(f, [0.2] * 6, 80)
        self.assertLess(cost, 1e-4)

    def test_stays_within_the_bounds(self):
        opt = es.SepCMA([0.95, 0.05], sigma=0.4, seed=3)
        for _ in range(20):
            xs = opt.ask()
            for x in xs:
                self.assertTrue(all(0.0 <= v <= 1.0 for v in x), x)
            opt.tell(xs, [-(x[0] + x[1]) for x in xs])  # the best is out at the upper corner
        self.assertGreater(min(opt.m), 0.9)

    def test_copes_with_noise(self):
        import random
        noise = random.Random(7)
        target = [0.3, 0.6, 0.4, 0.7]
        (_, _), opt = minimise(lambda x: sum((a - b) ** 2 for a, b in zip(x, target)) + noise.gauss(0, 0.002),
                               [0.5] * 4, 40)
        for a, b in zip(opt.m, target):
            self.assertAlmostEqual(a, b, delta=0.08)

    def test_the_same_seed_repeats(self):
        a = es.SepCMA([0.5] * 3, seed=11).ask()
        b = es.SepCMA([0.5] * 3, seed=11).ask()
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
