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
| [AI demonstration lap](#ai-demonstration-lap) | Suggested | Medium | Built (Watch AI, five drills) |
| [Demo cutscenes](#demo-cutscenes) | Owner | Large | Spiked 2026-10-30 |
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

**Why.** The drills cover fundamentals, but everyone has a corner they keep messing up.
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

## Choose your surface

**The idea.** A drill offers the same exercise on different surfaces: handbrake turns on tarmac,
dirt or snow; threshold braking on asphalt, gravel or ice. Pick one in the menu and Go to drill
takes you to a matching spot.

**Why.** Car control changes a lot with grip; practising the same technique across surfaces is
how rally schools teach it (the surface variants already touch this).

**What already helps.** The [venue catalogue](VENUE_CATALOG.md) lists measured, fit-tested spots
per surface and kind on each surveyed map (`docs/venue-catalog.json`, from `catalog.py scan`).
Venues are data ([ADR 0007](decisions/0007-venues-as-data.md)) and drills already declare the kind of
place they need (`venueNeeds`). Each surface's friction is readable in game (`core_environment.groundModels`, table in
[COURSE_AUDIT](COURSE_AUDIT.md)), so per-surface thresholds could scale with grip (a stop zone on ice, static
friction 0.40, against gravel's 0.68) instead of being tuned by hand per surface.

**Hard parts.** Per-surface thresholds (a stop zone on ice is longer), progress per surface, more
map loads (snow and ice are on Automation Test Track), and authored courses fitting each spot.

**Rough shape.** `environment.venues: {tarmac: id, dirt: id, snow: id}` on one drill (handbrake
turns first), a surface picker in the HUD and Academy screen, and per-surface progress.

---

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

## Demo cutscenes

**The idea.** When you open a drill, a third-person demo shows a run that passes, like a cutscene. It stops at
the moments that matter and explains the inputs: for a Scandinavian flick, a freeze as the brake loads the front,
another as the steering reverses and the weight swings the rear out. Owner's idea (2026-10-30).

**Why.** Watch AI only works where the game's AI can drive the drill (five road drills). The techniques that most
need showing (flicks, handbrake turns, trail braking, donuts) are exactly the ones it can't do.

**What already helps.** Scripted runs that pass every drill (`tools/ingame/scenarios.py`, including in-car
controllers for the donut); run records with every input at about 30 Hz; the input graph; the racing line.

**Spike (2026-10-30, 0.40.4, C08).** Two ways to play back a run were tried:

- *The game's replay system* (`core_replay`, details in [BEAMNG_API_NOTES](BEAMNG_API_NOTES.md)). Recorded a
  scripted C08 bronze, then played it from a copy in the mod's own `replays/` folder. Playback is exact (it's the
  recorded physics), and it can pause, run at 1/4 speed, step to the exact frame and be filmed from any free camera.
  Stopping gives the player their own car back. Costs and catches:
  - Size: about 240 kB per second of driving. A trimmed 12 s demo is about 3 MB (about 1 MB zipped); 40 drills would
    add about 40 MB to the download.
  - The car's inputs aren't replayed (vehicle Lua doesn't run), so the input graph and the cue text must come from the
    run record saved with the demo, lined up by time.
  - The mod graded the replay car as a live run (it added an attempt to C08's progress, since undone). A demo phase
    that ignores the car is required.
  - Files name the level and the car config, and hold that car's node data: an update to the Covet or the proving ground
    probably breaks them. They'd be re-recorded from the scenarios after updates (a `record_demos.py`).
- *Replaying the recorded inputs* (an in-car player feeding throttle, brake, handbrake and steering every frame, the
  way `_DONUT_LUA` drives). The inputs came back within about 0.01 of the original, but the car didn't follow: five
  replays all drifted 12 m right on the 70 m straight and missed gate 2 by 10 m, before the flick. Small
  differences at launch compound. Open-loop inputs alone can't make a demo; it would need the scenario's closed-loop
  steering (pure pursuit) with the pedals replayed. That's what the scenarios already do, and they pass only some
  of the time (C08: up to five tries), so a live demo could fail on screen.

**Hard parts.** The size and update fragility of replays; the timing of cues against a replay; a camera that frames
the car well (a fixed trackside camera works for one corner; a moving one needs a path); the demo must never touch
progress.

**Rough shape.** One drill (C08) end to end with replays: `record_demos.py` saves the `.rpl` trimmed to the run, plus
its run record and cue times; a demo phase in the mod suspends run detection, plays at full speed from a chase
camera, then at each cue slows to 1/4 and freezes with a card and the input graph; a key continues or skips. The
first time a drill is opened it plays automatically; after that it's a button.

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
working across Stream Deck updates. The mod needs a small local channel (GE Lua has LuaSocket);
a local HTTP command server was built once and rolled back to keep things simple (commit
2aa3530 has it), so this needs the owner's go-ahead first.

**Rough shape.** The mod sends a short JSON state over UDP to `127.0.0.1` when it changes; a
plugin with one "Rally Academy status" key shows phase, timer and medal. Commands stay as
hotkeys.

---

## Learning materials (surfaces first)

**The idea.** Supplementary material for drivers who want to understand the *why* behind the drills,
starting with surfaces: what each one is, how much grip to expect, and how that changes braking distance,
cornering speed and car control. A graphic first; later the same material inside the game (an "Learn"
page in the Academy screen, or a card shown before a drill that depends on the surface).

**Why.** The drills teach by doing; a driver who knows that gravel gives about 70 % of tarmac's grip and ice
about 40 % reads a stop zone or a corner speed better. The owner asked for this (2026-10-19).

**What already helps.** Real in-game numbers: every ground model's static and sliding friction, roughness and
loose depth from `core_environment.groundModels` (`python tools/ingame/surface.py` prints them; the table is
in [COURSE_AUDIT](COURSE_AUDIT.md)). Gravel 0.68 / dirt 0.69 / dusty dirt 0.68 / grass 0.61 / sand 0.60 /
mud 0.55 / snow 0.64 / ice 0.40 static friction against asphalt's 0.98 (0.40.0). Braking distance scales
roughly with 1/friction, so these turn into "stops in N m from 60 km/h" figures.

**Hard parts.** Friction is only part of the story (loose depth and roughness change how a surface feels,
tyres matter), so the material must not overclaim. In-game pages need design work to fit the Academy screen.

**Rough shape.** First step (logged for later): one graphic, a surface-by-surface chart of expected traction
using the real in-game numbers, with plain-language notes (what it feels like, what to change). Then a
"Learn" section in the Academy screen showing it, and short surface cards linked from the drills that use them.

## A Rally Academy proving ground (our own map)

**Status: accepted** (2026-10-19, [ADR 0008](decisions/0008-proving-ground-map.md)); it's on the
[ROADMAP](ROADMAP.md) now. The notes below are the research and prototype that led there.

**The idea.** One custom map built for the drills: dead-flat pads, straights and skidpads, standard corners
(constant, tightening, opening, hairpin), measured hills and a crest or jump, each laid out exactly as its
drill needs. The same layouts repeated on several surfaces give per-surface variants: handbrake turns on
gravel and on snow, threshold braking on asphalt, gravel and ice. Owner's idea (2026-10-19).

**Why.** The course audit ([COURSE_AUDIT](COURSE_AUDIT.md)) shows how much stock venues blur the mechanics:
the BMP downhill corner (seven drills) drops 14 m at up to 35 %, braking drills crossed tarmac patches, and
West Coast USA has little flat loose ground (`scan.py`). Our own map would be flat where a drill wants flat,
one surface where it wants one surface, identical between surfaces, quick to load (stock maps take 40-130 s)
and free of traffic and props. Medals and fixtures would compare like with like.

**What already helps.**
- The stock `template` level (`content/levels/template.zip`, 0.40) is BeamNG's starting point for new maps:
  its terrain comes from a heightmap image and one mask image per terrain material (`art/import/*.png`), and
  textures can be `.dds.link` files pointing at stock assets, so a map needn't copy them. We already write
  PNGs from Python (`scan.py`), so heights and surface layouts could be generated from data and kept in git.
- Surfaces are ground models with real friction (SNOW 0.64 static / 0.40 sliding, ICE 0.40, GRAVEL 0.68, DIRT
  0.69, ASPHALT 0.98, MUD 0.55 with 0.15 m of loose depth, SAND 0.60): a terrain material just names one.
- Venues are data ([ADR 0007](decisions/0007-venues-as-data.md)); a variant could be a venue per surface pad.
  `surface.py` / `audit.py` would verify each pad's surface, flatness and grip after every game update.
- Mods can ship levels (`levels/<name>/` in the zip; the community maps we use do).

**Hard parts.**
- Authoring: the terrain import, painting and road objects happen in the World Editor; scripting all of it is
  possible (heightmap and masks as images, roads and props as `items.level.json` objects) but is real work.
  A believable-looking map (backdrop, foliage, lighting) is far more work than a functional one.
- Game updates: levels lean on stock assets and formats, and 0.40 alone cleaned up assets and terrain. We'd
  re-check the map after each update (the audit helps).
- Size and load: a 1 km terrain is a few MB; textures linked, not copied. Must stay a small download.
- Variants touch the drill model: progress and medals per surface, thresholds per surface (scale with
  friction?), menu choice ([Choose your surface](#choose-your-surface) is the same idea from the menu side).
- Stock maps still matter for "real road" drills (D02, D05, stages); the map complements them.
- A large, one-way-ish choice: needs an ADR and the owner's go-ahead before building.

**Feasibility.** Feasible, medium to large. The functional core (flat pads of known surfaces, painted lines
drawn by the mod) is within reach because the template takes generated images; looks and maintenance are the
real cost.

**Lifecycle and tooling (researched on 0.40.0, 2026-10-19).**
- *Tools:* the in-game World Editor (Terrain Editor: import, sculpt, paint; Decal Road, Mesh Road and Road
  Architect editors; forest/biome, material and mesh editors; a level validator), plus the Terrain and Road
  Importer (`editor/terrainAndRoadImporter.lua`: heightmap PNG + roads JSON, conforms the terrain to the roads).
- *Scriptable from our tools:* the editor is Lua in the same VM the MCP server runs. Checked: live
  `TerrainBlock:setHeight` + `updateGrid` from MCP (heights are relative to the block's origin z), and the
  import is one call (`TerrainBlock:importMaps(heightmap, metresPerPixel, heightScale, holeMap, materials,
  textureMaps, flipY)`); levels save with `editor.saveLevelAs`. No dedicated map-building MCP tools; thin
  helpers in `tools/ingame/` would do it, as `scan.py` does for surveys.
- *Files:* a level is plain files: the template's `theTerrain.ter` (3 MB, 1024 x 1024 m at 1 m, 4 materials),
  `items.level.json` object lists, material JSON, `info.json`. All generatable from code and diffable in git.
- *Load time:* the template loads in about 8 s (West Coast USA: 24 s warm, 142 s on 0.40's first load).
- *Testing:* the tools we have (`audit.py`, `scan.py`, `surface.py`, scenarios, `record.py`) work on any map.
- *Assets:* shared packs in `content/assets/` (467 meshes: architecture, rocks, foliage, props), stock terrain and
  road materials and the 32 ground models. Mods can't create `.link` files yet (BeamNG says a tool is coming),
  so a map references stock files by path (they can move between versions) or copies them (bigger download;
  check BeamNG's terms before shipping copies).

**Rough shape.** A prototype: a 1 km² flat map from the template with three surface pads (gravel, asphalt,
snow) generated from images, linked textures only. Move B01 (braking) and C04 (handbrake hairpin) onto it
with one variant per surface, measure every pad with `audit.py`, and compare load time and feel against the
stock venues before deciding on more.

**Prototype (built 2026-10-19 on 0.40.0, not shipped).** `python tools/mapgen/build.py` writes
`mod/levels/ra_proving_ground/` from `tools/mapgen/proving_ground.json`: a 1 km² flat terrain (z 110 m) with
120 x 700 m strips of gravel, asphalt, snow and dirt and a mud pad on grass, using the template's terrain
materials and sky. (It was kept out of git and the zip until the owner chose to ship it.) Load it with `freeroam_freeroam.startFreeroam('levels/ra_proving_ground/info.json')`.
What we learned:
- *It's cheap.* No World Editor: about 150 lines of Python write every file (terrain, materials, objects). The
  level loads in about 4 s cold and 1 s on reload; editing the layout and rebuilding is a seconds-long loop,
  and the game hot-reloads a changed `.ter` even without a reload.
- *Surfaces are exact.* Wheel telemetry and `surface.py` read 100 % GRAVEL / ASPHALT / SNOW / DIRT / MUD /
  GRASS on the matching pads. Building it found a `surface.py` bug that also skewed the WCUSA audit (terrain
  counted by material name, not ground model): the BMP arena is DIRT_DUSTY (grip 0.68), not DIRT.
- *Gotchas* (in BEAMNG_API_NOTES): unique terrain material names (`ra_*`) and a `MissionGroup` root file.
  A fluid depth map (`.ter.depth.png`) looked needed (the log warns without one), but an all-zero one made
  the wheels sink 0.2 m and the car crawl; the level ships without.
- *Per-surface drills really differ* (scripted, Covet, one run each, so about ±1 m):

  | Pad | B01 at 5 m/s² (Student Driver) | Full brake from 70 km/h | C04 hairpin (Gravel Rally) |
  | --- | --- | --- | --- |
  | Asphalt | gold | 23.9 m (effective μ 0.81) | miss: clipped the cone, 38° slide |
  | Gravel | silver | 26.4 m (0.73) | gold, 31° slide |
  | Dirt | silver | 26.3 m (0.73) | gold, 33° slide |
  | Snow | miss: locked 2.3 s, stopped 5.9 m past | 38.2 m (0.50) | gold, 50° slide |

  So variants need per-surface targets (B01's 5 m/s² is impossible on snow; C04's line overshoots on
  asphalt), probably scaled from each surface's friction.
- *Still open:* looks (a bare grass plane with a hard terrain edge; no backdrop or props), painted
  markings, hills and corners (heights are generated flat; the `.ter` takes any heightmap), and where drill
  venues on it would live (venues.json works as is). The trial script was a scratch file; a real
  per-surface trial tool would come with variants.

## Corner signs for the open-ground courses

**The idea.** The proving ground's roads have rally corner boards and chevrons before every bend; the drills laid out
on open ground (C04's hairpin, C07's figure eight, B05's ring, D01's slalom) have none. Show a board or chevron where
those courses turn.

**Why.** The same immersion on every drill, not just the road ones.

**What already helps.** The courses are authored data drawn by `course.lua`; the boards are stock meshes
(`tools/mapgen/markers.py` names them).

**Hard parts.** Several drills share a pad with different courses, so the signs can't be map props: they would be
drawn or spawned per drill, and PRODUCT says markers are drawn, not spawned, for now.

**Rough shape.** A `sign` marker type in course data, drawn as a flat arrow like the cones, then real meshes if the
owner agrees to spawned props.

## Template

```markdown
## Name

**The idea.** What it is, from the player's side.

**Why.** What it would improve, for whom.

**What already helps.** Code, data or game features we'd build on.

**Hard parts.** What makes it big or risky. Be honest.

**Rough shape.** If we ever did it, the smallest useful first step.
```
