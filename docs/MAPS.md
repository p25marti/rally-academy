# Maps and venues

Where the drills take place. Goal: load a map at the drill's spot, drill it many
times with Retry, then move to the next drill, with as few map loads as possible
and most drills on gravel or dirt.

**Surveyed in-game 2026-10-15 on 0.39.4** with a car and a camera at each spot
(method at the end). Coordinates are world positions for the start/centre;
"tyres" is what the car's wheels actually reported, the authoritative surface.
Nothing here has been *driven* as a drill yet.

**Decision (2026-10-15): Option A**, West Coast USA as the home base with Utah for
stages. Revisit later for bespoke areas per drill (e.g. Italy's hillclimbs for
advanced cornering, Johnson Valley for rough terrain) if that gives a better result.

## Venues

Venues the drills use are data in `mod/gameplay/rallyAcademy/venues.json` (ids such as
`bmp-gravel-track` = W1, `bmp-dirt-arena` = W2, `bmp-dirt-circle` = W3, `wcusa-quarry` = W4,
`wcusa-offroad-circuit` = W5, `utah-ngrc-stages` = U1). This page keeps the survey notes;
to find, test and add venues, follow [VENUES.md](VENUES.md).

### West Coast USA (`west_coast_usa`): loose-surface training complex
Load ≈ 80 s (biggest map).

| Id | Venue | Where | Surface (tyres) | Notes |
| --- | --- | --- | --- | --- |
| W1 | **BMP Gravel Track** | layouts start at (103, 165, 118); Figure Eight at (53, 127, 119) | GRAVEL track, tarmac start line | Purpose-built rallycross venue: ~14–16 m wide, sand berms, two levels, figure-eight crossover, roundabout, jump, joker. 9 official layouts (Gravel Introduction, Figure Eight Basics, Figure Sixteen, Reverse Loop, Ample Sand, Reverse Figure Eight, Inverted Joker, Tie the Knot, Full Circuit). 150 m straight ahead of the start |
| W2 | **BMP dirt arena** | (337, 96, ~) | DIRT_DUSTY | ≥ 64 × 64 m open, flat (4°), fenced, grandstands; figure-eight tyre marks already there |
| W3 | **BMP dirt circle** | (265, 40, ~) | DIRT_DUSTY | ≈ 50 m circular infield, dead flat, light towers round the edge: a natural skidpad |
| W4 | Quarry | (729, −823, 158) | GRAVEL | Haul roads, terraces, spoil heaps; Spiral Descent for gradients. Cluttered |
| W5 | Off-Road Circuit | (567, 27, 148) | DIRT_DUSTY / rocky | Rough dirt figure-eight with jumps |
| W6? | Asphalt circle pad near BMP | (406, −122, 145) | ASPHALT | Candidate, not yet checked in a drill: found by `survey.py corners` (a 343° loop, radius ≈ 26–31 m, 9 m wide) and seen in the venue report as a large pad with a painted circle. Could suit circle drills on tarmac (B05, C06 variants) |

### Utah (`utah`): rally stages and desert
Load ≈ 30 s.

