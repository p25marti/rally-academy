# Changelog

All notable changes to this mod. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/). Release process: docs/RELEASING.md.

## [Unreleased]

### Added
- Project infrastructure: `tools/dev.py` (validate, lint, test, reproducible
  build, live-link into BeamNG, log viewer, version bump), LuaJIT unit tests
  with BeamNG stubs, luacheck config, CI and tag-driven GitHub Releases.
- Developer documentation under `docs/` and decision records.
- `dev.py lint`/`test` on Windows use a LuaJIT + luacheck toolchain built in
  WSL (`tools/ci/setup-lua.sh`), so `check --strict` runs locally without CI.
- `modScript.lua` loads the extension automatically when the mod is enabled
  (ported from the earlier skeleton repo), so key bindings work before the HUD is opened.
- Start and finish are saved per drill and map (`settings/rallyAcademySetups.json`)
  and restored when you select the drill again, even after a restart.
- The mod logs its key events to `beamng.log` (tag `rallyAcademy`): load, drill
  selection, marks, Retry, run start/finish times, scoring, abandoned runs.
  `python tools/dev.py log --ours` shows just those.
- Every attempt is recorded: Retry starts a telemetry sampler in your car (inputs,
  gear, RPM, speeds, ABS, and per wheel speed/surface/downforce, one sample per
  frame) and keeps a run record for grading. Developers can save the last one with
  `extensions.rallyAcademy.saveLastRun()`.
- **Go to drill** button: loads the drill's map if needed, puts you in the drill's
  car and places you at your saved start (straight into a run) or at the venue,
  so you can move from drill to drill without setting anything up by hand.
- FWD-first drill lineup: every drill names its car (Covet Student Driver for the
  basics, Covet Gravel Rally for the rest) and its venue on West Coast USA or Utah
  (docs/MAPS.md). Five drills that need RWD/AWD are parked and labelled in the HUD.
- HUD shows the run time: a live clock while driving (tenths), the final
  time after the finish (hundredths), and the drill's best time.
- **B01 threshold braking is graded automatically**: Mark stop zone where the car
  should stop, then brake from 65+ km/h. When the car stops, the run is scored from its
  telemetry: entry speed, whether you stopped in the 5 m zone, and whether any wheel
  locked for more than 0.5 s. The panel shows a ✓/✗ line with the numbers for each
  check. Cone contact isn't graded yet. Drills can now declare typed grading rules
  (`assessment.rules`, `endWhen`); `dev.py validate` checks them.

- **Gates**: drive to a spot and press **+ Gate** to put a gate across the road there.
  Gates are saved per map, drawn as coloured posts (yellow next, green passed, red
  missed), and the panel names the gate and your speed as you pass it.
- **A04 throttle modulation is graded automatically**: hold 27–33 km/h through three
  gates without braking between them. The run ends at the last gate.
- The B01 stop zone and finish circles are drawn in the world.

- **Rally Academy screen in the main menu** (More... → Rally Academy): browse all 48
  drills in order with your progress and what each one grades, then **Start drill**
  to load its map, car and start in one press. Auto-graded drills are highlighted;
  the rest are tagged **Coming soon** and can still be practised with Pass/Miss.
  Tabs: **Exercises**, **Analysis** (attempts, pass rates, best times and progress per
  module, from your saved progress), **About** and **Credits**.

- Open the Academy from inside a map: a **Rally Academy** tab in the pause menu (Esc), and
  a **Rally Academy: Open menu** binding (Options → Controls) that opens it over the game
  with physics paused. Back returns you to driving.

- **Three more drills graded automatically**: A05 braking accuracy (stop 0–2 m before a line
  you mark with **Mark stop line**, without locking a wheel), B02 lockup recognition (lock the
  wheels from 55+ km/h and release within 1 s), and A02 launches (reach 40 km/h with a 1–2
  shift: no stall, no shift hanging in neutral, no long wheelspin).
- Telemetry records whether the engine is running, for stall detection.
- **Car event checks** for grading: hard contact (damage), spinning out, leaving the road
  (what the wheels are on), rolling over, using the handbrake and punctures. B02 now also
  requires no spin and staying on the road.

### Changed
- The in-drive panel is rebuilt in Vue, matching the Academy screen's look: tighter layout
  (four grade lines fit without scrolling), auto-graded / Coming soon tag, Retry highlighted.
  It no longer needs the old panel's workarounds for vanishing after UI reloads.
- Go to drill starts maps the way the game's Freeroam menu does, so it also works from
  the main menu.
- The panel no longer shows the "route detection and self-assessment only" note.

### Fixed
- Orphaned copies of the HUD panel (left alive by the game after map loads)
  sent duplicate commands to Lua; they now clean themselves up.
- Switching car mid-run froze the timer; the run is now abandoned and you're
  asked to press Retry in the new car.
- Changing map kept the old map's start; now each map loads its own saved setup.
- After a Lua reload the HUD showed a drill Lua had forgotten, so buttons did
  nothing; the HUD now re-selects it.
- Retry now repairs the car as well as returning it to the start, so a
  crashed run restarts clean.
- HUD panel failed to load on 0.39 (`Unknown provider: bngApiProvider`); it now
  uses the global `bngApi` like the stock apps.
- HUD app is listed under the **Rally** category instead of "Unknown".
- The HUD panel often vanished after a UI reload (a 0.39.4 app-loader quirk);
  it now notices an empty slot and remounts itself.
- Retry put the car back facing backwards.
- Pass/Miss only score a driven run. Pressing them before driving does
  nothing; with a finish gate, Pass mid-run is refused (Miss abandons the run
  without a time), so a partial time can no longer become your best.
- The run timer started the moment you pressed Retry (a one-frame velocity
  spike after the teleport); it now starts when the car leaves the start.

## [0.1.0] - 2026-10-13

### Added
- Initial starter scaffold (imported, untested in-game): GE extension with
  mark start/finish, retry, sim-time timer, self-assessed Pass/Miss and
  progress saving; HUD app; Retry/Pass/Miss input actions; 48 drill
  definitions.
