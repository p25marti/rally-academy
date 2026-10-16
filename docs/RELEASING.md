# Releasing and publishing

## Versioning

[Semantic Versioning](https://semver.org/). While the mod is pre-1.0:

- `0.MINOR.0`: new features, drill-schema changes, progress-file migrations
- `0.x.PATCH`: fixes only
- Pre-releases for in-game test builds: `0.2.0-beta.1`

The version lives in **`VERSION`** (single source of truth). `dev.py bump`
also writes it into `mod/ui/modules/apps/RallyAcademy/app.json` (the version
BeamNG shows), and `dev.py validate` fails if the two disagree. The build
stamps it into the zip.

The zip is always named **`rally_academy.zip`**, never versioned, so an update
replaces the old file instead of loading alongside it.

## Cutting a release

1. Make sure `main` is green, and run the [in-game smoke test](TESTING.md#in-game-smoke-test)
   on the build from `main`.
2. On a branch `chore/release-X.Y.Z`:
   ```sh
   python tools/dev.py bump X.Y.Z
   ```
   In `CHANGELOG.md`, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and add a
   fresh empty `[Unreleased]` above it.
3. PR → CI green → squash-merge.
4. Tag the merge commit and push the tag:
   ```sh
   git switch main && git pull
   git tag -a vX.Y.Z -m "Rally Academy vX.Y.Z"
   git push origin vX.Y.Z
   ```
5. `.github/workflows/release.yml` checks the tag matches `VERSION`, re-runs
   all checks, and creates a GitHub Release with `rally_academy.zip`, its
   `.sha256`, and the changelog section as notes. Tags containing `-`
   (e.g. `v0.2.0-beta.1`) become pre-releases.

The repository is private, so GitHub Releases are for you and invited testers.

## Publishing to the BeamNG repository (public)

The official BeamNG mod repository is on beamng.com (the in-game Repository
browser shows the same mods). Uploads are reviewed by BeamNG staff, and
approved mods can be installed and auto-updated from inside the game.

Before the first public upload:

- [ ] Read BeamNG's current mod-repository rules on beamng.com. They change,
      and they decide what's accepted.
- [ ] Decide the public licence and add a `LICENSE` file (the author in `app.json` is set:
      Paul Martins).
- [ ] Replace "Prototype"/"ALPHA" labelling if appropriate, and make sure the
      README credits section is accurate.
- [ ] Prepare screenshots and a description (what it does, how to bind Retry,
      known limitations).

For each public upload:

1. Use the `rally_academy.zip` attached to the GitHub Release. Don't re-zip by
   hand: the build guarantees the zip root is `gameplay/`, `lua/`, `ui/`.
2. Upload it as a new version of the existing resource (not a new resource),
   with the changelog section as the update notes.
3. Don't add a `mod_info/` folder yourself. BeamNG's repository manages its own
   metadata for listed mods.
4. Once approved, install it from the in-game Repository on a clean profile
   (dev link removed: `dev.py unlink`) and repeat the smoke test.

Record each public upload in the CHANGELOG entry ("Published to BeamNG
repository on …").
