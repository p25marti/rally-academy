# Finding and adding a venue

How to find a good place for a drill, prove it works, and make the drill use it. Every
step runs against the live game; the tools are in `tools/ingame/`.

Since 2026-10-20 every shipped venue is on the proving ground ([ADR 0010](decisions/0010-every-drill-on-the-proving-ground.md)):
a new place is usually built in `tools/mapgen/proving_ground.json` and then proved here. The survey tools still
work on stock maps, which is how a real road's shape is found and copied.

```
 find candidates  ──▶  review them  ──▶  prove the best  ──▶  add it to venues.json
 (drive + bookmark,     (venue report:    (fit test: drive     (drills refer to it,
  finders, `fits`)       pictures, fits)   the drill's run)     validate, Go to drill)
```

## Before you start

- BeamNG.drive 0.39+ running, the mod linked (`python tools/dev.py link`), and the map you
  want to survey loaded with a car. The tools talk to the game's MCP server on
  `127.0.0.1:29292`.
- Bind **Rally Academy: Save spot** in Options → Controls (a wheel button works well).
- Know what the drill needs. Every drill has an `environment.venueNeeds` block in
  `mod/gameplay/rallyAcademy/exercises.json`: the shape of place (straight, corner, open
  area, hill, crest or route), length, width, radius, grade, allowed surfaces, and things to
  check by eye ([DRILL_DATA → Venue needs](DRILL_DATA.md#venue-needs)).

## 1. Find candidates

Use any mix of these.

**Scan the whole map's surfaces (fastest).** `python tools/ingame/scan.py [--level NAME]` reads the
terrain's own material map and heights from inside the game, a million points in a few seconds with no
driving, and writes `venue-reports/<map>/scan/index.html`: the map coloured by surface (flat ground on
the chosen surfaces bright, candidates outlined and numbered), the map's surface totals, and a card per
candidate with its biggest flat square, slope, bumps, room to the nearest object, an aerial view and a
`--at` pose for the fit test. Flat means flat at a car's scale: slope across 20 m (5 % by default) and
no point more than 0.25 m off the mean height within 9 m. Patchwork textures count when 70 % of the
ground within 5 m is on the surfaces. `--surfaces grass` (or any families) looks for other ground,
written to `scan-<surfaces>/`; `--aerial 0` leaves the camera alone.
Each candidate is then checked against the physics surfaces, the way BeamNG's Groundmodel Debug panel
reads them (`tools/ingame/surface.py`): what the car would actually drive on there, terrain and meshes
together, its grip, and how many obstacle triangles (metal, wood) sit on it. A texture that looks like sand
can be asphalt to the physics.
Limits of the grid: it reads terrain textures. Roads and buildings sit on top; trees are objects on grass
terrain. Each candidate's room (horizontal rays from its centre, under
20 m = "cluttered") and the aerial view catch most of that. Rivers aren't masked (water planes and water
blocks are). First runs (0.39.4): West Coast USA's best flat loose square is 48 m of dirt in the BMP
oval's infield; nefr is 98 % grass terrain, with only small dirt patches, but has flat open grass fields.

**Drive and bookmark.** Drive the map as normal and press **Save spot** wherever a drill
could work. Each press records your position and heading, the room to walls and barriers
in eight directions, the slope, the nearest road's width, and the surface under each wheel.
A message confirms it, for example "Spot 3 saved: room ahead 120 m, behind 80 m; road 9.0 m
wide; slope 0.8°". Spots go to `<user folder>/settings/rallyAcademy/spots.json`.
`python tools/ingame/survey.py spots` lists the ones on this map.

**Search for a specific drill.** The quickest route when you know which drill you're placing:

```sh
python tools/ingame/survey.py fits D03              # places on this map matching D03's venueNeeds
python tools/ingame/survey.py fits B01 --measure 5  # and check the best five on site
```

`--measure` drives the car to each of the best candidates to read the real surface and
room. Places on loose surfaces rank above tarmac.

**Browse by shape.** The finders search the map's AI road network, with no driving:

```sh
python tools/ingame/survey.py straights --min-length 150   # braking and speed drills
python tools/ingame/survey.py corners --max-radius 40      # radius, direction, hairpin / decreasing / increasing
python tools/ingame/survey.py hills                        # climbs and descents
python tools/ingame/survey.py crests                       # crests and jumps
python tools/ingame/survey.py open                         # open, flat, loose ground (terrain scan, slow)
```

