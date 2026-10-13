#!/usr/bin/env python3
"""Print the CHANGELOG.md section for a version (used by the release workflow).

Usage: python tools/release_notes.py 0.2.0
Exits non-zero if the section is missing or empty, so a release can't ship
without notes.
"""
import re
import sys
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parent.parent / "CHANGELOG.md"


def section(version: str) -> str:
    text = CHANGELOG.read_text(encoding="utf-8")
    pattern = rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)"
    m = re.search(pattern, text, flags=re.S | re.M)
    return m.group(1).strip() if m else ""


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    body = section(sys.argv[1])
    if not body:
        sys.exit(f"CHANGELOG.md has no notes for [{sys.argv[1]}]")
    print(body)
