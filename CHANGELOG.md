# Changelog

All notable changes to this mod. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/). Release process: docs/RELEASING.md.

## [Unreleased]

### Added
- Project infrastructure: `tools/dev.py` (validate, lint, test, reproducible
  build, live-link into BeamNG, log viewer, version bump), LuaJIT unit tests
  with BeamNG stubs, luacheck config, CI and tag-driven GitHub Releases.
- Developer documentation under `docs/` and decision records.
- `modScript.lua` loads the extension automatically when the mod is enabled
  (ported from the earlier skeleton repo), so key bindings work before the HUD is opened.

## [0.1.0] - 2026-10-13

### Added
- Initial starter scaffold (imported, untested in-game): GE extension with
  mark start/finish, retry, sim-time timer, self-assessed Pass/Miss and
  progress saving; HUD app; Retry/Pass/Miss input actions; 48 drill
  definitions.
