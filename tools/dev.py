#!/usr/bin/env python3
"""Rally Academy developer CLI.

Standard library only (Python 3.9+), so it runs the same on Windows, macOS,
Linux and in CI. Run `python tools/dev.py --help` for the command list.

Commands
  check     validate + lint + test + build (what CI runs)
  validate  check mod JSON files, drill data and version consistency
  lint      run luacheck over mod and test Lua (skipped if luacheck missing)
  test      run the Lua unit tests with LuaJIT (skipped if luajit missing)
  build     produce dist/rally_academy.zip, ready to install or publish
  link      point <BeamNG user folder>/mods/unpacked/rally_academy at ./mod
  unlink    remove that link (or copied folder)
  status    show detected user folder, link state and conflicting installs
  log       show the tail of beamng.log, filtered to Rally Academy + errors
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "mod"
DIST_DIR = ROOT / "dist"
VERSION_FILE = ROOT / "VERSION"
MOD_NAME = "rally_academy"  # zip / unpacked folder name; keep stable across releases
APP_JSON = Path("ui/modules/apps/RallyAcademy/app.json")
EXERCISES_JSON = Path("gameplay/rallyAcademy/exercises.json")
ALLOWED_TOP_LEVEL = {"gameplay", "lua", "ui", "art", "levels", "vehicles", "settings", "scripts"}
# Grading rule types and their required numeric parameters; mirrors R.TYPES in
# mod/lua/ge/extensions/rallyAcademy/rules.lua (docs/DRILL_DATA.md).
RULES_LUA = ROOT / "mod" / "lua" / "ge" / "extensions" / "rallyAcademy" / "rules.lua"


def rule_types() -> tuple[dict[str, list[str]], set[str]]:
    """R.TYPES (rule type -> required numeric params) and R.GATE_RULES, read from rules.lua
    so the validator and the evaluators can't drift apart."""
    src = RULES_LUA.read_text(encoding="utf-8")
    block = re.search(r"^R\.TYPES = \{\n(.*?)^\}", src, re.S | re.M)
    gates = re.search(r"^R\.GATE_RULES = \{(.*?)\}", src, re.M)
    if not (block and gates):
        fail(f"can't find R.TYPES / R.GATE_RULES in {RULES_LUA}")
    types = {m.group(1): re.findall(r"'(\w+)'", m.group(2))
             for m in re.finditer(r"^\s*(\w+) = \{(.*?)\},?\s*$", block.group(1), re.M)}
    return types, set(re.findall(r"'(\w+)'", gates.group(1)))


END_WHEN = {"finish", "stopped", "gates"}
ZIP_EPOCH = (2020, 1, 1, 0, 0, 0)  # fixed timestamp => reproducible zips
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
# The mod logs as `|I|GELua.rallyAcademy.rallyAcademy| ...` (extension name + tag).
OUR_LOG_PATTERN = re.compile(r"rallyAcademy|RallyAcademy|rally_academy")
LOG_PATTERN = re.compile(r"rallyAcademy|RallyAcademy|rally_academy|\|E\||\bERROR\b|stack traceback", re.I)


# --------------------------------------------------------------------------- output

def info(msg: str) -> None:
    print(f"  {msg}", flush=True)


def ok(msg: str) -> None:
    print(f"[ok]   {msg}", flush=True)


def skip(msg: str) -> None:
    print(f"[skip] {msg}", flush=True)


class CheckFailed(Exception):
    pass


def fail(msg: str) -> None:
    raise CheckFailed(msg)


# --------------------------------------------------------------------------- version

def read_version() -> str:
    version = VERSION_FILE.read_text(encoding="utf-8").strip()
    if not SEMVER.match(version):
        fail(f"VERSION '{version}' is not semantic (MAJOR.MINOR.PATCH)")
    return version


# --------------------------------------------------------------------------- validate

REQUIRED_EXERCISE_KEYS = {
    "id", "module", "title", "difficulty", "vehicle", "environment",
    "instructions", "resetInstructions", "assessment",
}
ASSESSMENT_MODES = {"selfAssessment", "automatic", "hybrid"}


