# Vehicles and drivetrain options

Which cars the drills use, what to look for in a drill car, and which drills
could be practised with more than one drivetrain. Car and config names come
from the original spreadsheet; every drill still has `modelId` and
`configPath` set to null, so **none of these names has been matched to a real
game config yet**. Driving-technique judgements here are design guidance, not
in-game findings.

## Current lineup

| Car | Drivetrain | Used by | Role |
| --- | --- | --- | --- |
| Ibishu Covet, Student Driver and 1.5 DX (manual) | FWD | A01–A06, B01–B03 | Slow, forgiving starter car for basics and braking |
| Hirochi Sunburst 1.6 Base (manual) | FWD | A07, A08, B05, B06, C01, C07, D01, D07, E02, F03 | Neutral road car for cornering and lift-off rotation |
| Hirochi Sunburst NGRC2 Asphalt Rally (manual) | AWD | B04, D03, D04, D06 | Tarmac rally car |
| Hirochi Sunburst NGRC2 Gravel Rally (manual) | AWD | 18 drills in modules B–F | The main rally car |
| Ibishu 200BX Type-LS (manual) | RWD | B07, C03, C05 | Light RWD car for oversteer and countersteer |
| Hirochi SBR4 NGRC2 Gravel Rally (manual) | RWD | E03 | RWD technique |
| Cherrier Vivace NGRC1 Gravel Rally (sequential) | AWD | E06, E07, F08 | Tougher car for jumps, rough ground and full stages |

Few cars means less to learn and less threshold tuning; every car is stock, so
players need no car mods; and the set covers FWD, RWD and AWD. The SBR4 is used
by one drill, so E03 could move to the 200BX to cut the lineup to five models.

## What to look for in a drill car

**Required for grading**

1. **ABS off for braking drills.** ABS prevents lockup, so B01, B02, A05 and
   parts of A03 can't be failed or practised with it on. Check each config.
2. **Traction and stability control off.** ESC and TCS hide the wheelspin,
   oversteer and slides that A02, B07 and module C train. Force them off where adjustable.
3. **Manual gearbox with player-controlled clutch.** Stall and clutch drills
   (A02, A03, C04) need a manual box and BeamNG's automatic clutch turned off,
   which is a game input setting. Detect it and warn, or mark those checks as
   not applicable. Keyboard players can't modulate a clutch, so A02 may need a
   controller-only note.
4. **One fixed config per drill option.** Thresholds depend on the car
   (understeer detection, lockup timing, reference times). Pin a `configPath`
   and check it at drill start (ROADMAP P1).

**Good qualities**

- Low to moderate power, so mistakes happen slowly (Covet, base Sunburst for modules A and B).
- Predictable, progressive handling: no snap oversteer; open diff or mild LSD on road cars.
- Ground clearance, suspension travel and toughness for module E crests, jumps,
  rough ground and water.
- One car family across difficulty levels (Sunburst base → Asphalt Rally →
  Gravel Rally) so the feel stays familiar while grip and power change.
- Light on performance: heavy modded cars lower the frame rate and the telemetry sample rate.

## Drivetrain options

42 of 48 drills can be practised with FWD, RWD or AWD: 34 work the same with
any drivetrain, 8 need different instructions per drivetrain, and 6 are
restricted to one or two.

### Option sets

Two sets of three, matched for power and weight within each set so the
drivetrain is the main difference.

| Drivetrain | Road set (modules A–D) | Rally set (modules B–F) |
| --- | --- | --- |
| FWD | Hirochi Sunburst 1.6 Base (M), already used | A FWD rally config (none chosen yet; check in-game) |
| RWD | Ibishu 200BX Type-LS (M), already used | Hirochi SBR4 NGRC2 Gravel Rally (M), already used |
| AWD | A Sunburst AWD road config (exact name to check) | Hirochi Sunburst NGRC2 Gravel Rally (M), already used |

Using the Sunburst for both FWD and AWD keeps the body and driving position the
same. The ABS/TCS/ESC rules above apply to every option.

### Group 1: same drill, any drivetrain (34)

"Value" is how much switching drivetrain teaches.

