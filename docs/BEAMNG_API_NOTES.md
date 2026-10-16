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
| Log at `<user folder>/beamng.log` | verified 0.39.4 | written in buffered chunks: the newest lines can lag a minute or more behind the game |
| `log(level, tag, msg)` from extension `rallyAcademy` appears as `|I|GELua.rallyAcademy.<tag>| msg` | verified 0.39.4 | we use tag `rallyAcademy` |

## Game Engine (GE) Lua

| API | Used for | Status |
| --- | --- | --- |
| Extension at `lua/ge/extensions/rallyAcademy.lua`, loaded by `extensions.load('rallyAcademy')`, reachable as `extensions.rallyAcademy` | entry point | verified 0.39.4 |
| `scripts/rally_academy/modScript.lua` runs on mod activation and loads the extension | auto-load | verified 0.39.4 (`extensions.rallyAcademy ~= nil` right after start) |
| Hooks `onExtensionLoaded()`, `onUpdate(dtReal, dtSim, dtRaw)` | lifecycle, timing | verified 0.39.4 |
| Hooks `onClientEndMission(levelPath)` (map unloading) and `onClientPostStartMission(levelPath)` (map + car loaded) | per-map setups | verified 0.39.4 (Driver Training → smallgrid → Driver Training) |
| Hook `onVehicleSwitched(oldId, newId, player)` | abandon a run on car switch | 0.39.4: switching mid-run returned to `setup`; an `onUpdate` id check is the fallback, so which one fired wasn't isolated |
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

## Vehicle Lua (telemetry)

Spike 2026-10-15 on 0.39.4 (Covet student_driver, Driver Training); answers GRADING.md open question 1.

