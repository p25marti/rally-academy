# 0004 — Telemetry: our own vehicle extension, BeamNG's own pattern

**Date:** 2026-10-15 · **Status:** Accepted

## Context

Automatic grading ([GRADING](../GRADING.md)) needs a per-attempt record of driver
inputs, engine state and **per-wheel** data (speed, surface, contact). Driver
inputs and wheel data live in each car's own Lua VM; grading runs in GE Lua. We
wanted to reuse an existing solution rather than build one, and to avoid
performance problems an existing solution might already have solved.

Everything below was checked against the 0.39.4 Lua source in the install and,
where marked, measured in-game (details in [PRIOR_ART](../PRIOR_ART.md#telemetry)).

| Option | Why not (or why) |
| --- | --- |
| `core_vehicleBridge` value-change notifications | Electrics only (no per-wheel data); one GE message per changed key per frame |
| `guistreams` (`wheelInfo`, `electrics`, `sensors`) | Feeds the UI (CEF), not GE Lua, and only while an app subscribes |
| OutGauge / MotionSim UDP | Fixed external packet formats, no per-wheel data in OutGauge, needs the player to enable it in settings |
| BeamNG.tech sensors (powertrain, IMU, Vehicle Stats Logger) | Behind `tech/license.lua`; not in BeamNG.drive |
| `telemetryLogger`, `utRecorder` (vehicle extensions in the game) | Fixed small field sets, CSV to disk / test-only GE target. `utRecorder` is BeamNG's own *pattern* for this job |
| [OfficialLambdax/BeamNG-Telemetry](https://github.com/OfficialLambdax/BeamNG-Telemetry) (MIT) | Transport needs a BeamMP server; 0.35-era, 9 commits. Good field reference only |
| **Our vehicle extension → `obj:queueGameEngineLua`** | Chosen |

## Decision

- Ship a vehicle extension, `lua/vehicle/extensions/rallyAcademy/telemetry.lua`,
  loaded into the player's car with `extensions.load('rallyAcademy/telemetry')`.
- In `updateGFX` (graphics step) it sends **one batched sample per tick** to GE via
  `obj:queueGameEngineLua`, the same mechanism the game uses in `utRecorder`,
  `gameplayStatistic` and the MCP tools. Graphics step, not physics step: the
  game's own OutGauge notes call the graphics step's cost "ok" and the physics
  step's (up to 2000 Hz) "big".
- Samples carry their own sim timestamp (`obj:getSimTime()`), so grading never
  assumes a fixed rate (it follows the frame rate: 60 Hz focused, 30 Hz with the
  window in the background).
- Field sources follow the game's own code: inputs from `electrics.values`, per
  wheel from `wheels.wheelRotators` (as `guistreams.wheelInfo` does), airborne as
  in `gameplayStatisticModules/watchAirtime` (all wheels `contactMaterialID == -1`).
- Fields are added by extending the sample builder, not the transport; GE parses
  each message once and the run record and rules never see the wire format.

## Consequences

- Measured on 0.39.4 (Covet, 4 wheels): **1.4 µs** to build a sample in the car,
  **14.9 µs** to parse it in GE, 234 bytes. At 60 Hz that is ~0.09% of a frame.
  Faster than the game's own `serialize()` (3.3 µs) and `lpack` (3.5 µs) encoders.
- The extension survives a Retry reset, but must be loaded into each new car
  (spawn, vehicle switch): the GE side owns that.
- Revisit if a drill needs more than the frame rate (then a physics-step sampler,
  as `motionSim` does, for that field only), or if GE parse cost ever shows up
  (then batch several samples per message).
- We maintain the field list ourselves; BeamNG may rename vehicle internals
  between versions, so every field stays in BEAMNG_API_NOTES with its verified build.
