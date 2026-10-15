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

Add a test:

```lua
-- tests/lua/test_scoring.lua
local T = {}
function T.speed_band_passes_inside_tolerance()
  assert(require('ge.extensions.rallyAcademy.rules').speedBand(30, 27, 33))
end
return T
```

## In-game smoke test

Run before every PR that touches `mod/`, and before every release. Record the
BeamNG version and result in the PR.

1. `python tools/dev.py status`: link present, no conflicting zip.
2. Launch BeamNG → Free Roam → any map (Automation Test Track is a good default) → any car.
3. Add the panel. In 0.39: `Alt+Shift+U` (HUD Layouts) → select a layout →
   **Edit Layout** → **＋ Add** → search "academy" → add **Rally Academy (Prototype)**.
   Tip: first **Layout Actions → Duplicate** your Freeroam layout and **Use Layout**
   on the copy, so your normal layout stays untouched. Panel appears; drill list shows 48 entries.
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

When a step fails, paste the `dev.py log` output into the issue or the chat.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and on every PR: it
builds LuaJIT + luacheck with `tools/ci/setup-lua.sh` (cached), runs
`dev.py check --strict`, and uploads `rally_academy.zip` as a build artifact,
so every PR has a downloadable build to try in-game.
