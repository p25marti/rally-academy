# 0014 — Curriculum tidy-up: E01 and B08 cut, B04 to the test road, A07 without a line

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
- **B04 trail braking moves to the test road's closing right** (venue `pg-test-road-east`): a corner that tightens
  from 60 m radius to 29 m is where easing the brake off as you turn in matters most, and the apex gate sits at its
  tightest. The targets held unchanged (scripted gold). It is gravel only now: the test road has no asphalt or snow
  twin, so B04's surface variants went.
- **C08 (the flick) stays on the corner.** It was meant for a hairpin, but neither hairpin worked: driven up, the
  weight stays on the back and a scripted flick rotated the FWD Covet 4-5°; driven down (from the leg above the
  second hairpin), 1-4°, and harder flicks ran wide of the apex gate. The 8° target can't be set honestly there, and
  on the corner the drill is verified.
- **A07 has no racing line** (`assessment.racingLine: false`): no Show line, no Watch AI.

## Consequences

- 41 drills; six on the shared corner (A07, A08, C01, C02, C08, E02), down from nine.
- Progress players have on E01 or B08 stays in their file, unused, and so does B04's on asphalt and snow.
- The asphalt and snow corners stay: the remaining corner drills' variants use them.
- Fixtures and the `surfacecorner` scenario for E01 are gone; the Watch AI scenario uses D03 and D09.