| Assumption | Status | Notes |
| --- | --- | --- |
| Electrics keys `throttle`, `brake`, `parkingbrake`, `steering`, `clutch` (+ `_input` raw variants), `gearIndex`, `rpm`, `wheelspeed`, `airspeed`, `abs`, `absActive`, `engineRunning`, `ignitionLevel` | verified 0.39.4 | 121 keys on the Covet; no `esc`/`tcs` on that car |
| Per-wheel data in `wheels.wheelRotators[0..wheelRotatorCount-1]`: `name` (FR/FL/RR/RL), `wheelSpeed` (m/s), `angularVelocity`, `radius`, `contactMaterialID1/2`, `downForce` (N, 0 = airborne), `isTireDeflated` | verified 0.39.4 | **not** in electrics |
| `core_vehicleBridge.registerValueChangeNotification` / `getCachedVehicleData` | read, not used | electrics only, one GE message per changed key per frame; can't deliver per-wheel data |
| A mod vehicle extension at `lua/vehicle/extensions/rallyAcademy/telemetry.lua` loads with `extensions.load('rallyAcademy/telemetry')`, reached as `extensions.rallyAcademy_telemetry` | verified 0.39.4 | in-memory modules via `package.loaded` are rejected ("extension unavailable") |
| Vehicle extensions survive a reset (`safeTeleport` with repair) | verified 0.39.4 | kept loaded and sending after Retry |
| `obj:queueGameEngineLua(code)` from `updateGFX` delivers to GE every frame | verified 0.39.4 | rate = frame rate: 30 fps with the window unfocused (background cap), 60 focused (vsync); stamp samples with summed `dt` |
| `core_levels.startLevel(path)`, path from `core_levels.getList()` (`fullfilename`) | Go to drill: load the drill's map | verified 0.39.4 — list names can differ in case from `getCurrentLevelIdentifier()` (`Utah` vs `utah`): compare case-insensitively. The extension survives the load; `onClientPostStartMission` fires once the map and car are in |
| `core_vehicles.replaceVehicle(model, {config = key})`; current car via `veh.JBeam` and `veh.partConfig` (`vehicles/<model>/<key>.pc`) | Go to drill: drill car | verified 0.39.4 — `onVehicleSpawned(vid, veh)` fires **synchronously inside** `replaceVehicle` (listen before calling); a teleport right after the swap sticks |
| `getObjectByID(id)` (GE) returns the vehicle object | verified 0.39.4 | used to stop the sampler in the car that was recording |
| Right after a repair-teleport the car settles: first samples show all wheels with `downForce` 0 and the engine re-idling | observed 0.39.4 | rules must look from the run's start mark, not from Retry |
| After a repair-teleport (Retry) the `brake` electric reads 0.3 with the car at rest and no pedal | observed 0.39.4 | the game's idle hold. "Speed when the brake was first touched" would read 0, so `entry_speed` uses the run's peak speed |
| `safeTeleport` may nudge the car about 2 m **a frame after** the teleport when the spot overlaps something | observed 0.39.4 | a run armed on "moved 0.5 m from the start" started instantly; the start is now armed 0.2 s after Retry, from where the car settled |
| The reset in Retry restores the player's default gearbox mode (realistic, in neutral) | observed 0.39.4 | scripted tests that switch to arcade must switch again after each Retry |
| Arcade gearbox: holding the brake at standstill selects reverse and drives backwards | observed 0.39.4 | scripted stops release the brake below 4 km/h and use the handbrake |
| Vehicle Lua `obj:getVelocity()`, `obj:getDirectionVector()`, `obj:getDirectionVectorUp()` | verified 0.39.4 | recorded as `vx, vy`, `hx, hy`, `uz`: slip angle (spin) and rollover |
| Vehicle Lua `beamstate.damage` (number, 0 after a repair) | verified 0.39.4 | recorded as `dmg`: hitting the track edge at ~45 km/h took it 0 -> 5722 |
| `wheels.wheelRotators[i].isTireDeflated`; `beamstate.deflateRandomTire()` | verified 0.39.4 | recorded as `flat` (count). Deflating adds ~1000 to `beamstate.damage`, one sample after the flag |
| Surface ids are the same list in every car: 2 METAL, 3 PLASTIC, 4 RUBBER (tyre barriers), ... 10 ASPHALT, 19 GRAVEL, 20 GRASS ... 32 SPIKE_STRIP | verified 0.39.4 | read with `particles.getMaterialByID` in **vehicle** Lua (GE has no `particles`); the table is copied into `rules.lua` (`R.SURFACES`) |
| BMP start straight surfaces | surveyed 0.39.4 | asphalt centre, gravel to about ±5-8 m, then grass, dirt and dusty dirt, with rubber tyre barriers at the edges |
| Electrics `engineRunning` (1/0) is recorded per sample as `eng` | verified 0.39.4 | stall detection; RPM alone reads ~160 while the engine re-idles after a reset |
| Telemetry lags GE by about a frame: when `onUpdate` sees the car cross a line, the car's sample past it hasn't arrived yet | observed 0.39.4 | a run graded on the frame of the last gate saw "gate 3 not reached"; runs ending at a gate now keep recording 0.3 s before grading |
| `debugDrawer:drawCylinder(vec3 a, vec3 b, radius, ColorF(r, g, b, a))` draws in normal play (not just the editor), redrawn every frame | verified 0.39.4 | gate posts and bars, stop zone outline, finish disc (screenshot on the BMP straight). `drawLine`, `drawSphere`, `drawTextAdvanced`, `drawSquarePrism` exist but are unused |
| `extensions.reload('rallyAcademy')` re-runs the extension file, but `require`d modules stay cached in `package.loaded` | verified 0.39.4 | an edited `rules.lua` wasn't picked up ("Unknown rule type"); the extension now clears its own modules from `package.loaded` when it loads |
| Lockup is visible per wheel | verified 0.39.4 | 40 km/h full brake, no ABS: all 4 wheels < 30% of `airspeed` within ~0.2 s |
| `contactMaterialID1` gives the surface | verified 0.39.4 | names via `particles.getMaterialByID(particles.getMaterialsParticlesTable(), id).name`: 10 ASPHALT, 11 ASPHALT_WET, 13 ROCK, 14 DIRT_DUSTY, 15 DIRT, 16 SAND, 17 SANDY_ROAD, 18 MUD, 19 GRAVEL, 20 GRASS, 21 ICE, 22 SNOW, 29 RUMBLE_STRIP, 30 COBBLESTONE; -1 = no contact |
| Terrain surface at a point (GE): `core_terrain.getTerrain():getMaterialIdxWs(pos)` → `:getMaterial(idx):getGroundmodelName()` | verified 0.39.4 | terrain only: road meshes/decals over it aren't seen (Italy, East Coast roads read as grass). Names vary per map (DIRT_LOOSE_DUSTY, DIRT_ROCKY…). Same approach as the rally editor's `surfaceProbe` |
| Rally stage data in `gameplay/missions/<level>/rallyStage/<id>/`: `info.json` start trigger + recommended car + times; `race.race.json` start positions + checkpoints; `rally/drivelineSpline.json` centre line + stats (distance, surface %) | read 0.39.4 | spline `widths` are all 10 (editor default), not road width |

## Input actions

| Assumption | Status |
| --- | --- |
| Custom actions in `lua/ge/extensions/core/input/actions/*.json` appear in Options → Controls | verified 0.39.4 (`core_input_actions.getActiveActions()` lists them; bound by the owner) |
| `"ctx": "tlua"` runs `onDown` in GE Lua | verified 0.39.4 (bound Retry key teleports to start) |

## UI apps

