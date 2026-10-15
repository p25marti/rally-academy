# Roadmap

Priorities, highest first. Move items into the CHANGELOG as they ship.

## P0 — Runs reliably in-game

- [ ] First in-game smoke test on the current build; record results in BEAMNG_API_NOTES.
      2026-10-13 on 0.39.4: steps 1–8 and 10 pass; 9 (progress survives a
      restart) still to do.
- [x] ~~Retry keeps velocity~~: not reproducible on 0.39.4, `setPositionRotation`
      leaves the car at rest. Retry also faced the car backwards (fixed).
- [x] Retry repairs damage (`spawn.safeTeleport` with vehicle reset).
- [x] Persist start/finish per drill and map (`settings/rallyAcademySetups.json`).
- [x] Log lines with a recognisable tag (`GELua.rallyAcademy.rallyAcademy`); `dev.py log --ours`.
- [x] Handle vehicle switch / level exit cleanly: a run in progress drops back to
      `setup`; leaving a map clears its start/finish; loading one brings in that map's setup.

## P1 — Authoring

- [ ] Capture and store `levelId`, vehicle model/config, start pose and finish gate in-game.
- [ ] Promote captured setups into `exercises.json` for drills with fixed locations.
- [ ] Match every drill car to a real config (`modelId`, `configPath`) and check ABS/ESC/TCS
      and gearbox per [VEHICLES.md](VEHICLES.md#to-check-in-game).
- [ ] **Ship a "Rally Academy" HUD layout** with the mod (the game reads
      `/settings/ui_apps/originalLayouts/*.uilayout.json` from the virtual FS)
      and switch to it on drill start / back on exit via
      `ui_appLayouts.setUsedLayout`, so players never edit their Freeroam layout.

## P2 — First automatically graded drill

Capabilities, drill-by-drill needs and build order: [GRADING.md](GRADING.md).
Reuse before building: [PRIOR_ART.md](PRIOR_ART.md).

- [x] Telemetry sampling and per-attempt run records ([ADR 0004](decisions/0004-telemetry-transport.md),
      ARCHITECTURE → Telemetry).
- [x] Generic gates: marked in-game, saved per map, drawn in the world, graded by rules.
- [ ] Route deviation (corridor or road edge) and penalties.
- [x] One fully automatic drill end-to-end: **B01** threshold braking (entry
      speed, stop inside a 5 m zone, no sustained lock), checked against recorded runs.
      Cone contact is not graded yet (needs scene control).
- [x] A04 speed hold: 27–33 km/h at three gates, no braking between them.

## P3 — Machine-readable drills

- [ ] Typed rule schema for all 48 drills; split into automatic and human-review rules.
- [ ] Rule evaluators with unit tests for each.

## P4 — Stages

- [ ] Stage assessments (F-module) built on BeamNG's rally/race tooling and pacenotes.

## P5 — Coaching and progression

- [ ] Drivetrain options per drill (FWD/RWD/AWD), with per-option progress and
      thresholds. Proposal: [VEHICLES.md](VEHICLES.md#drivetrain-options); needs a decision record.

- [ ] Progress migrations, warm-up detection, coaching feedback, difficulty
      progression, optional ghost comparison.

## Known issues (current build)

| Issue | Impact | Tracked by |
| --- | --- | --- |
| Retry may shift the car if the start spot is occupied | `safeTeleport` avoids overlaps, so a start right beside cones/props can be nudged | — |
| No in-game verification yet | Any engine API assumption may be wrong | BEAMNG_API_NOTES |
| Pass/Miss is self-assessed (all drills but B01 and A04) | No objective grading | P2/P3 |
