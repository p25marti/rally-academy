"""Unit tests for the fast-simulation harness (tools/driver/fast.py, docs/DRIVER.md#fast-simulation)."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "driver"))
import fast  # noqa: E402


class FakeGame:
    """Just enough of GE Lua: settings in memory and on disk, the save-while-loading flag, deterministic mode."""

    def __init__(self):
        self.disk = {"fpsLimitBackgroundEnabled": True}
        self.memory = dict(self.disk)
        self.deterministic = False
        self.saves = 0

    def lua(self, code):
        if "be:setPhysicsDeterministic(" in code:
            self.deterministic = "(true)" in code
        if "mem('" in code:
            key = code.split("mem('", 1)[1].split("'", 1)[0]
            value = code.rsplit(f"mem('{key}', ", 1)[1].split(")", 1)[0]
            assert "loadingSettingsInProgress = true" in code, "a setting changed without the no-save flag"
            self.memory[key] = {"true": True, "false": False}[value]
        if "settings.impl.getValues()" in code:
            return str(self.disk[code.split("['", 1)[1].split("']", 1)[0]]).lower()
        if "settings.getValue(" in code:
            return str(self.memory[code.split("('", 1)[1].split("')", 1)[0]]).lower()
        return "1"


class FastTest(unittest.TestCase):
    def test_fast_lifts_the_cap_and_turns_on_deterministic_mode(self):
        g = FakeGame()
        with fast.fast(g.lua):
            self.assertTrue(g.deterministic)
            self.assertIs(g.memory["fpsLimitBackgroundEnabled"], False)
        self.assertFalse(g.deterministic)
        self.assertIs(g.memory["fpsLimitBackgroundEnabled"], True)

    def test_restores_even_when_the_run_raises(self):
        g = FakeGame()
        with self.assertRaises(RuntimeError), fast.fast(g.lua):
            raise RuntimeError("attempt failed")
        self.assertFalse(g.deterministic)
        self.assertEqual(g.memory, g.disk)

    def test_never_changes_the_saved_settings(self):
        g = FakeGame()
        with fast.fast(g.lua):
            pass
        self.assertEqual(g.disk, {"fpsLimitBackgroundEnabled": True})

    def test_restore_uses_the_saved_value_not_the_one_in_memory(self):
        # a script died inside fast(): the cap is still lifted in memory
        g = FakeGame()
        g.memory["fpsLimitBackgroundEnabled"] = False
        g.deterministic = True
        fast.restore(g.lua)
        self.assertFalse(g.deterministic)
        self.assertIs(g.memory["fpsLimitBackgroundEnabled"], True)

    def test_restore_keeps_a_player_who_turned_the_cap_off(self):
        g = FakeGame()
        g.disk["fpsLimitBackgroundEnabled"] = g.memory["fpsLimitBackgroundEnabled"] = False
        with fast.fast(g.lua):
            pass
        self.assertIs(g.memory["fpsLimitBackgroundEnabled"], False)


if __name__ == "__main__":
    unittest.main()
