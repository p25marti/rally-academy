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
| `pause` | Esc menu: the Rally Academy tab, each rail page (list → details, Analysis, About, Credits), and the game's own tabs after reopening |
| `b01` | Stop zone: clean PASS, late braking MISS, full brake MISS (lockup) |
| `a04` | Gates marked down the straight; 30 km/h PASS, too fast at gate 3 MISS |
| `stops` | A05 stop line and B02 lockup recovery, a PASS and a MISS each |
| `launch` | A02 launch with a 1-2 shift passes |
| `events` | A handbrake spin, a run on the grass verge and a puncture are detected (and the puncture isn't contact) |
| `goto` | Go to drill loads Utah in the gravel Covet for E08, then West Coast USA again for B01 (slow: two map loads) |
| `mainmenu` | From the main menu: Academy → A04 → Start drill lands in the drill with the HUD up (slow: map load) |

The driving scenarios need West Coast USA loaded (e.g. Go to drill on B01): they mark their
start on the BMP start straight, drive with the arcade gearbox, then restore the realistic
gearbox and remove the attempts they recorded from your progress. Code: `tools/ingame/`
(`game.py` talks to the server, `academy.py` holds mod helpers, `scenarios.py` the checks);
scripts read the mod through `extensions.rallyAcademy.debugState()`, not its internals.
Their verdicts on the same inputs match the recorded fixtures, but physics varies run to run
by a few tenths of a metre, so they check verdicts, not exact numbers.

## Recording a fixture

Recorded runs pin the grading rules to real physics (`tests/lua/test_fixtures.lua`):

1. Drive the run, by hand or with a scenario. The run record is kept until the next Retry.
2. In the console, or through the MCP server, run
   `extensions.rallyAcademy.saveLastRun('settings/rallyAcademy/fixtures/<name>.json')`.
3. Copy `<user folder>/settings/rallyAcademy/fixtures/<name>.json` into `tests/fixtures/`.
4. Describe how it was driven (game version, map, car, inputs) in the header of
   `test_fixtures.lua`, and add a test that today's rules give the verdict the game showed.

## Finding a venue

Tools for finding and checking places for drills (venue ideas live in [MAPS.md](MAPS.md)).
Load the map first.

1. **Drive and bookmark.** Bind **Rally Academy: Save spot** (Options → Controls) and press
   it wherever a drill could work. Each spot records pose, room to walls and barriers in eight
   directions, slope, the nearest road's width, and the surface under each wheel, in
   `<user folder>/settings/rallyAcademy/spots.json`.
2. **Let the finders look too.** They search the map's AI road network, with no driving:
   ```sh
   python tools/ingame/survey.py straights --min-length 150   # braking and speed drills
   python tools/ingame/survey.py corners --max-radius 40      # hairpins, decreasing/increasing radius
   python tools/ingame/survey.py hills                        # climbs and descents
   python tools/ingame/survey.py crests                       # jumps and crests
   python tools/ingame/survey.py open                         # open flat loose areas (terrain scan, slow)
   ```
   Or start from a drill: `python tools/ingame/survey.py fits D03` searches the map for places
   matching that drill's `venueNeeds` (add `--measure 5` to place the car on the best five
   and check their real surfaces and room, gravel ranked before tarmac).
3. **Review them together.** `python tools/ingame/survey.py report` (add `--open` for open
   areas, `--quick` to skip measuring) writes `venue-reports/<map>/index.html`: one card per
   saved spot or find, with an aerial view (HUD hidden), measured surfaces and room, and the
   command to go there. Each card also lists the drills the place **fits**, **maybe** fits
   (a saved spot can't prove a corner exists) or **nearly** fits, with what's missing. With
   `--quick` surfaces aren't measured, so fits ignore surface. It moves the car and camera, then puts them back, and moves the
   game's screenshot copies out of your user folder into the report. The report is
   local output and not committed.
4. **Go and look.** `survey.py goto 3` (a saved spot) or `goto --at=X,Y,Z,DX,DY` (a find),
   then `survey.py here` for room and surfaces, or `survey.py surfaces --along=20,60
   --side=-8,0,8` for a grid across the road.
5. **Record it** in MAPS.md, and use the surfaces in the drill's `on_surface` rule.

Smaller commands: `terrain X Y …` (terrain ground model at points), `configs [model]`,
`levels`, `spots [--all]`. Not every find is drivable: the road network includes bridges,
car parks and loops, which is why the report shows a picture.

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
    show in order with your progress; only auto-graded drills (A04, B01) lack the
    **Coming soon** tag. Pick one, then **Start drill**: its map loads, the
    menu closes, the HUD appears and you're in the drill car at its start or venue.
    The Analysis, About and Credits tabs open and show your totals, the version and the
    author. Re-test this after every game update (the Vue mod API is new in 0.39).
15. **In a map**: press Esc. The pause menu has a **Rally Academy** tab; its Exercises,
    Analysis, About and Credits buttons show those pages. Then bind **Rally Academy: Open
    menu** (Options → Controls) and press it while driving: the Academy opens over the game
    and physics pause; press it again, or Back, and you're driving again where you were.

When a step fails, paste the `dev.py log` output into the issue or the chat.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and on every PR: it
builds LuaJIT + luacheck with `tools/ci/setup-lua.sh` (cached), runs
`dev.py check --strict`, and uploads `rally_academy.zip` as a build artifact,
so every PR has a downloadable build to try in-game.
