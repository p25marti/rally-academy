# Grading engine

What the engine needs so drills can be graded automatically instead of by
self-assessed Pass/Miss. This expands the Telemetry and Scoring parts of
[ARCHITECTURE](ARCHITECTURE.md#target-architecture) and the P2/P3 items in the
[ROADMAP](ROADMAP.md). Existing tools and mods we can reuse are in
[PRIOR_ART](PRIOR_ART.md); car choices are in [VEHICLES](VEHICLES.md).

**Status:** the telemetry sampler, run records and the rule engine exist.
Twenty-six drills are graded automatically: **A01** (gate, cone and parking box, with medals),
**A02** (launch and shift on a course, with medals), **A03** (downshifting on a course, with
medals), **A04** (speed hold through gates on a course, with medals), **A05** (stop before a line
on a course, with medals), **A07** (racing line and exit speed through a corner, with medals),
**A08** (late apex and a steady exit, with medals), **B01** (threshold braking into a course stop zone, with medals), **B02** (lockup recovery, with
medals), **B04** (trail braking through a corner, with medals), **B05** (left-foot braking round a
course circle, with medals), **B06** (correcting understeer back onto a course circle, with medals) and
**B07** (catching an oversteer slide, with medals) **C01** (lift-off rotation into a corner, with medals), **C02** (brake-induced rotation into a corner, with
medals), **D01** (six-cone slalom, with medals), **D08** (braking across a tarmac-to-gravel change, with medals), **E02** (FWD rotate-then-pull exit, with medals), **D03** and **D04** (tightening and opening corners, with medals), **D05** (blind crest hairpin, with medals), **D06** (uphill and
downhill corners, with medals), **E05** (a planted crest, with medals), **C04** (handbrake hairpin round a cone, with medals), **C07** (figure-eight round two cones, with medals) and **C08** (Scandinavian flick, with medals). Every other drill is still
`selfAssessment` with an empty `rules` list. Engine data sources not listed as
verified in [BEAMNG_API_NOTES](BEAMNG_API_NOTES.md) remain **unverified**.

Sections 1–7 below are the capabilities; [Drill coverage](#drill-coverage)
maps each of the 43 drills to the ones it needs.

## 1. Telemetry sampler

A fixed-rate recorder that turns each attempt into one run record. Rules check
that record afterwards, so evaluators stay pure Lua with unit tests.

| Data | Used for |
| --- | --- |
| Position, heading, velocity, yaw rate, up vector | gates, spins, slip angle, rollovers |
| Steering, throttle, brake, handbrake, clutch | trail braking, countersteer, no braking in zone, handbrake count |
| Gear, RPM, engine running | stalls, over-revs, missed shifts (A02, A03, E08) |
| Per-wheel speed, ground contact, surface type | lockup, wheelspin, airborne, off-road |
| Damage total, tyre and part state | collisions, punctures (E06, E07, F06) |

Position and velocity come from the game-engine side. Driver inputs and wheel
data live in the vehicle's own Lua VM and must be pulled across. Choose that
mechanism and record it in BEAMNG_API_NOTES before building on it.
[OfficialLambdax/BeamNG-Telemetry](PRIOR_ART.md#telemetry) reads almost all of
these fields and is the best reference.

## 2. Course geometry

| Primitive | What it checks | Drills |
| --- | --- | --- |
| Gate | A line with width and direction, crossed by the car (built: the car's centre; footprint later) | A04, A07, A08, C02, D01, D03 |
| Zone or box | Whole car inside a box (built for A01: the car's measured footprint, `park_in_box`); B01's zone checks the car's centre | A01 parking box, B01 5 m stop zone |
| Corridor or road edge | All wheels on the road or inside a lane, from an authored path or the surface under each wheel | about 20 drills |
| Distance along path | Where the car is relative to apex or exit markers | B04, B07, C05 |
| Line offset | Front bumper distance to a line | A05 (0–2 m), B03 |
| Marker | A point where speed is sampled | A04 (three markers), D01 |

All of these need in-game placement, saved per level (ROADMAP P1). BeamNG's
race path and checkpoint system may cover gates and timing
([PRIOR_ART](PRIOR_ART.md#built-into-beamng)).

## 3. Event detectors

Detectors turn raw samples into events with a start time, an end time and a size.

| Detector | How | Drills |
| --- | --- | --- |
| Wheel lockup | Wheel speed near zero while the car moves, with duration | A03, A05, B01, B02, B04, D06 |
| Wheelspin | Wheel speed well above ground speed for more than 1 s | A02, D04, E03 |
| Stall, over-rev, missed shift | RPM, engine state, time in neutral or wrong gear | A02, A03, C04, E08 |
| Reversing | Distance travelled against the way the car points (built: `no_reverse`) | A01, F03 |
| Handbrake count | Handbrake presses per run | C01, C02, C04 (exactly one), C08, E02 |
| Slip angle | Angle between heading and direction of travel | C01, C02, C03, C06 |
| Spin | Heading turns past a threshold against travel | most C, D and E drills |
| Countersteer | Steering opposite the rotation, and time to unwind | B07, C03 (under 3 s), C05 |
| Understeer | Yaw rate well below what steering and speed predict; needs a simple car model, tuned per car | B06, E02, E04 |
| Airborne, landing, rollover | Wheel contact, landing impact, car tipping over | E05, E06, E07 |
| Cone contact | Real cones and posts stand at authored courses' markers (ADR 0011): the car's collisions say which it touched (built: `markers_clear`); without them, the footprint coming within a drawn marker's radius | about 15 drills |
| Barrier contact, damage | Jump in damage total | D03, F01, F05 |
| Puncture | Tyre deflation; F06 needs a damage baseline because it starts punctured | E07, F06 |
| Recovery use | The game's own recover/reset was used | E08, F01, F04, F05, F08 |

Understeer is the hardest detector in general. Where the drill lays out the line (B06's course
circle) it doesn't need a car model: how far the car runs outside the line is the push (`ran_wide`).
Cone contact matters most because so many drills use it.

## 4. Measurements, run lifecycle and block statistics

**Derived measurements**

- Speed at a marker (A04 needs 27–33 km/h at three markers)
- Exit speed at a gate (D01 needs at least 25 km/h)
- Stop position relative to a line (A05, B03)
- Segment and stage times (D02, F02, F03)
- Input trends: throttle rising after the apex (D04), brake fully off by the
  apex (B04), no braking inside zones (A04)

**Run lifecycle**

- Start on crossing the start gate; end on the finish gate, on stopping, on
  timeout or on abort.
- Void a run if the player teleports, pauses, opens a menu or switches vehicle.
- Retry must repair damage (ROADMAP P0), or damage rules see the previous attempt.

**Block statistics**

- Pass counts such as 8/10 (exists today)
- Best and median times
- Within +7% or +8% of the fastest clean run in the block (D02, F02, F08)
- Target time ±2 s (F03)
- Personal reference times kept between sessions (F08)
- Results grouped by surface (B03, E01) and by vehicle option ([VEHICLES](VEHICLES.md#data-implications))
- A/B comparison of two setups (F07)

## 5. Rule engine

Each drill's `assessment.rules` becomes a list of typed rules with parameters
and time conditions, such as "no lock after entering the zone" or
"countersteer unwound before the exit marker". Each rule returns a readable
reason, such as "lockup 1.4 s at 38 m", because that reason is the coaching.
Rules are tested offline against recorded run fixtures.

**Built** (`lua/ge/extensions/rallyAcademy/rules.lua`, pure Lua). `evaluate(rules,
record, ctx)` looks only at samples from the run's start mark and returns
`{passed, checks = {{type, ok, text}}}`. Rule types so far:

| Type | Parameters | Passes when |
| --- | --- | --- |
| `entry_speed` | `minKmh` | The run's peak speed reaches `minKmh`. This uses the peak rather than the speed at first brake, because the brake reads 0.3 at rest after a reset. |
| `stop_zone` | `lengthM`, `widthM` | The car comes to rest inside a box centred on the marked zone, aligned with the car's heading when the zone was marked |
| `no_sustained_lockup` | `maxSeconds` (optional `ratio` 0.3, `minKmh` 7) | No wheel turns slower than `ratio` × the car's speed while braking for longer than `maxSeconds` |
| `gates_passed` | none | Every marked gate driven through, in order, inside its width |
| `speed_at_gates` | `minKmh`, `maxKmh` (optional `gate`: one gate, `-1` = last) | Speed when crossing each gate is inside the band |
| `no_brake_between_gates` | none (optional `fromGate`, `toGate`) | No brake above 0.1 between the two gates while moving faster than 2 m/s |
| `stop_before_line` | `minM`, `maxM` (optional `widthM` 8) | The car rests with its front bumper `minM`–`maxM` before the line. With an authored course line (`assessment.course.line`) the distance is measured from the car's own front bumper (its measured footprint); with a marked line, from where the car's centre was when the bumper was parked on it |
| `lockup_recovered` | `maxSeconds` (optional `minSeconds` 0.2) | The longest lock is at least `minSeconds` (you did provoke one) and at most `maxSeconds` (you released it) |
| `no_sustained_wheelspin` | `maxSeconds` (optional `ratio` 1.25, `slackKmh` 5, `fromGate`/`toGate`: only between them) | No wheel turns faster than `ratio` × the car's speed + `slackKmh` on throttle for longer than `maxSeconds` |
| `no_stall` | none | The engine never stops after running during the run (`eng` flag; RPM reads ~160 while re-idling after a reset) |
| `gear_reached` | `gear` | The highest gear used reaches `gear` |
| `clean_shifts` | none (optional `maxNeutralSeconds` 1, `minKmh` 10) | No shift hangs in neutral longer than `maxNeutralSeconds` while moving |
| `no_damage` | none (optional `maxDamage` 50) | Car damage (`beamstate.damage`) rises by no more than `maxDamage`: no hard contact. Damage within 0.3 s of a tyre going flat is the puncture's (~1000), not contact. Cones barely dent a car, so cone contact still needs scene control |
| `no_spin` | none (optional `maxSlipDeg` 70, `maxSeconds` 0.3, `minKmh` 10) | The car never slides more than `maxSlipDeg` off its direction of travel for longer than `maxSeconds`. Reverse gear is skipped. Defaults come from a recorded handbrake spin; drills that slide on purpose set their own |
| `on_surface` | `surfaces` (names, optional `maxWheelsOff` 2, `maxSeconds` 0.5) | No more than `maxWheelsOff` wheels touch a surface outside `surfaces` for longer than `maxSeconds`. Wheels in the air don't count. Surface names: `R.SURFACES` (ASPHALT, GRAVEL, DIRT, GRASS…) |
| `no_rollover` | none (optional `minUpZ` 0.35) | The car never tips past about 70° |
| `no_handbrake` | none (optional `minKmh` 10) | Handbrake not pulled while moving |
| `no_puncture` | none | No tyre goes flat during the run |
| `cones_passed` | none | Every course cone is passed on its `keep` side (the car crosses the line through the cone, square to the course, with the cone on that side) |
| `markers_clear` | none (optional `clearanceM` 0) | The car never touches a course's cones or gate posts. With the real props standing (ADR 0011), what the car's collisions touched decides; otherwise (no props, an old recording) its body coming within 0.15 m (+ `clearanceM`) of a marker, the body being the footprint measured from the car's nodes when the run starts |
| `park_in_box` | none (optional `insetM` 0, `label`) | At rest with all four corners of the body inside the course's box, shrunk by `insetM` on every side |
| `no_reverse` | none (optional `maxM` 0.3) | The car travels no more than `maxM` backwards (against the way it points) |
| `max_time` | `maxSeconds` | The run time is at most `maxSeconds` (medal time targets) |
| `trail_braked` | none (optional `fromGate` 1, `toGate` 2, `minSeconds` 0.4, `minBrake` 0.1, `minSteerDeg` 20) | Between the two gates (the braking marker and the apex) the car brakes over `minBrake` while the steering wheel is turned past `minSteerDeg` for at least `minSeconds` in total |
| `brake_off_by_gate` | none (optional `gate` 2, `maxBrake` 0.05) | The brake is at most `maxBrake` from crossing the gate (the apex) to the end of the run while moving; says how long before the gate it came off |
| `steady_exit` | none (optional `fromGate` −2, `toGate` −1, `maxCorrections` 1, `minSwingDeg` 10, `after`: where the window starts, in the text) | Between the two gates the steering doesn't swing back and forth: unwinding once is fine, each reversal of more than `minSwingDeg` degrees of steering wheel is a correction (`steer` is the wheel angle in degrees) |
| `circle_laps` | none (optional `laps`, default the circle's) | The car goes round the course circle (`assessment.course.circle`) that many times the way it is meant to be driven; going round the wrong way says so |
| `circle_corridor` | `widthM` (optional `maxSeconds` 0.3) | The car's position stays within `widthM` / 2 of the circle's line, allowing up to `maxSeconds` outside at a time; says the furthest it ran off |
| `throttle_held` | none (optional `maxGapSeconds` 0.3, `minThrottle` 0.05, `fromKmh` 0) | From the first moment on the throttle at `fromKmh` (pulling away and changing up before then is free) to the end, the throttle never drops under `minThrottle` for longer than `maxGapSeconds` |
| `rear_slide` | none (optional `minSlipDeg` 8, `turn` 'left', `fromGate` 1, `toGate` −1, `hint`: the coaching on a miss) | Between the two gates the rear steps out at least `minSlipDeg`: the slip angle with the car pointing further into the `turn` than it travels (`R.signedSlipDeg`). The front pushing wide doesn't count |
| `settled_by_gate` | none (optional `gate` −1, `maxSlipDeg` 4, `maxSteerDeg` 45) | Where the car crosses the gate, the slide is over (slip within `maxSlipDeg`) and the countersteer unwound (steering wheel within `maxSteerDeg` of straight); the gate's `label` names it in the text |
| `handbrake_pulls` | none (optional `count` 1, `minKmh` 5) | The handbrake goes on (over 0.5) exactly `count` times while moving |
| `flick` | none (optional `fromGate` 1, `toGate` 2, `turn` 'left', `awayDeg` 30, `intoDeg` 60, `maxSeconds` 1.5) | Between the two gates the steering wheel goes at least `awayDeg` away from the turn, then at least `intoDeg` into it within `maxSeconds` (a Scandinavian flick) |
| `throttle_on_between` | none (optional `fromGate` 2, `toGate` 3, `minThrottle` 0.5, `minSeconds` 0.5) | Between the two gates (the apex and the exit) the throttle is at `minThrottle` or more for at least `minSeconds` in total |
| `airtime` | none (optional `minSeconds` 0, `maxSeconds`, `minForce` 50) | The longest stretch with all four wheels off the ground (each wheel's downforce under `minForce` N) is between `minSeconds` and `maxSeconds` |
| `ran_wide` | none (optional `minM` 1, `maxM` 5, `fromGate` 1, `toGate` −1) | Between the two gates the car runs outside the course circle's line by `minM` to `maxM`: a mild push, not a trip off the circle |
| `back_on_line_by_gate` | none (optional `gate` −1, `maxM` 1.5) | Where the car crosses the gate it is within `maxM` of the course circle's line |
| `left_foot_brakes` | none (optional `minCount` 3, `minSeconds` 0.2, `minBrake` 0.05, `minThrottle` 0.05) | At least `minCount` brake applications made with the throttle still on, each held `minSeconds` or longer; braking with the throttle off says "you lifted to brake" |
| `progressive_downshifts` | `toGear` (optional `minHoldSeconds` 0.3: a gear counts once held that long, so a blip while shifting up isn't a downshift) | After the highest gear reached, the car goes down one gear at a time to `toGear` (3→2, not 4→2); neutral and reverse are skipped, going lower at the stop is fine |
| `no_over_rev` | `maxRpm` | The engine never spins past `maxRpm` (the Covet Student Driver's limiter is 6500 rpm); names the gear and speed where it did |
| `time_to_speed` | `kmh`, `maxSeconds` | The car reaches `kmh` within `maxSeconds` of moving off (the run's start mark, about 1 m/s, so the clutch bite before it isn't counted): A02's 0–40 km/h time |

**Gates** (`gates.lua`, pure) are lines across the road: a centre, the direction the
car faced when the gate was marked, and a width. A gate counts when the car's centre
crosses the line going forwards. Crossing it more than `max(15 m, 2 × width)` from the
centre doesn't count, because the car is elsewhere on the course. The crossing point
and speed are interpolated between samples. A drill declares its gates as
`assessment.gates = {count, widthM}`. The driver marks each gate with **+ Gate**, and
the gates are saved per map like a start. `endWhen: "gates"` ends the run 0.3 s after
the last gate, so the record includes the car's sample past it. The run is timed at the
gate itself.

The course is drawn in the world with the game's debug overlay (`debugDrawer`): gate
posts, yellow for the next gate, green once passed, red if missed. The stop zone and
the finish circle are drawn too.

A drill with `endWhen: "stopped"` ends when the car has been at rest (below
0.3 m/s) for 0.5 s at least 5 m from the start. A drill without it ends at the finish circle. Real
recorded runs in `tests/fixtures/` (B01 clean, overshoot and lockup) pin the
rules to real physics (`tests/lua/test_fixtures.lua`). B01's cone contact is
not graded yet: it needs scene control (section 7).

### Medal tiers

A drill with `assessment.tiers` awards a medal for each pass: **bronze** for passing the
drill's rules, **silver** and **gold** when the tier's rules pass too. A tier rule replaces
the drill rule of the same type (A01: a parking box 0.3 m or 0.5 m smaller all round) or adds
to them (a time target). `rules.grade` returns `tier` and `nextTier` (the first check the next
medal failed, shown in the HUD as "gold: Rear-right corner 0.07 m over the right edge of the gold
box"). Progress keeps the best medal and a count of each ([DRILL_DATA](DRILL_DATA.md#medal-tiers)).

A01 runs on the proving ground's dirt strip (venue `pg-dirt-strip`; first set on the BMP dirt arena). A01 targets (Covet Student Driver, 3.90 × 1.81 m): box 6.0 × 3.2 m, silver 5.4 × 2.6 m and
14 s, gold 5.0 × 2.2 m and 10 s. A scripted run at 14 km/h takes about 9.7 s; gold leaves
about 0.2 m each side, so a slightly crooked stop misses it.

A02 targets (Covet Student Driver, the proving ground's dirt strip; first set on the BMP start line's tarmac): bronze
is a clean pass (0–40 km/h within 8 s, shift under 1 s, wheelspin under 1 s, through the 40 km/h gate; the run ends
there); silver 0–40 in 4.5 s, shift under 0.6 s, wheelspin under 0.5 s; gold 3.5 s, 0.4 s, 0.25 s. On loose ground a
flat-out start spins the wheels (2.4 s on dirt) and the arcade box then holds 1st to the gate: the technique is to
feed the throttle in. Scripted from 25 % throttle at rest to full at 45 km/h: 0–40 in 3.2 s with no sustained
wheelspin on dirt, gravel and asphalt (gold, silver, gold). **Snow** (variant A02-snow) has its own times: 10 s,
silver 7 s, gold 5.5 s; fed in from 15 % to full at 80 km/h it took 6.2–6.3 s (bronze: a 0.7 s shift). The targets
leave room for a real clutch and manual shift; check them on the rig.

A03 targets (Covet Student Driver, the proving ground's dirt strip, venue `pg-dirt-strip`: dead level, all dirt; earlier on the BMP run-up, whose braking crossed the start line's tarmac, then the dirt arena's long straight): bronze is through the 60 km/h gate at 55–75 km/h in
3rd or higher, down one gear at a time to 2nd, under 6700 rpm, shifts under 1 s, no lock over
0.5 s, stopped in the 12 × 6 m box; silver: under 6300 rpm, shifts under 0.6 s, locks under 0.3 s,
a box 1 m smaller all round; gold: under 6000 rpm, 0.4 s, 0.15 s, 1.5 m smaller. The Covet tops out
2nd at about 60 km/h (6200 rpm), so reaching the gate in 3rd means shifting up around 45 km/h:
gear choice is part of the drill. Scripted with the sequential gearbox and scripted gears (the
arcade box holds 2nd to 61 km/h): gold.

A05 targets (the proving ground's dirt strip, stop line 60 m from the venue start, from 38+ km/h): bronze 0–2 m before
the line with no lock over 0.2 s; silver 0–1 m, 0.15 s; gold 0–0.5 m, 0.1 s. The line is drawn with a
cone at each end and thin gold, silver and bronze lines before it; near it the HUD reads "1.4 m to
the line". Scripted runs (0.40.0, dirt strip): 0.15 m (gold), 1.14 m (bronze), 0.58 m past (miss).

A07 and A08 targets (the proving ground's flat copy of the BMP left, venue `pg-corner-left`: 124°, radius
32 m, Covet Gravel Rally; the 3 m gates leave about 0.55 m each side of the car): A07 bronze 35 km/h at the
exit gate, one wheel off the gravel allowed, silver 46 km/h and all four wheels on, gold 55 km/h; A08 bronze
25 km/h at the exit, at most one correction to the finish, silver 38 km/h and no corrections, gold 45 km/h.
On the flat (0.40.0) the scripted racing line holds A07's exit gate up to a steady 60 km/h and runs wide at
63; on the stock downhill it clipped the posts above about 55, so A07's speeds rose from 30 / 40 / 48. A08's
apex gate is what limits it: the late line passes it at 41-48 km/h, and the road keeps turning past the exit
gate, so a car still adding lock there needs a correction before the finish (41 km/h: silver; 44: bronze).

B01 and B02 targets (the proving ground's dirt strip, venue `pg-dirt-strip`, Covet Student Driver; earlier on the
BMP run-up, whose braking crossed the start line's tarmac, then the dirt arena's long straight, which sloped up to
9.5 %): B01 from 65+ km/h stops with the car's centre in a 5 × 6 m zone 150 m from the start, all on dirt, no lock
over 0.5 s; silver 3 × 4 m and 0.3 s; gold 1.5 × 3 m and 0.2 s (the zones are drawn nested). B02 from 55+ km/h locks
the wheels at least 0.2 s and releases within 1 s, then stops in a 40 m stop area on the flat; silver releases
within 0.7 s, gold 0.5 s. Scripted on the dirt strip (0.40.0): B01 braking at 4.6–5.0 m/s² from 72 km/h stopped
0.3–1.3 m past the centre (silver, sometimes gold); B02 locked 0.5 s (gold).

B04 targets (the proving ground's flat corner, Covet Gravel Rally): brake from the marker 50 m into the
approach and keep braking while turning in for 0.4 s, fully off by the 4 m apex gate, no lock over 0.3 s;
bronze 30 km/h at the exit, silver 42 km/h with all four wheels on the gravel, gold 50 km/h (raised from 25 /
35 / 42 on the stock downhill). Scripted from 65 km/h: brake 0.2 easing to zero before the apex, 52 km/h out
(gold). On the flat a light brake with the throttle closed stops the car within the corner (the arcade box drops
to 1st and the engine brakes hard), so trail braking here is gentle; on the downhill gravity made up for it.

B05 targets (the proving ground's dirt ring, venue `pg-dirt-ring`; first set on the BMP dirt circle; Covet Gravel Rally): two anticlockwise laps of a 15 m ring, its centre on
the circle's centre; bronze inside a 6 m corridor (0.5 s outside allowed), throttle never off for more
than 0.5 s once at 25 km/h, two brake dabs on the throttle; silver a 4 m corridor, three dabs, 0.3 s
throttle gaps; gold a 3 m corridor, four dabs and both laps in 22 s. Scripted in 2nd with 0.25 brake dabs
every 25 m: 32 km/h held the line within 0.8 m in 21.6 s (gold); 34 km/h ran 1.6 m off (silver); 38 km/h
ran 4 m wide. The 15 m ring tops out at about 35 km/h on this dirt.

B06 targets (the proving ground's dirt arc, venue `pg-dirt-arc`; first set on the BMP dirt circle; Covet Gravel Rally): 22 m to a Turn in gate, then a left half of a 15 m ring
with Apex (90°), Regain (135°) and Exit (180°) gates 12 m wide. Bronze: the front pushes 1–5 m wide of the
line before the Regain gate and the car is back within 1.5 m of it at the Exit, no spin; silver: back within
1.5 m by the Regain gate; gold: a 2–4 m push, back within 1 m by the Regain gate. Scripted, holding the
entry speed into the ring: 30 km/h doesn't push (0.3 m); 40–42 km/h pushes 3–5 m; lifting for 10–12 m from
35 m (just after turn-in) brings it back by the Regain gate (gold at 40, silver at 42), lifting at 45 m only
by the Exit (bronze); 46 km/h with no lift runs 12 m wide.

D01 targets (the proving ground's dirt strip, venue `pg-dirt-strip`; first set on the BMP dirt arena; Covet Gravel Rally): six cones 15 m apart from 25 m ahead (the drill first said
12 m; 15 m suits the Covet on dirt), first kept on the right, then alternating, and a Finish gate at 115 m.
Bronze: every cone passed on its side, none touched, no spin, 25 km/h at the Finish, in 18 s; silver 14.8 s;
gold 13.8 s. Scripted: a ±3 m weave clears the cones at 30 km/h (14.6 s) and hits one from 34 km/h; ±2.4 m
holds 32 km/h (13.6 s).

D08 runs on the proving ground's surface-change straight (venue `pg-transition`, since 2026-10-20): the same gravel, tarmac, gravel sequence and gates, dead level; scripted braking at 4 m/s² from 62 km/h stopped in the zone (gold), and a full brake from the tarmac stopped short of the Gravel gate (miss). D08 targets (BMP run-up, Covet Gravel Rally): the start line's tarmac patch runs from 8 m before the line to 22 m
past it (surveyed with the car's wheels, 0.39.4); a Tarmac gate at the line, a Gravel gate 2.5 m left 24 m on,
and a stop zone 40 m past the line (still on the flat). Bronze: from 55 km/h, both gates, the car's centre
in a 6 x 5 m zone, no lock over 0.5 s, no spin; silver 4 x 3.5 m and 0.3 s; gold 2 x 2.5 m and 0.2 s.
Scripted from 62 km/h: braking at 4 m/s2 stops 0.5 m past the centre (gold), 5.5 m/s2 1.7 m (silver), 5.8
m/s2 2.7 m (bronze), 6 m/s2 just past the zone; a full brake from the tarmac locks the wheels for 1.7 s.

E02 targets: C02's corner, on the proving ground's flat copy. Bronze: the rear steps out 4°+ between the Turn
in and Apex gates, then half throttle or more for 0.5 s between the Apex and Exit (`throttle_on_between`), no
post touched, no handbrake, no spin, 30 km/h out; silver 8° and 55 km/h; gold 10° and 60 km/h. Scripted runs
with a brake pulse and 0.6 throttle from just before the apex came out at 68-69 km/h with 13° of rotation
(gold); 0.45 throttle never reached the half-throttle mark; holding 46 km/h instead never passed 16%.

Gravel lane drills (DR825, west of the town; MAPS W6; Covet Gravel Rally), since 2026-10-20 on the proving ground's flat copy of the lane (MAPS P4, 7 m of gravel): without the crest and the climb both corners carry more speed, so their silver and gold speeds rose (D03 30 / 36 km/h, D04 48 / 54 km/h); scripted on the copy D03 easing from 45 km/h left the Exit at 38 km/h (gold) and 55 km/h ran wide of the Apex; D04's throttle from 36 m left at 56 km/h (gold). The notes below are from the stock lane.
- D03: eastbound, a right-hander whose radius tightens from about 60 m to 18 m over a small crest. Bronze:
  Entry, Apex and Exit gates, no post touched, at most one wheel off the gravel for 0.5 s, no contact, no
  spin, 20 km/h out; silver 28 km/h; gold 34 km/h. Scripted: 38–46 km/h in, easing to 24–36 km/h by 45–50 m,
  came out at 27–38 km/h; 50 km/h in ran wide where it tightens.
- D04: northbound, a 19 m left-hander opening to a straight. Bronze: the gates, a third of the throttle for
  1 s after the apex, no front wheel spinning over 0.5 s after the apex (the launch doesn't count), at most one
  wheel off, no contact, no spin, 25 km/h out; silver 45 km/h; gold 52 km/h. Scripted throttle ramps from 0.25
  up to 0.34–0.45 gave 51–55 km/h out; up to 0.6 spun the front 0.9 s and ran wide. A bronze is hard to script
  (any throttle that counts carries the car past 45 km/h).

The Off-Road Circuit drills (D05, D06, E05) run on the proving ground's hill circuit since 2026-10-20: the circuit's first 640 m copied with its measured elevation and banking, concrete barriers where its walls stand. Scripted there: D05 at 37 km/h gold (55 km/h hits the wall at the crest), D06 at 45 / 40 km/h silver, E05 gold taking the banked left at 45 km/h and the kicker at 56 (on the stock circuit 55 km/h through the left was fine: its wall is continuous). Targets unchanged.

Off-Road Circuit drills (West Coast USA W5, Covet Gravel Rally). The circuit is a walled, ~10 m wide dusty-dirt
loop (road nodes `dirttrack_1`–`32`, about 1045 m); its jumps are small for the Covet (the biggest, the kicker
at `dirttrack_15b`, gives 0.3 s of air at 62 km/h), so E06 isn't built here.
- D05: a left hairpin turning 180° across a crest. Bronze: 30–45 km/h at the Turn in gate, the Crest and Exit
  gates, no post or wall touched, no spin; silver 33–42 km/h; gold 35–40 km/h. Scripted runs at 37–43 km/h
  made the corner; 55 km/h is graded too fast.
- D06: from the circuit's start, an uphill right-hander (9–14 %), the crest, a 7 % descent and a downhill
  left-hander. Bronze: all gates, nothing touched, no lock over 0.5 s, no spin, in 32 s; silver 26.5 s; gold
  24.5 s. Scripted: 38 km/h 29.6 s, 45 km/h 26.0 s, 50 km/h 24.2 s; 55 km/h hits the uphill corner's wall.
- E05: out of a left-hander, 45 m to the kicker. Bronze: 40 km/h at the Crest gate, all four wheels off the
  ground no more than 0.15 s, at most one steering correction after it, the Landing and Exit gates, no spin,
  no more than 150 damage (from about 52 km/h the car lands nose-first and scrapes its bumper: 27–84);
  silver 50 km/h; gold 54 km/h. Scripted: 46, 50 and 56 km/h stayed down; 57 km/h bottomed out once (1085);
  66 km/h flew 0.3 s and landed hard (1508).

C01 targets: C02's corner, on the proving ground's flat copy (a 32 m radius, under the 40 m the drill first
asked for; its `venueNeeds` allow 30 m). Bronze: the rear steps out 4°+ between the Turn in and Apex gates with
no brake between them, no post touched, no handbrake, no spin, 25 km/h out; silver 6° and 40 km/h; gold 8° and
45 km/h. On the flat a lift rotates the Covet much less than on the stock downhill (where the slope unloaded
the rear and the targets were 6 / 10 / 14°): scripted lifts at turn-in from 61 km/h gave 4.4-4.8°, from 54 km/h
0.6-0.8°; from 65 km/h the car can't make the apex gate. No scripted run reached silver.

C02 targets (the proving ground's flat corner, Covet Gravel Rally): a Turn in gate where the straight ends,
a 10 m Apex gate (the gravel's width) and a 6 m Exit gate at the track-out. Bronze: the rear steps out 8°+
between the Turn in and Apex gates (`rear_slide`) with the brake on while steering for 0.2 s (`trail_braked`, so
the rotation comes from the pulse), no post touched, no handbrake, no spin, 25 km/h at the Exit; silver 12° and
40 km/h; gold 15° and 45 km/h. Scripted (0.40.0) from 65 km/h with a full-brake pulse of 7-8 m just after the
Turn in gate: 12-17° (silver, gold); from 55 km/h a 5 m pulse gave 8-9° and a 4 m pulse 6-7°. The follower needs
the line ~2 m further inside after a rotation.

C04 targets (the proving ground's dirt strip; first set on the BMP dirt arena; Covet Gravel Rally): 34 m to an Entry gate, a Pivot cone to turn left round
(4.5 m from the line) and an Exit gate back the way you came, 9 m to the left. Bronze: one handbrake pull, the
rear swinging 20°+ between the gates, cone kept on the left, no post or cone touched, no stall, no spin
(slides up to 120° allowed for 0.5 s), 15 km/h out of the Exit; silver 25° and 25 km/h; gold 25° and 32 km/h.
Scripted: a pull at full lock makes the front plough (rear locked, slip −3 to −5°); turning in with a third
of the lock and pulling from ~45 km/h swings the rear 24–31°; from 38 km/h only 17°.

C07 targets (the proving ground's dirt strip; first set on the BMP dirt arena; Covet Gravel Rally): two cones 20 m apart side by side, 35 m ahead; five gates
pin the route (the crossing, the far side of the right lobe, the crossing, the far side of the left lobe,
the crossing). Bronze: all five in order, no cone or post touched, no spin, in 30 s; silver 23 s; gold
21.5 s. Scripted on 10 m circles round the cones: 20 km/h 25.0 s, 25 km/h 21.8 s, 28 km/h 21.3 s; 30–32 km/h
runs wide of the right lobe gate.

C08 targets: C02's corner with a Flick gate 40 m into the approach. Bronze: between the Flick and Apex gates,
60° of steering away from the corner then 60° into it within 1.5 s (`flick`), and the rear steps out 8°+;
otherwise as C02 (silver 12° and 40 km/h, gold 15° and 45 km/h). On the flat corner a scripted lift-and-flick
from 66 km/h (half lock away, then full lock in with full brake) gave 12.7-14.4° (silver); at 56 km/h 4.2°,
and a gentler flick with 0.8 brake 3-7°. The flick swings the car out, so the approach line sits nearer the
middle than C02's.

B07 targets (the proving ground's dirt arc; first set on the BMP dirt circle; Covet Gravel Rally): 22 m to a Turn in gate, a left quarter of a 15 m ring,
then a 7 m exit lane 18 m long. Bronze: the rear steps out 8°+ between the Turn in gate and the lane end,
through both lane gates without spinning, at most three steering corrections in the lane, and at the
lane end the slip is within 4° and the steering within 45° of straight. Silver: a 12° slide; gold: 15°
with at most two corrections. The Covet Gravel Rally resists oversteer: a 0.5 brake dab at turn-in gave
no slide (the slip with the rear out stays under 1°, and limit cornering reads about 5–7°); a full brake
for 4–6 m at the gate from 55–65 km/h gave 11.5–14.8° with the pure pursuit countersteering (bronze to
silver), and a sharp 2 m stab with more lock gave 21.6° but was still sliding at the lane end. No scripted
run reached gold; a driver flicking the car in should.

A04 targets (the proving ground's dirt strip; first set on the BMP run-up; three gates 25 m apart): bronze 27–33 km/h at every gate with no braking
between them; silver 28–32; gold 29–31. Gate speeds are shown to a tenth, since the medal bands are
only 2 km/h wide. A scripted throttle-only hold at 30.5 km/h read 29.3 / 30.0 / 29.1 on the BMP run-up (gold); a
30 km/h hold read 29.0 / 29.0 / 27.9–28.7 on the proving ground's four strips (silver, sometimes bronze).

Surface variants of module A ([ADR 0009](decisions/0009-surface-variants.md)): A01–A05 run on dirt (the base),
gravel, asphalt and snow strips of the proving ground, each with its own progress and medals. Scripted with each
drill's medal technique (the `surfaces` scenario, 0.40.0) all 20 pass: A01 and A05 gold everywhere (14 km/h
parking and a 3.5 m/s² stop from 44 km/h are within every surface's grip), A04 silver everywhere, A03 gold except
snow (bronze: the wheels spin the revs past silver's 6300 rpm in 1st, so shift up early), A02 as above. Only
A02-snow has its own targets so far.

B01 and C04 have the same variants, with the base targets on every surface: the driving adapts, not the medal.
B01 braking at 3.5 m/s² earns gold on dirt, gravel and asphalt; at 6 m/s² dirt and gravel lock the wheels (1.2-1.3 s)
while asphalt doesn't; on snow even 3.5 locks as the car slows, and 3.0 m/s² (braking earlier) earns gold. C04's
handbrake hairpin: dirt and gravel alike (23-31° of swing); on asphalt the grippy front cuts into the pivot cone
at the usual lock, so turn in with less (0.2 instead of 0.3: gold); on snow the rear swings 45-54°, and a slower
entry (40 km/h, out at 25-28) earns silver every time, gold needing a faster exit (33 km/h once).

D02 linked corners is automatic since 2026-10-21, on the test road's linked S (a left, a long right, a closing left):
gates and real posts at the first two apexes and an Exit gate 30 m after the S, on the gravel, no spin, no damage, and
exit speed (60 km/h; silver 67, gold 72). Scripted (arcade, centre line): a cautious 45 throughout exits at 65 (bronze);
55 into the first bend and 50 through the rest at 69 (silver); the same with the power on 14 m before the S ends at
74 (gold); 60 into the first bend runs out of room and touches the second apex's post (miss). Fixtures `d02_gold_pg`,
`d02_miss_overcommit_pg`.

D07 road camber is automatic since 2026-10-21, on the camber road's four identical 35 m corners: a gate at each apex
and the finish, real posts, on the gravel, no spin, no damage, and a minimum speed through both banked apexes (50 km/h;
silver 54, gold 57), so the drill rewards trusting the banking. The off-camber corners need no rule: their own
physics is the limit. Scripted (arcade, centre line): the banked corners held 59 km/h at the apex and ran off at about
62; the off-camber ones held 45 and ran off at 47-51. 57 km/h with 45 into the off-camber corners: gold; a cautious 45
everywhere: miss (46 km/h at the banked apex); 64: off in the off-camber right, touching its post. Fixtures
`d07_gold_pg`, `d07_miss_slow_pg`, `d07_miss_off_pg`.

D09 uphill hairpins (added 2026-10-20) climbs the proving ground's mountain face: seven gates (each hairpin's apex
and 15 m after it, then the Top) with real posts, on the road, no spin, no reversing, no damage, 75 s. Medals are
time to the Top and differ per surface, as the physics does: scripted (arcade, centre line) the best clean climbs
were 38.1 s on gravel (55 km/h legs, 28 round the hairpins), 33.9 s on asphalt (65 / 32) and 46.9 s on snow (50 / 24,
and 28 not 35 in the gentler bottom and top bends, where snow ran wide); a steady 22 km/h takes 64 s anywhere. So
silver / gold: gravel 41.5 / 38.5 s, asphalt 37.5 / 34.5 s, snow 50 / 47.5 s. The asphalt pace on gravel runs off the
road. Fixture `d09_gold_pg` (37.7 s).

The corner drills (A07, A08, B04, B08, C01, C02, C08, E02, like E01) have asphalt and snow variants on the gravel
corner's twins (same shape, gates and barriers; 2026-10-20). Scripted (the `corner_surfaces` scenario, 0.40.0), the
targets hold everywhere except one: A07 and A08 earn the same medals at the same speeds on all three surfaces (snow's
grip, 0.64, is close to gravel's 0.68). B04 on snow runs wide or stalls under the gravel technique; 60 km/h, a little
throttle under the brake and a gentle exit earn gold. C02 and C08 on asphalt need a harder rotation (72 km/h, a longer
pulse or a bigger flick: bronze to silver), C01 and C02 on snow a slower entry (54 km/h lift: gold; 58 km/h pulse: silver).
**C01 on asphalt has its own slide targets** (3° / 4° / 5° for bronze, silver, gold; gravel 4° / 6° / 8°): on tarmac
a lift at turn-in rotated the FWD Covet 3-4° in most scripted runs that made the gates (one full run reached 7°,
gold), and a faster entry for more rotation ran it wide of the apex gate. All 21 corner variants passed in one full
run (A07 silver on all three; B04 gold on all three; the rotation drills bronze to gold).

## 6. Hybrid grading

Some criteria test what the driver knows, not what the car did. These drills
need HUD prompts and the `hybrid` mode:

| Drill | What needs a human answer | Prompt |
| --- | --- | --- |
| A06 | Name the next bend before the first apex | Pick from options |
| B03 | Predict the stopping point | Place a marker before the run |
| B08, D07 | Which input or side changed the grip | Pick from options |
| E01 | Safe speed and braking observations per surface | Short form |
| F07 | One handling difference between setups | Free text |

## 7. Scene control

Authored courses (A01) draw their cones and gate posts with `debugDrawer` and measure
contact against the car's footprint, so they need no props. Real props remain the goal for
drills that want physical cones: spawn and reset cones and props on retry, enforce the vehicle config and
drivetrain ([VEHICLES](VEHICLES.md)), switch setups (F07) and inject a puncture (F06).

## Drill coverage

36 of 42 drills can be fully automatic once these capabilities exist; 6 need a
hybrid prompt. (Stage drills F01–F05 and F08 were cut: [ADR 0006](decisions/0006-stages-are-the-games-rally-mode.md).)

| Drill | Title | Capabilities needed | Mode |
| --- | --- | --- | --- |
| A01 | Steering and spatial awareness | Zone, cone contact, reversing | Automatic |
| A02 | Clutch engagement and launches | Stall, missed shift, wheelspin | Automatic |
| A03 | Gear selection and downshifting | Over-rev, lockup, stall, missed shift, line offset | Automatic |
| A04 | Throttle modulation | Speed at 3 markers, no braking in zones | Automatic |
| A05 | Braking accuracy | Line offset (0–2 m), contact, lockup | Automatic |
| A06 | Vision and looking ahead | Corridor, pick-next-bend prompt | Hybrid |
| A07 | Basic racing lines | Corridor, exit gate, exit speed | Automatic |
| A08 | Apex and exit selection | Gates, cone contact, steering steadiness after exit | Automatic |
| B01 | Threshold braking | Zone, lockup, cone contact | Automatic |
| B02 | Wheel lockup recognition | Lockup duration (~1 s), corridor | Automatic |
| B03 | Stopping-distance estimation | Prediction marker prompt, line offset, contact | Hybrid |
| B04 | Trail braking | Brake off by apex, lockup, corridor | Automatic |
| B05 | Left-foot braking | Circle laps and corridor, spin, throttle never off, brake on throttle | Automatic |
| B06 | Understeer correction | Push wide of the line, path regained by a gate, spin | Automatic |
| B07 | Oversteer correction | Rear slide, spin, exit lane, countersteer unwound, corrections | Automatic |
| B08 | Longitudinal weight transfer | Contact, spin, which-input prompt | Hybrid |
| C01 | Lift-off oversteer | Rear slide with no brake between gates, no handbrake, spin, posts, exit speed | Automatic |
| C02 | Brake-induced rotation | Rear slide between gates, no handbrake, spin, posts, exit gate and speed | Automatic |
| C03 | Throttle-induced oversteer | Slip angle, spin, countersteer under 3 s | Automatic |
| C04 | Handbrake rotation | Handbrake count = 1, rear slide, stall, spin, cone and gates, exit speed | Automatic |
| C05 | Countersteering and recovery | Spin, countersteer unwound by marker, exit lane | Automatic |
| C06 | Controlled slip angle | Slip angle held through arc, spin, corridor | Automatic |
| C07 | Lateral weight transfer | Gate sequence, cone contact, spin, abrupt stop | Automatic |
| C08 | Scandinavian flicks | Flick steering, rear slide, no handbrake, spin, posts, exit speed | Automatic |
| D01 | Slaloms and transitions | Cones on the correct side, cone contact, spin, exit speed ≥ 25 km/h, time | Automatic |
| D02 | Linked-corner sequencing | Apex gates and posts, on the road, exit speed (built 2026-10-21) | Automatic |
| D03 | Decreasing-radius corners | Gates, posts, wheels off the gravel, contact, spin, exit speed | Automatic |
| D04 | Increasing-radius corners | Gates, throttle after the apex, wheelspin after it, wheels off, contact, spin, exit speed | Automatic |
| D05 | Blind corners | Approach speed band, gates, posts, wall contact, spin | Automatic |
| D06 | Uphill and downhill corners | Gates, posts, wall contact, lockup, spin, time | Automatic |
| D07 | Road camber | Apex gates and posts, speed through the banked apexes, on the road, spin (built 2026-10-21) | Automatic |
| D08 | Mixed-surface transitions | Gates, posts, stop zone, lockup, spin | Automatic |
| D09 | Uphill hairpins (added 2026-10-20) | Gates and posts at each hairpin, on the road, spin, reversing, time | Automatic |
| E01 | Snow vs gravel vs tarmac | Corridor, contact, per-surface stats, observation prompt | Hybrid |
| E02 | FWD technique | Rear slide before the apex, throttle after it, no handbrake, spin, posts, exit speed | Automatic |
| E03 | RWD technique | Spin, corridor, wheelspin | Automatic |
| E04 | AWD technique | Understeer, corridor, exit speed | Automatic |
| E05 | Crest management | Crest speed, airtime, steady exit, landing damage, spin | Automatic |
| E06 | Jump takeoff and landing | Landing on road, rollover, damage | Automatic |
| E07 | Rough terrain | Puncture, damage, rollover, corridor | Automatic |
| E08 | Water crossings | Stall, damage, corridor, recovery use | Automatic |
| F06 | Puncture adaptation | Puncture injection, damage baseline, 35 km/h cap, rollover | Automatic |
| F07 | Vehicle setup comparisons | Setup switching, A/B stats, handling-difference prompt | Hybrid |

## Build order

Each step unlocks graded drills:

1. Telemetry sampler, gates, zones and segment timing. This makes A04 and B01
   fully automatic (ROADMAP P2). Done: sampler, stop zone, lockup, gates and speed
   at gates; B01 and A04 are automatic. Segment timing between gates remains.
2. Lockup, wheelspin, contact, damage and off-road detection (all built, plus spin,
   rollover, handbrake and puncture). This covers most
   of modules A, B and D.
3. Slip angle, spin, countersteer and handbrake detection. This opens module C.
4. Airborne, rollover, surface tracking, recovery use and block statistics,
   for modules E and F.
5. Understeer detection and hybrid prompts.

## Open questions

Each needs an in-game check, recorded in BEAMNG_API_NOTES:

- [x] How to pull per-wheel speed and driver inputs from vehicle Lua, and at what rate:
      our own vehicle extension sends one batched sample per frame (30 Hz unfocused,
      60 Hz focused); see BEAMNG_API_NOTES → Vehicle Lua
- [x] Whether the surface type under each wheel is readable: yes, `contactMaterialID1` per
      wheel, named via `particles` (BEAMNG_API_NOTES → Vehicle Lua)
- [ ] Whether cone positions can be read reliably from separate prop objects
- [ ] Whether gearbox state exposes missed shifts directly
- [ ] How to detect use of the game's own recovery and reset
- [ ] What the built-in drift and race modules are called and expose
