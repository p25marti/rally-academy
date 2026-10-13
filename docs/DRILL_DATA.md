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
        "modelId": null,                   // BeamNG model id, e.g. "covet" — fill when verified
        "configPath": null                 // e.g. "vehicles/covet/<config>.pc" — fill when verified
      },
      "environment": {
        "mapDisplayName": "ETK Driver Experience Center",
        "levelId": null,                   // BeamNG level folder name — fill when verified
        "areaHint": "East-side open skidpad: …"
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
        "rules": []                        // typed rules (P3); empty = no machine grading
      },
      "startTransform": null,              // {levelId, pos:{x,y,z}, rot:{x,y,z,w}} once authored
      "finishGate": null,                  // {pos:{x,y,z}, radius} once authored
      "references": { "map": "url", "vehicle": "url" }
    }
  ]
}
```

`dev.py validate` enforces: valid JSON, `schemaVersion == 1`, required keys,
id format and uniqueness, `1 ≤ requiredPasses ≤ attempts`, known `mode`,
`rules` is a list.

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
