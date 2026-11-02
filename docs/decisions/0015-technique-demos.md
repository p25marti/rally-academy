# 0015 — Technique demos: our skill runner drives the player's car for Watch AI

**Date:** 2026-11-02 · **Status:** Accepted

## Context

Watch AI ([ADR 0013](0013-racing-lines-from-the-map-builder.md)) has the game's AI drive a drill's racing line. It
drives the line, not a technique, so the drills where showing would help most have no demo: C08's Scandinavian flick,
C02's rotation, B04's trail braking. The driver model ([DRIVER](../DRIVER.md)) now drives C08's flick from a
technique card with tuned dials, gold on gravel, asphalt and snow. The owner asked for it in the game as Watch AI
(2026-11-02), with each step's cue shown while it drives, the phases marked on the input trace, and a half-speed
option.

Until now the runner was a developer tool, injected into the car by `tools/driver/attempt.py`. Shipping it means the
mod itself drives the player's car with its own controller, rather than handing the car to the game's AI.

## Decision

- **The runner ships with the mod**, as the vehicle extension `rallyAcademy/driver`
  (`mod/lua/vehicle/extensions/rallyAcademy/driver.lua`). The training tools load the same file, so the code the dials
  were tuned with is the code the player watches.
- **Technique cards ship as data**, in `mod/gameplay/rallyAcademy/techniques/`: the card (phases, cues, human limits,
  dials, and per drill the line the runner follows, in the course frame) and its tuned dials per surface
  (`<card>-<surface>.json`, written by `tools/driver/tune.py`). A drill opts in with `assessment.technique: "<card>"`;
  `dev.py validate` checks the card and the surface's dials exist.
- **Ship the tuned line, not the mod's racing line.** The dials were tuned on the scenarios' corner line, which keeps
  nearer the middle so the feint has room. The mod's minimum-curvature line is tighter, and retuning on it would cost
  about three hours of tuning per drill for a line that may not suit a flick.
- **Watch AI on a technique drill** (`M.demo`) is Retry, then the runner, configured from the card, the surface's
  tuned dials and the course laid out from the start (`technique.lua`, pure). It is offered only in the drill's own
  car (the dials were tuned in it) and on its course; otherwise the panel says why. As with ADR 0013 the run is graded
  but never counted, and any reset hands the car back: the runner lets go of the controls and puts the player's
  gearbox mode back (it drives in realistic mode, choosing its own gear).
- **The runner reports each phase** to the GE extension (`onDriverPhase`, with the car's sim time). The Coach panel
  shows the card's steps with the current one highlighted (a list, because the middle steps last under half a second
  each), the panel shows the current cue when the Coach app isn't up, and the input trace marks each phase with the
  card's short `mark` label.
- **Half speed** is a remembered preference (`demoSlowMo`, the **½ speed** button next to Watch AI) that applies the
  game's slow motion (`simTimeAuthority.set(0.5)`) while any Watch AI runs, and puts the previous speed back with the
  car.

## Consequences

- Dials have to work at the frame rates players have, not only in deterministic fast mode. The first gravel and
  asphalt dials passed in fast mode and at 30 fps but missed at a focused game's frame rates and at half speed (the
  runner decides at 20 Hz of sim time, and how those decisions fall between frames changes the result). The shipped
  dials were chosen again from the same tuning runs, checked in all four conditions (DRIVER, "Watch AI"). Future
  tuning should check normal speed with the frame cap lifted before writing a winner.
- A new technique needs a card, tuned dials for each surface, its drill's line, and `assessment.technique`; the runner
  itself drives only the flick's phases for now (generalising it is the versatile driver's job, IDEAS).
- Card text (cues, marks, the technique's description) is player-facing: it's still Claude's draft and needs the
  owner's review.