| Id | Venue | Where | Surface (tyres) | Notes |
| --- | --- | --- | --- | --- |
| U1 | **NGRC Rally Utah 2026 stages** | SS1 Deer Creek (−411, −635, 121) · SS2 Buckaroo (632, 843, 197) · SS3 (455, 397, 175) · SS4 (90, −109, 147) | GRAVEL | 3.7–4.6 km each, 99.6–100% gravel (BeamNG's own stats). River crossings, jumps, crests, canyon exposure. Each ships a driveline spline, pacenote notebooks, co-driver voice and gold/silver/bronze times; recommended car Sunburst `rally_am_gravel` |
| U2 | **Airstrip** | (−330, −562, 130) | DIRT_DUSTY | Dirt runway crossing, clear 150 m along it: straight-line drills |
| U3 | **Desert flat** | (−880, 928, ~) | DIRT_DUSTY | 96 × 96 m, dead flat (0.3 m), clear 87–150 m all round |
| U4 | Desert flat | (−104, −392, ~) | DIRT_DUSTY | 80 × 80 m, flat |
| U5 | Dead Man's Loop / Old Mill Loop | (787, −15, 147) / (−664, 531, 256) | loose and rocky dirt | 3.1 / 2.7 km gravel loops along cliffs and mesas |

### Italy (`italy`): gravel hillclimbs
Load ≈ 50 s. All six rally stages here are **tarmac**.

| Id | Venue | Where | Surface (tyres at checkpoints) | Notes |
| --- | --- | --- | --- | --- |
| I1 | **Gravel Hillclimb 1** | (597, 389, 174) | 12/14 GRAVEL | 3.1 km; narrow lane between stone walls (2–3 m clearance). Authentic, unforgiving |
| I2 | **Gravel Hillclimb 2** | (−350, −1715, 154) | 19/25 GRAVEL | 4.6 km, many hairpins, cliffs |
| I3 | Dirt field | (536, 216, ~) | DIRT / DIRT_DUSTY | 80 × 80 m flat, near I1 |
| I4 | Mixed Circuit 1 | (713, 762, 178) | 6 GRAVEL / 8 ASPHALT, alternating | Surface transitions |
| I5 | Quarry Loop | (−310, −1864, 161) | gravel/dirt middle, tarmac ends | 4.6 km |

### Others
| Map | Venue | Where | Surface | Notes |
| --- | --- | --- | --- | --- |
| Johnson Valley | Open desert | (1346, 18, ~) | DIRT_DUSTY | 128 × 128 m, clear 58–150 m |
| Johnson Valley | Desert Oversteer / Crankshaft Pass | (−1182, 257, 121) / (1376, 97, 115) | dusty dirt, sand | 4.4 km / 17.7 km rough desert routes |
| East Coast USA | SS Backroads | (−384, −439, 37) | dirt and tarmac alternating (62% gravel) | 5.3 km; bumpy, downhill braking zones. Map has no usable open loose ground |
| East Coast USA | Deforest Stage / Mud Clump Alley | (622, −144, 53) / (168, −659, 40) | DIRT | short dirt stage / muddy route |
| Jungle Rock Island | SS Howler Pass | *from files, not visited* | 93% gravel | 2.3 km, mud, jumps |
| Small Island | SS Rockwood | *from files, not visited* | 52% gravel | 4.4 km |
| Automation Test Track | snow and ice terrain, Clyde Peak | *from files, not visited* | SNOW, ICE | the stock option for E01 snow |

## Option A: West Coast USA home base, Utah for stages

Two maps. A–D and most of E stay at BMP (teleport between venues, no load).

| Drill | Venue | Drill | Venue |
| --- | --- | --- | --- |
| A01 spatial awareness | W2 arena | C01 lift-off oversteer | W1 corner |
| A02 launches | W1 straight | C02 brake rotation | W1 corner |
| A03 gears | W1 circuit | C03 throttle oversteer | W3 circle |
| A04 throttle zones | W1 straight | C04 handbrake | W1 hairpin / roundabout |
| A05 braking accuracy | W2 stop box | C05 countersteer | W2 arena |
| A06 vision | W1 layouts | C06 slip angle | W3 circle |
| A07 lines | W1 corner | C07 lateral transfer | W2 figure-eight |
| A08 apex/exit | W1 corner | C08 Scandi flick | W1 corner |
| B01 threshold braking | W1 straight (150 m) | D01 slalom | W2 arena |
| B02 lockup | W1 straight | D02 linked corners | W1 layouts |
| B03 stopping estimate | W1 straight + W2 | D03/D04 radius changes | W4 quarry / W1 |
| B04 trail braking | W1 corner | D05 blind corners | W4 quarry |
| B05 left-foot braking | W3 circle | D06 gradients | W4 quarry (Spiral Descent) |
| B06 understeer | W3 circle | D07 camber | W1 berms |
| B07 oversteer | W3 circle | D08 mixed surface | W1 tarmac start → gravel |
| B08 weight transfer | W1 bend | | |

| Drill | Venue |
| --- | --- |
| E01 surfaces | W1 gravel vs W1 tarmac; snow needs ATT (third map) or skip |
| E02–E04 FWD/RWD/AWD | W1 layouts |
| E05 crests, E06 jumps, E07 rough | W5 off-road circuit, W1 jump |
| E08 water | U1 SS1 river crossings |
| F06 puncture | U1 stages |
| F07 setup A/B | W1 laps |

## Option C: curriculum tour

One map per module (about six loads over the course), each drill where it fits best.

| Module | Map | Venues |
| --- | --- | --- |
| A Foundation | West Coast USA | W2 arena (A01, A05), W1 (A02–A04, A06–A08) |
| B Braking | West Coast USA | W1 straight (B01–B03), W1 corners (B04, B08), W3 circle (B05–B07) |
| C Rotation | West Coast USA → Italy | W3 circle (C03, C06), W2 (C05, C07), W1 (C01, C02); I2 hairpins (C04, C08) |
| D Cornering | Italy | I1/I2 hillclimbs (D02–D06), I4 Mixed Circuit (D08), I3 field (D01 slalom), camber on I2 (D07) |
| E Terrain | Utah (+ JV, ATT) | U1 crests/jumps/rivers (E05, E06, E08), U3/U4 flats (E02–E04), Johnson Valley rough routes (E07), ATT snow (E01) |
| F Adaptation and setup | Utah, West Coast USA | U1 stages (F06), W1 laps (F07). Full stages: the game's Rally mode (ADR 0006) |

## What the survey changed

- **West Coast USA is the strongest single map for technique**: BMP has a gravel
  circuit, an open dirt arena and a dirt circle side by side. Utah is the strongest
  for stages and terrain. Together they cover almost everything (Option A).
- **Italy's value is the two gravel hillclimbs** (narrow, walled, many hairpins):
  advanced cornering. Its rally stages are tarmac.
- **Johnson Valley** adds rough desert (E07) and huge open ground; **East Coast**
  adds dirt/tarmac stages but no open loose ground.
- Rally stages come with BeamNG data we can reuse: a driveline spline (route
  centre line), surface stats, pacenotes and start poses
  (`gameplay/missions/<level>/rallyStage/<id>/`).

## Method (repeatable)

The tools are in the repo: [VENUES.md](VENUES.md) (Save spot,
`tools/ingame/survey.py` finders and report). The original survey that produced the table
above used:
1. **Routes**: start pose and checkpoints from the mission's `race.race.json`;
   tyre contact read at every checkpoint (catches road meshes the terrain can't see).
2. **Open ground**: terrain sampled every 16 m (`core_terrain.getTerrainHeight`,
   `getTerrainNormal`, terrain material ground model); largest solid squares of flat
   (< ~10°, ≤ 2 m height spread) loose ground; then the car is placed there to check
   tyres and clearance (8-direction static raycasts) and a camera shot is taken.
   Beach sand and wet gravel squares turned out to be seabed or riverbed.
3. Stage surface/length come from the stage's `rally/drivelineSpline.json` stats.