def validate_exercises(data: dict) -> list[str]:
    errors: list[str] = []
    rule_types_, gate_rules = rule_types()
    if data.get("schemaVersion") != 1:
        errors.append("exercises.json: schemaVersion must be 1 (bump deliberately, see docs/DRILL_DATA.md)")
    exercises = data.get("exercises")
    if not isinstance(exercises, list) or not exercises:
        return errors + ["exercises.json: 'exercises' must be a non-empty list"]
    seen: set[str] = set()
    for i, ex in enumerate(exercises):
        where = f"exercises[{i}] ({ex.get('id', '?')})"
        missing = REQUIRED_EXERCISE_KEYS - ex.keys()
        if missing:
            errors.append(f"{where}: missing keys {sorted(missing)}")
            continue
        if not re.fullmatch(r"[A-Z]\d{2}", ex["id"]):
            errors.append(f"{where}: id must look like 'A01'")
        if ex["id"] in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(ex["id"])
        a = ex["assessment"]
        for key in ("attempts", "requiredPasses"):
            if not isinstance(a.get(key), int) or a[key] < 1:
                errors.append(f"{where}: assessment.{key} must be a positive integer")
        if isinstance(a.get("attempts"), int) and isinstance(a.get("requiredPasses"), int) \
                and a["requiredPasses"] > a["attempts"]:
            errors.append(f"{where}: requiredPasses > attempts")
        if a.get("mode") not in ASSESSMENT_MODES:
            errors.append(f"{where}: assessment.mode must be one of {sorted(ASSESSMENT_MODES)}")
        if not isinstance(a.get("rules", []), list):
            errors.append(f"{where}: assessment.rules must be a list")
        for j, rule in enumerate(a.get("rules", []) if isinstance(a.get("rules", []), list) else []):
            rtype = rule.get("type") if isinstance(rule, dict) else None
            if rtype not in rule_types_:
                errors.append(f"{where}: rules[{j}].type must be one of {sorted(rule_types_)}")
                continue
            missing_params = [k for k in rule_types_[rtype] if not isinstance(rule.get(k), (int, float))]
            if missing_params:
                errors.append(f"{where}: rules[{j}] ({rtype}) needs numeric {missing_params}")
        if a.get("endWhen", "finish") not in END_WHEN:
            errors.append(f"{where}: assessment.endWhen must be one of {sorted(END_WHEN)}")
        gates = a.get("gates")
        if gates is not None:
            count, width = (gates.get("count"), gates.get("widthM")) if isinstance(gates, dict) else (None, None)
            if not (isinstance(count, int) and count >= 1 and isinstance(width, (int, float)) and width > 0):
                errors.append(f"{where}: assessment.gates must be {{count: int >= 1, widthM: number > 0}}")
        uses_gates = a.get("endWhen") == "gates" or any(
            isinstance(r, dict) and r.get("type") in gate_rules for r in a.get("rules") or [])
        if uses_gates and gates is None:
            errors.append(f"{where}: gate rules and endWhen 'gates' need assessment.gates")
        if a.get("mode") == "automatic" and not a.get("rules"):
            errors.append(f"{where}: automatic drills need at least one rule")
    return errors


def cmd_validate(_args=None) -> None:
    version = read_version()
    json_files = sorted(MOD_DIR.rglob("*.json"))
    for path in json_files:
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, UnicodeDecodeError) as exc:
            fail(f"{path.relative_to(ROOT)}: invalid JSON: {exc}")
    ok(f"{len(json_files)} JSON files parse")

    app = json.loads((MOD_DIR / APP_JSON).read_text(encoding="utf-8"))
    if app.get("version") != version:
        fail(f"{APP_JSON} version '{app.get('version')}' != VERSION '{version}' "
             f"(run: python tools/dev.py bump {version})")
    ok(f"version {version} consistent")

    errors = validate_exercises(json.loads((MOD_DIR / EXERCISES_JSON).read_text(encoding="utf-8")))
    if errors:
        fail("drill data invalid:\n    " + "\n    ".join(errors))
    count = len(json.loads((MOD_DIR / EXERCISES_JSON).read_text(encoding="utf-8"))["exercises"])
    ok(f"{count} drills valid")

    stray = [p.name for p in MOD_DIR.iterdir() if p.name not in ALLOWED_TOP_LEVEL]
    if stray:
        fail(f"unexpected top-level entries in mod/: {stray} (only {sorted(ALLOWED_TOP_LEVEL)})")
    ok("mod/ layout ok")


