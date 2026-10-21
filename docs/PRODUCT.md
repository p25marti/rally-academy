# Product direction

What Rally Academy is for, who it's for, and the owner's standing decisions. Read this
before proposing features or UI. The *why* behind bigger technical choices is in
[decisions/](decisions/).

## What it is

Structured rally-driving practice for BeamNG.drive: short, repeatable drills that build
car control step by step. Load a drill, drill it many times in a row, then move on.
Automatic grading turns each run into specific coaching ("Front-right wheel locked for
1.9 s from 62 km/h"), not just a time.

## Who it's for

Sim-racing players who want to get better at rally driving. It's designed and tested on a
full rig: wheel, sequential shifter, handbrake, three pedals, and BeamNG's **realistic**
gearbox. It must also work on a keyboard or gamepad, but the rig is the reference.

## Standing decisions

| Decision | Detail | Since |
| --- | --- | --- |
| Car control is the scope; full stages are the game's | Stage drills were cut. The Academy points to the game's Rally mode ([ADR 0006](decisions/0006-stages-are-the-games-rally-mode.md)) | 2026-10-16 |
| Nothing is locked | Any drill can be tried; drills are **listed** in curriculum order (A01 → F07) | 2026-10-15 |
| Native BeamNG look | Use the game's own components and `--bng-*` colours, not a custom theme | 2026-10-15 |
| FWD first | Every active drill pins a FWD Covet; drills that need RWD/AWD are parked and labelled. Same drill on several drivetrains is a later ladder ([VEHICLES](VEHICLES.md)) | 2026-10-14 |
| Venues: Option A | West Coast USA (BMP) as home base, Utah for longer routes; bespoke per-drill areas may come later ([MAPS](MAPS.md)). Superseded by "Every drill on the proving ground" below | 2026-10-14 |
| Our own proving ground | A generated map of flat surface pads and road shapes for drills whose mechanic needs flat, single-surface ground; real-road features stay on stock maps. Per-surface variants are next ([ADR 0008](decisions/0008-proving-ground-map.md)) | 2026-10-19 |
| Every drill on the proving ground | Every exercise runs on our own map; crests, hills, camber, a jump, rough ground and water are built as terrain features in areas of their own, so the flat drill areas stay flat. Stock maps are now only sources for course shapes, and their venues are gone from `venues.json` ([ADR 0010](decisions/0010-every-drill-on-the-proving-ground.md)) | 2026-10-20 |
| Our own HUD layout | The mod ships **Rally Academy HUD** (the panel, a Coach with instructions and grades, an Inputs graph, the stock dash) and switches to it on the proving ground; players customise it without touching their other layouts, or turn the switch off ([ADR 0012](decisions/0012-own-hud-layout.md)) | 2026-10-21 |
| Curriculum tidy-up | E01 (surfaces: every corner drill has variants) and B08 (C01 and C02 side by side) cut; C08 and B04 move off the shared corner; A07 shows no racing line, choosing it is the drill ([ADR 0014](decisions/0014-curriculum-tidy-up.md)) | 2026-10-21 |
| Racing line on request | **Show line** (HUD button, Shift+F15) draws the drill's racing line on the ground, red to brake, yellow to hold, green to accelerate; off by default and remembered. **Watch AI** has the game's AI drive it: graded, never counted, and only on drills where its run passes ([ADR 0013](decisions/0013-racing-lines-from-the-map-builder.md)) | 2026-10-21 |
| Surface variants | The same drill on dirt, gravel, asphalt and snow: each surface its own drill (`A01-snow`) with its own progress and medals, picked with a Surface row; targets differ only where the physics demands it. Module A first ([ADR 0009](decisions/0009-surface-variants.md)) | 2026-10-20 |
| "Implemented" means auto-graded | Drills without automatic grading show **Coming soon** but stay playable with Pass/Miss | 2026-10-15 |
| Keep the HUD drop-down | Drill selection stays on the in-drive panel too; moving it fully into the menus is an open question | 2026-10-15 |
| Lua is authoritative | The UI shows Lua's state and sends commands; no logic lives only in the UI ([ARCHITECTURE](ARCHITECTURE.md)) | from the start |
| Drills set themselves up | Where a drill's layout is fixed, it is **authored course data** (gates, cones, a box) laid out from the venue start: Go to drill lands you ready to drive. Markers were drawn at first; since 2026-10-20 real cones and posts stand at them and touching one is what counts ([ADR 0011](decisions/0011-physical-course-markers.md), [DRILL_DATA](DRILL_DATA.md#authored-courses)) | 2026-10-16 |
| Medals | Graded drills can award **bronze / silver / gold**: a pass is bronze; silver and gold tighten the targets (a smaller box, a time). Block targets (8/10) still count passes ([GRADING](GRADING.md#medal-tiers)) | 2026-10-16 |
| Auto-retry on by default | After an auto-graded run the next attempt starts after 3 s; driving off cancels it, it waits while a zone or gates still need marking, and a HUD toggle turns it off (remembered) | 2026-10-16 |
| Keep integrations simple | External controls (Stream Deck, button boxes) go through game input actions and default keys (F13–F24). A local HTTP command server was built and rolled back the same day: more moving parts than it was worth ([STREAM_DECK](STREAM_DECK.md)) | 2026-10-16 |
| Grading explains itself | Every check returns a readable reason with numbers; that reason is the coaching ([GRADING](GRADING.md)) | 2026-10-15 |

## Where it's going

[ROADMAP](ROADMAP.md) has the order; bigger someday ideas are in [IDEAS](IDEAS.md). In short:

1. Grade more drills automatically, venue by venue.
2. Authored courses for the rest of the fixed-layout drills (A01 has one), then scene
   control: the mod places real cones, so hitting one is physical, not just measured.
3. Promote captured setups into the drill data, so drills work without marking.
4. Coaching and progression: per-attempt history, a recommended next drill, drivetrain
   variants.

## How it was built

The first versions (scaffold → grading, menus, Vue UI) were built in one long session with
an AI assistant (Claude), with the owner testing on the rig. That's why the docs are
detailed and why so much is recorded as "verified 0.39.4" in
[BEAMNG_API_NOTES](BEAMNG_API_NOTES.md): every engine behaviour was checked in-game,
usually by script through the game's MCP server. The history is in the
[CHANGELOG](../CHANGELOG.md), the ADRs and `git log`.