Each result prints an `--at=X,Y,Z,DX,DY` pose (and `--to NODE` for road sections) that the
later steps take.

## 2. Review them

```sh
python tools/ingame/survey.py report            # add --open for open areas, --quick to skip measuring
```

This writes `venue-reports/<map>/index.html`, one self-contained page you can open or share
(it isn't committed). It shows your saved spots plus the finders' best, one card each:

- an **aerial view** (taken with the HUD hidden);
- the numbers: length, width, radius, grade, **measured surface**, room in four directions;
- **fits**: drills whose needs the place meets;
- **maybe (by eye)**: a saved spot can't prove there's a corner, hill or crest, so those
  drills are listed here for you to judge from the picture;
- **nearly**: drills it misses by one thing, and what ("needs 8 m wide, is 7.3 m");
- **check by eye**: the drills' features, such as runoff, camber or a water crossing;
- the command to go there.

The report moves the car and camera around, then puts them back. It also moves the game's
screenshot copies out of your user folder into the report folder. With `--quick` the car isn't
moved, surfaces aren't measured, and "fits" ignores surface.

## 3. Go and look

```sh
python tools/ingame/survey.py goto 3                                   # a saved spot
python tools/ingame/survey.py goto --at=-477.46,-627.93,141.04,-0.9484,0.3172   # a find
python tools/ingame/survey.py here                                     # room and surface where you are
python tools/ingame/survey.py surfaces --along=20,60 --side=-8,0,8     # surface grid across the road
```

Drive it yourself too. The numbers can't tell you whether a corner is fun or the sightlines
make sense.

## 4. Prove it with a fit test

```sh
python tools/ingame/survey.py fit C04 --spot 3
python tools/ingame/survey.py fit C04 --at=-477.46,-627.93,141.04,-0.9484,0.3172 --to DR817_13
```

The fit test drives the drill's kind of run at the place:
- **straight:** a scripted run to the drill's entry speed, then threshold braking;
- **corner, hill, crest, route:** the game's AI drives along the road (to `--to`, or as far
  as the drill needs, following the road the way the car faces);
- **open area:** a steady circle sized to the drill.

It then prints **FITS** or **DOES NOT FIT** with the reasons: contact, rolling over,
leaving the drill's allowed surfaces, needing more length than the drill allows, or a
start spot the game had to nudge the car off. Nothing is saved to your drills or progress,
and the car is put back where it was, repaired.

## 5. Add it to venues.json

Venues are shared data: `mod/gameplay/rallyAcademy/venues.json` ([ADR 0007](decisions/0007-venues-as-data.md)).
If the place is a spot on an existing venue (another corner at the BMP gravel track, say),
skip to step 6. For a new venue, add an entry:

```jsonc
{
  "id": "wcusa-quarry-hairpin",        // short, unique; drills refer to this
  "mapsId": "W7",                      // the row you'll add to MAPS.md
  "name": "West Coast USA: Quarry hairpin",  // shown in the HUD and the Academy
  "levelId": "west_coast_usa",         // the map's folder name (survey.py levels)
  "spawn": {                           // where Go to drill puts the car
    "pos": {"x": -477.46, "y": -627.93, "z": 141.04},
    "dir": {"x": -0.9484, "y": 0.3172, "z": 0},
    "up":  {"x": 0, "y": 0, "z": 1}
  },
  "notes": "Gravel hairpin, radius ~14 m, 8 m wide; fit-tested for C04."
}
```

The spawn is a default spot that's easy to reach. Players still press **Mark start** for
the exact start (that's saved per player, per map). A saved spot's `pos` and `dir` from
`spots.json` drop straight in.

## 6. Point the drills at it

In `exercises.json`, set the drill's `environment.venue` to the venue's id and update its
`areaHint` (where on the venue, for this drill). Adjust `venueNeeds` if you learned
something, and rule settings that depend on the place, such as `on_surface` surfaces.

## 7. Check and record

After moving a drill, or after a game update, `python tools/ingame/audit.py --write` re-measures every
graded course along its recorded line and regenerates [COURSE_AUDIT](COURSE_AUDIT.md): surfaces and grip,
rise, steepest grade and tilt, with a note where hills, camber or a mixed surface blur the drill.

```sh
python tools/dev.py validate     # venue well formed, every drill's venue found, no leftover copies
```

Then in the game: select the drill, press **Go to drill**, and check you land at the venue in
the drill's car. Add a row to [MAPS.md](MAPS.md) for a new venue (id, where, surface,
notes) and a CHANGELOG line.

