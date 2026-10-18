# Testing

BeamNG can't run in CI, so testing has three layers. Each catches different
problems.

| Layer | Runs where | Catches | Command |
| --- | --- | --- | --- |
| Static checks | local + CI | broken JSON, bad drill data, version drift, Lua syntax/undefined globals, broken zip layout | `dev.py validate`, `dev.py lint` |
| Unit tests | local + CI | logic and state-machine regressions, under LuaJIT with stubbed engine globals | `dev.py test` |
| In-game smoke test | your PC, manually | anything about the real engine: API names, UI loading, physics, input bindings | checklist below |

`python tools/dev.py check --strict` runs the first two layers plus a build,
exactly as CI does.

## Unit tests

- Live in `tests/lua/test_*.lua`. Each file returns a table of `name = function`.
  The runner (`tests/lua/run.lua`) has no dependencies.
- Pure modules have their own files (`test_rules*.lua`, `test_gates.lua`,
  `test_runRecord.lua`, `test_fixtures.lua` for recorded in-game runs). The extension is
  tested by feature: `test_session`, `test_setups`, `test_telemetry`, `test_go_to_drill`,
  `test_grading_flow`, `test_gates_flow` and `test_menu`, sharing `ra_helpers.lua` (a fresh
  extension on the stubs, scripted runs that feed telemetry, and asserts).
- `tests/lua/beamng_stubs.lua` fakes the engine: `be:getPlayerVehicle`, a
  controllable vehicle (position/velocity/teleports), `vec3`, `guihooks.trigger`
  (captured events), and `jsonReadFile`/`jsonWriteFile` (reads the real
  `mod/` files, writes to memory).
- **Stubs encode assumptions.** When the game proves an assumption wrong (a method
  is named differently, a value has different units), fix the stub *first*,
  watch the tests fail, then fix the mod.
- Tests named `known_issue_*` deliberately pin current buggy behaviour (from
  [ROADMAP](ROADMAP.md)). The commit that fixes the bug flips the test.
- Prefer testing through the extension's public functions (`select`,
  `markStart`, `retry`, `onUpdate`, `recordAttempt`) and asserting on the
  published `rallyAcademyState` and on vehicle side effects.
- Assert with the helpers (`H.eq`, `H.has`, `H.near`), which raise on failure. A bare
  boolean expression asserts nothing.
- Engine tests use the **test drills** T01-T04 from `tests/fixtures/test_drills.json`, which the stubs
  add after the shipped catalogue: T01/T02 self-assessed (Student Driver / Gravel Rally), T03 marked
  gates, T04 a marked stop zone. Shipped drills keep changing as they get courses and medals, so tests
  about the engine shouldn't depend on them; tests about a drill (its fixtures, its course) use it by
  name. `dev.py validate` checks the test drills like shipped ones.

Add a test:

```lua
-- tests/lua/test_menu.lua (an extension test)
local H = require('ra_helpers')
local eq, setup = H.eq, H.setup
local T = {}
function T.menu_lists_the_drills_in_order()
  local _, M = setup()
  eq(M.getMenuData().lessons[1].id, 'A01', 'first drill')
end
return T
```

## Automated in-game scenarios

With BeamNG running and the mod linked (`dev.py link`), scripts drive the real game through
its built-in MCP server (`127.0.0.1:29292/mcp`, 0.39+):

```sh
python tools/dev.py ingame                 # list scenarios
python tools/dev.py ingame smoke b01 a04   # run some; exit code 1 if any check fails
```

