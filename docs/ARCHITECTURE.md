# Architecture

## Today (v0.1, imported scaffold)

```
mod/
├── gameplay/rallyAcademy/exercises.json        48 drills (data only)
├── scripts/rally_academy/modScript.lua         runs on mod activation: loads the extension
├── lua/ge/extensions/rallyAcademy.lua          GE extension: state, timing, retry, progress
├── lua/ge/extensions/core/input/actions/
│   └── rallyAcademy_actions.json               bindable actions: Retry / Pass / Miss
└── ui/modules/apps/RallyAcademy/               HUD app (AngularJS directive)
    ├── app.json  app.js  app.png
```

**Data flow**

```
 HUD (app.js) ──bngApi.engineLua("extensions.rallyAcademy.retry()")──▶ GE Lua
 Controls (actions.json) ──onDown "extensions.rallyAcademy.retry()"──▶ GE Lua
 GE Lua ──guihooks.trigger('rallyAcademyState', {...})──────────────▶ HUD
 GE Lua ──jsonReadFile / jsonWriteFile──▶ exercises.json (read) · settings/rallyAcademyProgress.json (r/w)
                                          · settings/rallyAcademySetups.json (r/w)
```

- `modScript.lua` loads the extension when the mod is enabled (unload mode
  `manual`, so it stays loaded). The **GE extension** owns all state. The HUD opening also calls
  `extensions.load('rallyAcademy')` then `publish()`, so the panel can be closed
  and reopened without losing a session.
- **State machine:** `idle → setup → ready → running → review → scored → ready …`
  - `select(id)` → `setup`; `markStart()` captures position and orientation;
    `markFinish()` captures a 5 m finish circle.
  - `retry()` teleports to the start → `ready`; moving faster than 1 m/s → `running`.
  - `onUpdate(dtReal, dtSim)` adds **simulation** time (pausing physics stops
    the clock) and checks the finish circle → `review`.
  - `recordAttempt(passed)` → `scored`, updates and saves progress.
- HUD updates are throttled to about 4 Hz while running.
- **Setups** (`settings/rallyAcademySetups.json`, schemaVersion 1):
  `levels[levelId][drillId] = {start = {pos, dir, up}, finish = {pos, radius}}`.
  Mark start/finish save immediately; `select(id)` loads the setup for the
  current map. No vehicle id is stored, so Retry resets whichever car you drive.
- **Car and map changes:** switching car (or losing it) mid-run abandons the run
  back to `setup`, unscored. `onClientEndMission` drops the map's start/finish;
  `onClientPostStartMission` re-selects the drill to load the new map's setup.
- **Telemetry and run records** ([ADR 0004](decisions/0004-telemetry-transport.md)):
  Retry loads `lua/vehicle/extensions/rallyAcademy/telemetry.lua` into the car and
  opens a record (`lua/ge/extensions/rallyAcademy/runRecord.lua`, pure Lua). The car
  sends one sample per frame to `M.onTelemetry`; samples from other cars, repeats
  and paused-sim duplicates are dropped. The record marks the run start (car left
  the start) and closes as `finished`, `abandoned` (car/map change, mid-run Miss,
  drill change) or `restarted` (Retry mid-run); the score is attached. Sampling
  stops when no run is open. `M.getLastRun()` returns it; `M.saveLastRun(path)`
  writes it as JSON (default `settings/rallyAcademy/lastRun.json`) for fixtures.
