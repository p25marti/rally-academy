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

- **Rally Academy screen in the main menu** (More... → Rally Academy): browse all the
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

- `python tools/dev.py ingame <scenario>`: scripted in-game checks (smoke, B01, A04,
  A05/B02, A02) through the game's MCP server, kept in `tools/ingame/`.

- **Save spot** binding (Options → Controls → "Rally Academy: Save spot"): bookmark where you
  are as a possible drill venue, with room, slope, the nearest road and surfaces measured.
- Every drill now says what kind of place it needs (`environment.venueNeeds`: shape, length,
  width, radius, grade, surfaces), and the venue tools use it: the report says which drills
  a place fits, and `survey.py fits <drill>` finds places for one.
- **A01 steering and spatial awareness is graded automatically, with medals.** Go to drill
  lands you at the BMP dirt arena with the course laid out: a 3 m gate, a cone to keep on your
  left and a parking box, drawn in the world. Stop once with the whole car inside the box,
  without touching the gate posts or the cone and without reversing. The HUD ticks off
  Gate / Cone / Box as you go, flags a clipped marker straight away, and near the box reads
  out where you are ("0.6 m to go · 0.2 m left of centre") with the car's outline on the
  ground. A pass is **bronze**; the smaller silver and gold boxes inside it, with time targets
  (14 s, 10 s), earn **silver** and **gold**, and the HUD says what the next medal needs.
  Best medal and medal counts are saved and shown in the Academy screen.
- **Stream Deck and key bindings:** every Rally Academy command is now a bindable input action
  (new: Go to drill, Next / Previous drill, Mark start, Use venue start, Mark finish, Add gate,
  Clear gates, Auto-retry on/off), and the mod ships default bindings on F13–F24, keys no
  keyboard has, so a Stream Deck's Hotkey keys work out of the box. A ready-made Stream Deck
  Mk.2 profile with BEAM.deck icons is in `extras/streamdeck/` (double-click to import). Layout
  and setup: `docs/STREAM_DECK.md`.
