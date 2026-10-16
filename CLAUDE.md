# Working agreement for AI collaborators

Read this first, then the doc relevant to the task. Humans: this is a short
summary of the docs, aimed at coding assistants.

## Ground rules

- **Never claim something works in BeamNG unless the owner tested it in-game.**
  Say "unit tests pass" or "untested in-game". Record what was verified in
  [docs/BEAMNG_API_NOTES.md](docs/BEAMNG_API_NOTES.md).
- `mod/` is exactly the shipped zip root. Nothing else goes in it.
- `mod/gameplay/rallyAcademy/exercises.json` is the drill source of truth; the
  spreadsheet in `reference/` is historical ([ADR 0002](docs/decisions/0002-drill-data-source-of-truth.md)).
- Lua is authoritative for state and logic; the HUD (`ui/`) only displays and
  sends commands ([ARCHITECTURE](docs/ARCHITECTURE.md)).
- Keep BeamNG-specific calls thin and at the edges so logic stays unit-testable.
  If you use a new engine global, add it to `.luacheckrc`, the test stubs, and
  BEAMNG_API_NOTES (status "unverified").

## Before you hand back work

```sh
python tools/dev.py check --strict   # must pass
python tools/dev.py ingame smoke     # with the game running, for UI or engine-facing changes
```

Update `CHANGELOG.md` → `[Unreleased]` for user-visible changes, and the docs
when behaviour, schema or workflow change. Characterisation tests that pin a
known bug (`known_issue_*`) get flipped in the same commit that fixes the bug.

## Git

Short-lived branches off `main` (`feat/…`, `fix/…`, `docs/…`, `chore/…`) and
Conventional Commit messages. While the owner works solo, fast-forward `main` from
the branch once `check --strict` passes and push; open PRs if collaborators join.
Never push tags or publish releases without the owner asking. Details: [DEVELOPMENT](docs/DEVELOPMENT.md#git-workflow).

## Getting builds onto the owner's machine

The owner's PC can be linked to a Claude session. With their BeamNG user
folder connected, deploy by copying `mod/` to
`<user folder>/mods/unpacked/rally_academy/` (or ask them to run
`python tools/dev.py link` in their own clone), and read `<user folder>/beamng.log`
after they test. Never write anywhere else in their user folder.
