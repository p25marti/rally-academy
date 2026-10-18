"""Unit tests for dev.py ship's branch naming (the git workflow command)."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import dev  # noqa: E402


class BranchNameTest(unittest.TestCase):
    def test_conventional_commit_type_becomes_the_branch_prefix(self):
        self.assertEqual(dev.branch_name("feat: A07 on a corner course, with medals"), "feat/a07-on-a-corner-course-with-medals")
        self.assertEqual(dev.branch_name("fix(ui): HUD overflow!"), "fix/hud-overflow")

    def test_a_subject_without_a_type_is_a_chore_and_long_ones_are_trimmed(self):
        self.assertEqual(dev.branch_name("tidy things up"), "chore/tidy-things-up")
        self.assertLessEqual(len(dev.branch_name("feat: " + "word " * 30)), len("feat/") + 40)


if __name__ == "__main__":
    unittest.main()
