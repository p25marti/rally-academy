# 0010 — Every drill on the proving ground, terrain features in their own areas

**Date:** 2026-10-20 · **Status:** Accepted (narrows [ADR 0008](0008-proving-ground-map.md): road-feature drills no
longer stay on stock maps)

## Context

ADR 0008 moved the drills that need flat, single-surface ground to our generated map and kept "real-road" drills
(blind crests, hills, camber, jumps, rough ground, water) on stock maps. The owner wants every exercise on the
proving ground (2026-10-20), with the terrain features built in areas of their own so the flat drill areas stay
flat.

## Decision

- The generator shapes terrain along roads: a road can carry an elevation `profile` (m above the ground level, one
  value per point), `camber` (banking per stretch) and `bumps` (rough ground, the whole road or a
  `from` / `to` stretch); the terrain follows the road over its
  width and a 2 m shoulder and blends back to the ground over `blendM` (30 m by default). Water sits in a road's dip (layout `water`: a WaterBlock).
- Feature roads live in their own areas (east of the strips first). The build refuses a layout whose shaping
  reaches any flat pad or flat road, so the flat drills can't be disturbed by accident.
- A drill tied to a real stock road keeps its course data by copying that road's centre line **and its measured
  elevation** (sampled from the stock map's terrain), shifted with the same heading, as the flat corner and lane
  copies already do. Drills without a fixed course get purpose-built features (a cambered corner, a jump, a rough
  road, a water splash).

## Consequences

- Every drill can run on one map that loads in seconds; stock maps remain only as the source of copied roads.
- Copied hills lose what the terrain around the stock road looked like (walls, banks, trees close by); the road
  surface itself, its grades and crests, are kept.
- Shaped terrain is no longer "dead flat", so the course audit's grade and rise columns matter again for those
  drills, as intended.
