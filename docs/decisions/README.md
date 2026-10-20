# Decision records

Short notes on decisions that would be expensive to reverse or confusing
without context. One file per decision, numbered, never rewritten. A later
decision supersedes an earlier one and links back to it.

Template: **Context** (what forced a choice) · **Decision** · **Consequences**.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-repo-layout-and-tooling.md) | `mod/` is the zip root; one stdlib-only Python CLI | Accepted |
| [0002](0002-drill-data-source-of-truth.md) | `exercises.json` is the drill source of truth | Accepted |
| [0003](0003-testing-without-the-game.md) | Unit-test Lua under LuaJIT with engine stubs | Accepted |
| [0004](0004-telemetry-transport.md) | Telemetry via our own vehicle extension and `obj:queueGameEngineLua` (BeamNG's own pattern) | Accepted |
| [0005](0005-main-menu-via-vue-ui-mods.md) | Main-menu Academy screen as a BeamNG Vue UI mod (button + route) | Accepted |
| [0006](0006-stages-are-the-games-rally-mode.md) | Full stages are the game's Rally mode; stage drills F01–F05, F08 cut | Accepted |
| [0007](0007-venues-as-data.md) | Venues are shared data (`venues.json`); drills refer to them by id | Accepted |
| [0008](0008-proving-ground-map.md) | Our own generated map, the proving ground, for flat single-surface drills | Accepted, narrowed by 0010 |
| [0009](0009-surface-variants.md) | Surface variants are drills of their own (`A01-snow`), picked with a Surface row | Accepted |
| [0010](0010-every-drill-on-the-proving-ground.md) | Every drill on the proving ground; terrain features (hills, camber, jump, rough, water) in their own areas | Accepted |
