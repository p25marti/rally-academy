# 0009 — Surface variants are drills of their own

**Date:** 2026-10-20 · **Status:** Accepted

## Context

The proving ground ([ADR 0008](0008-proving-ground-map.md)) has identical strips of dirt, gravel, asphalt and snow,
and the owner asked for the first exercises on each surface (2026-10-20). The prototype showed the same drill plays
differently per surface (B01's threshold braking is impossible at its dirt target on snow; C04's hairpin line
overshoots on asphalt), so a variant needs its own venue, sometimes its own targets, and its own progress and
medals. Everything in the mod (progress, medals, saved setups, fixtures, the HUD's best time) is keyed by drill id.

## Decision

- A drill may list `variants` in `exercises.json`: each has a lowercase `id`, a display `name`, a `venue`, and
  optional `areaHint`, `vehicle`, `rules`, `tiers` and `successDefinition`. The drill names its own surface in
  `surface` ("Dirt").
- The loader expands each variant into a full drill with id `<drill>-<variant>` (`A01-snow`), inheriting
  everything else. A variant's rule overrides replace every base rule of the same type (or are added), in the base
  rules and per medal tier: the same "replace by type" a medal tier already uses. Lua (`variants.lua`) and the
  Python tools (`tools/ingame/variants.py`, used by `dev.py validate`) expand the same way.
- Because a variant is just another id, progress, medals, setups and fixtures are per surface with no other change.
- The catalogue and the HUD's drop-down list base drills only; a **Surface** row of chips (HUD panel, Academy
  screen) picks the variant, with a dot for the best medal on each surface.
- Targets change per variant only where measured physics demands it (scripted runs per surface: the `surfaces`
  scenario); the technique a drill teaches stays the same.

## Consequences

- The drill list doesn't grow; module A gains 15 variants (gravel, asphalt and snow for A01-A05, dirt being the base).
- Progress views that sum per drill (the Academy screen's module counts, the Analysis page) count the base drill
  only for now.
- A variant can't change the course layout (it inherits the base course). If one ever needs to, it gets its own drill.