## The venue catalogue

`tools/ingame/catalog.py` surveys a whole map in one go and keeps the results in the repo, by the
**surface you actually drive on** (tarmac, gravel, dirt, snow, ice…) and kind of place (open
ground, straight, corner, hairpin, hill, crest):

```sh
python tools/ingame/catalog.py scan --per-kind 20 --fits 2   # the loaded map (30-60 min)
python tools/ingame/catalog.py scan --community              # a map players must install
python tools/ingame/catalog.py render                        # rebuild the page from the data
```

It runs the road finders and an open-ground scan on every surface (plus wide road-network nodes,
which is how car parks and paved pads show up), places the car at each spot to read the wheels'
surfaces, room and slope, then fit-tests the best spots of each kind on each surface, judging
"stayed on the road" against that spot's own surface. Results: `docs/venue-catalog.json` (data,
one entry per map, replaced on a re-scan) and [VENUE_CATALOG.md](VENUE_CATALOG.md) (generated).
Use it to find a venue fast, or, later, to offer a drill on the surface a player picks.

## Command reference

| Command | What it does |
| --- | --- |
| `survey.py spots [--all]` | Saved spots on this map (or every map) |
| `survey.py fits <drill> [--measure N]` | Places on this map that meet a drill's venueNeeds |
| `survey.py straights / corners / hills / crests` | Road sections from the AI road network (`--limit`, `--min-length`, `--max-radius`) |
| `scan.py [--level NAME] [--surfaces …] [--aerial N]` | Whole-map surface and flatness scan with a report ([above](#1-find-candidates)) |
| `audit.py [--write]` | Every graded drill's course: physics surfaces and grip along the driven line, rise, grade, tilt ([COURSE_AUDIT](COURSE_AUDIT.md)) |
| `surface.py` | The ground models' friction table (the module also counts surfaces around any point) |
| `survey.py open [--step 16]` | Open, flat, loose areas from a terrain scan (slow; `scan.py` supersedes it) |
| `survey.py report [--quick] [--open]` | The HTML venue report |
| `survey.py goto <id>` / `goto --at=…` | Put the car on a spot or a pose |
| `survey.py here` | Room in eight directions and the surface under each wheel |
| `survey.py surfaces --along=… --side=…` | Surface grid ahead of and across from the car |
| `survey.py fit <drill> --spot ID / --at=… [--to NODE]` | Fit test: drive the drill's run there |
| `survey.py terrain X Y …` | Terrain ground model at points (doesn't see road meshes) |
| `catalog.py scan [--per-kind N] [--fits N] [--community]` | Catalogue the loaded map by surface and kind ([above](#the-venue-catalogue)) |
| `catalog.py render` | Regenerate VENUE_CATALOG.md from the data |
| `survey.py configs [model]`, `survey.py levels` | Car configs, installed maps |

All are `python tools/ingame/survey.py …`, run from the repo root.

## Where things live

| What | Where |
| --- | --- |
| Venues the drills use | `mod/gameplay/rallyAcademy/venues.json` |
| What each drill needs | `environment.venueNeeds` in `mod/gameplay/rallyAcademy/exercises.json` |
| Your saved spots | `<user folder>/settings/rallyAcademy/spots.json` |
| Venue reports | `venue-reports/<map>/index.html` (local, not committed) |
| Survey notes and venue ideas | [MAPS.md](MAPS.md) |
| Every catalogued spot, by surface | [VENUE_CATALOG.md](VENUE_CATALOG.md), data in `docs/venue-catalog.json` |
| The tools | `tools/ingame/survey.py`, `roads.py` (finders), `venues.py` (matching), `fit.py` (fit test) |

## Gotchas

- **The road network isn't all rally roads.** It includes bridges, car parks, loops and
  ramps. The longest "straight" on West Coast USA is a bridge, which is why the report shows
  pictures.
- **Drivability isn't a surface.** The road network's drivability is a road class (the asphalt
  BMP straight is 0.5). Trust the measured surface instead.
- **"Room" is to the first static object at bumper height.** A sign, gantry or pole can make it
  read short; the fit test actually drives, so it's the better judge.
- **Terrain scans miss roads.** `open` and `terrain` read the terrain only, not road meshes or
  buildings on top. Check finds with `here` or a fit test.
- **Map loads take a minute** and the tools can't reach the game meanwhile.
