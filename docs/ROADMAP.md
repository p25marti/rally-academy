# Roadmap

Priorities, highest first. Move items into the CHANGELOG as they ship.

## P0 — Runs reliably in-game

- [ ] First in-game smoke test on the current build; record results in BEAMNG_API_NOTES.
      2026-10-13 on 0.39.4: steps 1–8 and 10 pass; 9 (progress survives a
      restart) still to do.
- [x] ~~Retry keeps velocity~~: not reproducible on 0.39.4, `setPositionRotation`
      leaves the car at rest. Retry also faced the car backwards (fixed).
- [ ] **Retry repairs damage** (`resetBrokenFlexMesh` + vehicle-side reset, as
      `core_checkpoints` does), so a crashed run restarts clean.
- [ ] **Persist start/finish per drill and map** (`levelId`) so setup survives
      reloads and restarts.
- [ ] Log lines with a recognisable prefix so `dev.py log` finds them.
- [ ] Handle vehicle switch / level exit cleanly (reset to `setup`, don't crash).

## P1 — Authoring

- [ ] Capture and store `levelId`, vehicle model/config, start pose and finish gate in-game.
- [ ] Promote captured setups into `exercises.json` for drills with fixed locations.
- [ ] **Ship a "Rally Academy" HUD layout** with the mod (the game reads
      `/settings/ui_apps/originalLayouts/*.uilayout.json` from the virtual FS)
      and switch to it on drill start / back on exit via
      `ui_appLayouts.setUsedLayout`, so players never edit their Freeroam layout.

## P2 — First automatically graded drill

- [ ] Telemetry sampling adapter (see ARCHITECTURE → Telemetry).
- [ ] Generic gates, route deviation, penalties.
- [ ] One fully automatic drill end-to-end. Candidates: **B01** threshold
      braking (stop inside a 5 m zone, no sustained lock) or **A04** speed hold
      (27–33 km/h at three markers).

## P3 — Machine-readable drills

- [ ] Typed rule schema for all 48 drills; split into automatic and human-review rules.
- [ ] Rule evaluators with unit tests for each.

## P4 — Stages

- [ ] Stage assessments (F-module) built on BeamNG's rally/race tooling and pacenotes.

## P5 — Coaching and progression

- [ ] Progress migrations, warm-up detection, coaching feedback, difficulty
      progression, optional ghost comparison.

## Known issues (current build)

| Issue | Impact | Tracked by |
| --- | --- | --- |
| Retry doesn't repair damage | A crashed car restarts the drill still damaged | — |
| After `extensions.reload("rallyAcademy")` the HUD keeps showing the old drill while Lua is back to `idle` | Buttons do nothing until you pick a drill again | — |
| Start/finish are in memory only | Setup lost on reload/restart | — |
| No in-game verification yet | Any engine API assumption may be wrong | BEAMNG_API_NOTES |
| Pass/Miss is self-assessed | No objective grading | P2/P3 |