| Scenario | What it checks |
| --- | --- |
| `smoke` | UI reload leaves one HUD panel; the drill drop-down opens on a click and picks; a drill without rules renders; menu opens/closes with physics paused/resumed |
| `a01` | The course is laid out at the BMP dirt arena with no marking; a centred run passes with a medal; the wrong side of the cone and a clipped gate post miss; auto-retry resets the car (the car steers by script: `academy.follow_path`) |
| `pause` | Esc menu: the Rally Academy tab, each rail page (list → details, Analysis, About, Credits), and the game's own tabs after reopening |
| `b01` | B01 on its course (BMP run-up, stop zone 30 m past the line): threshold braking earns a medal; braking too hard overshoots and misses; full brake misses (lockup) |
| `a04` | A04 on its course (BMP run-up, three gates): a steady 30 km/h earns a medal; 40 km/h at gate 3 misses |
| `stops` | A05 on its course (BMP dirt arena, stop line 60 m ahead) and B02 on its course (BMP run-up, 40 m stop area), a PASS and a MISS each |
| `trail` | B04 on the BMP downhill left: trail braking into the corner earns a medal; braking only before turn-in misses |
| `slalom` | D01 on the BMP dirt arena: a clean weave through six cones earns a medal; too fast clips a cone |
| `liftoff` | C01 on the BMP downhill left: a lift at turn-in rotates the car for a pass (up to five tries: scripted lifts pass a third to half the time); too slow misses |
| `figure8` | C07 on the BMP dirt arena: a clean figure-eight earns a medal; too fast runs wide and misses |
| `hairpin` | C04 on the BMP dirt arena: one handbrake pull round the pivot cone earns a medal; no handbrake misses |
| `flick` | C08 on the BMP downhill left: a lift-and-flick passes (up to five tries: scripted flicks pass a third to half the time); no flick misses |
| `rotation` | C02 on the BMP downhill left: a brake pulse after turn-in rotates the car for a medal (up to three tries); no rotation misses |
| `understeer` | B06 on the BMP dirt circle: a push corrected by lifting earns a medal; too slow to push, or no lift, misses |
| `oversteer` | B07 on the BMP dirt circle: a hard brake at turn-in steps the rear out and the caught slide earns a medal; no slide misses |
| `circle` | B05 on the BMP dirt circle: two laps on the throttle with brake dabs earn gold; no dabs, or lifting off to brake, miss |
| `corners` | A07 and A08 on the BMP downhill left (Covet Gravel Rally, racing line from `lines.py`): a clean line earns a medal on each; A07 clipping the exit post and A08 weaving after the exit miss |
| `gears` | A03 on its course (BMP run-up, sequential gearbox with scripted gears): 3rd to 2nd into the stop box earns a medal; 3rd straight to 1st misses |
| `launch` | A02 on its course (from the BMP start line; the run ends at the 40 km/h gate): a flat-out launch earns a medal; 34 km/h at the gate misses |
| `events` | A handbrake spin, a run on the grass verge and a puncture are detected (and the puncture isn't contact) |
| `goto` | Go to drill loads Utah in the gravel Covet for E08, then West Coast USA again for B01 (slow: two map loads) |
| `fit` | Venue fit test: B01 fits its straight but not facing the barrier; B05's circle fits the BMP dirt arena |
| `mainmenu` | From the main menu: Academy → A04 → Start drill lands in the drill with the HUD up (slow: map load) |

The driving scenarios need West Coast USA loaded (e.g. Go to drill on B01): `a01` drives its
course at the BMP dirt arena; the others mark their start on the BMP start straight, drive with the arcade gearbox, then restore the realistic
gearbox and remove the attempts they recorded from your progress. Code: `tools/ingame/`
(`game.py` talks to the server, `academy.py` holds mod helpers, `scenarios.py` the checks);
scripts read the mod through `extensions.rallyAcademy.debugState()`, not its internals.
Every graded run in a scenario also checks the HUD panel still fits (its content no taller than
the 390 × 340 panel); an overflow fails the scenario even if it didn't ask. Their verdicts on the same inputs match the recorded fixtures, but physics varies run to run
by a few tenths of a metre, so they check verdicts, not exact numbers.

## Recording videos

`python tools/ingame/record.py <scenario> ...` (or `--all` for every drill scenario) films scenarios from
inside the game for previewing changes away from the rig: a recorder built in memory saves a JPG every
1/20 s of simulation time with `createScreenshot2`, then ffmpeg encodes `recordings/<scenario>.mp4` (H.264,
about 1.2 Mbit/s, under 30 MB for a three-minute scenario) and the frames go to the Recycle Bin. Each clip
shows the scenario's pass and miss runs with the HUD.

It needs an ffmpeg with an H.264 encoder (`libx264`, `libopenh264` or `h264_mf`): set `RA_FFMPEG`, or it is
looked for on PATH and in apps' folders under Program Files and AppData (the owner's machine has one in
MOZA Pit House). `recordings/` is git-ignored.

## Recording a fixture

Recorded runs pin the grading rules to real physics (`tests/lua/test_fixtures.lua`):

1. Drive the run, by hand or with a scenario. The run record is kept until the next Retry.
2. In the console, or through the MCP server, run
   `extensions.rallyAcademy.saveLastRun('settings/rallyAcademy/fixtures/<name>.json')`.
