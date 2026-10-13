# Development

## Tooling

| Tool | Needed for | Required locally? |
| --- | --- | --- |
| Python 3.9+ | `tools/dev.py` (validate, build, link, log) | Yes |
| git | version control | Yes |
| LuaJIT 2.1 | `dev.py test` — runs unit tests in the same Lua flavour as BeamNG | Optional (CI runs it) |
| luacheck | `dev.py lint` — static analysis of Lua | Optional (CI runs it) |
| BeamNG.drive | real testing | Yes, for anything that touches the game |

`dev.py lint` / `test` print `[skip]` when their tool is missing; `--strict`
turns that into a failure (CI uses `--strict`).

Installing the Lua tools:

- **Linux / macOS / WSL:** `tools/ci/setup-lua.sh` builds LuaJIT and luacheck
  from source (needs a C compiler). Same script CI uses, so versions match.
- **Windows (native):** easiest is to run the script inside WSL. Alternatively,
  install LuaJIT and luacheck with your package manager of choice and make sure
  both are on `PATH`. If you skip this, just rely on CI.

All `dev.py` commands are run from the repo root:

```text
python tools/dev.py check     validate + lint + test + build
python tools/dev.py build     dist/rally_academy.zip (+ .sha256)
python tools/dev.py link      live-link mod/ into BeamNG  (--copy, --force, --user-folder)
python tools/dev.py unlink    remove the link
python tools/dev.py status    where's my user folder, what's installed, any conflicts
python tools/dev.py log       beamng.log tail filtered to us + errors  (-n 200, --all)
python tools/dev.py bump X.Y.Z  set version in VERSION and app.json
```

## Finding the BeamNG user folder

`dev.py` auto-detects, in order: `$BEAMNG_USER_FOLDER`, then
`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current`, then the newest
`%LOCALAPPDATA%\BeamNG.drive\<version>` folder (older layout). If yours is
elsewhere (the launcher lets you move it), pass `--user-folder` or set the
environment variable once:

```powershell
setx BEAMNG_USER_FOLDER "D:\BeamNGUser\current"
```

Run `python tools/dev.py status` to confirm what it found.

## The inner loop

`dev.py link` makes `<user folder>/mods/unpacked/rally_academy` a directory
junction (Windows) or symlink pointing at this repo's `mod/`. BeamNG loads it
as an unpacked mod, so saving a file in your editor changes what the game sees,
with no zip and no copy.

> If BeamNG ever fails to follow the junction, use `python tools/dev.py link --copy --force`
> and re-run it after each change. Note which one worked in BEAMNG_API_NOTES.

Typical cycle:

1. `python tools/dev.py check` — fast feedback before touching the game.
2. Edit Lua / JS / JSON under `mod/`.
3. In BeamNG, reload what changed:
   - **GE Lua** (`mod/lua/ge/...`): reload just our extension from the Lua console (`~`)
     with `extensions.reload("rallyAcademy")`, or reload all Lua with `Ctrl+L`.
   - **HUD app** (`mod/ui/...`): reload the UI. From the Lua console (`~`):
     `reloadUI()`.
   - **Drill data** (`exercises.json`): it's read when the extension loads, so
     a Lua reload is enough.
   - When in doubt, restart the level.
   *(These reload paths are marked "unverified" in BEAMNG_API_NOTES until
   confirmed on our game build. Update them when confirmed.)*
4. `python tools/dev.py log` to see errors from our code.
5. Run the [in-game smoke test](TESTING.md#in-game-smoke-test) before opening a PR.

Avoid having the release zip (`mods/rally_academy.zip`) installed while the dev
link exists. Two copies load and the results get confusing. `link` and `status`
warn about this.

## Editing guidelines

- **Lua** (GE extension): LuaJIT / Lua 5.1 syntax. Module pattern `local M = {} … return M`.
  Keep engine calls (`be:`, `guihooks`, file I/O) in small functions so logic can
  be tested with stubs. Each new engine global goes in `.luacheckrc`,
  `tests/lua/beamng_stubs.lua` and [BEAMNG_API_NOTES.md](BEAMNG_API_NOTES.md).
- **HUD** (`mod/ui/modules/apps/RallyAcademy`): AngularJS directive, view only.
  It calls Lua through `bngApi.engineLua(...)` and listens for the
  `rallyAcademyState` event. Never build Lua strings from unchecked user input.
- **Drills**: edit `exercises.json` directly, then `dev.py validate`. Schema: [DRILL_DATA.md](DRILL_DATA.md).
- Formatting is set by `.editorconfig` (2-space indent, LF line endings).

## Git workflow

- `main` is always releasable: CI green, docs current.
- Work on short-lived branches: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat: auto-grade B01 stopping zone`, `fix: zero velocity on retry`.
- Open a PR, fill in the template (including **how it was tested in-game**),
  wait for CI, squash-merge.
- Large or one-way decisions get a short record in [decisions/](decisions/).
- Never commit build output (`dist/`), BeamNG logs or anything from your user folder.
