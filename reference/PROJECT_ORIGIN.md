# Project origin

The project started as a ChatGPT conversation ("Rally Sim Learning Resources",
shared link: https://chatgpt.com/share/6ace9a8c-5748-83e9-8c48-e85166470fe8)
and moved to Claude for implementation on 2026-10-13. This file records what
that conversation decided, so the context doesn't depend on the link staying up.

## 1. Rig controls for fast practice

- The key practice loop is "save position → drive → return". BeamNG's default
  bindings: `Ctrl+Home` save position, `Home` return to it, `Insert` repair,
  `Shift+C` free camera, `F7` teleport car to camera, `M` map, `E` radial
  menu, `J` pause physics.
- Recommendation: put Return (`Home`) on a wheel button, and other actions on a
  Stream Deck (15-key or XL), plus a small wireless keyboard/touchpad for menus.
  Stream Deck Mobile is a free way to trial the layout.
- This is why the mod exposes Retry / Pass / Miss as bindable actions.

## 2. Curriculum research

Rally-school syllabi itemized and compared:

- **Richard Burns Rally** (2004): 17 lessons. Basic (controls, gears, gravel
  brake test, road positioning, qualification, passenger ride) and Advanced
  (gravel handbrake, left-foot braking, throttle oversteer, powerslide, tarmac
  handling/braking/handbrake, soft vs hard suspension figure-eights,
  Scandinavian flick, stage trial with pacenotes).
- **EA SPORTS WRC**: 12 lessons × asphalt/gravel/snow (adds regularity, stage
  obstacles, hybrid).
- **DiRT Rally 2.0 / Jon Armstrong**: 7 video lessons, 26 topics (drive
  types, surfaces, camber, jumps, punctures).
- **DiRT 4 Academy**: category-level structure only.
- **DirtFish** 3-day: skidpad, slalom, trail braking, Boneyard, pendulum,
  linked corners, the Grid, the Wedge, Mill Run.
- **Team O'Neil** 5-day: a 39-skill matrix, used as the backbone for progression.

Gaps in RBR that the synthesis fills: isolated trail braking, understeer
recovery, standalone countersteer drills, crests/jumps, camber and elevation,
snow, linked corners, pacenote drills, FWD/RWD/AWD technique, mistake recovery.

Suggested weighting: Team O'Neil for progression, DirtFish for exercise
design, RBR for isolated manoeuvres, EA WRC for surface repetitions, Jon
Armstrong for explanations.

## 3. Drill library

Synthesised into **48 skills in 6 modules of 8** (A Foundations, B Grip &
braking, C Rotation & slides, D Complex cornering, E Terrain & drivetrains,
F Stage performance), each turned into a self-built Free Roam drill with a
fixed car/config, official map area, reset point, scored attempts (mostly
8/10), and per-repetition PASS criteria. Output: the spreadsheet in this folder.

Maps used: ETK Driver Experience Center, Automation Test Track (aerodrome,
handling circuit, rally track), Utah, Italy, Johnson Valley, Utah NGRC Rally
Mode stages (v0.39), optional Winter West Coast mod.

Proficiency idea not yet implemented: three levels per skill (e.g. complete →
controlled → consistent exit speed/time).

## 4. "First-class mod" plan

ChatGPT produced the starter scaffold (imported as v0.1.0) and a roadmap
(P0–P5, now in docs/ROADMAP.md) with a target architecture (now in
docs/ARCHITECTURE.md). It said itself that the scaffold had never been run in BeamNG.