3. Copy `<user folder>/settings/rallyAcademy/fixtures/<name>.json` into `tests/fixtures/`.
4. Describe how it was driven (game version, map, car, inputs) in the header of
   `test_fixtures.lua`, and add a test that today's rules give the verdict the game showed.

## Finding a venue

Finding, reviewing, fit-testing and adding drill venues has its own guide:
[VENUES.md](VENUES.md).

## In-game smoke test

Run before every PR that touches `mod/`, and before every release. Record the
BeamNG version and result in the PR.

1. `python tools/dev.py status`: link present, no conflicting zip.
2. Launch BeamNG → Free Roam → any map (Automation Test Track is a good default) → any car.
3. Add the panel. In 0.39: `Alt+Shift+U` (HUD Layouts) → select a layout →
   **Edit Layout** → **＋ Add** → search "academy" → add **Rally Academy**.
   Tip: first **Layout Actions → Duplicate** your Freeroam layout and **Use Layout**
   on the copy, so your normal layout stays untouched. Panel appears; drill list shows 42 entries.
4. `python tools/dev.py log`: no errors mentioning `rallyAcademy`.
5. Select a drill → **Mark start** → drive ~50 m → **Mark finish** → **Retry**.
   The car returns to the start facing the same way.
6. Drive through the finish. The timer stops and the phase shows `review`.
7. **Pass**, then **Retry**, then **Miss**. The counter shows `1/2`.
8. Options → Controls: search "Rally Academy" and bind **Retry** to a key. Pressing it works.
9. Restart the game. `settings/rallyAcademyProgress.json` in the user folder
   still has the attempts, and selecting the same drill on the same map says
   "Loaded your saved start…"; **Retry** works without marking again.
10. Pause physics mid-run (`J`). The timer stops advancing.
11. **Go to drill** for a drill on another map (e.g. E08 from West Coast USA): the map
    loads, you're in the drill's car at the venue, and the panel says what to do next.
    Then a drill on the same map with a different car (e.g. B04 after A01): the car
    swaps and is placed within about a second.
12. **B01** (auto-graded): **Go to drill** → **Mark start** → do one braking run and
    stop → **Mark stop zone** where you stopped → **Retry**. Brake from 65+ km/h into
    the zone. When the car stops, the panel shows three ✓/✗ lines and PASS or MISS,
    and the counter goes up without pressing Pass. Locking the brakes
    for more than 0.5 s gives a MISS that names the wheel.
13. **A04** (gates): **Go to drill** → **Mark start** → drive 30, 55 and 80 m down the
    straight and press **+ Gate** at each. Coloured posts appear across the track. Then
    **Retry** and hold about 30 km/h: each gate shows its speed as you pass it, and
    the run ends at gate 3 with PASS or MISS.
14. **Academy screen**: from the main menu, **More...** → **Rally Academy**. All 42 drills
    show in order with your progress; only auto-graded drills (A01, A02, A04, A05, B01, B02) lack the
    **Coming soon** tag. Pick one, then **Start drill**: its map loads, the
    menu closes, the HUD appears and you're in the drill car at its start or venue.
    The Analysis, About and Credits tabs open and show your totals, the version and the
    author. Re-test this after every game update (the Vue mod API is new in 0.39).
15. **In a map**: press Esc. The pause menu has a **Rally Academy** tab; its Exercises,
    Analysis, About and Credits buttons show those pages. Then bind **Rally Academy: Open
    menu** (Options → Controls) and press it while driving: the Academy opens over the game
    and physics pause; press it again, or Back, and you're driving again where you were.
16. **A01** (authored course, medals): **Go to drill**. You land at the BMP dirt arena ready
    to drive, with a gate, a cone (a chevron shows the side to pass) and a parking box with
    two smaller boxes inside it, drawn ahead. Drive through, keep the cone on your left, and
    stop in the box: the HUD ticks Gate / Cone / Box, reads out the distance near the box,
    and shows a medal and what the next one needs. Three seconds later you're back at the
    start; drive off during the countdown and you stay put.

When a step fails, paste the `dev.py log` output into the issue or the chat.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and on every PR: it
builds LuaJIT + luacheck with `tools/ci/setup-lua.sh` (cached), runs
`dev.py check --strict`, and uploads `rally_academy.zip` as a build artifact,
so every PR has a downloadable build to try in-game.
