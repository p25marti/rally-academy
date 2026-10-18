# Agent guide

For coding agents (Claude Code, Codex, Cursor, …) and anyone wanting the short version.
Humans contributing: start with [CONTRIBUTING.md](CONTRIBUTING.md). This file summarises
the docs; when they disagree, the docs win and this file needs fixing.

**Read first:** [docs/PRODUCT.md](docs/PRODUCT.md) (what we're building, owner decisions),
then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), then the doc for your task.

## Repo map

| Path | What |
| --- | --- |
| `mod/` | Exactly the shipped zip root. Nothing else goes in it |
| `mod/gameplay/rallyAcademy/exercises.json` | The drills: source of truth ([DRILL_DATA](docs/DRILL_DATA.md), [ADR 0002](docs/decisions/0002-drill-data-source-of-truth.md)) |
| `mod/gameplay/rallyAcademy/venues.json` | Named venues (map, spawn) that drills refer to by id ([ADR 0007](docs/decisions/0007-venues-as-data.md)) |
| `mod/lua/ge/extensions/rallyAcademy.lua` | GE extension: session state machine, timing, grading flow, engine hooks |
| `mod/lua/ge/extensions/rallyAcademy/` | `rules.lua`, `gates.lua`, `layout.lua` (authored courses, car footprint), `runRecord.lua` (pure); `store.lua` (files), `course.lua` (drawing) |
| `mod/lua/vehicle/extensions/rallyAcademy/telemetry.lua` | Sampler inside the car's Lua VM ([ADR 0004](docs/decisions/0004-telemetry-transport.md)) |
| `mod/ui/modules/apps/RallyAcademy/app.vue` | In-drive HUD panel (Vue HUD app) |
| `mod/ui/ui-vue/mods/rallyAcademy/` | Academy screen: main menu, pause tab ([ADR 0005](docs/decisions/0005-main-menu-via-vue-ui-mods.md)) |
| `tests/lua/` | Unit tests under LuaJIT with engine stubs; `tests/fixtures/` = recorded in-game runs |
| `mod/lua/ge/extensions/core/input/actions/` + `mod/settings/inputmaps/` | Input actions and their default keys (F13–F24, never Alt: [STREAM_DECK](docs/STREAM_DECK.md)) |
| `tools/dev.py` | validate, lint, test, build, link, log, ingame |
| `tools/ingame/` | Scripted checks and venue surveys through the game's MCP server |
| `docs/` | Everything else; `docs/decisions/` = ADRs |
| `reference/` | Historical design input; not shipped, not authoritative |

## Ground rules

- **Say exactly how something was verified.** "Unit tests pass", "verified in-game by
  the `a04` scenario", "the owner drove it on the rig" and "untested in-game" are different
  claims. Scripted runs use the arcade gearbox and steady inputs, so they aren't a substitute
  for the owner driving. Record engine behaviour you confirmed in
  [BEAMNG_API_NOTES](docs/BEAMNG_API_NOTES.md), with the game version.
- Lua is authoritative for state and logic; the UI only displays and sends commands.
- Keep engine calls thin and at the edges so logic stays unit-testable. A new engine global
  goes in `.luacheckrc`, the test stubs and BEAMNG_API_NOTES (status "unverified" until
  checked in-game).
- Follow the owner's standing decisions in [PRODUCT.md](docs/PRODUCT.md); ask before
  reversing one. One-way or large choices get an ADR in `docs/decisions/`.
- [docs/IDEAS.md](docs/IDEAS.md) is a someday/maybe list, not a plan. Don't build from it
  unless the owner asks. Do add ideas there instead of letting them get lost.
- The owner's BeamNG user folder: only `mods/unpacked/rally_academy/` is ours to write
  (and `settings/rallyAcademy*`, which the mod itself writes). See "Live game" for the one
  side effect to clean up.

## Commands

```sh
python tools/dev.py check --strict     # validate + lint + unit tests + build; must pass
python tools/dev.py ingame smoke pause # with the game running (UI or engine-facing changes)
python tools/dev.py ingame             # list scenarios
python tools/dev.py link               # live-link mod/ into the game (junction)
python tools/dev.py log --ours         # the mod's lines from beamng.log
python tools/dev.py ship -F msg.txt    # check --strict, then branch, commit, fast-forward main, push
```

