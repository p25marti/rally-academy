# Rally Academy for BeamNG — developer starter (alpha)

This package is a *prototype and source scaffold*, **not** a validated/complete game mod.
Developed against the *published* BeamNG 0.39 modding conventions; it has **not been launched or tested inside BeamNG**.

## What works conceptually
- Imports **all 48 drills** from the earlier Excel workbook into data-only JSON.
- Uses a single **Game Engine Lua extension** and a **native HUD app** (AngularJS directive, per official docs).
- Adds three mod-specific controller actions (Retry / Pass / Miss) for keyboard, wheel, Stream Deck or button-box binding.
- Uses an explicit reusable start transform, a manually marked finish circle, sim-time timing, retry without mission reload.
- Saves manually assessed session results to `settings/rallyAcademyProgress.json` (verify write path in-game).

## What is NOT implemented
- Auto map loading, exact car/config spawning, predefined start coordinates, visual cone courses.
- Real telemetry validation: wheel lock, lateral slip, handbrake input, cone impacts, brake pressure, collision damage, steering traces, coaching insights.
- Real grades for the 48 different driving mechanics. A finish gate *only ends timing*; a person must judge Pass/Miss.
- Native mission cards, achievement/badge UI, sync, replay ghosts, detailed persistent attempts.

## Installation / first smoke test
1. Make sure `mod/rallyAcademy` isn't used as a wrapper inside the zip. The final zip must open directly with `gameplay/`, `lua/` and `ui/`.
2. Put `rally_academy_prototype.zip` under your BeamNG **user folder** `/mods/`, or unpack the `mod` *contents* to `userFolder/mods/unpacked/rally_academy/`.
3. Load Free Roam on any map with any existing vehicle.
4. From the HUD Apps editor, add **Rally Academy (Prototype)**. It loads the Lua extension on initialization. If absent, restart game; check Lua console for errors.
5. Select `A01`, drive to a starting point, click **Mark start**. Optionally drive to a finish spot and click **Mark finish**.
6. Click **Retry**. Drive forward; if a finish was marked, driving within 5 m of it stops the timer. Use **Pass** or **Miss** to manually grade a repetition, then Retry.
7. Bind `Rally Academy: Retry` to a spare wheel button in `Options > Controls`. Don't overwrite your steering/pedal maps.

## Key development tasks to make it production quality
- **P0** Correct the smoke test until UI init, Lua event delivery, and retry work reliably on the latest game build.
- **P1** Author stable `levelId`, vehicle model/config, 3D start pose and finish gate in the World Editor.
- **P2** Implement generic gates/route deviation/penalties plus one automatically scored drill with validated telemetry.
- **P3** Make 48 definitions fully machine-executable; implement objective rule evaluators and separate human-review rules.
- **P4** Build stage assessments with the first-party Rally Editor / `rallyStage` for pacenotes and stages.
- **P5** Add persistence migrations, warmup detection, coach feedback, difficulty progression and optional ghost comparisons.

## Useful API docs
- https://documentation.beamng.com/modding/programming/extensions/
- https://documentation.beamng.com/modding/ui/app_creation/
- https://documentation.beamng.com/modding/input/actions/
- https://documentation.beamng.com/world_editor/windows/race_path_editor/
- https://www.beamng.com/game/news/patch/beamng-drive-v0-39/
- https://docs.beamng.com/modding/mod-support/mod_packing/

## Attribution
The imported 48 drill definitions are adapted from a user-specific curriculum, not official BeamNG missions or licensed reproduction of any rally driving school's teaching materials.
