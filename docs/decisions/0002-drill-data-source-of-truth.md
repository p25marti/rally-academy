# 0002 — Drill data source of truth

**Date:** 2026-10-13 · **Status:** Accepted

## Context

The 48 drills were designed in a spreadsheet (`reference/…48_Drills.xlsx`) and
converted to `exercises.json`. Keeping two editable copies invites drift, and
the JSON will gain fields the spreadsheet can't express well (start
transforms, typed rules).

## Decision

`mod/gameplay/rallyAcademy/exercises.json` is the only source of truth. The
spreadsheet stays in `reference/` as historical design input and is not
regenerated or kept in sync. `dev.py validate` enforces the schema.

## Consequences

- Drill edits are reviewable JSON diffs.
- The spreadsheet's Session Log / progress tracking is replaced by in-game
  progress (`settings/rallyAcademyProgress.json`). A CSV export can be added later.