| Assumption | Status | Notes |
| --- | --- | --- |
| **Vue HUD apps from a mod:** `ui/modules/apps/<Name>/app.vue` + `"vue": true` in `app.json` | verified 0.39.4 | `ui_apps.getUIAppsData()` reports `hasAppVue = true`, `vueFile = /ui/modules/apps/RallyAcademy/app.vue`; rendered by `AppHost` through the runtime mod compiler (no Angular slot). Same directive name, so existing HUD layouts keep the panel. 3 of 3 UI reloads came back with exactly one panel. Imports: `useBridge().api.engineLua`, `useEvents()` (listeners removed on unmount) |
| The game ships its own rally HUD apps (`rallyCornerCalls`, `rallyVisualPacenotes`, `rallyTimecard`, `rallyStageTiming`, `rallyRecce`, ...) | seen 0.39.4 | worth studying for the F-module stages |
| *The rows below are about the old Angular panel (`app.js`), replaced by `app.vue`; kept for reference.* | | |
| Legacy AngularJS apps in `ui/modules/apps/<Name>/` with `app.json` + `app.js` still load | verified 0.39.4 | catalogued by `ui_apps.getUIAppsData()` |
| `bngApi` is injectable in directives | **broken 0.39.4** | `Unknown provider: bngApiProvider`. It is a **global**; stock apps use it without injecting |
| `app.json` without `types` is filed under "Unknown" | verified 0.39.4 | we set `ui.apps.categories.rally` |
| Adding an app: `Alt+Shift+U` (HUD Layouts) → layout → **Edit Layout** → **＋ Add app** | verified 0.39.4 | Layout Actions → Duplicate makes a separate layout; Use Layout switches |
| Angular `element.scope()` is available for debugging | broken 0.39.4 | debug info is disabled; read the DOM instead |
| Remounting HUD apps cleans up the old Angular scope | **broken 0.39.4** | after map loads/vehicle swaps an orphaned panel can stay alive and still receive events (2 `rallyAcademyState` listeners, 1 panel on screen). The panel destroys itself on the next event if its element is detached, deferred until after the broadcast: `$destroy()` during a `$broadcast` throws (`reading '$$nextSibling'`). Count listeners (`$rootScope.$$listenerCount`), not scopes: `ng-if` child scopes inherit the panel's properties |
| Angular apps mount via `window.UIAppsServiceShim.mountDirective(slotId, appData)` (`ui/modules/apps/app-service.js`) into `.ui-angular-app-slot#bng-app-slot_<directive>_<instance>` | verified 0.39.4 | Angular's injector lives on `#angular-root` (`.data('$injector')`) |
| Panel survives a UI reload | **broken 0.39.4** | the shim can mount into a slot Vue then replaces (same id) and ignores later mounts; ~½ of reloads left an empty panel. `app.js` self-heals (unmount + mount after 3 s empty, max 2 tries) — 0 failures in 15 reloads after the fix |
| A mod `app.js` is loaded once per page | **broken 0.39.4** | often injected twice (two `?_dc=` script tags ms apart); don't keep per-load state that breaks if the file runs twice |
| Editing `app.js` hot-refreshes the panel | unreliable 0.39.4 | can fail with `Directive cache refresh failed`; run `reloadUI()` after editing |
| Vue UI mods: files in `/ui/ui-vue/mods/<mod>/` (our `mod/ui/ui-vue/mods/rallyAcademy/`) are compiled at runtime; `index.js` exports `onLoad`/`onUnload` | verified 0.39.4 | `extensions.ui_uiMods.getVueMods()` lists them; edits hot-reload. Docs: `ui/ui-vue/mods/README.md` in the game folder |
| Main-menu buttons via `events.on("MainMenuButtons", addButton)`; `iconId` is a `bngIcons` glyph name (we use `raceFlag`) | verified 0.39.4 | mod buttons show under **More...** (route `menu.others`), tagged "Mod", not on the top level |
| Routes: `window.bngRoutes.add` + `ui_router_routeManager.registerModRoutes`; navigate with `ui_router.navigate(name)` | verified 0.39.4 | our `menu.rallyAcademy` opens from the main menu and also over the game view from inside a map |
| The Vue bridge's `lua.*` only has functions listed in `LuaFunctionSignatures.js`; others need `runRaw` from `@/bridge/libs/Lua.js` | verified 0.39.4 | `lua.extensions.rallyAcademy` is undefined; `runRaw("extensions.rallyAcademy.getMenuData()")` returns the table |
| `core_levels.startLevel` from the main menu loads the map but doesn't enter freeroam: no HUD layout, the menu route stays up | verified 0.39.4 | use `freeroam_freeroam.startFreeroam(path)`, as the Freeroam menu does |
| After a map started from our menu, the UI stays on our route until `ui_router.navigate('play')` | verified 0.39.4 | the game's own main-menu exit handler navigates to `play` in freeroam; we do the same once the car is placed |
| `simTimeAuthority.pause(bool)` / `getPause()` pause and resume physics (photomode uses them) | verified 0.39.4 | the Academy key binding pauses while the screen is open over a map |
| Route lifecycle hook `meta.luaRoute.onLeave = "rallyAcademy.onMenuLeave"` runs when the route is left by any path | verified 0.39.4 | leaving our route with `ui_router.navigate('play')` called it and physics resumed |
| Pause-menu mod tab: `ui_pause_actions.registerModTab` + `registerModButton({componentName, props})` | partly verified 0.39.4 | the **Rally Academy** tab shows in the pause menu's top bar and `getVisibleModTabs()` lists its 4 buttons; scripted clicks (DOM `click()`, `ui_click`) don't switch pause tabs, not even native ones visibly, so the card content needs a real click to confirm |
| The game has its own **Rally** entry under More... | seen 0.39.4 | not investigated yet: may overlap with F-module stages (PRIOR_ART) |

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
