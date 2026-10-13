# BeamNG API notes

Every engine API, path convention or behaviour the mod relies on, with its
verification status. BeamNG's modding docs are incomplete and APIs change
between versions, so **nothing is "verified" until it has worked in-game on a
named build.**

Status: `unverified` (from docs or memory) · `verified <build>` (worked in-game) · `broken <build>` (with notes).

Target build: **BeamNG.drive 0.39.4** (build 20972). Update when you upgrade, and re-run the smoke test.

## Packaging and loading

| Assumption | Status | Notes |
| --- | --- | --- |
| Zip in `mods/` loads; zip root must contain `lua/`, `ui/`, … directly | unverified | `dev.py build` guarantees layout |
| Unpacked mods load from `mods/unpacked/<name>/` | verified 0.39.4 | log: `mountEntry -- /mods/unpacked/rally_academy/` |
| A directory junction there is followed | verified 0.39.4 | `dev.py link` (junction) works; `--copy` not needed |
| Mod files are visible at the virtual FS root (`gameplay/...` readable via `jsonReadFile`) | verified 0.39.4 | 48 drills load |
| User folder: `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current` | verified 0.39.4 | override with `BEAMNG_USER_FOLDER` |
| Log at `<user folder>/beamng.log` | verified 0.39.4 | |

## Game Engine (GE) Lua

| API | Used for | Status |
| --- | --- | --- |
| Extension at `lua/ge/extensions/rallyAcademy.lua`, loaded by `extensions.load('rallyAcademy')`, reachable as `extensions.rallyAcademy` | entry point | verified 0.39.4 |
| `scripts/rally_academy/modScript.lua` runs on mod activation and loads the extension | auto-load | verified 0.39.4 (`extensions.rallyAcademy ~= nil` right after start) |
| Hooks `onExtensionLoaded()`, `onUpdate(dtReal, dtSim, dtRaw)` | lifecycle, timing | verified 0.39.4 |
| The engine caches hook functions at load; replacing `M.onUpdate` at runtime has no effect | debugging | verified 0.39.4 |
| `dtSim` is 0 while physics is paused | pause-safe timer | verified 0.39.4 |
| `be:getPlayerVehicle(0)` | player vehicle | verified 0.39.4 |
| `veh:getID()`, `getPosition()`, `getVelocity()`, `getDirectionVector()`, `getDirectionVectorUp()` | snapshot, speed | verified 0.39.4 |
| `getVelocity()` on the frame after `setPositionRotation` reports a huge value (~430 m/s) | run-start detection | verified 0.39.4 — also require the car to leave the start |
| `veh:setPositionRotation(x,y,z, qx,qy,qz,qw)` | retry teleport | verified 0.39.4 — **leaves the car at rest** (4.25 m/s → 0.03 m/s); does not repair damage |
| Rotation for `setPositionRotation` = `quatFromDir(-dirVec, upVec)` | orientation capture | verified 0.39.4 — `quatFromDir(dirVec, …)` faces the car **backwards** (same convention as `core_checkpoints`) |
| `vec3(...)`, `:length()`, `:normalized()`, vector subtraction | maths | verified 0.39.4 |
| `guihooks.trigger(name, table)` → Angular `$scope.$on(name, fn(event, data))` | Lua → HUD | verified 0.39.4 |
| `jsonReadFile(path)` / `jsonWriteFile(path, table, pretty)` | data and progress | verified 0.39.4 |
| Writing `settings/rallyAcademyProgress.json` lands in the user folder | persistence | verified 0.39.4 (survival across a restart: unverified) |

## Input actions

| Assumption | Status |
| --- | --- |
| Custom actions in `lua/ge/extensions/core/input/actions/*.json` appear in Options → Controls | verified 0.39.4 (`core_input_actions.getActiveActions()` lists them; bound by the owner) |
| `"ctx": "tlua"` runs `onDown` in GE Lua | verified 0.39.4 (bound Retry key teleports to start) |

## UI apps

| Assumption | Status | Notes |
| --- | --- | --- |
| Legacy AngularJS apps in `ui/modules/apps/<Name>/` with `app.json` + `app.js` still load | verified 0.39.4 | catalogued by `ui_apps.getUIAppsData()` |
| `bngApi` is injectable in directives | **broken 0.39.4** | `Unknown provider: bngApiProvider`. It is a **global**; stock apps use it without injecting |
| `app.json` without `types` is filed under "Unknown" | verified 0.39.4 | we set `ui.apps.categories.rally` |
| Adding an app: `Alt+Shift+U` (HUD Layouts) → layout → **Edit Layout** → **＋ Add app** | verified 0.39.4 | Layout Actions → Duplicate makes a separate layout; Use Layout switches |
| Angular `element.scope()` is available for debugging | broken 0.39.4 | debug info is disabled; read the DOM instead |

## Developer loop

| Assumption | Status | Notes |
| --- | --- | --- |
| `extensions.reload("rallyAcademy")` in the console reloads only our extension | verified 0.39.4 | resets state; reselect a drill afterwards |
| `Ctrl+L` reloads GE Lua | unverified | |
| `reloadUI()` in the Lua console reloads the UI | verified 0.39.4 | |
| `~` opens the Lua console | verified 0.39.4 | |
| Built-in MCP server at `http://127.0.0.1:29292/mcp` (`beamng-game`) | verified 0.39.4 | screenshots, `run_lua`, `ui_click`, `inject_input`, `reload_ui`, … Lets an assistant drive the smoke test |

## Candidate APIs (not used yet)

| API | For | Notes |
| --- | --- | --- |
| `veh:resetBrokenFlexMesh()` + vehicle-side `recovery.clear()` / `autoplace` | P0 repair on retry | what `core_checkpoints.ResetToSavedCheckpoint` does |
| `spawn.safeTeleport(veh, pos, quatFromDir(dir))` | alternative teleport | used by `main.lua`; note it takes the *un-negated* direction |
| Electrics (`throttle`, `brake`, `parkingbrake`, `steering`, wheel speeds) from vehicle Lua | P2 telemetry | needs a VLua → GE bridge |
| `getCurrentLevelIdentifier()` | per-map persistence | |
| `ui_appLayouts.setUsedLayout(filename)` + shipped `/settings/ui_apps/originalLayouts/*.uilayout.json` | own HUD layout | see ROADMAP P1 |
