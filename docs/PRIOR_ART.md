# Prior art

Existing BeamNG systems, tools and mods we can reuse instead of rebuilding.
Researched 2026-10-14 from web search summaries; the **Telemetry** section was
re-checked against the game's own Lua and measured in-game on 2026-10-15. Other
sections are still unconfirmed, and every API stays `unverified` in
[BEAMNG_API_NOTES](BEAMNG_API_NOTES.md) until tested in-game.

**Summary:** no existing mod grades driving drills, so the rule engine and
drill scoring ([GRADING](GRADING.md)) are ours to build. Much of the layer
beneath them already exists, mostly inside BeamNG.

The game ships its logic as readable Lua in the install folder. We can call
its modules at runtime and read them to learn the APIs, but the code is
proprietary, so we don't copy large chunks of it into this repo.

## Built into BeamNG

| System | What it gives us | Covers |
| --- | --- | --- |
| Race path, checkpoints, time trials ([overview](https://www.beamng.com/game/news/patch/race-system-overview/)) | Gates, checkpoint crossing, start lines, segment and stage timing, plus editors to lay them out | Course geometry, timing, D02, F02–F05 |
| Rally mode: Rally Editor, rally stage missions, visual pacenotes ([dev post](https://beamng.com/goto/post?id=1403802); a 30 km stage was [added in 0.39](https://racinggames.gg/article/beamngdrives-039-patch-brings-a-graphics-overhaul-proper-rally-stages-and-more)) | Stage authoring and pacenote playback | Module F, especially F01 |
| Drift spots: start and scoring lines, drift data editor, score targets ([format](https://docs.beamng.com/modding/levels/level_formats/driftspots/)) | The game already detects and scores drifts | Slip angle and held slides (C03, C06) |
| Cone prefabs ([tutorial](https://www.beamng.com/threads/time-trial-and-prefab-tutorial.101736)) | Cones are physics objects, so a moved cone means contact | Cone contact, about 15 drills |
| `core_checkpoints` | Reset and repair logic; we already copy its rotation convention | Run lifecycle, repair on retry |
| `electrics.values` on the vehicle (e.g. `wheelspeed`, `avgWheelAV`) ([docs](https://documentation.beamng.com/modding/vehicle/vehicle_system/electrics/)) | Raw speed and input signals | Telemetry |

## Telemetry

**Verified 2026-10-15** against the 0.39.4 Lua source in the install, with in-game
measurements where noted. Decision: [ADR 0004](decisions/0004-telemetry-transport.md).

### Inside the game

| System (file) | What it does | Use for us |
| --- | --- | --- |
| `utRecorder` (`lua/vehicle/extensions/utRecorder.lua`) | Vehicle extension: each `updateGFX` packs inputs, speeds, position, direction and calls `obj:queueGameEngineLua(...)` to a GE recorder | **The pattern we follow**: our sampler is the same mechanism with per-wheel data and a faster encoder |
| `gameplayStatistic` + `gameplayStatisticModules/watchAirtime`, `watchBurnout` | Career stats: vehicle-side watchers in `updateGFX`, results sent to GE with `obj:queueGameEngineLua` | Same pattern. `watchAirtime` is the reference airborne test (all wheels `contactMaterialID == -1`, ground speed > 6 m/s, upright) |
| `guistreams` (`lua/vehicle/guistreams.lua`) | `wheelInfo` (name, radius, angular velocity, `lastSlip`, downforce, braking torque…), `engineInfo`, `electrics`, `sensors` (g-forces, roll/pitch/yaw) | Feeds the **UI**, not GE, only while an app subscribes. Reference for canonical field sources |
| `core_vehicleBridge` + vehicle `gameplayInterface` | Subscribe to electrics keys; cached in GE | Electrics only, one message per changed key per frame. Fine for occasional values, not for per-wheel sampling |
| `telemetryLogger` (vehicle extension) | Records inputs, speed, position, g-forces to CSV on disk | Too narrow; writes files, not a feed |
| `telemetry/core.lua` (GE) | Gameplay analytics events to `telemetry/<session>.jsonl` | Not vehicle data |
| OutGauge / MotionSim (`lua/vehicle/protocols/`) | UDP to an external program; settings-gated, fixed packets (OutGauge has no per-wheel data) | External dashboards only. Their comments document the rate trade-off: graphics step cost "ok", physics step (≤ 2000 Hz) "big" |
| MCP `get_electrics` (`mcp/tools/telemetry.lua`) | One-off async read via `be:queueObjectLua` → `obj:queueGameEngineLua` | Same mechanism, on demand; handy for debugging |
| `mqttGrafanaDemo` (vehicle extension) | Streams to an MQTT broker | External; a model for an optional live dashboard later |
| BeamNG.tech sensors (`tech/powertrainSensor`, IMU…), Vehicle Stats Logger | Rich sensors | Gated by `tech/license.lua`; the stats logger isn't in .drive |
| `dynamicVehicleData` (vehicle extension) | Works out transmission, drivetrain, fuel type | Later: checking drill cars ([VEHICLES](VEHICLES.md)) |

### Outside the game

| Source | What it is | Use for us |
| --- | --- | --- |
| [OfficialLambdax/BeamNG-Telemetry](https://github.com/OfficialLambdax/BeamNG-Telemetry) | MIT vehicle extension reading inputs, per-wheel speed/slip/material/brakes, energy; samples on the graphics tick; JSON lines | Transport depends on a **BeamMP server**, 0.35-era, 9 commits, 1 star. Field reference only |
| [BeamNGpy / BeamNG.tech](https://documentation.beamng.com/beamng_tech/sensors/) | See [below](#beamngtech) | Not usable in a shipped mod |

### Measured cost of our sampler (0.39.4, Covet, 4 wheels)

| Step | Cost | For comparison |
| --- | --- | --- |
| Build one sample in the car (`string.buffer`) | 1.4 µs | `serialize()` (utRecorder) 3.3 µs, `lpack` (vehicleBridge) 3.5 µs |
| Parse it in GE (`loadstring` + run) | 14.9 µs | at 60 Hz: 0.9 ms per second, ~0.09% of a frame |
| Message size | 234 bytes | |

Delivery follows the frame rate (60 Hz focused, 30 Hz in the background). The
vehicle extension survives a Retry reset.

## Community mods

| Mod | What it is | Use for us |
| --- | --- | --- |
| [Rally Mode smart co-driver / PacenoteDirector](https://www.beamng.com/resources/rally-mode-smart-co-driver-stages-with-pacenotes.21824) | Co-driver and pacenote tooling | Possible base for F-module pacenote drills; licence not checked |
| [ai pacenotes](https://beamng.com/posts/1692551/) | Generated pacenotes | Same as above |
| [BeamNG Hotseat](https://www.beamng.com/resources/beamng-hotseat.39243/) | Reuses built-in time trials, cones and ghost deltas | A worked example of the reuse pattern we'd follow |
| [Time trial and prefab tutorial](https://www.beamng.com/threads/time-trial-and-prefab-tutorial.101736) | Building a course from cone prefabs and a race path | Drill authoring |

No gymkhana, autocross or driving-school mod with cone penalties or pass/fail
grading turned up.

## What this changes

1. **Telemetry:** our own vehicle extension on BeamNG's `utRecorder` pattern ([ADR 0004](decisions/0004-telemetry-transport.md)); Lambdax as a field reference.
2. **Gates and timing:** try BeamNG's race path and checkpoints before writing
   our own geometry. Our code then shrinks to zones, corridors and
   bumper-to-line offsets.
3. **Cones:** spawn stock prefabs and detect contact by movement.
4. **C-module slides:** read the built-in drift detection first; it may already
   provide slip angle and spin.
5. **F-module:** build on rally mode and its pacenotes instead of our own stage
   system (ROADMAP P4).

## What sensor data is documented

BeamNG's [electrics docs](https://documentation.beamng.com/modding/vehicle/vehicle_system/electrics/)
say there is **no definitive list of electrics**: each vehicle's parts and
controllers add their own. They describe the main ones (speed, `wheelspeed`,
`avgWheelAV`, RPM, gear, pedals) and note the docs are incomplete. Per-wheel
slip, contact material, deflation, damage and gearbox internals live in vehicle
Lua tables outside `electrics.values` and aren't documented; the Lambdax
extension is the best public example of reading them. The older
[Vehicle Lua wiki](https://wiki.beamng.com/Vehicle_Lua) is partly out of date.

The reliable way is to ask the game:

1. Load the drill car, open the console with `~`, and switch its context
   dropdown to the current vehicle.
2. Run `dump(electrics.values)`, drive a little, and run it again to see what changes.
3. Run `dump(wheels.wheels[0])` for one wheel (table name from memory; may differ in 0.39).

Record what you find in BEAMNG_API_NOTES as `verified <build>`.

## BeamNG.tech

BeamNG.tech is BeamNG's research and industry edition. It runs the same
soft-body physics as BeamNG.drive but is built for programs that drive the
simulator: a Python API (BeamNGpy), a ROS bridge, simulated sensors (cameras,
lidar, radar, ultrasonic, IMU, GPS, electrics, and a powertrain sensor at up to
2000 Hz), and frame-by-frame stepping. Its users are universities, carmakers
and testing companies. Academic and non-commercial use is free on request;
commercial use needs a paid licence (terms not re-checked).

It doesn't help the mod itself: players run BeamNG.drive, and everything
grading needs is reachable from in-game Lua. A
[forum answer](https://forum.beamng.tech/t/inquiry-about-beamng-tech-requirement-for-vehicle-telemetry/223)
notes BeamNG.drive exposes electrics without a .tech licence; only deeper data
such as motor and axle torques is .tech-only. Its one possible use is an
optional developer tool that drives a car through a drill and checks the
grader, which would need a licence. Unit tests on recorded run fixtures give
most of that value for free.
