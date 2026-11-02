# Driver model

Design for a trained driver that demonstrates the techniques the game's AI can't drive. It starts with C08, the
Scandinavian flick. Agreed with the owner on 2026-11-01. The wider idea and its research notes are in
[IDEAS](IDEAS.md#versatile-driver-reinforcement-learning); this is the plan for its first slice.

Status: **steps 1-3 of the build plan built**: stage 1 drives C08 to gold from varied starts on all three surfaces.
Stage 2 and the in-game demo aren't built yet.

## Goal and constraints

- **First goal: demos of hard techniques.** The demo shows the player the technique ("watch, then try it"). Coaching
  and new drills come later and reuse the parts.
- **First drill: C08** on gravel, asphalt and snow. A scripted driver and input tapes exist, so they're the baseline:
  the gravel tape passes 5 of 5 replays; asphalt and snow pass at best 4 of 5, from a perfect start.
- **No driving by the owner.** The demonstrations come from scripted drivers, written coaching knowledge and trial and
  error. Players' runs may be added later, which is a separate decision ([PRODUCT](PRODUCT.md)).
- **One machine, any time of day.** Training uses the owner's PC with one game instance; it can run while the owner
  uses the PC.

## The approach: skills with tuned dials, then a learned correction

The flick is split into skills. Each skill is a small hand-written controller with a few dials. Training happens in two
stages:

1. **Stage 1:** an optimiser tunes the dials.
2. **Stage 2:** a small network learns a *correction* on top of each controller's output (residual reinforcement
   learning).

Each stage is useful on its own. Stage 1 alone gives demos that recover from drift better than tapes do.

Alternatives considered:

- **Tuned controllers only.** That's stage 1, kept as the first milestone.
- **Learning the whole flick from scratch.** Too slow to discover on one machine, with nothing working along the way.

## The flick as skills

Today's scripted flick (`scenarios._flick_run`) is open loop by distance: from 54 m it lifts and steers right (0.5) for
8 m, then left (-1.0) with full brake for 8 m, then hands back to the path follower. It never reads what the car is
doing. Each skill here ends when a **measurement** says so instead.

| # | Skill | The car | Ends when | Learned |
| --- | --- | --- | --- | --- |
| 1 | Approach | holds about 60 km/h on the line | the Flick gate is passed | no: path follower and speed hold |
| 2 | Feint | lifts, steers away (right) | the car has turned `feintYawDeg` away from the corner | dials, then a correction |
| 3 | Load and turn-in | steers hard left with a stab of brake | the feint's swing away has slowed to `loadUnwindDegS` | dials, then a correction |
| 4 | Catch | counter-steers and works the throttle to hold the slide | the car points at the Exit gate, or the slide fades | dials, then a correction |
| 5 | Exit | throttle on through Exit | the Exit gate is passed | no: path follower |

Skills 2-4 last about 2 seconds, so learning is confined to a small problem.

**The flick is a pendulum** (measured in step 2, C08 gravel):

- The feint turns the car only about 4° right.
- It is still turning away at about 22°/s when the turn-in has run for 0.4 s, because the wheel takes about 0.4 s to
  get from right to full left at the human steering rate.
- The rear only comes round (+60°/s, 23° of slide) after that, during the catch.

So the first design's triggers couldn't fire, and these replaced them:

| First design | Why it couldn't fire | Replaced by |
| --- | --- | --- |
| "the yaw rate away peaks" | with the steering held, the turn away doesn't peak within the feint | how far the car has turned |
| "the slide reaches its target" | it happens after the load phase | the swing away slowing |

## Technique cards

Coaching knowledge enters as a **technique card**: one JSON file per technique under `tools/driver/cards/`. Claude
drafts each card from coaching material in its own words, citing the sources, and the owner reviews it. A card holds:

- the phases (skills), in order, each with its controller and the **dials** it uses, given as `[min, max, start]`
- `endsWhen` for each phase, as a measurement
- a time limit for each phase
- **reward terms** from the coaching text (for example, the weight moves to the outside during the feint)
- **human limits**: reaction time, and how fast the steering and pedals can move
- **faults**: what a missed phase looks like and its coaching cue
- a plain-language **cue** for each phase

