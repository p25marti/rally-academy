# Stream Deck and key bindings

Every Rally Academy command is a game input action, so anything that can press a key can drive
the drills: a keyboard, a button box, or an Elgato Stream Deck. The mod ships default bindings
on keys no keyboard has (F13–F24), so a Stream Deck works out of the box and nothing collides
with the game's own controls.

## Default bindings

Shipped in `mod/settings/inputmaps/keyboard_rallyAcademy.json` (a suffixed bindings file, the
way BeamNG lets mods add defaults without replacing the game's own; [docs](https://documentation.beamng.com/modding/input/bindings/)).
You can rebind any of them in Options → Controls (search "Rally Academy").

| Key | Action | What it does |
| --- | --- | --- |
| F13 | Retry | Back to the start, car repaired |
| F14 | Go to drill | Load the selected drill's map and car, place you at its start |
| F15 | Previous drill | Select the previous drill (a message names it) |
| F16 | Next drill | Select the next drill |
| F17 | Open menu | Open or close the Academy screen (pauses the game) |
| F18 | Mark start / Move course here | Save where you are as the start; a course drill lays its course out from here |
| F19 | Use venue start | Course drills: put the course back at the venue |
| F20 | Mark finish / stop zone / stop line | Where you are |
| F21 | Add gate | Mark the next gate across the road |
| F22 | Clear gates | Remove the gates you marked |
| F23 | Score pass | Self-assessed drills |
| F24 | Score miss | Self-assessed drills; abandons a run on graded drills |
| Shift+F13 | Auto-retry on/off | A message confirms which |
| Shift+F14 | Save spot | Bookmark a possible venue ([VENUES](VENUES.md)) |

**Never use Alt in these bindings.** Ctrl+Alt+Shift+F4 contains Alt+F4, which closed the game
when we tried it (0.39.4). `dev.py validate` rejects Alt, unknown actions, duplicate keys and
actions left unbound.

## Stream Deck Mk.2 layout (15 keys)

|   | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| **Row 1** | Retry (F13) | Go to drill (F14) | Previous drill (F15) | Next drill (F16) | Menu (F17) |
| **Row 2** | Move course here (F18) | Venue start (F19) | Mark finish (F20) | + Gate (F21) | Clear gates (F22) |
| **Row 3** | Pass (F23) | Miss (F24) | Auto-retry (Shift+F13) | Save spot (Shift+F14) | spare |

Row 1 is what you press while drilling; row 2 is setup; row 3 is scoring and extras. Retry sits
top-left, where your thumb finds it without looking.

## Setting up the Stream Deck

Once (about five minutes):

1. Open the Stream Deck app and create a profile, e.g. "Rally Academy". Optionally link it to
   `BeamNG.drive.exe` (profile settings → "Switch to this profile when this app is active").
2. For each key in the layout: drag **System → Hotkey** onto it, open the hotkey's key list,
   and pick the key from the **F-keys** section (F13–F24; for Shift+F13, also tick Shift).
3. Give each key a title (the action name) or an icon. The
   [BEAM.deck icon pack](https://beamng.com/posts/1487204) has BeamNG-styled icons.
4. In the game, with a drill selected, press the keys: Next drill shows the drill's name,
   Retry puts you back at the start.

### Sharing the profile

Export it (Stream Deck preferences → Profiles → right-click → Export) and commit the
`.streamDeckProfile` file to `extras/streamdeck/`. Other drivers then double-click it to import.
Elgato documents profiles as made in the app and exported, not hand-written, so we keep the
exported file rather than generating one.

## Troubleshooting

- **Keys do nothing:** the game window must have focus (Stream Deck sends ordinary key
  presses). Check Options → Controls → search "Rally Academy" for the bindings.
- **You changed a binding in Controls:** your change is saved in the user folder's
  `settings/inputmaps/keyboard.diff` and wins over the mod's default.
- **Live state on the keys** (timer, medal, countdown) needs a Stream Deck plugin; it's in
  [IDEAS](IDEAS.md).
