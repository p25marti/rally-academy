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
  ship      check, commit on a branch, fast-forward main, push, delete the branch
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
VENUES_JSON = Path("gameplay/rallyAcademy/venues.json")
ACTIONS_JSON = Path("lua/ge/extensions/core/input/actions/rallyAcademy_actions.json")
BINDINGS_JSON = Path("settings/inputmaps/keyboard_rallyAcademy.json")
ALLOWED_TOP_LEVEL = {"gameplay", "lua", "ui", "art", "levels", "vehicles", "settings", "scripts"}
# Grading rule types and their required numeric parameters; mirrors R.TYPES in
# mod/lua/ge/extensions/rallyAcademy/rules.lua (docs/DRILL_DATA.md).
RULES_LUA = ROOT / "mod" / "lua" / "ge" / "extensions" / "rallyAcademy" / "rules.lua"


def rule_types() -> tuple[dict[str, list[str]], set[str]]:
    """R.TYPES (rule type -> required numeric params) and R.GATE_RULES, read from rules.lua
    so the validator and the evaluators can't drift apart."""
    src = RULES_LUA.read_text(encoding="utf-8")
    block = re.search(r"^R\.TYPES = \{\n(.*?)^\}", src, re.S | re.M)
    gates = re.search(r"^R\.GATE_RULES = \{(.*?)\}", src, re.M | re.S)
    if not (block and gates):
        fail(f"can't find R.TYPES / R.GATE_RULES in {RULES_LUA}")
    types = {m.group(1): re.findall(r"'(\w+)'", m.group(2))
             for m in re.finditer(r"^\s*(\w+) = \{(.*?)\},?\s*$", block.group(1), re.M)}
    return types, set(re.findall(r"'(\w+)'", gates.group(1)))


def lua_name_list(name: str) -> list[str]:
    """A list of names in rules.lua, such as R.COURSE_RULES or R.TIERS (it may span lines)."""
    m = re.search(rf"^R\.{name} = \{{(.*?)\}}", RULES_LUA.read_text(encoding="utf-8"), re.M | re.S)
    if not m:
        fail(f"can't find R.{name} in {RULES_LUA}")
    return re.findall(r"'(\w+)'", m.group(1))


def _num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


# What a course gate may do to the car as it crosses (rallyAcademy.lua): 'puncture' deflates a random tyre (F06).
GATE_EVENTS = {"puncture"}


def course_errors(course) -> list[str]:
    """assessment.course: gates, cones and a parking box in metres from the start (x right, y ahead)."""
    if not isinstance(course, dict):
        return ["assessment.course must be an object"]
    errors = []
    unknown = set(course) - {"gates", "cones", "box", "line", "zone", "circle", "predict"}
    if unknown:
        errors.append(f"assessment.course: unknown keys {sorted(unknown)}")
    for kind in ("gates", "cones"):
        items = course.get(kind, [])
        if not isinstance(items, list):
            errors.append(f"assessment.course.{kind} must be a list")
            continue
        for i, it in enumerate(items):
            if not (isinstance(it, dict) and _num(it.get("y")) and _num(it.get("x", 0))):
                errors.append(f"assessment.course.{kind}[{i}] needs numeric y (and x)")
            elif kind == "gates" and not (_num(it.get("widthM")) and it["widthM"] > 0):
                errors.append(f"assessment.course.gates[{i}] needs widthM > 0")
            elif kind == "cones" and it.get("keep", "left") not in ("left", "right"):
                errors.append(f"assessment.course.cones[{i}].keep must be 'left' or 'right'")
            elif kind == "gates" and it.get("event", "puncture") not in GATE_EVENTS:
                errors.append(f"assessment.course.gates[{i}].event must be one of {sorted(GATE_EVENTS)}")
    box = course.get("box")
    if box is not None and not (isinstance(box, dict) and _num(box.get("y")) and _num(box.get("x", 0))
                                and _num(box.get("lengthM")) and box["lengthM"] > 0
                                and _num(box.get("widthM")) and box["widthM"] > 0):
        errors.append("assessment.course.box needs numeric y (and x), lengthM > 0 and widthM > 0")
    zone = course.get("zone")
    if zone is not None and not (isinstance(zone, dict) and _num(zone.get("y")) and _num(zone.get("x", 0))):
        errors.append("assessment.course.zone needs numeric y (and x)")
    line = course.get("line")
    if line is not None and not (isinstance(line, dict) and _num(line.get("y")) and _num(line.get("x", 0))
                                 and _num(line.get("widthM", 8)) and line.get("widthM", 8) > 0):
        errors.append("assessment.course.line needs numeric y (and x) and widthM > 0")
    predict = course.get("predict")
    if predict is not None:
        gates = course.get("gates") if isinstance(course.get("gates"), list) else []
        p = predict if isinstance(predict, dict) else {}
        lo, hi, step, gate = p.get("minM"), p.get("maxM"), p.get("stepM", 1), p.get("gate", 1)
        if not (_num(lo) and _num(hi) and lo < hi and _num(step) and step > 0
                and isinstance(gate, int) and 1 <= gate <= len(gates)
                and _num(p.get("defaultM", lo)) and lo <= p.get("defaultM", lo) <= hi):
            errors.append("assessment.course.predict needs minM < maxM, stepM > 0, defaultM between them and gate = one of the course's gates")
    circle = course.get("circle")
    if circle is not None and not (isinstance(circle, dict) and _num(circle.get("x", 0)) and _num(circle.get("y", 0))
                                   and _num(circle.get("radiusM")) and circle["radiusM"] > 0
                                   and circle.get("turn", "left") in ("left", "right")
                                   and isinstance(circle.get("laps", 1), int) and circle.get("laps", 1) >= 1):
        errors.append("assessment.course.circle needs radiusM > 0, numeric x and y, turn 'left' or 'right' and laps >= 1")
    return errors


