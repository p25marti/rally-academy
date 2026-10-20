# Changelog

All notable changes to this mod. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/). Release process: docs/RELEASING.md.

## [Unreleased]

### Added
- **D03 tightening and D04 opening corners moved to the proving ground**: West Coast USA's gravel lane rebuilt flat
  next to the strips, same shape, same gates. Without the crest and the climb both corners carry more speed, so
  their medal speeds rose a little (D03 30 / 36 km/h, D04 48 / 54 km/h).
- **Barriers line the exercise paths**, set back with run-off (the owner's choice): red-and-white concrete race
  barriers 10 m outside the corner's bend, guardrail with posts along its approach and down both sides of every
  strip, spectator tape on the inside of the bend. A small mistake runs onto the grass; only a big one reaches a
  barrier, and hitting one counts as contact.
- **Natural autumn woods**: each tree species and leaf turns its own colour (copper beeches, crimson oaks, oaks still
  turning yellow-green, golden birches), so the mixed forests come out in a scatter of fall colours instead of one
  orange.
- **The proving ground's roads look driven on**: the gravel corner is a real dirt road now, with wheel ruts on the
  line, loose gravel pushed wide and ragged grassy edges; every strip has a natural edge into the grass and worn
  tracks down the middle; the asphalt strip has edge lines, a dashed 12 m test lane and a start line, with skid
  marks where B01 and A05 stop and handbrake swings round C04's cone on every surface; the ring and the mud pad
  have their tracks too. It's all paint on top: grip and grading are unchanged.
- **The proving ground feels lived in**: grass cover on the grass (green and autumn-dry tufts), bare forest
  floor under the woods, a low late-afternoon sun with long shadows, and the game's own rally kit as scenery: a
  service park behind the start line (team gazebos with tables and chairs, site cabins, a branded fence), start
  boards and clocks behind each strip, floodlights between the strips, safety cushions past their far ends, and
  a direction board and spectator tape at the corner. All of it stays off the drill areas.
- **Surface variants for module A** (ADR 0009): A01-A05 on dirt, gravel, asphalt and snow, each surface with its own
  progress and medals. Pick the surface on the HUD panel or the Academy screen (a dot shows your best medal on
  each). A02's launch on snow has its own, slower times; everything else plays the same targets on every surface.
  B01 threshold braking and C04 handbrake hairpins have the same four surfaces: brake earlier on snow, use less
  lock for the hairpin on asphalt.
- **A02 launches and A04 throttle hold moved to the proving ground's dirt strip** (A02 used to start on the BMP
  start line's tarmac). On loose ground a flat-out launch spins the wheels: feed the throttle in.
- **The proving ground looks like a real place**: a 2 km map now, the practice areas in a wooded valley with
  rolling hills all round (no more edge of the world), rock on the steep faces and about 17,000 trees in autumn
  colours, using the game's own tree library. Drill areas stay dead flat with trees kept 35 m back.
- **The Rally Academy proving ground, our own map** (ADR 0008): a small generated level that ships with
  the mod and loads in seconds. Flat gravel, asphalt, snow and dirt areas on grass, and a gravel corner.
- **Seven corner drills moved to a flat copy of their corner** (A07, A08, B04, C01, C02, C08, E02): the
  BMP downhill left rebuilt on the proving ground with the same shape and gates but no 14 m drop, so the
  technique, not the hill, decides the run. Targets re-measured there: A07's exit speeds rose to 35 / 46 /
  55 km/h and B04's to 30 / 42 / 50 km/h (the flat corner carries more speed), and C01's lift-off rotation
  fell to 4 / 6 / 8 degrees (on the downhill the slope had been doing part of the work).
- **Straight-line drills moved to the proving ground's dirt strip** (A03 gears, A05 stop line, B01 threshold
  braking, B02 lockup recovery): dead level and all dirt, where the arena's straight sloped up to 9.5 %.
  Targets unchanged.
- **The dirt arena and dirt circle drills moved to the proving ground too** (A01, B05, B06, B07, C04, C07, D01):
  the same courses on dead-level dirt, a few seconds' load away. Targets unchanged; every one passed its
  scenario there first time. Road-feature drills (A02, A04, D03-D06, D08, E05) stay on West Coast USA.
- **A03 downshifting also moved to the all-dirt straight**, and a gear now counts only once it's held
  0.3 s: 0.40's sequential gearbox can blip 3-2-3 while shifting up, which read as a downshift.
