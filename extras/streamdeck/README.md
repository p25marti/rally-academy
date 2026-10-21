# Stream Deck profile

`rally_academy.streamDeckProfile`: the Rally Academy profile for the Elgato Stream Deck Mk.2
(15 keys), exported from Stream Deck 7.6. Double-click it to import. It only uses Stream Deck's
built-in Hotkey action, so no plugins are needed.

| Row | Keys (key sent) |
| --- | --- |
| 1 | Retry (F13) · Go to drill (F14) · Prev drill (F15) · Next drill (F16) · Menu (F17) |
| 2 | Set start (F18) · Start (venue start, F19) · Finish (F20) · Gate (F21) · Clear gate (F22) |
| 3 | Pass (F23) · Fail (miss, F24) · Auto-retry (Shift+F13) · Save spot (Shift+F14) · Line (racing line, Shift+F15) |

These match the mod's default bindings (`mod/settings/inputmaps/keyboard_rallyAcademy.json`).
The game window needs focus for the keys to work. Layout, icons and setup:
[docs/STREAM_DECK.md](../../docs/STREAM_DECK.md). This folder is not part of the mod zip.

**Auto-switching.** The profile is linked to the owner's BeamNG install
(`D:\SteamLibrary\...\BeamNG.drive.x64.exe`). On another PC, re-link it in the profile settings
("Switch to this profile when this app is active") or switch to it by hand.

**Icons** are from [BEAM.deck](https://www.beamng.com/threads/beam-deck-beamng-icon-pack-for-elgato-stream-deck-and-sim-rigs.87570/)
by 23Terrabytes (MIT, per the pack's license file), made from BeamNG.drive assets, except Line, drawn for this
profile. Check the
icons' terms before publishing this profile anywhere public.

**Updating it:** change the profile in the Stream Deck app, export it over this file; `tests/python/test_streamdeck.py`
checks the keys still match the default bindings. (The Line key was added by editing the export's manifest, copying
the Auto-retry key; the owner hasn't re-exported since.)