def tier_errors(tiers, rule_types_: dict, base_rules: list) -> list[str]:
    """assessment.tiers: [{name: 'silver', rules: [...]}, {name: 'gold', ...}], in R.TIERS order."""
    if not isinstance(tiers, list):
        return ["assessment.tiers must be a list"]
    errors, names = [], lua_name_list("TIERS")
    got = [t.get("name") if isinstance(t, dict) else None for t in tiers]
    if got != names[:len(got)]:
        errors.append(f"assessment.tiers names must be {names} in that order (got {got})")
    if not base_rules:
        errors.append("assessment.tiers need assessment.rules (a pass is bronze)")
    insets = []
    for t in tiers:
        name = t.get("name") if isinstance(t, dict) else t
        rules = t.get("rules") if isinstance(t, dict) else None
        if not isinstance(rules, list) or not rules:
            errors.append(f"assessment.tiers ({name}) need a non-empty rules list")
            continue
        for rule in rules:
            rtype = rule.get("type") if isinstance(rule, dict) else None
            if rtype not in rule_types_:
                errors.append(f"assessment.tiers ({name}): rule type must be one of {sorted(rule_types_)}")
            elif [k for k in rule_types_[rtype] if not _num(rule.get(k))]:
                errors.append(f"assessment.tiers ({name}): {rtype} needs numeric {rule_types_[rtype]}")
            elif rtype == "park_in_box":
                insets.append(rule.get("insetM", 0))
    if insets != sorted(insets):
        errors.append("assessment.tiers: each tier's park_in_box insetM must be larger than the last")
    return errors


END_WHEN = {"finish", "stopped", "gates", "laps"}
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


def venue_needs_errors(needs) -> list[str]:
    """venueNeeds checks live with the matcher (tools/ingame/venues.py), so they can't drift."""
    sys.path.insert(0, str(ROOT / "tools" / "ingame"))
    import venues  # noqa: E402 - stdlib-only module next to the in-game tools
    return venues.validate(needs)


def _vec_ok(v) -> bool:
    return isinstance(v, dict) and all(isinstance(v.get(k), (int, float)) for k in ("x", "y", "z"))


def expanded(exercises: list) -> list:
    """Every drill with its surface variants expanded (tools/ingame/variants.py, as the mod does)."""
    sys.path.insert(0, str(ROOT / "tools" / "ingame"))
    import variants  # noqa: E402 - stdlib-only module next to the in-game tools
    return variants.all_drills([e for e in exercises if isinstance(e, dict)])


VARIANT_KEYS = {"id", "name", "venue", "areaHint", "vehicle", "rules", "tiers", "successDefinition", "aiDemo"}