- **B01 threshold braking and B02 lockup recovery moved to a flat, all-dirt straight** (the BMP dirt
  arena's long straight, new venue bmp-dirt-arena-long). On the run-up their braking crossed the start
  line's tarmac patch onto gravel, so grip changed mid-stop; now the whole stop is on one surface.
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
- **D03 tightening and D04 opening corners are graded automatically, with medals**, on a gravel lane west of
  the town (new venues gravel-lane-tightening, gravel-lane-opening): ease off as a right-hander closes up;
  feed the throttle in as a left-hander opens without spinning the front wheels. Medals for exit speed.
- **Three drills on the West Coast USA Off-Road Circuit are graded automatically, with medals.** D05: a
  left hairpin over a blind crest, taken at a steady, conservative speed (medals for a tighter speed band).
  D06: an uphill corner, the crest and a downhill corner from the circuit's start, against the clock. E05:
  carry speed over a kicker crest while keeping all four wheels on the ground ("Wheels off the ground for
  0.30 s: ease off before the crest" otherwise). New venues offroad-blind-hairpin and offroad-kicker.
- **E02 FWD technique is graded automatically, with medals**, on the BMP downhill left: rotate the car a
  little with a lift or brake dab at turn-in, then get back on the throttle from the apex and let the front
  pull it out ("Back on the throttle for 1.8 s before the exit"; "drive the front out" otherwise).
- **D08 mixed-surface transitions are graded automatically, with medals**, on the BMP run-up: brake on
  the start line's tarmac, ease off as the car crosses onto gravel while steering gently left, and stop in
  a drawn zone without locking the wheels. Medals for smaller zones and less lockup.
- **D01 slaloms are graded automatically, with medals**, on the BMP dirt arena: weave through six
  drawn cones 15 m apart without touching one ("Went the wrong side of cone 3 (keep it on your right)"
  otherwise) and through the Finish gate, with time medals (14.8 s, 13.8 s).
- **C01 lift-off oversteer is graded automatically, with medals**, on the BMP downhill left: lift
  sharply at turn-in, no brake until the apex, and let the rear rotate ("Rear stepped out 11.0°");
  "carry more speed and lift sharply as you turn in" when it doesn't.
- **C07 figure-eights are graded automatically, with medals**, on the BMP dirt arena: round two drawn
  cones through five gates (crossing, right lobe, crossing, left lobe, crossing) without touching a cone,
  with time medals (23 s, 21.5 s).
- **C04 handbrake hairpins are graded automatically, with medals**, on the BMP dirt arena: a drawn
  hairpin round a pivot cone; one firm handbrake pull ("1 handbrake pull") must swing the rear round
  ("Rear stepped out 30.4°") before you drive out through the exit gate. Medals for driving out faster.
- **C08 Scandinavian flicks are graded automatically, with medals**, on the BMP downhill left: steer
  away from the corner, then sharply into it in one movement ("Flicked 180° away, then into the turn
  0.4 s later"), swing the rear and catch it. Turning straight in says "No flick".
- **C02 brake-induced rotation is graded automatically, with medals**, on the BMP downhill left: turn
  in, pulse the brake to swing the rear into the corner ("Rear stepped out 12.2°"), catch it and drive
  out between the exit posts. Medals for a bigger rotation and more exit speed.
- **B06 understeer correction is graded automatically, with medals**, on the BMP dirt circle: turn into
  a drawn half circle too fast so the front pushes wide ("Front pushed 2.9 m wide"), then ease off and
  bring the car back onto the line ("Back on the line by the regain"). Silver and gold for regaining the
  line sooner, from a controlled push.
- **B07 oversteer correction is graded automatically, with medals**, on the BMP dirt circle: brake
  hard or lift as you turn into a left-hander to make the rear step out ("Rear stepped out 14.3°"),
  catch it, and drive down a drawn exit lane with the slide over and the steering unwound ("Steering
  still 90° at the lane end: unwind the countersteer sooner" otherwise). Medals for catching a bigger
  slide (12°, 15°) with fewer corrections.
- **B05 left-foot braking is graded automatically, with medals**, on the BMP dirt circle: two laps
  of a 15 m ring drawn on the dirt, with silver and gold corridors either side of the line. Keep
  your right foot on the throttle all the way round ("Off the throttle for 0.6 s" otherwise) and dab
  the brake with your left foot to tighten the line ("4 brake dabs on the throttle"). The HUD ticks
  off each lap and says how far off the line you are. Courses can now have a circle to lap, and a
  drill can end after its laps (`endWhen: "laps"`).
- **B04 trail braking is graded automatically, with medals**, on the BMP downhill left: brake from
  the marker, keep easing the brake off as you turn in ("Trail-braked 1.2 s into the turn"), be off
  it by the apex gate ("Still braking at the apex (35%)" otherwise). Medals for exit speed.
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
- **Barriers follow the corner properly**: the concrete wall and guardrails were twisted off the curve (a rotation
  read the wrong way round); they now run joined up along it, guardrail beams towards the road, posts behind.
- A start you saved before a drill got its own course, or moved venue, no longer overrides it: the old
  start is cleared when you select the drill, and the HUD says why ("Your saved start was cleared
  because it now lays out its own course").
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
