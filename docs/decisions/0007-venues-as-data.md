# 0007 — Venues are shared data

**Date:** 2026-10-16 · **Status:** Accepted

## Context

Every drill carried its own copy of its venue in `environment`: `levelId`,
`mapDisplayName` and the `spawn` pose Go to drill uses. 42 drills shared six venues; the
BMP Gravel Track alone was copied into 23 drills. Moving a venue's spot meant editing every
copy, and the venue tools (`survey.py`, [VENUES.md](../VENUES.md))
had no single list of venues to work from.

## Decision

- `mod/gameplay/rallyAcademy/venues.json` holds the venues: id, MAPS id, name, `levelId`,
  `spawn` and notes.
- A drill's `environment` keeps only what's specific to the drill: `venue` (an id),
  `areaHint` and `venueNeeds`.
- The extension fills `levelId`, `mapDisplayName` and `spawn` into each drill from its venue
  when it loads, so the HUD, the Academy screen and Go to drill are unchanged. The Python tools
  and test helpers resolve venues the same way.
- `dev.py validate` checks the file and every reference, and rejects drills that still carry
  their own venue fields.

## Consequences

- One edit moves a venue for every drill on it. New venues found with the venue tools become
  one entry, which drills then point to.
- The drill schema stays version 1 (the loader keeps the resolved fields), but older copies of
  `exercises.json` without `venue` won't validate.
- Next step on the roadmap (P1): captured setups (start, finish, gates) could move into venue or
  drill data, so drills work without marking.