def variant_errors(ex: dict) -> list[str]:
    """A drill's `variants` (ADR 0009) are well formed: a lowercase id, a name, a venue."""
    errors: list[str] = []
    vs = ex.get("variants")
    if vs is None:
        return errors
    if not isinstance(vs, list) or not vs:
        return ["variants must be a non-empty list"]
    if not isinstance(ex.get("surface"), str):
        errors.append("a drill with variants needs `surface`: the name of its own surface (\"Dirt\")")
    seen = set()
    for i, v in enumerate(vs):
        if not isinstance(v, dict):
            errors.append(f"variants[{i}] must be an object")
            continue
        if not re.fullmatch(r"[a-z]+", str(v.get("id", ""))):
            errors.append(f"variants[{i}]: id must be lowercase letters ('snow')")
        if v.get("id") in seen:
            errors.append(f"variants[{i}]: duplicate id {v.get('id')!r}")
        seen.add(v.get("id"))
        for k in ("name", "venue"):
            if not isinstance(v.get(k), str) or not v.get(k):
                errors.append(f"variants[{i}]: {k} must be a non-empty string")
        unknown = set(v) - VARIANT_KEYS
        if unknown:
            errors.append(f"variants[{i}]: unknown keys {sorted(unknown)}")
    return errors


def validate_venues(venues: dict, exercises: dict) -> list[str]:
    """venues.json is well formed, every drill names a known venue, and no drill still carries
    its own copy of the venue (levelId, mapDisplayName, spawn): one source per venue."""
    errors: list[str] = []
    if venues.get("schemaVersion") != 1:
        errors.append("venues.json: schemaVersion must be 1")
    ids = set()
    for i, v in enumerate(venues.get("venues") or []):
        where = f"venues[{i}] ({v.get('id', '?')})"
        for k in ("id", "name", "levelId"):
            if not isinstance(v.get(k), str) or not v.get(k):
                errors.append(f"{where}: {k} must be a non-empty string")
        if v.get("id") in ids:
            errors.append(f"{where}: duplicate id")
        ids.add(v.get("id"))
        sp = v.get("spawn") or {}
        if not all(_vec_ok(sp.get(k)) for k in ("pos", "dir", "up")):
            errors.append(f"{where}: spawn needs pos, dir and up as {{x, y, z}}")
    for ex in expanded(exercises.get("exercises") or []):
        env = ex.get("environment") or {}
        if env.get("venue") not in ids:
            errors.append(f"{ex.get('id')}: environment.venue {env.get('venue')!r} isn't in venues.json")
        copies = [k for k in ("levelId", "mapDisplayName", "spawn") if k in env]
        if copies:
            errors.append(f"{ex.get('id')}: environment has {copies}; those come from the venue")
    return errors


def validate_exercises(data: dict) -> list[str]:
    errors: list[str] = []
    rule_types_, gate_rules = rule_types()
    if data.get("schemaVersion") != 1:
        errors.append("exercises.json: schemaVersion must be 1 (bump deliberately, see docs/DRILL_DATA.md)")
    exercises = data.get("exercises")
    if not isinstance(exercises, list) or not exercises:
        return errors + ["exercises.json: 'exercises' must be a non-empty list"]
    seen: set[str] = set()
    for ex in exercises:
        if isinstance(ex, dict):
            errors += [f"{ex.get('id', '?')}: {e}" for e in variant_errors(ex)]
    if errors:
        return errors
    for i, ex in enumerate(expanded(exercises)):  # variants are checked as the drills they become
        where = f"{ex.get('id', '?')}" if ex.get("variantOf") else f"exercises[{i}] ({ex.get('id', '?')})"
        missing = REQUIRED_EXERCISE_KEYS - ex.keys()
        if missing:
            errors.append(f"{where}: missing keys {sorted(missing)}")
            continue
        if not re.fullmatch(r"[A-Z]\d{2}(-[a-z]+)?" if ex.get("variantOf") else r"[A-Z]\d{2}", ex["id"]):
            errors.append(f"{where}: id must look like 'A01'")
        if ex["id"] in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(ex["id"])
        a = ex["assessment"]
        for key in ("attempts", "requiredPasses"):
            if not isinstance(a.get(key), int) or a[key] < 1:
                errors.append(f"{where}: assessment.{key} must be a positive integer")
        if "aiDemo" in a and not isinstance(a["aiDemo"], bool):
            errors.append(f"{where}: assessment.aiDemo must be true or false")  # a variant's, once merged
        if "racingLine" in a and a["racingLine"] is not False:
            errors.append(f"{where}: assessment.racingLine can only be false (no racing line for this drill)")
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
        course = a.get("course")
        if course is not None:
            errors += [f"{where}: {e}" for e in course_errors(course)]
            if gates is not None:
                errors.append(f"{where}: a course brings its own gates; drop assessment.gates")
        course_gates = isinstance(course, dict) and bool(course.get("gates"))
        rule_list = [r for r in a.get("rules") or [] if isinstance(r, dict)]
        uses_gates = a.get("endWhen") == "gates" or any(r.get("type") in gate_rules for r in rule_list)
        if uses_gates and gates is None and not course_gates:
            errors.append(f"{where}: gate rules and endWhen 'gates' need assessment.gates (or gates in assessment.course)")
        if a.get("endWhen") == "laps" and not (isinstance(course, dict) and course.get("circle")):
            errors.append(f"{where}: endWhen 'laps' needs a circle in assessment.course")
        course_rules = set(lua_name_list("COURSE_RULES"))
        if any(r.get("type") in course_rules for r in rule_list) and course is None:
            errors.append(f"{where}: course rules ({sorted(course_rules)}) need assessment.course")
        if "tiers" in a:
            errors += [f"{where}: {e}" for e in tier_errors(a["tiers"], rule_types_, rule_list)]
        env = ex.get("environment") or {}
        if "venueNeeds" not in env:
            errors.append(f"{where}: environment.venueNeeds is required (what kind of place the drill needs; docs/DRILL_DATA.md)")
        else:
            errors += [f"{where}: {e}" for e in venue_needs_errors(env["venueNeeds"])]
        if a.get("mode") == "automatic" and not a.get("rules"):
            errors.append(f"{where}: automatic drills need at least one rule")
    return errors


