# 0011 — Physical course markers

**Date:** 2026-10-20 · **Status:** Accepted (reverses PRODUCT's "markers are drawn, not spawned props, for now")

## Context

Authored courses (DRILL_DATA) have been drawn with `debugDrawer`: gate posts and cones are overlay cylinders,
and `markers_clear` fails a run when the car's measured footprint comes within 0.15 m of one. Nothing is there to
hit, so a clipped cone is a number, not a thump, and a near miss that a real cone would survive can fail. The owner
asked for real cones (2026-10-20, "scene control", PRODUCT's step 2).

The game ships soft-body prop vehicles: traffic cones (`cones`, `large.pc`) and flexible delineator posts
(`delineator`, `pole.pc`). Its own drift mode spawns a pole with `core_vehicles.spawnNewVehicle` (no auto-enter),
reads the player car's `map.objects[id].objectCollisions` to see it was hit, and stands it back up with
`requestReset(RESET_PHYSICS)`. All three work from our extension (verified 0.40.0 on the proving ground: two props
in 0.4 s, the player stays in their car, a cone hit at walking pace shows in the collision list, and the reset puts
it back on its spot).

## Decision

- Every course marker is a physical prop: a delineator post at each gate post, a large traffic cone at each course
  cone and at each end of a stop line. `layout.lua` tags each marker with its `kind`; `props.lua` (the only module
  that spawns) stands them on the ground when the course is laid out, leaves them alone when the same course is
  laid out again, resets them on Retry and removes them on drill change, map unload and extension unload. They are
  named `ra_prop_*`, so a reloaded extension removes the previous one's.
- While a run is going, whatever the player car touches is recorded (name and speed). When props stand, those
  touches decide `markers_clear` ("Clipped the cone at 18 km/h"); the measured distance only reports how close the
  car came. Without props (unit tests, old recordings, an engine that can't spawn) `markers_clear` measures as
  before, so recorded fixtures grade the same.
- The overlay stays for what props can't show: gate state colours (the bar and the post tops above the real posts),
  a cone's passed / missed ring, the pass hint, boxes, zones, lines and circles.

## Consequences

- Hitting a cone is physical and moves it; the next Retry stands it back up.
- Laying out a course spawns a few vehicles (about 0.2 s each): a short hitch when a drill is selected, none on
  Retry. The game shows its "switch vehicle" hint once props exist; they are flagged not player-usable.
- A scripted line that passed 0.1 m from a post used to "clip" it; now only a touch counts, so a few scripted miss
  cases had to aim to actually touch.
- Open-ground courses can now carry corner signs the same way (IDEAS), if the owner wants them.