| Drill | Title | Value | What changes between drivetrains |
| --- | --- | --- | --- |
| A01 | Steering and spatial awareness | Low | Barely anything at parking speed |
| A02 | Clutch engagement and launches | Medium | Wheelspin: FWD and RWD spin easily, AWD rarely |
| A03 | Gear selection and downshifting | Low | Heel-toe feel; RWD can step out on a bad downshift |
| A04 | Throttle modulation | Low | Speed hold is the same everywhere |
| A05 | Braking accuracy | Low | Brake balance only |
| A06 | Vision and looking ahead | Low | Eyes-and-calls drill |
| A07 | Basic racing lines | Medium | Best line shifts: FWD favours an early exit, RWD a later apex |
| A08 | Apex and exit selection | Medium | How hard you can accelerate on exit |
| B01 | Threshold braking | Low | Weight balance changes the lockup point a little |
| B02 | Wheel lockup recognition | Low | Same skill |
| B03 | Stopping-distance estimation | Low | Results depend on the car; track predictions per car |
| B04 | Trail braking | Medium | RWD rotates more easily on trail brake |
| B06 | Understeer recognition | Medium | Easiest to provoke in FWD; AWD understeers on power |
| C07 | Lateral weight transfer | Medium | Rear grip differs on the figure-eight |
| D01 | Slaloms and rapid transitions | Medium | RWD rear can swing at speed |
| D02 | Linked-corner sequencing | Medium | Exit drive differs |
| D03 | Decreasing-radius corners | Medium | Lift-off reaction differs |
| D05 | Blind corners | Low | Speed management drill |
| D06 | Uphill and downhill corners | Medium | Uphill traction varies a lot |
| D07 | Road camber | Low | Grip awareness |
| D08 | Mixed-surface transitions | High | Each drivetrain reacts differently to sudden grip loss |
| E01 | Snow vs gravel vs tarmac | High | Grip by surface varies hugely by drivetrain |
| E05 | Crest management | Low | Stability on landing |
| E06 | Jump takeoff and landing | Medium | Throttle on landing pitches each car differently |
| E07 | Rough terrain | Medium | Traction on uneven ground; AWD is easiest |
| E08 | Water crossings | Low | Mostly ground clearance |
| F01 | Pacenote interpretation | Medium | Same calls, different pace |
| F02 | Timed consistency runs | Medium | Track consistency per car |
| F03 | Speed management and regularity | Low | Target-time drill |
| F04 | Driving unfamiliar stages | Medium | Road reading is the same |
| F05 | Long-stage concentration | Medium | Focus drill |
| F06 | Puncture adaptation | High | A punctured driven wheel behaves very differently |
| F07 | Vehicle setup comparisons | Medium | A/B setup within one car; drivetrain could be the A/B change |
| F08 | Full-stage integration | High | The whole skill set on each car |

### Group 2: any drivetrain, technique changes (8)

These need per-drivetrain instructions and possibly per-drivetrain thresholds.

| Drill | Title | FWD | RWD | AWD |
| --- | --- | --- | --- | --- |
| B05 | Left-foot braking | Main use: rotates and settles the front | Less useful; mainly settles the car | Key rally technique |
| B07 | Oversteer recognition | Provoke by lifting or braking, not throttle | Throttle pulse (as written) | Throttle on a rear-biased car, or lift |
| B08 | Longitudinal weight transfer | Lift-off rotation is strong | Rotation by brake and lift; power rotation is extra | Mix of both |
| C01 | Lift-off oversteer | Classic and gentle (as written) | Sharper and quicker | Mild |
| C02 | Brake-induced rotation | Works well | Works, easily overdone | As written |
| C04 | Handbrake rotation | Simplest | Simple | Depends whether the handbrake disconnects the drive (check in-game) |
| C08 | Scandinavian flick | Flick plus lift, no power slide | Flick, then catch with throttle | As written |
| D04 | Increasing-radius corners | Throttle exit causes understeer | Throttle exit causes oversteer | Both, mildly |

### Group 3: restricted (6)

| Drill | Title | Allowed | Why |
| --- | --- | --- | --- |
| C03 | Throttle-induced oversteer | RWD, AWD (rear-biased) | FWD can't oversteer under power |
| C05 | Countersteering and recovery | RWD, AWD | Needs a power-on rear slide to catch |
| C06 | Controlled slip angle | RWD, AWD | FWD can't hold a slide on throttle |
| E02 | FWD technique | FWD only | Defined by drivetrain |
| E03 | RWD technique | RWD only | Defined by drivetrain |
| E04 | AWD technique | AWD only | Defined by drivetrain |

E02–E04 already form the drivetrain comparison as a set; with options they
could become one drill run three ways.

## Data implications

Not implemented; would need a decision record and a schema change
([DRILL_DATA](DRILL_DATA.md#changing-the-schema)):

- `vehicle` becomes a list of options, each with drivetrain, `modelId`,
  `configPath`, a default flag and an optional instruction override (Group 2).
- Progress and best times are kept per drill **and** option, so a FWD best is
  never compared with an AWD best.
- Grading thresholds (reference times, lockup timing, understeer) are tuned per option.

## To check in-game

For each car: exact config name, drivetrain, gearbox, and whether ABS, ESC and
TCS are fitted or adjustable. Also: the two missing configs (FWD rally,
Sunburst AWD road) and handbrake behaviour on AWD rally cars (C04). Record the
results in BEAMNG_API_NOTES and fill `modelId`/`configPath` in `exercises.json`.