def bindings_errors(actions: dict, bindings: dict) -> list[str]:
    """Default key bindings (docs/STREAM_DECK.md): every action bound once, to a known action,
    and no Alt: Ctrl+Alt+Shift+F4 contains Alt+F4, which closed the game (0.39.4)."""
    errors, seen, bound = [], {}, set()
    if bindings.get("devicetype") != "keyboard" or not isinstance(bindings.get("bindings"), list):
        return [f"{BINDINGS_JSON}: needs devicetype 'keyboard' and a bindings list"]
    for b in bindings["bindings"]:
        action, control = b.get("action"), str(b.get("control", ""))
        if action not in actions:
            errors.append(f"{BINDINGS_JSON}: unknown action {action!r}")
        if "alt" in control.split():
            errors.append(f"{BINDINGS_JSON}: {action} uses Alt ({control!r}); Alt+F4 closes the game")
        if control in seen:
            errors.append(f"{BINDINGS_JSON}: {control!r} bound to both {seen[control]} and {action}")
        seen[control] = action
        bound.add(action)
    missing = sorted(set(actions) - bound)
    if missing:
        errors.append(f"{BINDINGS_JSON}: actions without a default binding: {missing}")
    return errors


def levels_check() -> None:
    """Generated levels (ADR 0008) must match their layouts: tools/mapgen/<layout>.json -> mod/levels/<name>/, by the
    manifest the last build wrote (layout and generator hashes, a hash per file). No game install needed."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("mapgen_build", ROOT / "tools" / "mapgen" / "build.py")
    mapgen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mapgen)
    layouts = sorted((ROOT / "tools" / "mapgen").glob("*.json"))
    for path in layouts:
        layout = json.loads(path.read_text(encoding="utf-8"))
        diff = mapgen.stale(layout)
        if diff:
            fail(f"mod/levels/{layout['name']}/ doesn't match {path.relative_to(ROOT).as_posix()} "
                 f"({'; '.join(diff[:4])}{'...' if len(diff) > 4 else ''}): run python tools/mapgen/build.py")
    ok(f"{len(layouts)} generated level(s) match their layouts")


DRILLS_MD = ROOT / "docs" / "DRILLS.md"


def drills_markdown() -> str:
    """docs/DRILLS.md: every drill by module, where it runs, its surfaces and how it's graded, from exercises.json and
    venues.json (`python tools/dev.py drills` writes it; validate checks it's current)."""
    drills = json.loads((MOD_DIR / EXERCISES_JSON).read_text(encoding="utf-8"))["exercises"]
    venues = {v["id"]: v for v in json.loads((MOD_DIR / VENUES_JSON).read_text(encoding="utf-8"))["venues"]}
    auto = [d for d in drills if d["assessment"].get("mode") == "automatic"]
    medals = [d for d in auto if d["assessment"].get("tiers")]
    parked = [d for d in drills if d.get("parked")]
    n_var = sum(len(d.get("variants") or []) for d in drills)
    modules: dict[str, list] = {}
    for d in drills:
        modules.setdefault(d["module"], []).append(d)
    out = ["# Drills", "",
           "<!-- Generated from mod/gameplay/rallyAcademy/exercises.json by `python tools/dev.py drills`: "
           "don't edit by hand. -->", "",
           f"**{len(drills)} drills** in {len(modules)} modules, all on the mod's own map, the proving ground. "
           f"**{len(auto)}** are graded automatically from telemetry ("
           + ("all" if len(medals) == len(auto) else str(len(medals))) + " with bronze, silver and gold medals); "
           f"the other {len(drills) - len(auto)} are self-assessed with Pass and Miss"
           + (f", {len(parked)} of them waiting for a RWD or AWD car" if parked else "") + ". "
           f"{n_var} surface variants (the same drill on another surface, with its own progress and medals) make "
           f"{len(drills) + n_var} drills to play in all. How each one is graded: [GRADING](GRADING.md); the data: "
           "[DRILL_DATA](DRILL_DATA.md).", ""]
    for name, ds in modules.items():
        num, _, title = name.strip().partition(" ")
        letter = ds[0]["id"][0]
        out += [f"## {letter} · {title.strip().capitalize().replace('&', '&')}", "",
                "| Drill | What you practise | Where | Surfaces | Grading |", "| --- | --- | --- | --- | --- |"]
        for d in ds:
            a = d["assessment"]
            if d.get("parked"):
                grading = "Self-assessed (parked: " + d["parked"].rstrip(".") + ")"
            elif a.get("mode") == "automatic":
                grading = "Automatic, medals" if a.get("tiers") else "Automatic"
                if a.get("aiDemo"):
                    grading += ", Watch AI"
            else:
                grading = "Self-assessed"
            surfaces = [d.get("surface")] + [v["name"] for v in d.get("variants") or []] if d.get("surface") else ["single surface"]
            venue = venues.get(d["environment"].get("venue"), {}).get("name", d["environment"].get("venue", "-"))
            first = d.get("instructions", "").split(". ")[0].rstrip(".").replace("|", "/") + "."
            out.append(f"| **{d['id']}** {d['title']} | {first} | {venue.replace('Proving ground: ', '')} | "
                       f"{', '.join(surfaces)} | {grading} |")
        out.append("")
    return "\n".join(out)


def cmd_drills(_args=None) -> None:
    DRILLS_MD.write_text(drills_markdown(), encoding="utf-8", newline="\n")
    ok(f"wrote {DRILLS_MD.relative_to(ROOT)}")


def cmd_validate(_args=None) -> None:
    version = read_version()
    json_files = sorted(MOD_DIR.rglob("*.json"))
    for path in json_files:
        try:
            text = path.read_text(encoding="utf-8")
            if path.name.endswith((".level.json", ".forest4.json")):  # level objects, trees: one object per line
                for line in text.splitlines():
                    if line.strip():
                        json.loads(line)
            else:
                json.loads(text)
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
    drills = json.loads((MOD_DIR / EXERCISES_JSON).read_text(encoding="utf-8"))["exercises"]
    n_variants = len(expanded(drills)) - len(drills)
    ok(f"{len(drills)} drills valid" + (f", {n_variants} surface variants" if n_variants else ""))
    if not DRILLS_MD.is_file() or DRILLS_MD.read_text(encoding="utf-8") != drills_markdown():
        fail(f"{DRILLS_MD.relative_to(ROOT)} is out of date with the drill data (run: python tools/dev.py drills)")
    ok(f"{DRILLS_MD.relative_to(ROOT)} matches the drills")
    venues = json.loads((MOD_DIR / VENUES_JSON).read_text(encoding="utf-8"))
    errors = validate_venues(venues, json.loads((MOD_DIR / EXERCISES_JSON).read_text(encoding="utf-8")))
    if errors:
        fail("venue data invalid:\n    " + "\n    ".join(errors))
    ok(f"{len(venues['venues'])} venues valid, every drill's venue found")

    test_drills = json.loads((ROOT / "tests" / "fixtures" / "test_drills.json").read_text(encoding="utf-8"))
    errors = validate_exercises(test_drills)
    test_venues = json.loads((ROOT / "tests" / "fixtures" / "test_venues.json").read_text(encoding="utf-8"))
    errors += validate_venues(test_venues, {"exercises": []})
    venue_ids = {v["id"] for v in venues["venues"] + test_venues["venues"]}
    errors += [f"{e['id']}: unknown venue {e['environment'].get('venue')}" for e in test_drills["exercises"]
               if e["environment"].get("venue") not in venue_ids]
    if errors:
        fail("test drills (tests/fixtures/test_drills.json) invalid:\n    " + "\n    ".join(errors))
    ok(f"{len(test_drills['exercises'])} test drills valid")

    errors = bindings_errors(json.loads((MOD_DIR / ACTIONS_JSON).read_text(encoding="utf-8")),
                             json.loads((MOD_DIR / BINDINGS_JSON).read_text(encoding="utf-8")))
    if errors:
        fail("default key bindings invalid:\n    " + "\n    ".join(errors))
    ok("default key bindings cover every action, no Alt")

    levels_check()

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


def python_tests() -> None:
    """Unit tests for the Python tooling (tests/python, stdlib unittest)."""
    result = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests/python", "-q"],
                            cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout + result.stderr)
        fail("Python tool tests failed")
    ran = re.search(r"Ran (\d+) tests?", result.stderr)
    ok(f"Python tool tests pass ({ran.group(1) if ran else '?'} tests)")