def cmd_bump(args) -> None:
    version = args.version
    if not SEMVER.match(version):
        fail(f"'{version}' is not semantic (MAJOR.MINOR.PATCH)")
    VERSION_FILE.write_text(version + "\n", encoding="utf-8")
    app_path = MOD_DIR / APP_JSON
    text = app_path.read_text(encoding="utf-8")
    new_text, n = re.subn(r'("version"\s*:\s*")[^"]*(")', rf"\g<1>{version}\g<2>", text, count=1)
    if n != 1:
        fail(f"could not find version field in {APP_JSON}")
    app_path.write_text(new_text, encoding="utf-8")
    ok(f"VERSION and {APP_JSON} set to {version}; now add a CHANGELOG.md section")


# --------------------------------------------------------------------------- lint / test

def lua_files() -> list[str]:
    # Repo-relative POSIX paths: valid both natively and inside WSL (run with cwd=ROOT).
    files = sorted(MOD_DIR.rglob("*.lua")) + sorted((ROOT / "tests" / "lua").rglob("*.lua"))
    return [p.relative_to(ROOT).as_posix() for p in files]


# Inside WSL, tools/ci/setup-lua.sh installs to this prefix (as CI does). This
# sh snippet puts the toolchain on PATH/LUA_PATH, then execs the tool ("$@").
WSL_LUA_ENV = (
    "T=$HOME/.lua-toolchain; PATH=$T/bin:$PATH; "
    "LUA_PATH=$T'/share/lua/5.1/?.lua;'$T'/share/lua/5.1/?/init.lua;;'; "
    "LUA_CPATH=$T'/lib/lua/5.1/?.so;;'; export PATH LUA_PATH LUA_CPATH; exec \"$@\""
)
_wsl_toolchain: bool | None = None


def wsl_has_lua_toolchain() -> bool:
    global _wsl_toolchain
    if _wsl_toolchain is None:
        _wsl_toolchain = False
        if os.name == "nt" and shutil.which("wsl.exe"):
            try:
                r = subprocess.run(["wsl.exe", "-e", "sh", "-c", "test -x $HOME/.lua-toolchain/bin/luajit"],
                                   capture_output=True, timeout=60)
                _wsl_toolchain = r.returncode == 0
            except (OSError, subprocess.TimeoutExpired):
                pass
    return _wsl_toolchain


def lua_tool(name: str) -> tuple[list[str], str] | None:
    """Command prefix for a Lua tool and where it came from: native PATH first,
    then (on Windows) the WSL toolchain from tools/ci/setup-lua.sh."""
    exe = shutil.which(name)
    if exe:
        return [exe], "native"
    if wsl_has_lua_toolchain():
        return ["wsl.exe", "-e", "sh", "-c", WSL_LUA_ENV, "sh", name], "WSL"
    return None


def cmd_lint(args=None) -> None:
    tool = lua_tool("luacheck")
    if not tool:
        if args is not None and getattr(args, "strict", False):
            fail("luacheck not found (see docs/DEVELOPMENT.md#tooling)")
        skip("lint: luacheck not installed (CI runs it)")
        return
    cmd, where = tool
    result = subprocess.run([*cmd, "--config", ".luacheckrc", *lua_files()], cwd=ROOT)
    if result.returncode != 0:
        fail("luacheck reported problems")
    ok(f"luacheck clean ({where})")


def cmd_test(args=None) -> None:
    tool = lua_tool("luajit")
    if not tool:
        if args is not None and getattr(args, "strict", False):
            fail("luajit not found (see docs/DEVELOPMENT.md#tooling)")
        skip("test: luajit not installed (CI runs it)")
        return
    cmd, where = tool
    result = subprocess.run([*cmd, "tests/lua/run.lua", "."], cwd=ROOT)
    if result.returncode != 0:
        fail("Lua tests failed")
    ok(f"Lua tests pass ({where})")


# --------------------------------------------------------------------------- build

