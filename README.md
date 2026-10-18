# Rally Academy for BeamNG.drive

A BeamNG.drive mod for structured rally-driving practice: 42 progressive drills
(foundations → braking → rotation → complex cornering → terrain → adaptation; full
stages are the game's own Rally mode),
instant retry to a marked start, run timing, and per-drill progress tracking.

> **Status: alpha.** Retry, timing, progress, Go to drill and telemetry recording
> run on BeamNG 0.39.4. Fifteen drills (A01–A05, A07, A08, B01, B02, B04–B07, C02, C08) are graded
> automatically from telemetry, A01 with bronze/silver/gold medals; the others use self-assessed Pass/Miss for now. The
> Academy screen lives in the main menu (More... → Rally Academy) and the pause menu;
> see the [roadmap](docs/ROADMAP.md).

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Coding agents: [AGENTS.md](AGENTS.md). Product
direction and the owner's standing decisions: [docs/PRODUCT.md](docs/PRODUCT.md).

## Quick start (developers)

Requirements: Python 3.9+ and git. LuaJIT + luacheck are optional locally
(CI always runs them) — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#tooling).

```sh
python tools/dev.py check      # validate data, lint, unit-test, build dist/rally_academy.zip
python tools/dev.py link       # live-link ./mod into your BeamNG mods folder
python tools/dev.py log        # tail beamng.log, filtered to Rally Academy + errors
```

Then in BeamNG: Free Roam → UI Apps → add **Rally Academy**.

## Install (players)

Download `rally_academy.zip` from the latest GitHub Release and drop it, still
zipped, into `<BeamNG user folder>/mods/`. Don't keep an older copy or the
unpacked dev link alongside it.

## Repository map

| Path | What lives there |
| --- | --- |
| `mod/` | Exactly what ships. Its contents become the zip root (`gameplay/`, `lua/`, `ui/`). |
| `mod/gameplay/rallyAcademy/exercises.json` | The 42 drills — the source of truth for drill data ([schema](docs/DRILL_DATA.md)). |
| `tests/lua/` | Unit tests that run the mod's Lua under LuaJIT with stubbed BeamNG globals. |
| `tools/dev.py` | One CLI for check / build / link / log / bump. |
| `.github/workflows/` | CI on every push/PR; release on `v*` tags. |
| `docs/` | How everything works — start with [DEVELOPMENT](docs/DEVELOPMENT.md). |
| `reference/` | Source material: the original drill spreadsheet and planning history. |

## Documentation

- [DEVELOPMENT.md](docs/DEVELOPMENT.md) — setup, the in-game edit/reload loop, git workflow
- [TESTING.md](docs/TESTING.md) — unit tests, in-game smoke test, what CI checks
- [RELEASING.md](docs/RELEASING.md) — versioning, GitHub Releases, publishing to the BeamNG repository
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the mod is put together, and where it's heading
- [DRILL_DATA.md](docs/DRILL_DATA.md) — drill schema and how to edit drills
- [GRADING.md](docs/GRADING.md) — what automatic grading needs, drill by drill
- [PRIOR_ART.md](docs/PRIOR_ART.md) — BeamNG systems, tools and mods we can reuse
- [VEHICLES.md](docs/VEHICLES.md) — drill cars, what to look for, drivetrain options
- [BEAMNG_API_NOTES.md](docs/BEAMNG_API_NOTES.md) — every engine API we rely on, and whether it's verified
- [ROADMAP.md](docs/ROADMAP.md) — priorities and known issues
- [MAPS.md](docs/MAPS.md) — surveyed venues (gravel/dirt) and where each drill takes place
- [VENUES.md](docs/VENUES.md) — how to find, fit-test and add a venue for a drill
- [VENUE_CATALOG.md](docs/VENUE_CATALOG.md) — measured practice spots on each surveyed map, by surface and kind
- [STREAM_DECK.md](docs/STREAM_DECK.md) — default key bindings (F13–F24) and a Stream Deck layout
- [decisions/](docs/decisions/) — short records of why things are the way they are

## Credits

Drill curriculum adapted from public rally-school syllabi (Richard Burns Rally,
EA SPORTS WRC, DiRT Rally 2.0 / Jon Armstrong, DirtFish, Team O'Neil). These are
original exercises inspired by them, not reproductions of any school's material
and not official BeamNG missions.
