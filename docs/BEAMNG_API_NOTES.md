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
| `spawn.safeTeleport(veh, pos, quatFromDir(dir, up), nil, nil, nil, nil, true)` | Retry: teleport + repair | verified 0.39.4 — damage 14931 → 0 after a 27 km/h guardrail hit; back within 0.02 m, same heading, at rest. Takes the **plain** direction quat (it turns 180° itself). Snaps to ground and nudges the car if the spot is occupied (props count as vehicles) |
| `vec3(...)`, `:length()`, `:normalized()`, vector subtraction | maths | verified 0.39.4 |
| `guihooks.trigger(name, table)` → Angular `$scope.$on(name, fn(event, data))` | Lua → HUD | verified 0.39.4 |
| `jsonReadFile(path)` / `jsonWriteFile(path, table, pretty)` | data and progress | verified 0.39.4 |
| Writing `settings/rallyAcademyProgress.json` lands in the user folder | persistence | verified 0.39.4, survives a game restart |
| `getCurrentLevelIdentifier()` returns the level folder name (e.g. `driver_training`) | per-map setups in `settings/rallyAcademySetups.json` | verified 0.39.4 |

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
| Angular apps mount via `window.UIAppsServiceShim.mountDirective(slotId, appData)` (`ui/modules/apps/app-service.js`) into `.ui-angular-app-slot#bng-app-slot_<directive>_<instance>` | verified 0.39.4 | Angular's injector lives on `#angular-root` (`.data('$injector')`) |
| Panel survives a UI reload | **broken 0.39.4** | the shim can mount into a slot Vue then replaces (same id) and ignores later mounts; ~½ of reloads left an empty panel. `app.js` self-heals (unmount + mount after 3 s empty, max 2 tries) — 0 failures in 15 reloads after the fix |
| A mod `app.js` is loaded once per page | **broken 0.39.4** | often injected twice (two `?_dc=` script tags ms apart); don't keep per-load state that breaks if the file runs twice |
| Editing `app.js` hot-refreshes the panel | unreliable 0.39.4 | can fail with `Directive cache refresh failed`; run `reloadUI()` after editing |

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
| Electrics (`throttle`, `brake`, `parkingbrake`, `steering`, wheel speeds) from vehicle Lua | P2 telemetry | needs a VLua → GE bridge |
| `ui_appLayouts.setUsedLayout(filename)` + shipped `/settings/ui_apps/originalLayouts/*.uilayout.json` | own HUD layout | see ROADMAP P1 |
| `electrics.values.wheelspeed`, `avgWheelAV` (rad/s); no fixed list of electrics per vehicle | P2 telemetry | from the [electrics docs](https://documentation.beamng.com/modding/vehicle/vehicle_system/electrics/); check with `dump(electrics.values)` in the vehicle console |
| Per-wheel slip, contact material, deflated/broken state from vehicle Lua (e.g. `wheels.wheels[i]`) | P2 telemetry, punctures, surface | table names from memory; [BeamNG-Telemetry](PRIOR_ART.md#telemetry) reads these on 0.35 |
| Race path / checkpoints / time-trial system | gates and timing | see [PRIOR_ART](PRIOR_ART.md#built-into-beamng); module names unknown |
| Built-in drift detection (drift spots) | slip angle, spins (module C) | module names unknown |
| Rally mode and pacenotes | module F | experimental in-game feature; 0.39 added a 30 km stage |
| Stock cone prefabs are physics objects that move on contact | cone contact | from a community tutorial |
| Game input setting "automatic clutch" can be read | A02/A03 clutch drills | see [VEHICLES](VEHICLES.md#what-to-look-for-in-a-drill-car) |