def build_zip(out_dir: Path) -> Path:
    version = read_version()
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{MOD_NAME}.zip"
    files = sorted(p for p in MOD_DIR.rglob("*")
                   if p.is_file() and not any(part.startswith(".") for part in p.relative_to(MOD_DIR).parts))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in files:
            arc = path.relative_to(MOD_DIR).as_posix()
            data = path.read_bytes()
            if Path(arc) == APP_JSON:  # stamp version from the single source of truth
                app = json.loads(data.decode("utf-8"))
                app["version"] = version
                data = (json.dumps(app, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
            zi = zipfile.ZipInfo(arc, ZIP_EPOCH)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            zf.writestr(zi, data)
    target.write_bytes(buf.getvalue())
    digest = hashlib.sha256(buf.getvalue()).hexdigest()
    (out_dir / f"{MOD_NAME}.zip.sha256").write_text(f"{digest}  {target.name}\n", encoding="utf-8")

    with zipfile.ZipFile(target) as zf:  # sanity: zip root must be the mod root, never a wrapper folder
        tops = {n.split("/", 1)[0] for n in zf.namelist()}
    if not tops <= ALLOWED_TOP_LEVEL:
        fail(f"zip has unexpected top-level entries {sorted(tops - ALLOWED_TOP_LEVEL)}")
    ok(f"built {target.relative_to(ROOT) if target.is_relative_to(ROOT) else target} "
       f"(v{version}, {len(files)} files, sha256 {digest[:12]}…)")
    return target


def cmd_build(args) -> None:
    cmd_validate()
    build_zip(Path(args.out).resolve() if args.out else DIST_DIR)


def cmd_check(args) -> None:
    cmd_validate()
    cmd_lint(args)
    cmd_test(args)
    build_zip(DIST_DIR)
    print("\nAll checks passed.")


# --------------------------------------------------------------------------- local install

def candidate_user_folders() -> list[Path]:
    env = os.environ.get("BEAMNG_USER_FOLDER")
    if env:
        return [Path(env)]
    cands: list[Path] = []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        base = Path(local)
        cands.append(base / "BeamNG" / "BeamNG.drive" / "current")   # newer layout
        legacy = base / "BeamNG.drive"                               # older per-version layout
        if legacy.is_dir():
            versions = sorted((p for p in legacy.iterdir() if p.is_dir() and re.match(r"\d+\.\d+", p.name)),
                              key=lambda p: [int(x) for x in re.findall(r"\d+", p.name)], reverse=True)
            cands.extend(versions)
    home = Path.home()
    cands.append(home / ".local" / "share" / "BeamNG" / "BeamNG.drive" / "current")  # Linux native build
    return cands


def resolve_user_folder(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_dir():
            fail(f"user folder {path} does not exist")
        return path
    for cand in candidate_user_folders():
        if cand.is_dir():
            return cand
    fail("BeamNG user folder not found. Pass --user-folder or set BEAMNG_USER_FOLDER "
         "(find it via the BeamNG launcher's user-folder option). Tried:\n    "
         + "\n    ".join(str(c) for c in candidate_user_folders()))
    raise AssertionError  # unreachable


def unpacked_target(user: Path) -> Path:
    return user / "mods" / "unpacked" / MOD_NAME


def is_link(path: Path) -> bool:
    if path.is_symlink():
        return True
    if os.name == "nt" and path.exists():  # directory junctions are not symlinks to Python < 3.12
        try:
            return bool(os.readlink(path))
        except OSError:
            return False
    return False


def conflicting_installs(user: Path) -> list[Path]:
    mods = user / "mods"
    found = []
    for pattern in ("rally_academy*.zip", "rally-academy*.zip", "repo/rally_academy*.zip"):
        found.extend(mods.glob(pattern))
    return found


def cmd_link(args) -> None:
    user = resolve_user_folder(args.user_folder)
    target = unpacked_target(user)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or is_link(target):
        if args.force:
            remove_target(target)
        else:
            fail(f"{target} already exists (use --force to replace, or `unlink`)")
    if args.copy:
        shutil.copytree(MOD_DIR, target)
        ok(f"copied mod/ -> {target} (re-run `link --copy --force` after each change)")
    elif os.name == "nt":
        # A directory junction needs no admin rights or Developer Mode, unlike a symlink.
        result = subprocess.run(["cmd", "/c", "mklink", "/J", str(target), str(MOD_DIR)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            fail(f"mklink /J failed: {result.stdout}{result.stderr}\n  Try: link --copy")
        ok(f"junction {target} -> {MOD_DIR}")
    else:
        target.symlink_to(MOD_DIR, target_is_directory=True)
        ok(f"symlink {target} -> {MOD_DIR}")
    for z in conflicting_installs(user):
        print(f"[warn] {z} is also installed; disable or remove it so two copies don't load")
    info("In game: edit files, then reload Lua (see docs/DEVELOPMENT.md#the-inner-loop).")


def remove_target(target: Path) -> None:
    if is_link(target):
        if os.name == "nt":
            os.rmdir(target)  # removes the junction only, never the repo contents
        else:
            target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)


def cmd_unlink(args) -> None:
    user = resolve_user_folder(args.user_folder)
    target = unpacked_target(user)
    if not (target.exists() or is_link(target)):
        skip(f"nothing at {target}")
        return
    remove_target(target)
    ok(f"removed {target}")


def cmd_status(args) -> None:
    user = resolve_user_folder(args.user_folder)
    target = unpacked_target(user)
    print(f"user folder : {user}")
    if is_link(target):
        state = f"linked -> {os.readlink(target)}"
    elif target.is_dir():
        state = "copied folder (not live)"
    else:
        state = "not installed"
    print(f"unpacked mod: {target} [{state}]")
    for z in conflicting_installs(user):
        print(f"[warn] also installed as zip: {z}")
    log = user / "beamng.log"
    print(f"log file    : {log} [{'present' if log.exists() else 'missing'}]")


def cmd_ingame(args) -> None:
    """In-game scenarios through BeamNG's MCP server (tools/ingame/, see docs/TESTING.md)."""
    cmd = [sys.executable, str(ROOT / "tools" / "ingame" / "run.py"), *(args.scenarios or ["--list"])]
    sys.exit(subprocess.call(cmd))


def cmd_log(args) -> None:
    user = resolve_user_folder(args.user_folder)
    log = user / "beamng.log"
    if not log.exists():
        fail(f"{log} not found (start the game once)")
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    if args.ours:
        lines = [ln for ln in lines if OUR_LOG_PATTERN.search(ln)]
    elif not args.all:
        lines = [ln for ln in lines if LOG_PATTERN.search(ln)]
    for ln in lines[-args.n:]:
        print(ln)


# --------------------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dev.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check", help="validate + lint + test + build (CI entry point)")
    p.add_argument("--strict", action="store_true", help="fail instead of skipping when luajit/luacheck missing")
    p.set_defaults(func=cmd_check)
    sub.add_parser("validate", help="validate JSON, drills and version").set_defaults(func=cmd_validate)
    p = sub.add_parser("ingame", help="run in-game scenarios (BeamNG running, mod linked)")
    p.add_argument("scenarios", nargs="*", help="scenario names; none lists them")
    p.set_defaults(func=cmd_ingame)
    p = sub.add_parser("lint", help="luacheck")
    p.add_argument("--strict", action="store_true")
    p.set_defaults(func=cmd_lint)
    p = sub.add_parser("test", help="Lua unit tests")
    p.add_argument("--strict", action="store_true")
    p.set_defaults(func=cmd_test)
    p = sub.add_parser("build", help="build dist/rally_academy.zip")
    p.add_argument("--out", help="output directory (default: dist/)")
    p.set_defaults(func=cmd_build)
    p = sub.add_parser("bump", help="set the version in VERSION and app.json")
    p.add_argument("version")
    p.set_defaults(func=cmd_bump)

    for name, func, helptext in (("link", cmd_link, "live-link mod/ into BeamNG"),
                                 ("unlink", cmd_unlink, "remove the live link"),
                                 ("status", cmd_status, "show local install state"),
                                 ("log", cmd_log, "tail beamng.log")):
        p = sub.add_parser(name, help=helptext)
        p.add_argument("--user-folder", help="BeamNG user folder (default: auto-detect / $BEAMNG_USER_FOLDER)")
        if name == "link":
            p.add_argument("--copy", action="store_true", help="copy instead of junction/symlink")
            p.add_argument("--force", action="store_true", help="replace an existing install")
        if name == "log":
            p.add_argument("-n", type=int, default=80, help="number of lines (default 80)")
            p.add_argument("--all", action="store_true", help="do not filter")
            p.add_argument("--ours", action="store_true",
                           help="only Rally Academy lines (the mod's own log tag and UI messages), no other game errors")
        p.set_defaults(func=func)

    args = parser.parse_args(argv)
    try:
        args.func(args)
    except CheckFailed as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
