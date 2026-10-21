# Architecture

## Layout

```
mod/                                            exactly the shipped zip root
├── gameplay/rallyAcademy/exercises.json        the drills (data only; docs/DRILL_DATA.md)
├── gameplay/rallyAcademy/venues.json           named venues the drills refer to
├── scripts/rally_academy/modScript.lua         runs on mod activation: loads the extension
├── lua/ge/extensions/rallyAcademy.lua          GE extension: session, timing, grading flow, engine hooks
├── lua/ge/extensions/rallyAcademy/
│   ├── rules.lua      grading rules over a run record (pure)
│   ├── gates.lua      gate geometry and crossings (pure)
│   ├── layout.lua     authored courses laid out from the start; the car's footprint (pure)
│   ├── runRecord.lua  per-attempt telemetry record (pure)
│   ├── store.lua      saved progress and setups (jsonReadFile/jsonWriteFile only)
│   ├── props.lua      real cones and posts at a course's markers (spawn, reset, touches; ADR 0011)
│   └── course.lua     world markers: gates, cones, boxes, stop zone/line, finish (debugDrawer only)
├── lua/vehicle/extensions/rallyAcademy/telemetry.lua   sampler in the car's Lua VM
├── lua/ge/extensions/core/input/actions/
│   └── rallyAcademy_actions.json               bindable actions: Retry, Pass, Miss, Open menu
├── ui/modules/apps/RallyAcademy/               HUD panel (Vue HUD app: app.json "vue": true); hud.js (the
│                                               extension's state for every HUD app) and trace.js (the input
│                                               trace), shared by the three apps
├── ui/modules/apps/RallyAcademyCoach/          HUD: the drill's instructions, then the run's grade (ADR 0012)
├── ui/modules/apps/RallyAcademyInputs/         HUD: throttle and brake over time (ADR 0012)
├── settings/ui_apps/originalLayouts/           the Rally Academy HUD layout (ADR 0012)
│   ├── app.json  app.vue  app.png
└── ui/ui-vue/mods/rallyAcademy/                Academy screen: main menu, pause tab (Vue UI mod)
```

**Data flow**

```
 HUD (app.vue) ──api.engineLua("extensions.rallyAcademy.retry()")───▶ GE Lua
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
- **Telemetry and run records** ([ADR 0004](decisions/0004-telemetry-transport.md)). Each sample
  has inputs, gear, rpm, engine running, speeds, heading and velocity (slip angle), up vector
  (rollover), damage, flat-tyre count, and per wheel speed, surface and downforce:
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
- **Authored courses** (`layout.lua`, pure): a drill with `assessment.course` gets its gates,
  cones and parking box laid out from the start (the venue spawn on the drill's map, or the
  player's Mark start), heights from `be:getSurfaceHeightBelow`. The course's gates become
  the drill's gates, so the gate code above runs unchanged. When a run starts, the car's
  footprint is measured from its nodes (its position isn't the body's centre) and stored in
  the run record with the course; `trackCourse` gives live feedback (cone side, a clipped
  marker, the parking aid and the medal box the car is in), published as `course`.
  Grading goes through `rules.grade`, which adds medal tiers. After a graded run,
  auto-retry counts down 3 s of sim time, then calls Retry (cancelled if the car moves off).
- **HUD ↔ Lua sync:** when Lua publishes the catalogue with no drill selected (game
  start, extension reload), the HUD selects the drill it shows (or the first).

Known gaps are listed in [ROADMAP.md](ROADMAP.md).

## Design

**Layers.** A pure-Lua core (no engine globals) behind thin engine-facing edges, so the logic
is unit-tested under plain LuaJIT with stubs ([ADR 0003](decisions/0003-testing-without-the-game.md)):

- **Pure:** `rules.lua`, `gates.lua`, `runRecord.lua`. Tested directly, including against
  recorded in-game runs (`tests/fixtures/`).
- **Edges:** `store.lua` (files), `course.lua` (drawing), `props.lua` (spawned props), the vehicle `telemetry.lua`, and the
  engine calls inside `rallyAcademy.lua` (teleport, car swap, map load, UI routing, pause).
  Tested through the BeamNG stubs and the in-game scenarios (`dev.py ingame`).
- **Entry point:** `rallyAcademy.lua` holds the session state machine (idle → setup → ready →
  running → review → scored) and wires the rest together. Per-run state lives in one table
  that `resetRun()` replaces wholesale.

**Telemetry** ([ADR 0004](decisions/0004-telemetry-transport.md)): the car's sampler sends one
batched sample per frame to GE (inputs as applied and as the driver gave them, gear, rpm, engine running, speeds, heading and
velocity, up vector, damage, flat tyres, per-wheel speed/surface/downforce). Field list:
`rules.lua` header.

**Scoring.** Each drill's `assessment.rules` is a list of typed rules evaluated over the run
record when the run ends; each returns a readable reason. A drill is `automatic` (rules
decide Pass/Miss), `hybrid` (planned: rules plus a human answer) or `selfAssessment`
(Pass/Miss buttons). Rule types, capabilities per drill and build order: [GRADING.md](GRADING.md).

**UI technology.** BeamNG's UI is one shared embedded-Chromium page. Since 0.39 the game also has an
official **Vue UI mod** system (`ui/ui-vue/mods/README.md` in the game folder):
runtime-compiled `.vue` files that can add main-menu buttons, routes, pause-menu
tabs and slots, with no build step. The main-menu **Academy screen** uses it
([ADR 0005](decisions/0005-main-menu-via-vue-ui-mods.md)):
`mod/ui/ui-vue/mods/rallyAcademy/` (`index.js` registers the button and the
`menu.rallyAcademy` route; `AcademyMenu.vue` is the screen, with the game's tabs for
`pages/ExercisesPage.vue`, `AnalysisPage.vue`, `AboutPage.vue` and `CreditsPage.vue`;
`academy.js` holds shared helpers, including `useAcademyData()`). In a map, Esc opens the
pause menu with a **Rally Academy** tab whose rail buttons show the same pages
(`pause/PausePage.vue`), and the "Rally Academy: Open menu" binding opens the full screen
over the game with physics paused (`openMenu`/`closeMenu`/`toggleMenu`, resumed by the
route's `onLeave` hook). It calls
`extensions.rallyAcademy.getMenuData()` and `startDrill(id)`. The HUD panel is a Vue HUD
app too (`ui/modules/apps/RallyAcademy/app.vue`, `"vue": true` in `app.json`), compiled at
runtime by the same mod compiler, so the whole UI is Vue. Its input trace draws the throttle and brake
live from the car's electrics stream (`useStreams`) while driving, then the run's own trace (`trace` in the published
state, from `runRecord.inputTrace`) with its gates marked.

**Authoring.** Starts, finishes, stop zones/lines and gates are marked in-game and saved per
map and drill (`store.lua`). Planned (ROADMAP P1): promote captured setups into
`exercises.json` so a drill is ready without marking. Full stages are the game's Rally mode
([ADR 0006](decisions/0006-stages-are-the-games-rally-mode.md)).

**Progress** is saved per drill (`settings/rallyAcademyProgress.json`, `schemaVersion` 1).
Schema changes get a migration in `store.lua`.

**Edge cases to design for:** UI focus/menus open, physics paused, vehicle
switched mid-run, damage reset, leaving the map, teleports breaking the
trajectory, UI reloaded mid-session, conflicts with built-in missions/scenarios,
unknown vehicle configs.
