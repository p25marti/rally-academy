"""Unit tests for the default key bindings check in tools/dev.py (docs/STREAM_DECK.md)."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import dev  # noqa: E402

ACTIONS = {"rally_academy_retry": {}, "rally_academy_menu": {}}


def binds(*pairs):
    return {"devicetype": "keyboard", "version": 1, "bindings": [{"action": a, "control": c} for a, c in pairs]}


class BindingsTest(unittest.TestCase):
    def test_every_action_bound_once_passes(self):
        self.assertEqual(dev.bindings_errors(ACTIONS, binds(("rally_academy_retry", "f13"), ("rally_academy_menu", "f17"))), [])

    def test_alt_is_rejected_because_alt_f4_closes_the_game(self):
        errors = dev.bindings_errors(ACTIONS, binds(("rally_academy_retry", "ctrl alt shift f4"), ("rally_academy_menu", "f17")))
        self.assertTrue(any("Alt" in e for e in errors), errors)

    def test_unknown_missing_and_duplicate_bindings_are_reported(self):
        errors = dev.bindings_errors(ACTIONS, binds(("rally_academy_retry", "f13"), ("rally_academy_typo", "f13")))
        text = " ".join(errors)
        self.assertIn("unknown action 'rally_academy_typo'", text)
        self.assertIn("bound to both", text)
        self.assertIn("rally_academy_menu", text)

    def test_the_shipped_file_is_valid(self):
        import json
        actions = json.loads((dev.MOD_DIR / dev.ACTIONS_JSON).read_text(encoding="utf-8"))
        bindings = json.loads((dev.MOD_DIR / dev.BINDINGS_JSON).read_text(encoding="utf-8"))
        self.assertEqual(dev.bindings_errors(actions, bindings), [])


if __name__ == "__main__":
    unittest.main()
