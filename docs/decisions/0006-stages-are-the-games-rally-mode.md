# 0006 — Full stages are the game's Rally mode, not Academy drills

**Date:** 2026-10-16 · **Status:** Accepted

## Context

Module F ("Rally stage performance") planned eight stage-level drills. BeamNG 0.39 ships
a full Rally mode (`lua/ge/extensions/gameplay/rally/`, stage missions in
`gameplay/missions/<map>/rallyStage/`). It has:

- real stages on six maps;
- co-driver pacenotes with voice, a recce mode and a notebook;
- rally loops with time controls, penalties and speeding detection;
- an attempt log;
- gold, silver and bronze medals against an authored reference time, with reset
  penalties (`starThresholds.lua`).

Building our own versions would duplicate it, and do it worse.

| Drill | Rally mode covers it? |
| --- | --- |
| F01 Pacenote interpretation | Yes |
| F02 Timed consistency runs | Yes (timed attempts, attempt log) |
| F03 Speed management / regularity | Mostly (speeding detection on road sections) |
| F04 Unfamiliar stages | Yes |
| F05 Long-stage concentration | Yes (rally loops) |
| F08 Full-stage integration | Yes (medals against reference times) |
| F06 Puncture adaptation | No |
| F07 Vehicle setup comparisons | No |

## Decision

- Cut F01, F02, F03, F04, F05 and F08 from `exercises.json`.
- Keep F06 and F07, renamed as module "Adaptation & setup", with **unchanged IDs**.
  Saved progress and setups are keyed by drill ID, and the spreadsheet in `reference/`
  still matches.
- The Academy screen (Exercises tab and About) points to the game's Rally mode for full
  stages.

## Consequences

- 42 drills. Progress or setups saved for the cut drills stay in the settings files,
  unused and harmless.
- The Academy's scope is car control (modules A to E) plus adaptation (F06, F07). Stage
  driving is the game's mode.
- The game's rally HUD apps and tooling remain useful references (PRIOR_ART), for example
  for timing or pacenote ideas in the remaining drills.