- **Go to drill** (`M.goToDrill`, HUD button under the drill list): loads the drill's
  `environment.levelId` if needed (`core_levels.startLevel`, resumed in
  `onClientPostStartMission`), puts the player in `vehicle.modelId`/`configPath`
  (`core_vehicles.replaceVehicle`, placed once `onVehicleSpawned` reports it, 6 s
  fallback), then Retry from the saved start, or teleport to `environment.spawn`
  (the venue's default spot) to mark one. Changing drill mid-trip cancels it.
- **Automatic grading:** for an `automatic` drill, the end of the run calls
  `rules.evaluate` (`lua/ge/extensions/rallyAcademy/rules.lua`, pure Lua) on the run
  record. For a stop drill, the context includes the zone marked with Mark stop zone. The result
  is attached to the record (`run.grade`), logged, scored through `recordAttempt`,
  and published as `grade` for the HUD's ✓/✗ lines. `endWhen: "stopped"` ends the
  run when the car is at rest, away from the start. The start is armed 0.2 s after
  Retry, because the repair-teleport can nudge the car a frame later.
- **Gates** (`lua/ge/extensions/rallyAcademy/gates.lua`, pure): **+ Gate** marks a line
  across the road at the car, facing the way it points (width from `assessment.gates`).
  Gates are saved with the start in `settings/rallyAcademySetups.json`. `onUpdate` checks
  the next gate each frame for live feedback ("Gate 2 of 3: 31 km/h") and for
  `endWhen: "gates"`. Grading re-reads crossings from the run record. `drawCourse`
  draws gates, the stop zone and the finish circle every frame with `debugDrawer`.
- **HUD ↔ Lua sync:** when Lua publishes the catalogue with no drill selected (game
  start, extension reload), the HUD selects the drill it shows (or the first).

Known gaps are listed in [ROADMAP.md](ROADMAP.md).

## Target architecture

Carried over from the original technical roadmap, refined:

**Layers.** Keep a pure-Lua core (no engine globals) behind thin adapters:

```
lua/ge/extensions/rallyAcademy.lua            entry point; wires adapters to the core; engine hooks
lua/ge/extensions/rallyAcademy/session.lua    state machine (pure)
lua/ge/extensions/rallyAcademy/rules.lua      rule evaluators (pure; split per type once it grows)
lua/ge/extensions/rallyAcademy/telemetry.lua  vehicle sampling adapter (engine-facing)
lua/ge/extensions/rallyAcademy/store.lua      progress persistence + schema migrations
```

Pure modules are unit-tested directly; adapters are covered by the stubs and
the in-game smoke test.

**Telemetry.** Sample at a fixed, rate-limited interval into a canonical run
record: `simTime, pos, orientation, vel, steering, throttle, brake, handbrake,
wheelSlip, damage`. Engine-side position and velocity come from GE. Driver
inputs and wheel data live in the vehicle's own Lua VM and must be pulled
across (e.g. `queueLuaCommand` with a callback, or electrics streams). Which
mechanism to use gets decided and recorded in BEAMNG_API_NOTES before building on it.

**Scoring.** Each drill's `assessment.rules` becomes a list of typed rules
evaluated over the run record: `gate`, `speed_range`, `brake_profile`,
`no_handbrake`, `slip_angle_range`, `no_collision`, `exit_heading`. A drill is
`automatic` (all rules machine-checked), `hybrid` (machine rules plus a human
Pass/Miss), or `selfAssessment` (today's behaviour).

Full capability list, per-drill needs and build order: [GRADING.md](GRADING.md).

**HUD technology.** BeamNG's UI is one shared embedded-Chromium page. Mods add
HUD apps as AngularJS 1.x directives; that is the only documented path (the
game's newer Vue 3 screens are a precompiled bundle mods can't extend). A
framework such as Preact or Vue could be bundled into `mod/` and mounted inside
our directive, at the cost of a build step, CSS isolation from other apps and an
unknown Chromium version. The HUD stays a plain directive while it is small; a
framework would need a decision record and an in-game test first.

**Authoring.** Start poses and gates are captured in-game and saved per
`levelId`, then promoted into `exercises.json` (`startTransform`,
`finishGate`, later gate lists). Longer stages can build on BeamNG's own
race/rally path tooling.

**Progress.** Attempt summaries and mastery are stored separately and
schema-versioned, with forward migrations in `store.lua`.

**Edge cases to design for:** UI focus/menus open, physics paused, vehicle
switched mid-run, damage reset, leaving the map, teleports breaking the
trajectory, UI reloaded mid-session, conflicts with built-in missions/scenarios,
unknown vehicle configs.
