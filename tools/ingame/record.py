"""Record in-game scenarios as videos: python tools/ingame/record.py <scenario> [<scenario> ...] | --all

Each scenario (scenarios.py: a drill's scripted pass and miss runs) is filmed from inside the game: a small
recorder extension, loaded from memory (nothing in mod/), saves a JPG every 1/30 s of simulation time with
createScreenshot2 into <user folder>/settings/rallyAcademy/video/<scenario>/; the frames are then encoded
to recordings/<scenario>.mp4 (H.264) and moved to the Recycle Bin.

Needs an ffmpeg with an H.264 encoder (libopenh264, libx264 or h264_mf): set RA_FFMPEG to its path, or it
is looked for on PATH and in a few common app installs. Options: --scale 0.5 (frame size against the game
window), --out DIR (default recordings/).
"""
import argparse
import ctypes
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8")

import academy as A  # noqa: E402
from game import GameError, call, lua, rpc  # noqa: E402
from scenarios import SCENARIOS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
# The game writes about 20 JPGs a second at half size (0.39.4); faster capture just queues up behind it.
FPS = 20
ENCODERS = ("libx264", "libopenh264", "h264_mf")

# The recorder: an extension built in memory and registered through package.preload, so it survives the
# mod reloading at the start of every scenario. Frames are paced by simulation time (dtSim), so a physics
# pause adds none and the video plays at real speed.
RECORDER = r"""
if not extensions.isExtensionLoaded('raRecorder') then
  local R = {state = {on = false, n = 0, acc = 0}}
  function R.onUpdate(_dtReal, dtSim)
    local s = R.state
    if not s.on then return end
    s.acc = s.acc + (dtSim or 0)
    if s.acc >= s.every then
      s.acc = s.acc - s.every
      s.n = s.n + 1
      createScreenshot2({filename = s.dir .. string.format('f_%%05d', s.n), writeJPG = true, superSampling = 1,
                         rescaleFactor = s.scale})
    end
  end
  package.preload['raRecorder'] = function() return R end
  extensions.load('raRecorder')
end
local s = raRecorder.state
s.dir, s.scale, s.every, s.n, s.acc, s.on = %s, %s, %s, 0, 0, true
return 'recording'
"""


def find_ffmpeg():
    cands = [os.environ.get("RA_FFMPEG"), shutil.which("ffmpeg")]
    for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)"), os.environ.get("LOCALAPPDATA")):
        if base and Path(base).is_dir():
            cands += [str(p) for p in Path(base).glob("*/*/ffmpeg.exe")] + [str(p) for p in Path(base).glob("*/ffmpeg.exe")]
            cands += [str(p) for p in Path(base).glob("*/Apps/*/ffmpeg.exe")]
    for exe in cands:
        if not exe or not Path(exe).exists():
            continue
        try:
            out = subprocess.run([exe, "-hide_banner", "-encoders"], capture_output=True, text=True, timeout=20).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        for enc in ENCODERS:
            if f" {enc} " in out:
                return exe, enc
    return None, None


def recycle(path):
    """Move a file or folder to the Recycle Bin (Windows), never a hard delete."""
    class SHFILEOPSTRUCTW(ctypes.Structure):
        _fields_ = [("hwnd", ctypes.c_void_p), ("wFunc", ctypes.c_uint), ("pFrom", ctypes.c_wchar_p),
                    ("pTo", ctypes.c_wchar_p), ("fFlags", ctypes.c_ushort), ("fAnyOperationsAborted", ctypes.c_int),
                    ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", ctypes.c_wchar_p)]
    op = SHFILEOPSTRUCTW(None, 3, str(path) + "\0", None, 0x0040 | 0x0010 | 0x0004 | 0x0400, 0, None, None)
    return ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op)) == 0


def frames_dir(name):
    """The frames folder's real path, from the game (settings/rallyAcademy/video/<name>/)."""
    rel = f"settings/rallyAcademy/video/{name}/"
    call("make_dir", {"path": "/" + rel})
    info = call("file_info", {"path": "/" + rel})
    if isinstance(info, str):
        info = json.loads(info)
    real = info.get("realPath") if isinstance(info, dict) else None
    return rel, Path(real) if real else None


