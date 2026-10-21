# Drill data

**Source of truth:** `mod/gameplay/rallyAcademy/exercises.json`
([ADR 0002](decisions/0002-drill-data-source-of-truth.md)). The spreadsheet in
`reference/` is the original design and is no longer kept in sync.

Edit the JSON directly, then run `python tools/dev.py validate`.

## Schema (version 1)

```jsonc
{
  "schemaVersion": 1,
  "exercises": [
    {
      "id": "A01",                         // required, unique, letter = module (A–F) + 2 digits
      "module": "01  FOUNDATION & PRECISION",
      "title": "Steering and spatial awareness",
      "difficulty": "Core",
      "vehicle": {
        "displayName": "Ibishu Covet — Student Driver (M), FWD",
        "modelId": "covet",                // BeamNG model id (see VEHICLES.md)
        "configPath": "vehicles/covet/student_driver.pc"
      },
      "environment": {
        "venue": "bmp-dirt-arena",         // required: a venue id from venues.json (below)
        "areaHint": "BMP dirt arena (MAPS W2) …", // where on the venue, for this drill
        "venueNeeds": {"kind": "open", "areaM": 30}  // required: see "Venue needs"
      },
      "instructions": "What the driver does (shown in the HUD).",
      "resetInstructions": "Where/how to place the start.",
      "props": "Cones etc. to place manually.",
      "assessment": {
        "attempts": 10,                    // required, ≥ 1: runs in one scored block
        "requiredPasses": 8,               // required, 1..attempts: passes needed for the block to count
        "successDefinition": "Per-run PASS criteria in plain English.",
        "metricToRecord": "Successful precise parks / 10",
        "mode": "selfAssessment",          // required: selfAssessment | automatic | hybrid
        "endWhen": "finish",               // optional: finish (circle, default) | stopped (car at rest) | gates (last gate) | laps (course circle)
        "gates": {"count": 3, "widthM": 10}, // optional: gates the driver marks with + Gate
        "course": {...},                   // optional: an authored course (below); replaces gates
        "rules": [],                       // typed rules; empty = no machine grading
        "tiers": [...],                    // optional: silver and gold medals (below)
        "aiDemo": true                     // optional: offer Watch AI (ADR 0013); only where the AI's run passes
      },
      "parked": "Needs RWD or AWD ...",   // optional: why the drill is set aside for now (HUD shows it)
      "references": { "map": "url", "vehicle": "url" }
    }
  ]
}
```

`dev.py validate` enforces: valid JSON, `schemaVersion == 1`, required keys,
id format and uniqueness, `1 ≤ requiredPasses ≤ attempts`, known `mode`,
`rules` is a list, known `endWhen`. Each rule needs a known `type` and that type's
numeric parameters, and an `automatic` drill needs at least one rule. Gate rules
and `endWhen: "gates"` need `assessment.gates` or gates in `assessment.course`; course
rules need a course; `course` and `tiers` are checked as described below.

