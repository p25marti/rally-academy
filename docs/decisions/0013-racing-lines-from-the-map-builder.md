# 0013 — Racing lines are computed by the map builder

**Date:** 2026-10-21 · **Status:** Accepted

## Context

The owner asked for a racing line to show on the road (2026-10-21), after the proving ground's roads joined the game's
road graph. The plan offered was a "show me the line" toggle, off by default, drawn from the scripted lines the in-game
scenarios drive (`tools/ingame/lines.py`). A closer look showed those lines don't make a teaching line:

- Only the corner drills have a real racing line (offsets off the BMP corner's centre line, tuned per drill and
  nudged outward because the pure-pursuit follower cuts inside). The road drills (D02-D09, E05-E08) drive the road's
  centre line, and the strip drills drive straight lines or cone weaves.
- They live in Python test tooling, in each drill's course frame, so shipping them would mean copying tuned
  numbers into drill data by hand.

The map builder already knows every road exactly: its centre line, width, surface and the terrain under it.

## Decision

- `tools/mapgen/racingline.py` computes a line for every road with turn markers, each way its drills drive it: the
  **minimum-curvature path** inside the road (keeping half a car and a little from each edge), starting in the
  middle where the drills start the car. Each point carries a target speed from a simple model (the surface's grip,
  the banking or off-camber measured from the terrain, a standing start, braking for each corner) and what to do
  there: brake, hold the corner's limit, or accelerate.
- The builder writes them into the level (`rallyAcademy/racingLines.json`), so they're rebuilt whenever a road moves
  and `dev.py validate` catches a stale copy.
- The mod reads the current map's file. A drill gets the stretch of line through its start, facing its way, up to
  30 m past its last gate (`layout.racingLine`, pure). It's drawn as a flat ribbon on the ground, red, yellow and
  green, when the player turns **Show line** on (HUD button, Shift+F15); off by default, remembered.

## Consequences

- Every road drill and corner drill has a line, on every surface variant (each corner and hairpin road is its own
  line), with no per-drill data to maintain. Strip and ring drills have none (no road).
- One line per road: drills that teach a different line on the same corner (A08's late apex) show the general one.
  A per-drill override can come later if the owner wants it.
- The speed model is a guide, not physics: no gearing, gradient, downforce or combined grip. The colours (where to
  brake and where to go) matter more than the numbers, which the HUD doesn't show.
- The scripted scenario lines stay as they are: they're tuned for the follower, not for teaching.
