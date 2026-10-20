"""Screenshots of the proving ground from fixed viewpoints: python tools/mapgen/views.py [name ...]

With the game running and the level loaded (it loads it if not). Writes recordings/views/<name>.jpg (gitignored),
so every visual change to the map can be looked at the same way. The car is parked where each view needs it;
the camera goes back to the orbit camera at the end. The game keeps its own copy of each screenshot under
<user folder>/screenshots/mcp/: this moves those into recordings/views/game-copies/.
"""
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingame"))
import academy as A  # noqa: E402
import survey  # noqa: E402
from game import call, lua, screenshot  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "recordings" / "views"
LEVEL = "ra_proving_ground"
Z = 110.0

# name: (car position and heading, or None; camera position; point the camera looks at)
VIEWS = {
    "strip_start": ((375, -470, 0), (375, -478, Z + 2.2), (375, -380, Z + 1.0)),
    "strip_south": ((375, -150, 180), (375, -142, Z + 2.2), (375, -260, Z + 4.0)),
    "corner_entry": ((-280, -20, 0), (-280, -28, Z + 2.2), (-285, 60, Z + 1.0)),
    "corner_exit": ((-362, 72, 230), (-354, 80, Z + 2.5), (-400, 20, Z + 2.0)),
    "west_view": ((-120, -300, 270), (-112, -300, Z + 2.2), (-400, -300, Z + 6.0)),
    "paddock": (None, (8, -496, Z + 4), (0, -530, Z + 1)),
    "start_line": ((-375, -470, 0), (-372, -496, Z + 3.0), (-375, -440, Z + 0.5)),
    "strips_ahead": ((125, -470, 0), (125, -478, Z + 2.2), (125, -300, Z + 3.0)),
    "lane": ((34.6, 134.6, 118.6), (27.6, 138.4, Z + 2.4), (70, 115, Z + 1.0)),
    "overview": (None, (0, -1050, Z + 230), (0, -200, Z)),
    "from_hills": (None, (-700, 500, Z + 120), (100, -250, Z)),
}


def look(cam, target, fov=70):
    d = [t - c for t, c in zip(target, cam)]
    q = lua(f"local q = quatFromDir(vec3({d[0]:.2f}, {d[1]:.2f}, {d[2]:.2f}):normalized(), vec3(0, 0, 1)) "
            "return string.format('%.6f,%.6f,%.6f,%.6f', q.x, q.y, q.z, q.w)")
    rot = dict(zip("xyzw", map(float, q.split(","))))
    call("set_free_camera", {"pos": dict(zip("xyz", cam)), "rot": rot, "fov": fov})


def main(names):
    if str(lua("return tostring(getCurrentLevelIdentifier())")) != LEVEL:
        lua(f"freeroam_freeroam.startFreeroam('levels/{LEVEL}/info.json') return 1")
        A.wait_level(LEVEL)
    OUT.mkdir(parents=True, exist_ok=True)
    started = time.time()
    try:
        for name in names or VIEWS:
            car, cam, target = VIEWS[name]
            if car:
                h = math.radians(car[2])
                A.place({"x": car[0], "y": car[1], "z": Z}, {"x": math.sin(h), "y": math.cos(h)}, lift=0.5)
            look(cam, target)
            time.sleep(3)  # trees and imposters stream in
            screenshot(str(OUT / f"{name}.jpg"))
            print("wrote", (OUT / f"{name}.jpg").relative_to(ROOT), flush=True)
    finally:
        call("set_camera", {"name": "orbit"})
        survey.tidy_game_copies(started, OUT)


if __name__ == "__main__":
    main(sys.argv[1:])
