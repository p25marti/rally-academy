"""Run in-game scenarios: python tools/ingame/run.py <name> [<name> ...] | --list"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8")

import academy as A  # noqa: E402
from game import GameError, rpc  # noqa: E402
from scenarios import SCENARIOS  # noqa: E402


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "--list"):
        for name, fn in SCENARIOS.items():
            print(f"  {name:8} {fn.__doc__.strip().splitlines()[0]}")
        return 0
    try:
        rpc("tools/list", timeout=5)
    except Exception as e:  # noqa: BLE001
        print(f"BeamNG's MCP server isn't answering on 127.0.0.1:29292 ({e}). Start the game first.")
        return 2
    failed = []
    for name in argv:
        if name not in SCENARIOS:
            print(f"unknown scenario {name!r}; try --list")
            return 2
        print(f"== {name}", flush=True)
        A.SIDE_PROBLEMS.clear()
        try:
            problems = SCENARIOS[name]()
        except (GameError, RuntimeError) as e:
            problems = [f"aborted: {e}"]
            print(f"  FAIL {problems[0]}")
        problems = list(problems) + A.SIDE_PROBLEMS  # e.g. the HUD overflowing after a graded run
        failed += [f"{name}: {x}" for x in problems]
    print("\nall scenarios as expected" if not failed else "\n" + "\n".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
