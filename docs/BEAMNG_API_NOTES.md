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
| Mod files are visible at the virtual FS root (`gameplay/...` readable via `jsonReadFile`) | verified 0.39.4 | all drills load (48 then; 42 since ADR 0006) |
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
| The engine caches hook functions at load; replacing `M.onUpdate` at runtime has no effect | debugging | verified 0.39.4 — `extensions.hookUpdate('onUpdate')` rebuilds the cache |
| An extension can be built in memory: `package.preload['name'] = function() return M end; extensions.load('name')` | the video recorder (`tools/ingame/record.py`) | verified 0.39.4 — survives `extensions.reload('rallyAcademy')` |
| `createScreenshot2({filename, writeJPG, superSampling, rescaleFactor})` saves a frame (path relative to the user folder, no extension) | the video recorder, dev only (not in `mod/`) | verified 0.39.4 — asynchronous: JPGs at 0.5 scale land about 20 a second, so faster capture queues up and files keep arriving for minutes after; the game window can be in the background |
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
| `veh:getNodeCount()`, `veh:getNodePosition(i)` = node i's offset from `getPosition()` in **world** axes | the car's footprint for A01 (`park_in_box`, `markers_clear`) | verified 0.39.4 — Covet Student Driver: 759 nodes, 3.92 × 1.81 m, and its position is **not** the body's centre: the body reaches 1.85 m ahead, 2.07 m behind, 1.23 m left, 0.58 m right |
| `veh:getSpawnWorldOOBB()` (`getCenter`, `getHalfExtents`, `getAxis`), `veh:getInitialLength()/Width()/Height()` | footprint fallback | verified 0.39.4 — agree with the nodes (half extents 0.905 × 1.96; 3.92 × 1.81 × 1.33). `be:getObjectOOBB` doesn't exist |
| `core_terrain.getTerrain()`: `getWorldBox()`, `getMaterialCount()`, `getMaterialName(i)`, `getMaterial(i):getGroundmodelName()`, `getMaterialIdxWs(vec3)`; `core_terrain.getTerrainHeight(vec3)` | whole-map surface scan (`tools/ingame/scan.py`, dev only) | verified 0.39.4 — about 500 000 points a second in one Lua loop; on a level loaded from the menu `core_terrain.getTerrain()` can be nil, so fall back to the scene tree's TerrainBlock. West Coast USA's terrain materials use ground models such as DIRT_ROCKY and DIRT_GRASS that wheels never report (the BMP dirt surfaces drivers feel are decals and meshes on top) |
| `debugDrawer:renderGroundModelDebug(type, name, colour, radius, tile, pos, depthScale, countOnly)` and `renderStaticColDebug(...)` (after `Engine.setStaticColDebugEnabled(true)`) return how many terrain tiles / mesh triangles of ground model `name` lie within `radius` (≤ 60 m) of `pos`; `countOnly = true` draws nothing | `tools/ingame/surface.py` (scan candidates, course audit), dev only | verified 0.40.0 (the Groundmodel Debug panel's own calls, `lua/ge/extensions/util/groundModelDebug.lua`). About 0.2 ms a call at 10 m; not limited to the camera's surroundings. Mesh triangles are counted by horizontal distance, so gantries and bridges overhead count too: check the surface under a car (`be:getSurfaceHeightBelow` from 1.5 m up) before trusting mesh ground. Aliases count under their own names (BEACHSAND, not SAND): loop over every name, aliases included, and fold them via `core_environment.groundModels[name].parent`. **Terrain tiles are matched by terrain material name, not ground model**: a material `ra_gravel` with ground model GRAVEL counts only as `ra_gravel`, so loop over `core_terrain.getTerrain()`'s materials (`getMaterialName(i)`, `getMaterial(i):getGroundmodelName()`); stock maps happened to work because their material names often equal ground model names |
| `core_environment.groundModels[name]`: `isAlias`, `parent`, `cdata.staticFrictionCoefficient`, `slidingFrictionCoefficient`, `roughnessCoefficient`, `defaultDepth`, `strength` | grip in the scan and audit, the friction table in COURSE_AUDIT | verified 0.40.0: 32 ground models, 28 aliases (DIRT_ROCKY → DIRT_DUSTY, BEACHSAND → SAND, DIRT_LOOSE → GRAVEL, …). Static friction: ASPHALT 0.98, GRAVEL 0.68, DIRT 0.69, DIRT_DUSTY 0.68, GRASS 0.61, SAND 0.60, MUD 0.55, SNOW 0.64, ICE 0.40 |
| The sequential gearbox, shifted with `controller.mainController.shiftToGearIndex`, can blip back a gear and return within 0.1 s while shifting up (3 → 0 → 2 → 0 → 3) | gear rules (A03) | seen 0.40.0 at 45 km/h in the Covet Student Driver; `progressive_downshifts` ignores gears held under 0.3 s |
| `TerrainBlock:setHeight(gx, gy, h)` + `updateGrid(min, max)` edit the terrain live (no editor needed); `h` is relative to the block's origin (`getPosition().z`, 100 m on the template) | proving-ground research | verified 0.40.0 from MCP on the template level (in memory, not saved) |
| A level written by hand from Python loads: `info.json`, `main/items.level.json` (the `MissionGroup` SimGroup; without it: "MissionGroup not found"), NDJSON `items.level.json` per group, a `TerrainBlock` with `terrainFile` and `materialTextureSet`, and a version 9 `.ter` (version byte, u32 size, u16 heights, u8 material per square, u32 count + length-prefixed material names; height = block z + raw / 65535 × maxHeight) | `tools/mapgen/build.py` (proving-ground prototype) | verified 0.40.0: loads in about 4 s cold, 1 s on reload; a changed `.ter` is hot-reloaded by the resource manager. Terrain material internal names must be unique across maps (the game keeps the last map's: "Internal name collision"), hence `ra_*` copies of the template's. Without `<terrain>.ter.depth.png` the log says fluids are disabled as a ground type and the ground is hard; with an all-zero 1024² map (the template's is 2048², mostly zero) every wheel sank 0.2 m (`wheelRotators[i].contactDepth`) and the Covet crawled at full throttle on gravel, so we ship none. Stock maps' depth maps are mostly 0 with 1/2 and 254/255 clusters; the encoding is unverified |
| Trees: a `Forest` object (in an `items.level.json`) plus `forest/<type>.forest4.json` (one item per line: `pos`, `rotationMatrix` row-major, `scale`, `type`) and `art/forest/managedItemData.json` (`TSForestItemData` with a `shapeFile`). The shared library `/assets/meshes/foliage/trees_library/` is always mounted, but its **materials are defined per level**: ship definitions (we copy Driver Training's, pointing at `/assets/materials/tree/`); some meshes name `m_ind_*` leaves nobody defines, and the beech/oak merged-foliage textures aren't in the shared pack | `tools/mapgen/nature.py` | verified 0.40.0: 17k trees load in 1.4 s. Distant trees are drawn from imposters the game bakes into `<user folder>/temp/` on first load and doesn't rebake when materials change: a load with missing materials leaves them orange (the placeholder) until that cache is cleared |
| Grass cover: `GroundCover` objects (billboard grass) grow on the terrain materials named in each `Types[].layer` (the internal name, e.g. `ra_Grass`); stock setups are copied whole and their materials borrowed (gridmap_v2 and automation_test_track ones use only shared textures). Static props: `TSStatic` with `shapeName`; meshes under `/art/shapes/` (the rally kit, cabins, barriers) have their materials loaded by the game itself, those under `/assets/meshes/` mostly don't. Time of day: the level's `TimeOfDay` `startTime` (0 = noon; 0.19 late afternoon, 0.24 sunset) | `tools/mapgen/build.py`, `borrow.py` | verified 0.40.0. Some rally boards have their origin mid-height (lift them ~0.9 m); single-sided boards vanish from behind |
| `DecalRoad` objects (`nodes` [[x, y, z, width], ...], `material`, `textureLength`, `renderPriority`: lower draws on top) paint over the terrain without changing it: the wheels still read the terrain material (checked on ruts, lines, tracks and mud tracks). Objects find materials by **name**, which in a stock materials file can differ from `mapTo` (gridmap_v2's skidmarks_01): set `name` when borrowing | `tools/mapgen/decals.py` | verified 0.40.0 |
| `TerrainBlock:importMaps(heightmapPath, metersPerPixel, heightScale, holeMap, materials, textureMaps, flipY)` builds terrain from images; `editor.saveLevelAs(path)` saves a level | proving-ground research | read from `editor/terrainEditor.lua` / `editor/api/core.lua` (0.40.0), not yet called |
| Level load times | choosing venues | 0.40.0: template 8 s; West Coast USA 24 s warm, 142 s on the first load after the update |
| `WaterBlock` objects' `getWorldBox()`: the top is the water surface | masking lakes in the scan | verified 0.39.4 on nefr (a lake read as a 333 m flat mud square until masked); `River` boxes span half a map, so rivers aren't masked |
| `be:getSurfaceHeightBelow(vec3)` → ground height under a point (start above the ground) | drawing authored courses at ground level | verified 0.39.4 — flat to ±0.25 m over 50 m of the BMP dirt arena |

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
| GE `map.findClosestRoad(pos)` → node, node, distance; `map.getMap().nodes[name]` = `{pos, radius, normal, junction, links}`, link `{drivability, speedLimit, lanes, oneWay, ...}` | verified 0.39.4 | road width = 2 × radius; West Coast USA has 8,589 nodes. **Drivability is a road class, not a surface:** the asphalt BMP start straight is 0.5. Links can sit on only one of the two nodes |
| GE `castRayStatic(from, dir, maxDist)` → distance to static geometry | verified 0.39.4 | Save spot's room in eight directions |
| GE `ui_message(msg, ttl, category)` shows an on-screen message | verified 0.39.4 | Save spot confirmation |
| GE `extensions.ui_visibility.setCef(bool)` hides or shows the whole UI | verified 0.39.4 | venue report aerials; restore it in a `finally` |
| Vehicle Lua has `serialize(table)` (a Lua literal), usable in `obj:queueGameEngineLua` | verified 0.39.4 | Save spot sends wheel surfaces back |
| Electrics `steering` (telemetry `steer`) is the **steering wheel angle in degrees**, not −1..1 | verified 0.39.4 — about +80° mid-corner through the BMP downhill left in the Covet Gravel Rally; `steering_input` is the −1..1 input. `steady_exit` thresholds are in degrees |
| BMP gravel track layouts: time trials `gameplay/missions/west_coast_usa/timeTrial/wcusa_tt_gravel_001…`, `race.race.json` `pathnodes` = checkpoints {pos, radius = half the track width, normal = direction of travel} | read 0.39.4 — the circuit runs **north-east** from the start line (102.6, 165.5) through (180.6, 204.1) to (405.8, 421.3), round to (256.8, 427.8) and back south-west via (43.4, 173.4) |
| Vehicle Lua `powertrain.getDevice('mainEngine')`: `maxRPM`, `idleRPM`, `revLimiterRPM`; `powertrain.getDevice('gearbox').gearRatios` | verified 0.39.4 — Covet Student Driver: limiter 6500 rpm, idle 800; ratios 3.73 / 2.05 / 1.32 / 0.90, reverse −3.54 (A03's over-rev limits) |
| Vehicle Lua `controller.mainController.setGearboxMode('sequential')` then `shiftToGearIndex(n)` | verified 0.39.4 — scripted gear choice with an automatic clutch (the `gears` scenario). Starts in neutral; `shiftUp`/`shiftDown` don't exist on the controller (`shiftUpOnDown` etc. are input handlers). A 3rd→1st request at 40 km/h didn't over-rev: the box seems to protect itself |
| Vehicle Lua `input.event('steering' \| 'throttle' \| 'brake' \| 'parkingbrake', value, 2)` sets a driver input | verified 0.39.4 (filter 2; what the other filter values do wasn't checked) | scripted steering (`academy.follow_path`, the `a01` scenario); `electrics.values.steering_input` reads it back |
| MCP `drive_to` (`waypoint` node or `pos`, `routeSpeed` m/s, `routeSpeedMode`, `aggression`, `avoidCars`) drives the player car's AI to a road node; `set_ai {mode: 'disabled'}` hands control back | verified 0.39.4 | venue fit tests drive corners and routes; a target off the road makes it route somewhere else, so aim at a node along the road (`roads.follow`) |
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
| GE Lua `require('socket')` is LuaSocket 3.0-rc1 (TCP and UDP) | verified 0.39.4 — not used (a local command server was tried and rolled back; commit 2aa3530) |
| Hook `onExtensionUnloaded()` runs on `extensions.reload` | verified 0.39.4 — not used now |
| A mod's `settings/inputmaps/keyboard_<suffix>.json` adds default bindings alongside the game's and the player's `keyboard.diff` | verified 0.39.4 — listed by `core_input_bindings.getUsedBindingsFiles()`; `getControlForAction('rally_academy_retry')` returned our control. Modifier syntax as in the game's files: `"ctrl shift r"` |
| Alt+F4 inside a combo (Ctrl+Alt+Shift+F4) closes the game | observed 0.39.4 — never bind Alt (`dev.py validate` rejects it) |
| F13–F24 (`"f13"`…) as bindings | verified 0.39.4 — real key presses (Windows `keybd_event`, as a Stream Deck Hotkey sends) of F16, F15 and F13 ran Next drill, Previous drill and Retry. Shift+F13/F14 not pressed yet |

## UI apps

| Assumption | Status | Notes |
| --- | --- | --- |
| `app.json` without `types` is filed under "Unknown" | verified 0.39.4 | we set `ui.apps.categories.rally` |
| 0.40 rewrote the default HUD layouts (`settings/ui_apps/layouts/default/freeroam.uilayout.json`: minimap added, our panel gone); custom layouts survive | verified 0.40.0 | the saved "Rally Academy" layout still has the panel; switch to it with Use Layout. The scenarios click the HUD's Retry, so they need the panel up |
| 0.40 still emits `MainMenuButtons` / `BroadcastMainMenuButtons` (the redesigned tile menu); `ui_router_routeManager.registerModRoutes` and `ui_pause_actions.registerModTab` unchanged | 0.40.0: the event is in `ui-vue/dist/rt-modules.js`; the Academy screen and pause tab pass `mainmenu`/`pause`; the button itself not yet seen on the new menu | none of 0.40's breaking UI changes (`v-bng-panel` removed, `ChangeState` no longer sent, `createVueApp` deprecated) are used here |
| Adding an app: `Alt+Shift+U` (HUD Layouts) → layout → **Edit Layout** → **＋ Add app** | verified 0.39.4 | Layout Actions → Duplicate makes a separate layout; Use Layout switches |
| **Vue HUD apps from a mod:** `ui/modules/apps/<Name>/app.vue` + `"vue": true` in `app.json` | verified 0.39.4 | `ui_apps.getUIAppsData()` reports `hasAppVue = true`, `vueFile = /ui/modules/apps/RallyAcademy/app.vue`; rendered by `AppHost` through the runtime mod compiler (no Angular slot). Same directive name, so existing HUD layouts keep the panel. 3 of 3 UI reloads came back with exactly one panel. Imports: `useBridge().api.engineLua`, `useEvents()` (listeners removed on unmount) |
| An empty Lua table reaches the UI (guihooks, `runRaw`) as `{}`, not `[]` | verified 0.39.4 | check `Array.isArray` before using a list (an empty drill `rules` list crashed the HUD panel) |
| A native HTML `<select>` in a HUD app can't be opened by clicking | **broken 0.39.4** | the off-screen UI browser never shows the native pop-up list (the game's whole Vue UI has one `<select>`). Use `BngDropdown` (`items` = `{label, value}`, optional `group`/`grouped` headers, `show-search`; emits `valueChanged`) |
| The game ships its own rally HUD apps (`rallyCornerCalls`, `rallyVisualPacenotes`, `rallyTimecard`, `rallyStageTiming`, `rallyRecce`, ...) | seen 0.39.4 | worth studying for the F-module stages |
| Vue UI mods: files in `/ui/ui-vue/mods/<mod>/` (our `mod/ui/ui-vue/mods/rallyAcademy/`) are compiled at runtime; `index.js` exports `onLoad`/`onUnload` | verified 0.39.4 | `extensions.ui_uiMods.getVueMods()` lists them; edits hot-reload. Docs: `ui/ui-vue/mods/README.md` in the game folder |
| Main-menu buttons via `events.on("MainMenuButtons", addButton)`; `iconId` is a `bngIcons` glyph name (we use `raceFlag`) | verified 0.39.4 | mod buttons show under **More...** (route `menu.others`), tagged "Mod", not on the top level |
| Routes: `window.bngRoutes.add` + `ui_router_routeManager.registerModRoutes`; navigate with `ui_router.navigate(name)` | verified 0.39.4 | our `menu.rallyAcademy` opens from the main menu and also over the game view from inside a map |
| The Vue bridge's `lua.*` only has functions listed in `LuaFunctionSignatures.js`; others need `runRaw` from `@/bridge/libs/Lua.js` | verified 0.39.4 | `lua.extensions.rallyAcademy` is undefined; `runRaw("extensions.rallyAcademy.getMenuData()")` returns the table |
| `core_levels.startLevel` from the main menu loads the map but doesn't enter freeroam: no HUD layout, the menu route stays up | verified 0.39.4 | use `freeroam_freeroam.startFreeroam(path)`, as the Freeroam menu does |
| After a map started from our menu, the UI stays on our route until `ui_router.navigate('play')` | verified 0.39.4 | the game's own main-menu exit handler navigates to `play` in freeroam; we do the same once the car is placed |
| `simTimeAuthority.pause(bool)` / `getPause()` pause and resume physics (photomode uses them) | verified 0.39.4 | the Academy key binding pauses while the screen is open over a map |
| Route lifecycle hook `meta.luaRoute.onLeave = "rallyAcademy.onMenuLeave"` runs when the route is left by any path | verified 0.39.4 | leaving our route with `ui_router.navigate('play')` called it and physics resumed |
| Pause-menu mod tab: `ui_pause_actions.registerModTab` + `registerModButton({componentName, props, icon})` | verified 0.39.4 | the **Rally Academy** tab and its rail pages work, clicked with `ui_click` (scenario `pause`). Every button needs a valid bngIcons `icon`: `BngIcon` reads `.glyph` of `null` and throws, which corrupts the whole Vue UI (tabs vanish, later Esc presses fail) until a UI reload. Registrations survive UI reloads and a re-registered button keeps its old position, so unregister the tab first. The main card is ~450 px wide. The menu reopens on the last rail page |
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

## Appendix: the old Angular HUD panel

Replaced by the Vue panel (`app.vue`) on 2026-10-16; kept for anyone writing an Angular
HUD app on 0.39.

| Assumption | Status | Notes |
| --- | --- | --- |
| Legacy AngularJS apps in `ui/modules/apps/<Name>/` with `app.json` + `app.js` still load | verified 0.39.4 | catalogued by `ui_apps.getUIAppsData()` |
| `bngApi` is injectable in directives | **broken 0.39.4** | `Unknown provider: bngApiProvider`. It is a **global**; stock apps use it without injecting |
| Angular `element.scope()` is available for debugging | broken 0.39.4 | debug info is disabled; read the DOM instead |
| Remounting HUD apps cleans up the old Angular scope | **broken 0.39.4** | after map loads/vehicle swaps an orphaned panel can stay alive and still receive events (2 `rallyAcademyState` listeners, 1 panel on screen). The panel destroys itself on the next event if its element is detached, deferred until after the broadcast: `$destroy()` during a `$broadcast` throws (`reading '$$nextSibling'`). Count listeners (`$rootScope.$$listenerCount`), not scopes: `ng-if` child scopes inherit the panel's properties |
| Angular apps mount via `window.UIAppsServiceShim.mountDirective(slotId, appData)` (`ui/modules/apps/app-service.js`) into `.ui-angular-app-slot#bng-app-slot_<directive>_<instance>` | verified 0.39.4 | Angular's injector lives on `#angular-root` (`.data('$injector')`) |
| Panel survives a UI reload | **broken 0.39.4** | the shim can mount into a slot Vue then replaces (same id) and ignores later mounts; ~½ of reloads left an empty panel. `app.js` self-heals (unmount + mount after 3 s empty, max 2 tries) — 0 failures in 15 reloads after the fix |
| A mod `app.js` is loaded once per page | **broken 0.39.4** | often injected twice (two `?_dc=` script tags ms apart); don't keep per-load state that breaks if the file runs twice |
| Editing `app.js` hot-refreshes the panel | unreliable 0.39.4 | can fail with `Directive cache refresh failed`; run `reloadUI()` after editing |