On Windows, Lua tools run through WSL automatically ([DEVELOPMENT](docs/DEVELOPMENT.md#tooling)).

## Working with the live game

BeamNG 0.39+ runs an MCP server at `http://127.0.0.1:29292/mcp` (JSON-RPC). Agents with MCP
support can use it directly; `tools/ingame/game.py` wraps it for scripts. Useful tools:
`run_lua` (GE Lua), `run_lua_vehicle` (the car's Lua), `ui_eval` / `ui_click` / `ui_key`
(the UI), `inject_input` (driver inputs), `set_position`, `set_camera`, `get_ui_state`,
`reload_ui`, `screenshot_image`.

Learned the hard way (0.39.4):

- **Async tools.** Some answer "call again in a moment"; the result comes on a later call.
  `run_lua_vehicle` always does: call, wait about a second, call again.
- **`ui_eval`:** a `\n` inside the JS arrives as a real newline (it breaks regex literals
  and the call returns "async" forever). `return await …` doesn't work; store the result on
  `window` and read it back with a second call.
- **Screenshots** (`screenshot_image`, `screenshot`) also save a copy to
  `<user folder>/screenshots/mcp/`. That's the one write outside our folders: move your
  captures to the Recycle Bin when you're done (ask before hard-deleting).
- **Reading mod state:** use `extensions.rallyAcademy.debugState()`, not `debug.getupvalue`.
- **Reloading after edits:**
  - `extensions.reload('rallyAcademy')` re-runs the extension, which clears its own module
    cache.
  - The car keeps the old telemetry sampler until `extensions.unload('rallyAcademy_telemetry')`
    runs in vehicle Lua.
  - Vue files hot-reload; `reload_ui` rebuilds the whole UI, after which the HUD remounts for
    a moment, so poll before you assert.
- **Lua tables in JS:** an empty Lua table arrives as `{}`, not `[]`. Check `Array.isArray`
  before using a list.
- **UI rules:**
  - A native `<select>` can't be opened in BeamNG's UI; use `BngDropdown`.
  - Pause-menu mod buttons need a valid `icon`, or the whole Vue UI breaks until a reload.
- **Map loads** take 40–70 s and the MCP server stops answering meanwhile; poll with
  timeouts. From the main menu, start maps through `freeroam_freeroam.startFreeroam`.
- **Scripted driving:**
  - Retry restores the player's realistic gearbox; switch to arcade after each Retry.
  - Arcade turns a held brake at standstill into reverse; release the brake below 4 km/h.
  - Physics varies run to run by about a metre; check verdicts, not exact numbers.
  - Steering a line: `academy.follow_path` (pure pursuit through MCP, one round trip per
    tick) drives course-frame points; precision to ~0.1 m.
  - Choosing gears: `course_run(..., gearbox="sequential", on_tick=...)` with `A.shift_to(n)`
    (the arcade box shifts on its own and holds 2nd to ~60 km/h in the Covet).

## Recipes

**Engine tests use test-only drills** (T01-T04, `tests/fixtures/test_drills.json`, added to the catalogue by
the stubs): T01/T02 self-assessed (Student Driver / Gravel Rally), T03 marked gates, T04 a marked stop zone.
Don't build engine tests on shipped drills: converting a drill would break them.

**Make a drill auto-graded:**
1. Read its entry in `exercises.json` and the capability table in [GRADING](docs/GRADING.md).
2. Use existing rule types (`R.TYPES` in `rules.lua`) where you can. Set
   `assessment.mode: "automatic"`, `rules`, and `endWhen` or `gates` as needed.
3. Check the drill's venue: its `environment.venueNeeds` describes the place
   (`survey.py fits <id>` searches for one), and survey it if a rule depends on it, e.g.
   `on_surface` surfaces (`survey.py surfaces`).
4. Drive scripted pass and miss runs in-game, then save them as fixtures (below).
5. Add a fixture test that the rules agree with the game's verdicts.
6. Update GRADING's status line, ROADMAP and the CHANGELOG.

**Add a rule type:**
1. Add an evaluator `E.<name>(rule, samples, ctx)` returning `ok, text` (the text is the
   coaching), and an entry in `R.TYPES`. The validator reads `R.TYPES` from `rules.lua`
   itself.
2. Add unit tests on synthetic runs, plus a recorded run if the rule depends on physics.
3. Document it in GRADING's rule table.

**Record a fixture:** drive the run (by hand or a scenario), then call
`extensions.rallyAcademy.saveLastRun('settings/rallyAcademy/fixtures/<name>.json')`. Copy the
file from the user folder into `tests/fixtures/` and note how it was driven at the top of
`tests/lua/test_fixtures.lua`.

**Add an in-game scenario:** add a function with a docstring to `tools/ingame/scenarios.py`,
decorated with `@scenario`. Use the `academy.py` helpers, return a list of problems, and
clean up any progress you record (`A.clear_progress`). List it in TESTING.

**Find a venue:** `survey.py fits <drill>` searches the map for the drill's `venueNeeds`. Or
bookmark with the Save spot binding, or run the finders (`survey.py
straights|corners|hills|crests|open`). Review them with `survey.py report`, prove the best with
`survey.py fit <drill> --spot ID | --at …`, then add it to `venues.json` ([docs/VENUES.md](docs/VENUES.md), the full workflow).

**UI changes:**
1. Use native components (`@/common/components/base`) and `--bng-*` colours.
2. The pause card is about 450 px wide; the HUD panel is 390×340.
3. Run the `smoke` and `pause` scenarios, and look at a screenshot.

## Before you hand back work

- `check --strict` passes. With the game available, the relevant scenarios pass.
- Update CHANGELOG `[Unreleased]` for user-visible changes, and the docs when behaviour,
  schema or workflow change.
- Tests that pin a known bug (`known_issue_*`) get flipped in the same commit that fixes it.

## Git

- Short-lived branches off `main` (`feat/…`, `fix/…`, `docs/…`, `chore/…`), Conventional
  Commits, one logical change per commit.
- Use `dev.py ship` rather than chaining git commands: never pipe `check` through `tail` in a
  `&&` chain, the pipe hides the failure (it once let a lint error reach `main`).
- While the owner works solo, fast-forward `main` from the branch once `check --strict`
  passes, push, and delete the branch. With collaborators, open a PR using the template.
- Never push tags or publish releases without the owner asking.
- On Windows with the game running, avoid `git switch main` before merging: the switch
  rewrites `mod/` files under the live game, which hot-reloads them.
- Details: [DEVELOPMENT](docs/DEVELOPMENT.md#git-workflow).

## Getting builds onto the owner's machine

With their BeamNG user folder reachable, either:
- copy `mod/` to `<user folder>/mods/unpacked/rally_academy/`, or
- have them run `python tools/dev.py link` in their own clone.

Read `<user folder>/beamng.log` after they test.
