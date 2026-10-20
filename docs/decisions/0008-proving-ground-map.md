# 0008 — Our own map: the Rally Academy proving ground

**Date:** 2026-10-19 · **Status:** Accepted

## Context

Stock venues blur the mechanics a drill is about. The course audit ([COURSE_AUDIT](../COURSE_AUDIT.md))
found seven drills on a corner that drops 14 m at up to 35 %, braking drills crossing tarmac patches, and
little flat loose ground on West Coast USA. A prototype (see [IDEAS](../IDEAS.md#a-rally-academy-proving-ground-our-own-map))
showed that a functional level can be generated from data in Python, without the World Editor: it loads
in about 4 s, every pad reads exactly its surface, and the same drill plays measurably differently per
surface. The owner chose to build it (2026-10-19).

## Decision

- The mod ships a level, `ra_proving_ground` (`mod/levels/ra_proving_ground/`), **generated** by
  `tools/mapgen/build.py` from a layout file (`tools/mapgen/proving_ground.json`). The layout is the
  source of truth; the generated files are committed so the zip and the live link work without a build
  step, and `dev.py validate` checks they match the layout (rebuild after editing it).
- Functional first: flat terrain, surface pads and road shapes painted into the terrain's material layer
  on grass, the stock template's terrain materials and sky referenced by path (nothing copied). Looks
  (backdrop, props) come later and only if cheap.
- Venues on it are ordinary `venues.json` entries (`levelId: "ra_proving_ground"`). A drill moves there when
  its mechanic is better isolated on flat, single-surface ground; real-road drills (blind corners, hills,
  crests, camber) stay on stock maps. Corners can replicate a stock corner's centre line exactly, flat,
  so a drill keeps its course data.
- Per-surface variants (the same layout on gravel, snow, asphalt) are the next step; they change the drill
  model (targets and progress per surface) and get their own decision.

## Consequences

- One more thing to re-check after game updates: the level leans on the template's materials, sky and the
  `.ter` format (version 9 on 0.40). `audit.py` and `surface.py` verify each venue's surface and flatness.
- Map loads for drills on it drop from 20-140 s to a few seconds.
- The zip grows by the terrain file (3 MB raw, but flat and constant, so about 6 kB compressed) and the level appears in
  the game's map list.
- Stock maps stay the home of road-feature drills; the "Venues: Option A" decision is narrowed, not reversed.
