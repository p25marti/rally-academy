# First-class architecture

State machine: `idle -> setup -> ready -> running -> review -> scored -> ready` with transitions isolated in GE Lua.

HUD: View/controller only; do not author physics logic in JS.

Scoring: Require typed rules: `gate`, `speed_range`, `brake_profile`, `no_handbrake`, `slip_angle_range`, `no_collision`, `exit_heading`.

Telemetry: Rate-limited GE/VLua bridge; canonical run sample includes `(simTime, pos, orientation, vel, steering, throttle, brake, handbrake, wheelSlip, damage)`.

Authoring: map-level `race.race.json` route authoring, persist start/finish transforms, compile into Academy exercise JSON.

Progress: Store attempt summaries and mastery independently; schema-version progress and support migration.

Testing: pure Lua rules outside game, smoke integration on 0.39.x, test game upgrades, test packed-zip mod with unpacked content removed.

Edge cases: menu focus, pause clock, switching vehicle, damage reset and re-warm, map exit, gap in trajectory after teleport, UI recreation, simultaneous mission mode, unknown config.