Rules are objects such as `{"type": "stop_zone", "lengthM": 5, "widthM": 6}`. The
types and their parameters are listed in [GRADING.md](GRADING.md#5-rule-engine);
`R.TYPES` in `rules.lua` is the one list: `tools/dev.py validate` reads it (and `R.GATE_RULES`) from that file. In an
`automatic` drill, the rules decide Pass or Miss when the run ends, and the HUD
shows one ✓/✗ line per rule.

## Authored courses

A drill whose layout is fixed describes it in `assessment.course`, in metres from the start:
`x` to the right, `y` ahead (the way the car faces at the start). The mod lays it out from the
venue's spawn when you're on the drill's map, or from your Mark start (**Move course here**),
and draws it; nothing needs marking ([PRODUCT](PRODUCT.md): drills set themselves up).
Gate posts and cones (and a stop line's end cones) are real props: a flexible delineator post or a
traffic cone stands at each, reset on Retry, and touching one is a clip ([ADR 0011](decisions/0011-physical-course-markers.md)).

```jsonc
"course": {
  "gates": [{"x": 0, "y": 8, "widthM": 3}],          // gates to drive through, in order;
                                                     // "headingDeg": -93 turns a gate to face a corner's road
  // a gate may carry "event": "puncture" (a random tyre goes flat as the car crosses it: F06)
  "predict": {"gate": 1, "minM": 10, "maxM": 45, "stepM": 1, "defaultM": 25}, // B03: the driver sets a mark this far
                                                     // past the gate on the HUD; it becomes the course's line
  "cones": [{"x": 0, "y": 20, "keep": "left"}],      // keep the cone on your left (pass it on its right)
  "box": {"x": -1.5, "y": 33, "lengthM": 6, "widthM": 3.2}, // parking box, square to the course
  "line": {"x": 0, "y": 60, "widthM": 8},           // a stop line, a cone at each end (A05)
  "zone": {"x": 0, "y": 150},                       // a stop zone's centre; its size comes from the stop_zone rule (B01)
  "circle": {"x": -15, "y": 0, "radiusM": 15, "turn": "left", "laps": 2} // a ring to lap (B05): its centre,
                                                     // the line's radius, which way round; the corridor comes
                                                     // from the circle_corridor rule; endWhen "laps" ends the run.
                                                     // With gates and endWhen "gates" (B06), laps is unused
}
```

The course's gates work like marked gates (`gates_passed`, live feedback, `endWhen: "gates"`),
so a drill with a course has no `assessment.gates`. The cones and gate posts are drawn, not
spawned: `markers_clear` measures the car's body against them. Course rules
(`R.COURSE_RULES`: `cones_passed`, `markers_clear`, `park_in_box`, `circle_laps`, `circle_corridor`)
need a course, and `endWhen: "laps"` needs a circle in it.

## Medal tiers

`assessment.tiers` adds silver and gold on top of a pass (bronze). Each tier lists rules that
replace the drill rule of the same type, or add to them:

```jsonc
"tiers": [
  {"name": "silver", "rules": [{"type": "park_in_box", "insetM": 0.3}, {"type": "max_time", "maxSeconds": 14}]},
  {"name": "gold",   "rules": [{"type": "park_in_box", "insetM": 0.5}, {"type": "max_time", "maxSeconds": 10}]}
]
```

Names are `silver` then `gold` (`R.TIERS`); a tier's `park_in_box` box must be smaller than the
last. Block targets (`requiredPasses`) still count passes; progress also keeps `bestTier` and
`tiers` (medal counts).

## Surface variants

A drill can run on several surfaces ([ADR 0009](decisions/0009-surface-variants.md)). It names its own surface and
lists the others:

```json
"surface": "Dirt",
"variants": [
  {"id": "gravel", "name": "Gravel", "venue": "pg-gravel-strip"},
  {"id": "snow", "name": "Snow", "venue": "pg-snow-strip",
   "rules": [{"type": "time_to_speed", "kmh": 40, "maxSeconds": 12}],
   "tiers": [{"name": "gold", "rules": [{"type": "time_to_speed", "kmh": 40, "maxSeconds": 7}]}]}
]
```

Each variant becomes a drill of its own, `A02-snow`, with its own progress and medals. It inherits everything from
the drill except what it sets: `venue` (required), `areaHint`, `vehicle`, `successDefinition`, `aiDemo`, and rule
overrides.
An override replaces every rule of the same type (or is added), in `rules` and in the named medal tier, as medal
tiers do. Set targets per surface only where the measured physics needs it; run the `surfaces` scenario
(TESTING) after a change. `dev.py validate` checks variants as the drills they become.

## Venues

Venues live in `mod/gameplay/rallyAcademy/venues.json` and drills refer to one by id
(`environment.venue`, [ADR 0007](decisions/0007-venues-as-data.md)). When the mod loads the
drills, it fills each drill's `environment.levelId`, `mapDisplayName` and `spawn` from its
venue, so the HUD, the Academy screen and Go to drill read them from the drill as before.
Change a venue once and every drill on it follows. Finding and adding venues:
[VENUES.md](VENUES.md).

```jsonc
{
  "schemaVersion": 1,
  "venues": [
    {
      "id": "bmp-gravel-track",                 // what drills refer to
      "mapsId": "W1",                           // its row in docs/MAPS.md
      "name": "West Coast USA: BMP Gravel Track", // shown in the HUD and the Academy
      "levelId": "west_coast_usa",              // BeamNG level folder name
      "spawn": {"pos": {...}, "dir": {...}, "up": {...}}, // Go to drill's default spot (Mark start overrides)
      "notes": "Purpose-built rallycross venue …"
    }
  ]
}
```

`dev.py validate` checks the file and that every drill's venue exists. It also rejects a
drill that still carries its own `levelId`, `mapDisplayName` or `spawn`, so each venue has
one source.

## Venue needs

Every drill says what kind of place it needs, in `environment.venueNeeds`. The venue tools
use it to say which drills a spot suits (`survey.py report`) and to search a map for a
drill's venue (`survey.py fits <drill>`). `dev.py validate` requires it and checks its
fields (the checks live in `tools/ingame/venues.py`).

```jsonc
"venueNeeds": {
  "kind": "straight",          // straight | corner | open | hill | crest | route
  "lengthM": 150,              // usable length (straight, route, crest) or along an open area
  "widthM": 8,                 // road width (not for open areas)
  "areaM": 50,                 // open: smallest side of the open ground
  "radiusM": [15, 50],         // corner: minimum radius range
  "turnDeg": 90,               // corner: how far it turns at least
  "shape": "hairpin",          // corner: constant | decreasing | increasing | hairpin
  "gradePct": 6,               // hill: at least this steep
  "maxGradePct": 3,            // straight: no steeper than this (braking drills)
  "maxSlopeDeg": 3,            // flat enough (open areas, starts)
  "surfaces": ["GRAVEL", "DIRT", "ASPHALT"], // allowed; listed in order of preference
  "features": ["runoff outside the corner"]  // what only a person can confirm
}
```

Everything but `kind` is optional. Surface names are the wheels' ground models
(`R.SURFACES` in `rules.lua`). Saved spots can't prove a corner, hill or crest exists, so the
report lists those drills as "maybe".

## Modules

| Letter | Module | Drills |
| --- | --- | --- |
| A | 01 Foundation & precision | 8 |
| B | 02 Grip & braking | 8 |
| C | 03 Rotation & slides | 8 |
| D | 04 Complex cornering | 8 |
| E | 05 Terrain & drivetrains | 8 |
| F | 06 Rally stage performance | 8 |

## Changing the schema

1. Make additive changes where possible (new optional fields need no version bump).
2. For breaking changes, bump `schemaVersion`, update the Lua loader to accept
   the new version, update `validate_exercises` in `tools/dev.py` and this doc,
   and add a CHANGELOG entry.
3. Rule types (P3) will be documented here as they're implemented.
