"""Unit tests for the authored-course checks in tools/dev.py (course_errors): B03's predict and F06's gate events."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import dev  # noqa: E402

GATES = [{"x": 0, "y": 120, "widthM": 8}]


class CourseDataTest(unittest.TestCase):
    def test_a_prediction_range_on_a_gate_is_fine(self):
        self.assertEqual(dev.course_errors({"gates": GATES, "predict": {"gate": 1, "minM": 10, "maxM": 45, "defaultM": 25}}), [])

    def test_a_bad_prediction_range_is_reported(self):
        for p in ({"gate": 1, "minM": 45, "maxM": 10}, {"gate": 2, "minM": 10, "maxM": 45},
                  {"gate": 1, "minM": 10, "maxM": 45, "defaultM": 60}, {"gate": 1, "minM": 10, "maxM": 45, "stepM": 0}):
            self.assertTrue(dev.course_errors({"gates": GATES, "predict": p}), p)

    def test_gate_events_are_from_the_known_list(self):
        self.assertEqual(dev.course_errors({"gates": [dict(GATES[0], event="puncture")]}), [])
        errors = dev.course_errors({"gates": [dict(GATES[0], event="explode")]})
        self.assertTrue(any("event" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