def stop():
    """Stop recording (checked: a call can be lost while the game is busy); returns the frame count."""
    for _ in range(10):
        try:
            state = lua("raRecorder.state.on = false return tostring(raRecorder.state.on) .. ' ' .. raRecorder.state.n")
            on, n = str(state).split()
            if on == "false":
                return int(n)
        except (GameError, ValueError):
            pass
        time.sleep(1)
    raise RuntimeError("couldn't stop the recorder")


def drain(folder, frames, quiet_s=15):
    """createScreenshot2 writes asynchronously and can trail the capture by minutes: wait until every frame
    is on disk, or none has arrived for `quiet_s` seconds."""
    last, since = -1, time.time()
    while folder and folder.is_dir():
        n = len(list(folder.glob("f_*.jpg")))
        if n >= frames:
            return n
        if n != last:
            last, since = n, time.time()
        elif time.time() - since > quiet_s:
            return n
        time.sleep(1)
    return 0


def record(name, ffmpeg, encoder, out_dir, scale):
    rel, real = frames_dir(name)
    if real and real.is_dir() and any(real.iterdir()):
        drain(real, 10 ** 9, quiet_s=5)  # frames left over from an interrupted recording: let them land first
        recycle(real)
        rel, real = frames_dir(name)
    lua(RECORDER % (repr(rel).replace("'", '"'), scale, 1 / FPS))
    print(f"== {name} (recording)", flush=True)
    A.SIDE_PROBLEMS.clear()
    try:
        problems = list(SCENARIOS[name]()) + A.SIDE_PROBLEMS
    except (GameError, RuntimeError) as e:
        problems = [f"aborted: {e}"]
    finally:
        time.sleep(1.5)  # the grade on the HUD, then stop
        frames = stop()
    drain(real, frames)
    if not real or not real.is_dir():
        return problems + [f"no frames folder for {name}"]
    # The game now and then skips a capture (while it's busy, e.g. resetting the car), and ffmpeg stops at the
    # first gap in a numbered sequence: renumber the frames that were written.
    shots = sorted(real.glob("f_*.jpg"))
    for i, f in enumerate(shots, 1):
        f.rename(real / f"s_{i:05d}.jpg")
    missing = frames - len(shots)
    out = out_dir / f"{name}.mp4"
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(real / "s_%05d.jpg"),
           "-c:v", encoder, "-b:v", "1200k", "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
           "-movflags", "+faststart", str(out)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        return problems + [f"encoding failed: {res.stderr.strip()[:300]}"]
    for _ in range(5):  # the game may still hold the last frame open for a moment
        if recycle(real):
            break
        time.sleep(2)
    print(f"  {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}: {frames} frames, "
          f"{len(shots) / FPS:.0f} s, {out.stat().st_size / 1e6:.1f} MB" + (f", {missing} skipped" if missing else ""), flush=True)
    return problems


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("scenarios", nargs="*")
    p.add_argument("--all", action="store_true", help="every drill scenario (not smoke/pause/mainmenu/goto/fit)")
    p.add_argument("--scale", type=float, default=0.45)
    p.add_argument("--out", default=str(ROOT / "recordings"))
    a = p.parse_args(argv)
    names = a.scenarios or ([n for n in SCENARIOS if n not in ("smoke", "pause", "mainmenu", "goto", "fit", "events")]
                            if a.all else [])
    if not names:
        p.print_help()
        return 2
    unknown = [n for n in names if n not in SCENARIOS]
    if unknown:
        print(f"unknown scenario(s) {unknown}; see run.py --list")
        return 2
    ffmpeg, encoder = find_ffmpeg()
    if not ffmpeg:
        print("No ffmpeg with an H.264 encoder found; set RA_FFMPEG to one (e.g. a full build from ffmpeg.org).")
        return 2
    try:
        rpc("tools/list", timeout=5)
    except Exception as e:  # noqa: BLE001
        print(f"BeamNG's MCP server isn't answering on 127.0.0.1:29292 ({e}). Start the game first.")
        return 2
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"ffmpeg: {ffmpeg} ({encoder})")
    failed = []
    for name in names:
        failed += [f"{name}: {x}" for x in record(name, ffmpeg, encoder, out_dir, a.scale)]
    print("\nall recorded, scenarios as expected" if not failed else "\n" + "\n".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
