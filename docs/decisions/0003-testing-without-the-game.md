# 0003 — Testing without the game

**Date:** 2026-10-13 · **Status:** Accepted

## Context

BeamNG can't run in CI or in a Claude session, and in-game testing is manual
and slow. The scaffold had never been run.

## Decision

- Run the mod's real Lua under **LuaJIT** (same flavour as BeamNG) with a
  small fake engine (`tests/lua/beamng_stubs.lua`) and a dependency-free
  runner. No busted or LuaRocks.
- Lint with **luacheck** using an explicit allow-list of engine globals.
- Build both from source with a pinned script (`tools/ci/setup-lua.sh`) so CI
  and local versions match.
- Keep a written in-game smoke test (docs/TESTING.md), and a ledger of engine
  assumptions with verification status (docs/BEAMNG_API_NOTES.md).

## Consequences

- Logic regressions are caught automatically. Engine-integration bugs are only
  caught in-game, which is why the stubs and API notes must be corrected
  whenever the game disagrees with them.
- Pushes architecture toward a pure core with thin engine adapters.
