# Contributing to Rally Academy

Thanks for helping. This mod is small enough to understand in an afternoon; these pages get
you there:

1. [docs/PRODUCT.md](docs/PRODUCT.md): what we're building, for whom, and the owner's
   standing decisions.
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the pieces fit.
3. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): tooling and the dev loop.
4. [docs/TESTING.md](docs/TESTING.md): unit tests, in-game scenarios, the manual smoke test.

Using a coding agent? It should read [AGENTS.md](AGENTS.md), which also covers driving the
live game through its MCP server.

## Set up

```sh
git clone https://github.com/p25marti/rally-academy.git
cd rally-academy
python tools/dev.py check     # validate, lint, unit tests, build (Lua tools optional locally)
python tools/dev.py link      # live-link mod/ into your BeamNG mods folder
```

You need Python 3.9+ and BeamNG.drive 0.39 or newer. On Windows, LuaJIT and luacheck run
in WSL; see [DEVELOPMENT](docs/DEVELOPMENT.md#tooling). Then in the game: Freeroam → HUD
Layouts → add the **Rally Academy** app. The main menu has **More... → Rally Academy**.

## Testing your change

- **Always:** `python tools/dev.py check --strict` (CI runs the same).
- **With the game running:** `python tools/dev.py ingame smoke pause`, plus the driving
  scenarios for grading changes (`b01`, `a04`, `stops`, `launch`, `events`). They drive the
  real game by script and print what they checked.
- **By hand:** drive the drill you changed. Scripted runs can't tell how a drill *feels*
  on a wheel.

Say in your PR how you tested, and what you couldn't test.

## Good first contributions

- **Make a drill auto-graded.** Pick a "Coming soon" drill whose needs are already built
  (see GRADING's coverage table): gates, stop zones, lockup, wheelspin, spin, leaving the
  road, damage. The recipe is in [AGENTS.md](AGENTS.md#recipes).
- **Find a venue** for a drill without a good spot yet: bookmark spots while driving, run
  `survey.py report`, and record what works in [MAPS.md](docs/MAPS.md)
  ([how](docs/TESTING.md#finding-a-venue)).
- **Improve a drill's text:** instructions and pass criteria live in `exercises.json`.
- **Check an "unverified" row** in [BEAMNG_API_NOTES](docs/BEAMNG_API_NOTES.md) on your game
  version.

Have a bigger idea? Add it to [docs/IDEAS.md](docs/IDEAS.md) (someday/maybe) and talk to the
owner before building it.

## Conventions

- **Branches:** `feat/…`, `fix/…`, `docs/…` or `chore/…`, with
  [Conventional Commit](https://www.conventionalcommits.org/) messages.
- **Changelog:** user-visible changes get a line in `CHANGELOG.md` under `[Unreleased]`.
- **`mod/`** is exactly what ships: nothing else goes in it.
- **Code:** Lua keeps logic in the pure modules (unit-testable) and engine calls at the edges.
  The UI uses the game's own Vue components and colours.
- **Bigger or one-way decisions** (data schema, new dependencies, scope) get a short record
  in [docs/decisions/](docs/decisions/).

## Reporting a bug

Include your BeamNG version, the drill, the map and car, what you did and what happened.
Attach the mod's lines from the log:

```sh
python tools/dev.py log --ours
```
