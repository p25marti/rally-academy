# Ideas: someday, maybe

A parking lot for ideas we're **not** building now, and may never build because they're
big, uncertain or not worth it yet. They're kept so they aren't lost, and so whoever picks
one up starts from what we already know.

This isn't the roadmap: nothing here is planned or promised. [ROADMAP.md](ROADMAP.md) is the
plan. To work on an idea, raise it with the owner first. If it goes ahead, it moves to the
roadmap (and gets an ADR if it's a big decision).

**Adding an idea:** copy the template at the end. Keep it short and honest about the hard
parts. "Who" says whether it came from the owner or was suggested.

| Idea | Who | Size | Status |
| --- | --- | --- | --- |
| [Real-time spoken coaching](#real-time-spoken-coaching) | Owner | Large | Idea |
| [Freeform exercise builder](#freeform-exercise-builder) | Owner | Large | Idea |
| [Attempt replays and telemetry charts](#attempt-replays-and-telemetry-charts) | Suggested | Medium | Idea |
| [Ghost of your best run](#ghost-of-your-best-run) | Suggested | Medium | Idea (also ROADMAP P5) |
| [AI demonstration lap](#ai-demonstration-lap) | Suggested | Medium | Idea |
| [Sharing drills and scores](#sharing-drills-and-scores) | Suggested | Large | Idea |

---

## Real-time spoken coaching

**The idea.** A voice that coaches while you drive, not only after the run: "brake now",
"ease off, front-left is locking", "too fast for gate 2", "good, hold it". Plus a spoken
debrief after the run, from the same reasons the HUD shows today. Spoken by a local
text-to-speech engine such as [Piper](https://github.com/rhasspy/piper) or
[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), so there's no cloud service and no delay.

**Why.** On a rig your eyes belong on the road. A coach's voice is how real rally schools
teach, and the grading already produces the words.

**What already helps.**
- Every grading check returns a readable reason (`rules.lua`). The debrief text exists.
- Live data is already in GE Lua every frame: speed, brake, wheel lockup, slip angle, gate
  crossings. Live feedback today is the HUD's "Gate 2 of 3: 31 km/h".
- The game has a co-driver audio system for its Rally mode (`gameplay/rally/voicepack.lua`,
  `audioManager.lua`), and Lua can play sounds.

**Hard parts.**
- **Running the TTS.** Neither engine can run inside the game's Lua. Two shapes:
  - *Pre-rendered phrases* (simplest): generate a fixed vocabulary of clips with Piper or
    Kokoro at build time ("brake", "lift", "lockup front left", numbers, drill names). Ship
    them in `mod/` as audio files and play them through the game's audio. No extra process
    for players; limited sentences.
  - *Companion app* (flexible): a small local program streams our events (WebSocket, UDP or
    a file the mod writes) and speaks any sentence. Players install and run something
    extra. Kokoro needs a decent CPU or GPU next to a running sim.
- **Timing and restraint.** Live cues must arrive within about 200 ms or they're worse than
  nothing. A coach that talks too much is distracting. Needs rules for when to speak, with
  priorities and cool-downs.
- **Good cues need a model of "right".** "Brake now" needs a reference braking point; per
  drill that's a marked spot or a learned best attempt.
- Licences of the voices and models, if shipping clips.

**Rough shape.** Start with the post-run debrief from pre-rendered clips (no live timing).
Then a few live cues on one drill (B01 lockup, A04 gate speeds), using the game's
co-driver audio path. The companion app comes only if fixed phrases prove too limiting.

## Freeform exercise builder

**The idea.** Make your own exercise anywhere: drop a start, gates, a stop zone or a finish
on any map, pick what gets judged (speed at each gate, no braking, stay on the road, a
target time), name it, then drill it like a built-in one with timing, history and best
times. Optionally save and share it.

**Why.** The 42 drills cover fundamentals, but everyone has a corner they keep messing up.
Practising *that* corner, repeatably and measured, is what a rally school can't offer at home.

**What already helps.**
- Marking in the world already works: **Mark start**, **Mark finish / stop zone / stop
  line**, **+ Gate**, saved per map (`store.lua`), drawn in the world (`course.lua`).
- Run timing, Retry, per-attempt telemetry records and progress already exist.
- 18 rule types already exist (`R.TYPES`), each with readable reasons. A builder mostly
  lets the player pick from them and set numbers.
- The drill schema is data (`exercises.json`), and the Academy screen lists drills from data.

**Hard parts.**
- **Where custom drills live.** A player file (e.g. `settings/rallyAcademy/customDrills.json`)
  merged with the built-in catalogue, with IDs that never clash. Plus versioning when the
  schema changes.
- **A builder UI** that's quick on a rig: place gates while driving (we have that), and choose
  rules with sensible defaults rather than a form full of numbers.
- **Free placement** (gates off the current car position, moving or deleting one gate) needs
  a camera-based editor or the game's own editor tools.
- **Sharing** means validating untrusted files and coping with maps a recipient doesn't have.

**Rough shape.**
1. "Custom drill" in the Academy: start, any number of gates, optional finish. Judged on time,
   with "stay on the road" and "no damage" toggles. Saved locally.
2. A rule picker with defaults per rule type.
3. Export and import as a small JSON file.

Prior art: the game's race and Rally editors, and the community
[Rally Stage Creator](https://www.beamng.com/resources/rally-stage-creator.39134/) mod
([PRIOR_ART](PRIOR_ART.md)).

## Attempt replays and telemetry charts

**The idea.** For any past attempt, show what happened: speed and brake traces along the
run, wheel lockups, slip angle, where each gate was crossed. Compare two attempts on one
chart. Maybe link to the game's replay of that attempt.

**What already helps.** Each attempt already records 30–60 Hz telemetry (`runRecord.lua`).
The Analysis tab exists and already says this is coming. The game has a replay system.

**Hard parts.** Today only the latest run is kept. Storing history means deciding size limits
(about 1 MB per minute of JSON) and pruning. Charts must work inside the game's UI with no
build step.

## Ghost of your best run

**The idea.** A translucent marker (or a full ghost car) showing where your best attempt was
at this moment in the run. Also in ROADMAP P5 as "optional ghost comparison".

**What already helps.** Recorded positions with time stamps; `debugDrawer` for drawing a
marker; the game's own time-trial ghosts as prior art.

**Hard parts.** Lining runs up by distance rather than time, so a slow start doesn't wreck the
comparison. A full ghost car is far more work than a marker.

## AI demonstration lap

**The idea.** Before you try a drill, watch the game's AI drive it, from a camera you choose.

**What already helps.** The game's AI can be scripted to follow a path (`set_ai`, `drive_to`
through the MCP server; `ai` in vehicle Lua).

**Hard parts.** The AI drives neatly, not like a rally driver: threshold braking, Scandinavian
flicks and left-foot braking aren't its style. It may teach the wrong thing for half the
drills.

## Sharing drills and scores

**The idea.** Share custom drills, or compare your block results and best times with friends.

**Hard parts.** Needs a server or a manual file exchange, plus trust and cheating questions.
Probably only worth it after the exercise builder exists.

---

## Stream Deck plugin with live keys

**The idea.** The Stream Deck keys show the session, not just labels: the run timer, the phase,
the last medal, the auto-retry countdown, the selected drill's name on the Next/Previous keys,
Auto-retry lit when it's on.

**Why.** On a rig you can't read a small HUD panel mid-drill; a glance down at the deck is easy.

**What already helps.** Every command is already an input action with a default F13–F24 key
([STREAM_DECK](STREAM_DECK.md)), and Lua publishes the full state (`rallyAcademyState`).
OutGauge shows the game can send UDP to local tools; a 2023 community plugin
([streamdeck-beamng](https://github.com/tomaszpieczykolan/streamdeck-beamng)) reads OutGauge
for a speedometer key.

**Hard parts.** A Stream Deck plugin (Elgato SDK, Node/TypeScript) to write, package and keep
working across Stream Deck updates. The mod needs a small local channel: GE Lua sending state
as UDP to localhost (check that the game's Lua has sockets) or the plugin reading a file.

**Rough shape.** The mod sends a short JSON state over UDP to `127.0.0.1` when it changes; a
plugin with one "Rally Academy status" key shows phase, timer and medal. Commands stay as
hotkeys.

---

## Template

```markdown
## Name

**The idea.** What it is, from the player's side.

**Why.** What it would improve, for whom.

**What already helps.** Code, data or game features we'd build on.

**Hard parts.** What makes it big or risky. Be honest.

**Rough shape.** If we ever did it, the smallest useful first step.
```
