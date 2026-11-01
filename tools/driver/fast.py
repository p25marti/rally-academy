"""Fast simulation for training (docs/DRIVER.md#fast-simulation): deterministic mode with the background frame cap
lifted, about 5.5x real time on 0.40.4 with the same physics.

    python tools/driver/fast.py check     # measure 1x and fast, then confirm the settings are back as saved
    python tools/driver/fast.py restore   # put the game back to its saved settings (after a crashed run)

In code:

    with fast():
        ...  # attempts run at frame rate x 0.05 s of physics

The cap is lifted in memory only: `settings.setValue` skips saving while `settings.loadingSettingsInProgress` is set,
so the player's settings file is never written. Restoring reads the values saved on disk, not ones remembered at the
start, so it also repairs a game left in fast mode by a script that died. (If something else saves the settings while
fast mode is on, the lifted cap is saved with them; `restore` can't tell. Don't change settings during a run.)
"""
import argparse
import contextlib
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingame"))

# Settings that fast mode changes in memory, restored from the saved file.
SETTINGS = ("fpsLimitBackgroundEnabled",)

_MEM = ("local function mem(k, v) local f = settings.loadingSettingsInProgress settings.loadingSettingsInProgress = true "
        "settings.setValue(k, v) settings.loadingSettingsInProgress = f end ")


def _game():
    import game  # noqa: PLC0415 - only needed with the game running; tests pass their own
    return game


def _lua_value(v):
    return "true" if v is True else "false" if v is False else repr(v)


def set_in_memory(lua, key, value):
    """Change a game setting without saving it to the settings file."""
    lua(_MEM + f"mem('{key}', {_lua_value(value)}) return 1")


def saved(lua, key):
    """A setting's value as saved on disk (not as currently in memory)."""
    out = lua(f"return tostring(settings.impl.getValues()['{key}'])")
    return {"true": True, "false": False}.get(out, out)


def current(lua, key):
    out = lua(f"return tostring(settings.getValue('{key}'))")
    return {"true": True, "false": False}.get(out, out)


def restore(lua=None):
    """Normal mode and the saved frame settings. Safe to call any time."""
    lua = lua or _game().lua
    lua("be:setPhysicsDeterministic(false) return 1")
    for key in SETTINGS:
        set_in_memory(lua, key, saved(lua, key))


@contextlib.contextmanager
def fast(lua=None):
    """Deterministic physics with the background frame cap lifted; always restored on the way out."""
    lua = lua or _game().lua
    try:
        set_in_memory(lua, "fpsLimitBackgroundEnabled", False)
        lua("be:setPhysicsDeterministic(true) return 1")
        yield
    finally:
        restore(lua)


def sim_speed(seconds=6.0, vlua=None):
    """Simulation seconds per real second, from the player's car clock. Needs a car and physics running."""
    vlua = vlua or _game().vlua

    def clock():
        return float(vlua("return obj:getSimTime()")), time.time()
    s0, w0 = clock()
    time.sleep(seconds)
    s1, w1 = clock()
    return (s1 - s0) / (w1 - w0)


def check():
    g = _game()
    problems = []
    normal = sim_speed()
    with fast():
        quick = sim_speed()
        print(f"fast:   {quick:.2f}x  {g.call('get_fps_limit_reason')}")
    print(f"normal: {normal:.2f}x")
    if g.lua("return tostring(be:getPhysicsDeterministic())") != "false":
        problems.append("deterministic mode is still on")
    for key in SETTINGS:
        if current(g.lua, key) != saved(g.lua, key):
            problems.append(f"{key} isn't back to its saved value")
    if quick < 2.5:
        problems.append(f"fast mode ran only {quick:.2f}x (expected about 5x)")
    for p in problems:
        print("PROBLEM:", p)
    print("restored: settings as saved, normal mode" if not problems else "")
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=["check", "restore"])
    args = ap.parse_args()
    if args.command == "restore":
        restore()
        print("restored: settings as saved, normal mode")
        return 0
    return check()


if __name__ == "__main__":
    sys.exit(main())