The cards stay training-only under `tools/` for now. When the coach or a demo in the mod reads them, they move into
`mod/`, with an ADR.

## Where it runs

- **The skill runner runs in the car's Lua** as a vehicle extension, like the tape player. It switches skills on the
  card's measurements, applies the human limits and evaluates the network.
- **It decides on a fixed 20 Hz clock of simulation time.** That's the 0.05 s step of deterministic mode, so a driver
  trained fast behaves the same at normal speed.
- **A round trip through the MCP server per tick (as `academy.follow_path` does) can't keep up.** It's too slow, it's
  paced by real time, and it's unusable at 5× speed.
- **Python sets up each attempt and collects the result,** through the controlled start from the tape work: physics
  stopped, Retry, extension loaded, physics resumed. The result is the run record and the grader's verdict.
- **Training code** (the optimiser, PyTorch) runs in Python between attempts. New dials or weights reach the car as a
  file.
- **The network:** two layers of 32 neurons, with its weights in JSON. Lua evaluates it, a few hundred multiply-adds
  per decision.
- **What it sees, all relative to the car:** speed, yaw rate, rear slip angle, the current skill and the time spent in
  it, the distance and angle to the next gate, and the controller's own output.

## Fast simulation

Measured on 0.40.4 (2026-11-01, details in [BEAMNG_API_NOTES](BEAMNG_API_NOTES.md#developer-loop)):

- **Deterministic mode runs 0.05 s of physics per rendered frame,** so its speed is the frame rate × 0.05. Unfocused,
  the background frame cap (30 fps) gives 1.5×.
- **Lifting the background cap in memory gives about 5.5× unfocused.** Focused there's no cap on this machine (vsync on
  but not limiting), and it gives about 5.1×. The cap is lifted through the game's own "don't save while loading
  settings" flag, so the settings file is never written, and it's restored afterwards.
- **The physics is the same at every speed.** One input script gave the same motion at 1.5× and 5× (to the centimetre
  on the first pair). Normal mode against deterministic mode differed by 0.5-0.8 m over 36 m, which is the usual
  run-to-run spread.
- **Graphics don't matter much.** At 5.5×, physics takes 5.6 ms of a 9 ms frame and rendering about 3 ms. Even with no
  rendering at all, the ceiling is about 8×. Graphics settings are left alone.
- **The harness's own overhead matters as much.** At first an attempt took 20 s wall time for about 2.5 s of driving:
  every `game.vlua` call waits 1.2 s to read the car's reply, and the attempt polled the car for its result. Car
  commands now go one way (`queueLuaCommand`), and the runner hands its report to GE Lua itself
  (`obj:queueGameEngineLua`). An attempt now takes about 5 s, and a 396-attempt tuning run about 52 minutes.
- **Train unfocused, cap lifted.** Focus and frame rate change only the speed, never the result.
- **Untested:** each car's physics runs on its own thread, so three Covets on the gravel, asphalt and snow corners
  might train all three surfaces in parallel.

At 5.5×, about 2,500 five-second attempts fit in an hour.

**Frame timing in a player's game.** Players run in normal mode at their own frame rate, and inputs reach the car once
per rendered frame:

- At 60 fps or more, the 20 Hz decisions are off by at most about 17 ms.
- At 30 fps (unfocused, or a slow PC), they land every one or two frames, a wobble of up to 33 ms that deterministic
  mode never shows.

So training adds a random 0-1 frame delay to each decision, and acceptance includes normal mode at 30 fps and
uncapped.

## Training

**Stage 1: dials (CMA-ES).** About 8-12 dials per surface.

- **Score:** the grader's verdict plus margins (slip angle beyond its target, clearance to the posts, exit speed). A
  plain pass or fail is too blunt to learn from.
- **Varied starts:** each attempt starts ±5 km/h and ±1 m sideways from the usual start.
- **Size:** a few hundred attempts per surface, minutes at 5.5×.

**Stage 2: correction (SAC).** SAC is a reinforcement-learning algorithm that's frugal with attempts.

- Trained directly in BeamNG, about 50k-200k decisions per surface, roughly 30 minutes at 5.5×.
- Episodes start at the beginning of skill 2 or later, taken from stage 1's runs, so the hard parts get practised most.
- **Fallback:** a cheap Python car model fitted to stage 1's logged runs, if training in BeamNG turns out too slow.

## Acceptance

- **Stage 1:** at least 19 of 20 varied attempts pass on each of gravel, asphalt and snow.
- **Stage 2:** the same with wider starts (±10 km/h, ±2 m), mostly silver or better.
- **Both:** they pass in fast mode, and in normal mode at 30 fps and uncapped (scenario `flick_ai`).

## In the game

C08 gets **Watch AI**, as the five road drills have it:

- The skill runner drives live at normal speed in the player's session.
- Each phase's cue from the card appears as the phase starts, with an optional slow-motion beat at the phase changes
  (`simTimeAuthority` slow motion).
- A demo that misses says so honestly.

## Testing

- **Unit tests (LuaJIT):** the skill runner's phase switching and human limits, and the Lua network against the Python
  reference on recorded inputs.
- **In game:** scenario `flick_ai` (the acceptance runs above). Its runs become fixtures.

## Build plan

Each step is usable on its own and is verified before the next starts.

1. **Fast-run harness** (`tools/driver/fast.py`). **Built 2026-11-01.**
   - `with fast():` turns on deterministic mode and lifts the background cap in memory.
   - `restore()` puts both back from the values saved on disk, so it also repairs a game left in fast mode by a script
     that died.
   - `sim_speed()` reads `obj:getSimTime()` against the wall clock.
   - Verified in game (0.40.4) by `python tools/driver/fast.py check`: 5.09× focused, 5.02× unfocused, 1.00× normal,
     and settings back as saved afterwards. A script killed inside `fast()` left fast mode on; `fast.py restore` put
     the saved cap back. Unit tests in `tests/python/test_fast.py`.
2. **Card and skill runner.** **Built 2026-11-01.**
   - **The pieces:**
     - `tools/driver/cards/scandinavian_flick.json`, the card.
     - `tools/driver/runner.lua`, injected into the car the way the tape player is. Its pure core is unit-tested in
       `tests/lua/test_driver_runner.lua`, and its slip angle is checked against the grader's.
     - `tools/driver/attempt.py`, which runs attempts from a controlled start and prints each verdict, a score, and
       how and when each phase ended.
   - **The dials** start from the old script: 66 km/h, the feint 14 m past the Flick gate at 0.5. Asphalt uses
     72 km/h and 0.7.
   - **Results.** Verified in game (0.40.4) by `attempt.py`, every attempt from the same controlled start, with every
     phase ending on its measurement:

     | Surface | Normal speed | Fast | Slide | The tape |
     | --- | --- | --- | --- | --- |
     | Gravel | 10 of 10 gold | 10 of 10 gold | 23° | 5 of 5 replays |
     | Asphalt | not run | 5 of 5 gold | 16° | best 4 of 5 |
     | Snow | not run | 5 of 5 gold | 20° | best 4 of 5 |

     Fast runs from one start repeat almost exactly, so 5 of 5 there is close to one sample. Stage 1's varied starts
     are the real test.
   - **Learned: the reaction time.** At first, a 150 ms reaction time delayed every measured phase end. With the
     trigger values 3° and 20°/s, gravel fell to 2 of 10: the swing grew to 38° and the car clipped the Apex post.
   - **Owner decision (2026-11-01): human limits, not human hesitation.**
     - A rehearsed move doesn't wait out a reaction time, so phases end as soon as their measurement fires.
     - The reaction time applies only to *corrections*: the catch's counter-steer responds to the slide as it was
       150 ms ago, and the same will hold for stage 2's correction.
     - What must never happen is an input a person couldn't make. The rate limits guard that: lock to lock in half a
       second (`steerRatePerS` 4), which the owner confirmed is humanly possible, and pedals in an eighth of a
       second.

     Without the delay, 3° and 20°/s are the card's starting values again. They passed every run in the table above
     (rerun after the change) with a 26° slide.
3. **Stage 1** (`tools/driver/tune.py`, CMA-ES). **Built and accepted 2026-11-02.**
   - **The pieces:**
     - `es.py`, the optimiser.
     - `tune.py`, which tunes 11 dials per surface: 12 generations of 11 candidates, each driving 3 varied starts. That
       is 396 attempts, about 52 minutes in fast mode, then a selection on 10 fresh starts.
     - `attempt.py --vary`, which starts attempts ±5 km/h and ±1 m to the side. The sideways offset uses
       `spawn.safeTeleport` while physics is stopped, as Retry does.
     - `attempt.py restore`, which repairs a game after an interrupted run: normal mode, the runner off, and drill
       progress and session settings put back from `logs/session-<drill>.json`.
     - The tuned dials, in `tools/driver/dials/<card>-<surface>.json`.
   - **Baseline:** the card's own dials, from 20 varied starts (seed 100). Speed is what breaks them; the sideways
     offset hardly matters.

     | Surface | Passes | How the misses happened |
     | --- | --- | --- |
     | Gravel | 17 of 20 | 3–4 km/h fast: the slide grew to 34–35° and the car clipped the Apex post |
     | Asphalt | 16 of 20 | 3.5–5 km/h slow: the slide stayed at 7–8°, short of the 8° needed |
     | Snow | 19 of 20 | one slow start, offset sideways: clipped the Turn-in gate |

   - **Acceptance.** Verified in game (0.40.4) by `attempt.py --vary --seed 300`, starts the tuning never saw. Normal
     speed ran unfocused at the 30 fps cap, so it also covers the frame-timing wobble.

     | Surface | Fast | Normal speed | Slide | Exit speed |
     | --- | --- | --- | --- | --- |
     | Gravel | 20 of 20 gold | 20 of 20 gold | 19–26° | 53 km/h |
     | Asphalt | 20 of 20 gold | 20 of 20 gold | 19–28° | 52–53 km/h |
     | Snow | 20 of 20 gold | 20 of 20 gold | 18–25° | 50 km/h |

   - **What the tuning found.** It differs by surface:
     - **Gravel:** switches the catch's counter-steer on (`catchGain` 1.04 against the card's 0). The feint comes
       sooner (12.6 m past the Flick gate) and harder (0.74).
     - **Asphalt:** arrives faster (76 km/h) with a gentle feint (0.34), and turns in at full lock.
     - **Snow:** keeps the counter-steer off and a softer turn-in (0.81).

     All three now exit at 50 km/h or more, against the 45 needed for gold. Those differences are a candidate for the
     card's per-surface notes once the owner has reviewed them.
   - **Learned: choose by fresh starts, not by the best score.** The best single fitness of the first gravel run (3
     starts, generation 4) passed only 15 of 20 fresh starts, worse than the card. Later candidates passed 20 of 20.
     So `tune.py` now ends with a selection: the top 5 candidates of the second half, plus the optimiser's final mean,
     drive the same 10 fresh starts, and the one with the most passes, then the best mean score, is kept.

     Gravel's dials predate that step. They were picked by hand the same way: the most consistent of four candidates
     that passed all 40 starts of seeds 100 and 200.
   - **Learned: an interrupted run leaves the drill's state behind.** Stopping the first tuning run skipped its
     cleanup, leaving C08's progress counting 89 tuning attempts. It was put back by hand from the log, which is why
     sessions now save the progress first.
4. **Stage 2** (`tools/driver/train.py`, SAC, PyTorch) plus the network in the runner. Done at stage 2's acceptance.
5. **Watch AI for C08 in the mod.** The runner and cards move into `mod/`, with an ADR, plus the `flick_ai` scenario,
   CHANGELOG and docs.

Python dependencies are for `tools/driver/` only; the mod ships none of them. Stage 1 needed none: `es.py` is a small
CMA-ES (the diagonal variant) in plain Python, unit-tested on standard test functions. Stage 2 will need PyTorch.