- **A02 clutch engagement and launches, on a course with medals.** Go to drill lands you on the BMP
  start line with a 40 km/h gate drawn 60 m down the straight. Launch, shift 1→2 and be at 40 km/h
  through the gate; the run ends there (nobody has to stop on the straight's banked end). The run
  reports your 0–40 km/h time; silver and gold need a quicker launch (4.5 s, 3.5 s), a quicker shift
  and less wheelspin.
- **A03 gear selection and downshifting is graded automatically, with medals.** Go to drill puts
  you on the BMP run-up with a 60 km/h gate and a stop box on the flat past the start line. Reach
  60 km/h in 3rd, then brake and downshift one gear at a time to 2nd and stop in the box. New checks:
  skipping a gear on the way down ("Skipped from 4th to 2nd") and over-revving ("Over-revved to
  7200 rpm in 2nd at 45 km/h"). Silver and gold need lower revs, quicker shifts, less lockup and a
  more accurate stop.
- **A04 throttle modulation on a course, with medals.** The three gates are laid out for you on the
  BMP run-up (no more + Gate). Hold 30 km/h through them without braking: 27–33 km/h is a pass,
  28–32 silver, 29–31 gold. Gate speeds now show tenths ("29.3 / 30.0 / 29.1 km/h").
- **A05 braking accuracy on a course, with medals.** The stop line is laid out for you in the BMP
  dirt arena, with a cone at each end and gold, silver and bronze bands before it. Stop with the
  front bumper 0–2 m before it (silver 1 m, gold 0.5 m), measured from your car's own bumper; the
  HUD reads out the distance as you approach.
- **A07 basic racing lines and A08 apex and exit selection are graded, with medals**, on a new
  BMP corner venue: a 124° downhill left with a straight approach. A07: through the 3 m exit gate at
  the track-out, all wheels on the gravel; medals for exit speed (40 and 48 km/h). A08: a 3 m
  late-apex gate on the inside, the exit gate, then a straight run to the finish with no steering
  corrections ("2 steering corrections after the exit gate"). Course gates can now face a corner's
  road (`headingDeg`).
- **B01 threshold braking and B02 lockup recovery on courses, with medals.** Both lay out their stop
  zone on the BMP run-up's flat gravel (no more Mark stop zone). B01: stop with the car's centre in
  the zone, drawn with smaller silver (3 m) and gold (1.5 m) zones inside it, and less lockup for each
  medal; the HUD reads "4.2 m to the zone centre". B02: lock and release inside a 40 m stop area;
  silver and gold need a quicker release (0.7 s, 0.5 s).
- **HUD fits long grade lists:** failed checks first, then the passed checks with numbers, up to
  five lines; the rest fold into "N more checks passed".
- **B01, B02, B03 and A03 start on the BMP run-up**, 120 m behind the start line (new venue
  `bmp-gravel-runup`), so their stops land on flat gravel instead of the start straight's banked
  end (it banks 9–16° from 100 m past the line).
- **Auto-retry:** after an auto-graded run, the next attempt starts after 3 s (drive off to
  stay where you are; it waits while a stop zone or gates still need marking). On by default; the HUD's Auto-retry button turns it off, remembered in
  `settings/rallyAcademy/prefs.json`.
- Authored courses in the drill data (`assessment.course`: gates, cones, a parking box, laid out
  from the start) and medal tiers (`assessment.tiers`); new rules `cones_passed`,
  `markers_clear` (the car's measured footprint against drawn cones and posts), `park_in_box`,
  `no_reverse` and `max_time`. **Move course here** re-lays a course from where you are;
  **Use venue start** puts it back.
- Venue catalogue (`tools/ingame/catalog.py`): surveys a map's practice spots by the surface you
  drive on and kind of place, measures and fit-tests them, and keeps the results in
  `docs/venue-catalog.json` and `docs/VENUE_CATALOG.md`.
- Venue fit test (`survey.py fit <drill> --spot ID`): drives the drill's kind of run at a
  candidate place and says whether it fits, without touching your drills or progress.
- Venue tools for contributors: road-network finders (straights, corners, hills, crests),
  an open-area terrain scan, and an HTML venue report with aerial views
  (`tools/ingame/survey.py`).

### Removed
- Six stage drills (F01 pacenotes, F02 consistency, F03 regularity, F04 unfamiliar stages, F05
  long stage, F08 full stage): the game's own Rally mode does these properly, and the Academy
  now points to it. F06 (punctures) and F07 (setup comparisons) stay, with the same IDs.

### Changed
- Drill venues are shared data (`venues.json`): six named venues instead of a copy of the
  map and spawn in each drill. Nothing changes in play.
- The HUD app is listed as "Rally Academy" (was "Rally Academy (Prototype)"), and the Academy's
  drill details show directions to the venue spot.
- The in-drive panel is rebuilt in Vue, matching the Academy screen's look: tighter layout
  (four grade lines fit without scrolling), auto-graded / Coming soon tag, Retry highlighted.
  It no longer needs the old panel's workarounds for vanishing after UI reloads.
- Go to drill starts maps the way the game's Freeroam menu does, so it also works from
  the main menu.
- The panel no longer shows the "route detection and self-assessment only" note.

### Fixed
- Opening the **Rally Academy** tab in the Esc menu broke the whole menu ("No layout data was
  received from the router", then missing tabs) until the UI was reloaded: its buttons had no
  icons. They do now, and the tab shows a compact drill list with details for its narrow card.
- The drill drop-down on the in-drive panel couldn't be clicked open (a native list doesn't open
  in the game's UI). It's now the game's own drop-down, grouped by module, with search.
- The in-drive panel disappeared when a drill without automatic grading was selected (an empty
  rules list from Lua isn't a JavaScript array).
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
