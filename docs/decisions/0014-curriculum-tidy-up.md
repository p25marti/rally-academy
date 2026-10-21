# 0014 — Curriculum tidy-up: E01 and B08 cut, drills off the shared corner, A07 without a line

**Date:** 2026-10-21 · **Status:** Accepted

## Context

A review of all 43 drills (2026-10-21) found some that no longer fit after the surface variants (ADR 0009), the move
to the proving ground (ADR 0010) and the racing line (ADR 0013):

- **E01 Snow vs gravel vs tarmac** was the surface comparison as a drill of its own, on the gravel corner. Since ADR
  0009 every corner drill has its own asphalt and snow versions, so E01 repeated what the Surface row does.
- **B08 Longitudinal weight transfer** was a self-assessed comparison of lift-only, light-brake and neutral entries on
  the same corner: what C01 (lift-off) and C02 (brake pulse) teach, side by side, still waiting on a comparative
  grading design.
- **Nine drills shared one left-hander** (A07, A08, B04, B08, C01, C02, C08, E01, E02), while the map has hairpins, a
  test road, a camber road and a hill circuit.
- **A07** asks the driver to try early, middle and late apexes; Show line and Watch AI hand them one answer.

The owner agreed to every suggestion (2026-10-21).

## Decision

- **Cut E01 and B08.** Their ids stay retired (like F01-F05 and F08, ADR 0006). C01's and C02's instructions now
  explain the weight transfer B08 was about: a neutral entry first, then what the lift or the brake pulse adds.
- **Move drills off the shared corner** where another road teaches the technique better: C08 (the flick) and B04
  (trail braking), each in a change of its own with re-tuned targets and scripted runs.
- **A07 has no racing line** (`assessment.racingLine: false`): no Show line, no Watch AI.

## Consequences

- 41 drills. Progress players have on E01 or B08 stays in their file, unused.
- The asphalt and snow corners stay: the remaining corner drills' variants use them.
- Fixtures and the `surfacecorner` scenario for E01 are gone; the Watch AI scenario uses D03 and D09.
