# Grading engine

What the engine needs so drills can be graded automatically instead of by
self-assessed Pass/Miss. This expands the Telemetry and Scoring parts of
[ARCHITECTURE](ARCHITECTURE.md#target-architecture) and the P2/P3 items in the
[ROADMAP](ROADMAP.md). Existing tools and mods we can reuse are in
[PRIOR_ART](PRIOR_ART.md); car choices are in [VEHICLES](VEHICLES.md).

**Status:** the telemetry sampler, run records and the rule engine exist.
**B01** (threshold braking) and **A04** (speed hold through gates) are graded
automatically; every other drill is still
`selfAssessment` with an empty `rules` list. Engine data sources not listed as
verified in [BEAMNG_API_NOTES](BEAMNG_API_NOTES.md) remain **unverified**.

Sections 1–7 below are the capabilities; [Drill coverage](#drill-coverage)
maps each of the 48 drills to the ones it needs.

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
| Zone or box | Whole car inside a polygon | A01 parking box, B01 5 m stop zone |
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
| Reversing | Reverse gear or negative forward speed | A01, F03 |
| Handbrake count | Handbrake presses per run | C01, C02, C04 (exactly one), C08, E02 |
| Slip angle | Angle between heading and direction of travel | C01, C02, C03, C06 |
| Spin | Heading turns past a threshold against travel | most C, D and E drills |
| Countersteer | Steering opposite the rotation, and time to unwind | B07, C03 (under 3 s), C05 |
| Understeer | Yaw rate well below what steering and speed predict; needs a simple car model, tuned per car | B06, E02, E04 |
| Airborne, landing, rollover | Wheel contact, landing impact, car tipping over | E05, E06, E07 |
| Cone contact | Record each cone's spawn position and flag any that moves | about 15 drills |
| Barrier contact, damage | Jump in damage total | D03, F01, F05 |
| Puncture | Tyre deflation; F06 needs a damage baseline because it starts punctured | E07, F06 |
| Recovery use | The game's own recover/reset was used | E08, F01, F04, F05, F08 |

Understeer is the hardest detector. Cone contact matters most because so many
drills use it.

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

## 6. Hybrid grading

Some criteria test what the driver knows, not what the car did. These drills
need HUD prompts and the `hybrid` mode:

| Drill | What needs a human answer | Prompt |
| --- | --- | --- |
| A06 | Name the next bend before the first apex | Pick from options |
| B03 | Predict the stopping point | Place a marker before the run |
| B08, D07 | Which input or side changed the grip | Pick from options |
| E01 | Safe speed and braking observations per surface | Short form |
| F01 | Pacenote interpretation | Self-assessed, or graded from route errors |
| F07 | One handling difference between setups | Free text |

## 7. Scene control

Spawn and reset cones and props on retry, enforce the vehicle config and
drivetrain ([VEHICLES](VEHICLES.md)), switch setups (F07) and inject a puncture (F06).

## Drill coverage

41 of 48 drills can be fully automatic once these capabilities exist; 7 need a
hybrid prompt.

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
| B05 | Left-foot braking | Circle corridor, contact, spin, throttle never zero | Automatic |
| B06 | Understeer correction | Understeer, path regained by marker, contact | Automatic |
| B07 | Oversteer correction | Spin, exit lane, countersteer unwound | Automatic |
| B08 | Longitudinal weight transfer | Contact, spin, which-input prompt | Hybrid |
| C01 | Lift-off oversteer | Slip angle, no handbrake, spin, corridor | Automatic |
| C02 | Brake-induced rotation | Slip angle, no handbrake, spin, exit gate | Automatic |
| C03 | Throttle-induced oversteer | Slip angle, spin, countersteer under 3 s | Automatic |
| C04 | Handbrake rotation | Handbrake count = 1, stall, spin, corridor, barrier contact | Automatic |
| C05 | Countersteering and recovery | Spin, countersteer unwound by marker, exit lane | Automatic |
| C06 | Controlled slip angle | Slip angle held through arc, spin, corridor | Automatic |
| C07 | Lateral weight transfer | Gate sequence, cone contact, spin, abrupt stop | Automatic |
| C08 | Scandinavian flicks | Slip direction, no handbrake, spin, road edge | Automatic |
| D01 | Slaloms and transitions | Cone contact, spin, exit speed ≥ 25 km/h | Automatic |
| D02 | Linked-corner sequencing | Corridor, contact, segment time, +8% of best | Automatic |
| D03 | Decreasing-radius corners | Hard-stop detection, barrier damage, corridor, exit gate | Automatic |
| D04 | Increasing-radius corners | Exit lane, throttle rising after apex, wheelspin, spin | Automatic |
| D05 | Blind corners | Corridor, contact, steering direction before marker | Automatic |
| D06 | Uphill and downhill corners | Exit gate, lockup, gear | Automatic |
| D07 | Road camber | Corridor, understeer/oversteer, which-side prompt | Hybrid |
| D08 | Mixed-surface transitions | Corridor, cone contact, surface tracking | Automatic |
| E01 | Snow vs gravel vs tarmac | Corridor, contact, per-surface stats, observation prompt | Hybrid |
| E02 | FWD technique | Understeer, corridor, no handbrake, exit heading | Automatic |
| E03 | RWD technique | Spin, corridor, wheelspin | Automatic |
| E04 | AWD technique | Understeer, corridor, exit speed | Automatic |
| E05 | Crest management | Airborne/landing, spin, exit heading | Automatic |
| E06 | Jump takeoff and landing | Landing on road, rollover, damage | Automatic |
| E07 | Rough terrain | Puncture, damage, rollover, corridor | Automatic |
| E08 | Water crossings | Stall, damage, corridor, recovery use | Automatic |
| F01 | Pacenote interpretation | Route errors, damage, recovery use | Hybrid |
| F02 | Timed consistency runs | Stage time, +7% of best clean | Automatic |
| F03 | Speed management | Target time ±2 s, reversing, speed cap | Automatic |
| F04 | Unfamiliar stages | Corridor, damage, recovery use, 4 of 5 routes | Automatic |
| F05 | Long-stage concentration | Loop count, recovery use, damage | Automatic |
| F06 | Puncture adaptation | Puncture injection, damage baseline, 35 km/h cap, rollover | Automatic |
| F07 | Vehicle setup comparisons | Setup switching, A/B stats, handling-difference prompt | Hybrid |
| F08 | Full-stage integration | Recovery use, +8% of reference time | Automatic |

## Build order

Each step unlocks graded drills:

1. Telemetry sampler, gates, zones and segment timing. This makes A04 and B01
   fully automatic (ROADMAP P2). Done: sampler, stop zone, lockup, gates and speed
   at gates; B01 and A04 are automatic. Segment timing between gates remains.
2. Lockup, wheelspin, contact, damage and off-road detection. This covers most
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
