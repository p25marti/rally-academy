# BeamNG API notes

Every engine API, path convention or behaviour the mod relies on, with its
verification status. BeamNG's modding docs are incomplete and APIs change
between versions, so **nothing is "verified" until it has worked in-game on a
named build.**

Status: `unverified` (from docs or memory) · `verified <build>` (worked in-game) · `broken <build>` (with notes).

Target build: **BeamNG.drive 0.39.x** (update when you upgrade, and re-run the smoke test).

## Packaging and loading

| Assumption | Status | Notes |
| --- | --- | --- |
| Zip in `mods/` loads; zip root must contain `lua/`, `ui/`, … directly | unverified | `dev.py build` guarantees layout |
| Unpacked mods load from `mods/unpacked/<name>/` | unverified | |
| A directory junction/symlink there is followed | unverified | fallback: `dev.py link --copy` |
| Mod files are visible at the virtual FS root (`gameplay/...` readable via `jsonReadFile`) | unverified | |
| User folder: `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current` (new) or `%LOCALAPPDATA%\BeamNG.drive\<ver>` (old) | unverified | override with `BEAMNG_USER_FOLDER` |
| Log at `<user folder>/beamng.log` | unverified | |

## Game Engine (GE) Lua

| API | Used for | Status |
| --- | --- | --- |
| Extension at `lua/ge/extensions/rallyAcademy.lua`, loaded by `extensions.load('rallyAcademy')`, reachable as `extensions.rallyAcademy` | entry point | unverified |
| `scripts/rally_academy/modScript.lua` runs on mod activation; `load(name)` + `setExtensionUnloadMode(name, "manual")` load the extension and keep it loaded | auto-load | unverified |
| Hooks `onExtensionLoaded()`, `onUpdate(dtReal, dtSim, dtRaw)` | lifecycle, timing | unverified |
| `dtSim` is 0 while physics is paused | pause-safe timer | unverified |
| `be:getPlayerVehicle(0)` | player vehicle | unverified |
| `veh:getID()`, `getPosition()`, `getVelocity()`, `getDirectionVector()`, `getDirectionVectorUp()` | snapshot, speed | unverified |
| `veh:setPositionRotation(x,y,z, qx,qy,qz,qw)` | retry teleport | unverified — **does not reset velocity** (suspected) |
| `quatFromDir(forward, up)` | orientation capture | unverified |
| `vec3(...)`, `:length()`, `:normalized()`, vector subtraction | maths | unverified |
| `guihooks.trigger(name, table)` → Angular `$scope.$on(name, fn(event, data))` | Lua → HUD | unverified |
| `jsonReadFile(path)` / `jsonWriteFile(path, table, pretty)` | data and progress | unverified |
| Writing `settings/rallyAcademyProgress.json` lands in the user folder | persistence | unverified |

## Input actions

| Assumption | Status |
| --- | --- |
| Custom actions in `lua/ge/extensions/core/input/actions/*.json` appear in Options → Controls | unverified |
| `"ctx": "tlua"` runs `onDown` in GE Lua | unverified |

## UI apps

| Assumption | Status |
| --- | --- |
| Legacy AngularJS apps in `ui/modules/apps/<Name>/` with `app.json` + `app.js` still load in 0.39 | unverified |
| `bngApi.engineLua(code)` is injectable in directives | unverified |

## Developer loop

| Assumption | Status |
| --- | --- |
| `extensions.reload("rallyAcademy")` in the console reloads only our extension | unverified |
| `Ctrl+L` reloads GE Lua | unverified |
| `reloadUI()` in the Lua console reloads the UI | unverified |
| `~` opens the Lua console | unverified |

## Candidate APIs (not used yet)

| API | For | Notes |
| --- | --- | --- |
| Vehicle-Lua `recovery.saveHome()` / `recovery.loadHome()` via `veh:queueLuaCommand` | P0 retry fix | what the built-in Ctrl+Home / Home use (to confirm) |
| `spawn.safeTeleport(...)` | P0 retry fix | signature varies by version |
| Electrics (`throttle`, `brake`, `parkingbrake`, `steering`, wheel speeds) from vehicle Lua | P2 telemetry | needs a VLua → GE bridge |
| `getCurrentLevelIdentifier()` | per-map persistence | |
