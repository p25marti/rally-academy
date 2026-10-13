# Roadmap

Priorities, highest first. Move items into the CHANGELOG as they ship.

## P0 — Runs reliably in-game

- [ ] First in-game smoke test on the current build; record results in BEAMNG_API_NOTES.
- [ ] **Retry resets the car properly**: zero velocity, optionally repair, no
      leftover momentum. Pinned by `known_issue_retry_keeps_velocity`. Candidate:
      BeamNG's own save/load-home recovery, or a teleport with a physics reset.
- [ ] **Persist start/finish per drill and map** (`levelId`) so setup survives
      reloads and restarts.
- [ ] Log lines with a recognisable prefix so `dev.py log` finds them.
- [ ] Handle vehicle switch / level exit cleanly (reset to `setup`, don't crash).

## P1 — Authoring

- [ ] Capture and store `levelId`, vehicle model/config, start pose and finish gate in-game.
- [ ] Promote captured setups into `exercises.json` for drills with fixed locations.

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
| Retry teleports but keeps velocity/damage | Car arrives at the start still moving | `known_issue_retry_keeps_velocity` |
| Start/finish are in memory only | Setup lost on reload/restart | — |
| No in-game verification yet | Any engine API assumption may be wrong | BEAMNG_API_NOTES |
| Pass/Miss is self-assessed | No objective grading | P2/P3 |
| `recordAttempt` accepted in `ready` before driving | A run can be logged without being driven | — |
