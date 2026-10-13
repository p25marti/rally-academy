# 0001 — Repository layout and tooling

**Date:** 2026-10-13 · **Status:** Accepted

## Context

The starter scaffold shipped a `mod/` folder plus a README warning that zipping
it with a wrapper folder breaks loading. We need fast local iteration in
BeamNG, reproducible release builds, and tooling that works on Windows (where
BeamNG runs), in CI (Linux) and in a Claude session (Linux).

## Decision

- `mod/` is exactly the zip root. Nothing outside it ships.
- A single Python 3.9+ standard-library script, `tools/dev.py`, does
  validation, build, linking into BeamNG, log viewing and version bumps. No
  pip installs, no Makefile (Windows-friendly).
- The version lives in `VERSION`, is mirrored into `app.json`, and the build
  stamps it into the zip.
- Builds are reproducible (sorted entries, fixed timestamps) and the zip name
  is stable: `rally_academy.zip`.
- Local testing uses a junction/symlink from `mods/unpacked/rally_academy` to
  `mod/`, with a `--copy` fallback.

## Consequences

- Contributors need only Python + git to build and test-install.
- Any new shipped asset type must be added to `ALLOWED_TOP_LEVEL` in `dev.py`.
