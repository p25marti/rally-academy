# 0013 — Racing lines from the map's roads, through each drill's gates; the AI can drive them

**Date:** 2026-10-21 · **Status:** Accepted (revised the same day: lines are now worked out in the mod, per drill)

## Context

The owner asked for a racing line on the road and AI demonstration laps (2026-10-21), after the proving ground's roads
joined the game's road graph. The plan offered was a "show me the line" toggle, off by default, drawn from the
scripted lines the in-game scenarios drive (`tools/ingame/lines.py`). A closer look showed those don't make a teaching
line:

- Only the corner drills have a real racing line (offsets off the BMP corner's centre line, tuned per drill and
  nudged outward because the pure-pursuit follower cuts inside). The road drills (D02-D09, E05-E08) drive the road's
  centre line, and the strip drills drive straight lines or cone weaves.
- They live in Python test tooling, in each drill's course frame.

The first version had the map builder compute one minimum-curvature line per road. The AI demo then showed that a
line that ignores the drill misses its gates: A07's 3 m exit gate sits at the track-out, and the road's own line ran
3.3 m to one side of it.

## Decision

- **The map supplies roads, the mod works out lines.** The map builder writes each drill road (those with turn
  markers) to the level as `rallyAcademy/roads.json`: its centre line every 3 m with the ground's height and how the
  road tilts across, its width and its surface's grip (`tools/mapgen/racingline.py`).
- **A drill's line goes through its gates** (`racingLine.lua`, pure): from where the drill starts the car, along the
  road it's on the way it faces, the **minimum-curvature path** inside the road (half a car and a little from each
  edge) that passes every gate at least 1 m inside its posts, to 30 m past the last gate. Each point carries a target
  speed from a simple model (grip, the road's banking or off-camber, a standing start, braking for each corner) and
  what to do there: brake, hold the corner's limit, or accelerate.
- **Show line** draws it as a flat ribbon on the ground, red, yellow and green (HUD button, Shift+F15); off by
  default, remembered.
- **Watch AI** puts the car back at the start and lets the game's AI drive the same line
  (`ai.driveUsingPath{script = ...}`, within 1 m of it, aggression 0.8, its own speeds). The run is graded like the
  player's, so the student sees what the line earns, but it isn't recorded: no attempt, no progress, no auto-retry.
  Retry, Miss or the car stopping at the line's end hands the car back.

## Consequences

- Every road drill and corner drill has a line on every surface variant, and the line always agrees with the drill's
  current gates: editing a course needs no map rebuild. Strip and ring drills have none (no road).
- A drill that teaches a particular line (A08's late apex) gets it only as far as its gates force it.
- The speed model is a guide, not physics: no gearing, gradient, downforce or combined grip. The colours (where to
  brake and where to go) matter more than the numbers, which the HUD doesn't show. The AI picks its own speeds.
- The scripted scenario lines stay as they are: they're tuned for the follower, not for teaching.