def cmd_test(args=None) -> None:
    python_tests()
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


# --------------------------------------------------------------------------- ship

def git(*args: str, capture: bool = False) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=capture, text=True)
    if r.returncode != 0:
        fail(f"git {' '.join(args)} failed" + (f": {r.stderr.strip()}" if capture and r.stderr else ""))
    return r.stdout if capture else ""


def branch_name(subject: str) -> str:
    """'feat: A07 on a corner course' -> 'feat/a07-on-a-corner-course' (Conventional Commit type first)."""
    m = re.match(r"(\w+)(?:\([^)]*\))?!?:\s*(.*)", subject)
    kind, rest = (m.group(1), m.group(2)) if m else ("chore", subject)
    slug = re.sub(r"[^a-z0-9]+", "-", rest.lower()).strip("-")[:40].strip("-") or "change"
    return f"{kind}/{slug}"


def cmd_ship(args) -> None:
    """The solo-owner git workflow (AGENTS.md, DEVELOPMENT.md) as one command: refuses at the first
    failure, so a failing check can never be committed and pushed."""
    message = Path(args.file).read_text(encoding="utf-8") if args.file else args.message
    if not message or not message.strip():
        fail("give a commit message (-m) or a file (-F)")
    if git("branch", "--show-current", capture=True).strip() != "main":
        fail("run ship from main with your changes uncommitted (it makes the branch itself)")
    if not git("status", "--porcelain", capture=True).strip():
        fail("nothing to ship: no changes")
    r = subprocess.run([sys.executable, str(Path(__file__).resolve()), "check", "--strict"], cwd=ROOT)
    if r.returncode != 0:
        fail("check --strict failed: nothing was committed")
    branch = args.branch or branch_name(message.strip().splitlines()[0])
    git("switch", "-c", branch)
    git("add", "-A")
    msg_file = ROOT / ".git" / "SHIP_MSG"
    msg_file.write_text(message, encoding="utf-8")
    try:
        git("commit", "-q", "-F", str(msg_file))
    finally:
        msg_file.unlink(missing_ok=True)
    git("push", "-q", ".", "HEAD:main")  # fast-forward only: refuses if main moved on
    git("switch", "-q", "main")
    git("branch", "-q", "-d", branch)
    if args.no_push:
        ok(f"committed to main via {branch} (not pushed)")
        return
    git("push", "-q", "origin", "main")
    ok(f"shipped: {git('log', '--oneline', '-1', capture=True).strip()}")


# --------------------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dev.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check", help="validate + lint + test + build (CI entry point)")
    p.add_argument("--strict", action="store_true", help="fail instead of skipping when luajit/luacheck missing")
    p.set_defaults(func=cmd_check)
    sub.add_parser("validate", help="validate JSON, drills and version").set_defaults(func=cmd_validate)
    sub.add_parser("drills", help="regenerate docs/DRILLS.md from the drill data").set_defaults(func=cmd_drills)
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

    p = sub.add_parser("ship", help="check --strict, commit on a branch, fast-forward main, push, delete the branch")
    p.add_argument("-m", "--message", help="commit message (Conventional Commits; the branch is named from it)")
    p.add_argument("-F", "--file", help="read the commit message from a file")
    p.add_argument("--branch", help="branch name (default: from the message subject)")
    p.add_argument("--no-push", action="store_true", help="stop after fast-forwarding main locally")
    p.set_defaults(func=cmd_ship)

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
