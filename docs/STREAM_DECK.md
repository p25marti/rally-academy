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
| Shift+F15 | Racing line on/off | Show the road's racing line; a message confirms which (and says when the drill has none) |

**Never use Alt in these bindings.** Ctrl+Alt+Shift+F4 contains Alt+F4, which closed the game
when we tried it (0.39.4). `dev.py validate` rejects Alt, unknown actions, duplicate keys and
actions left unbound.

## Stream Deck Mk.2 layout (15 keys)

|   | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| **Row 1** | Retry (F13) | Go to drill (F14) | Previous drill (F15) | Next drill (F16) | Menu (F17) |
| **Row 2** | Move course here (F18) | Venue start (F19) | Mark finish (F20) | + Gate (F21) | Clear gates (F22) |
| **Row 3** | Pass (F23) | Miss (F24) | Auto-retry (Shift+F13) | Save spot (Shift+F14) | Line (Shift+F15) |

Row 1 is what you press while drilling; row 2 is setup; row 3 is scoring and extras. Retry sits
top-left, where your thumb finds it without looking.

### Icons (BEAM.deck)

Picked from the [BEAM.deck icon pack](https://beamng.com/posts/1487204) (search the names in the
Stream Deck icon library). Orange is for the keys you press every run, white for setup, green
and red for scoring.

| Key | Icon | Why |
| --- | --- | --- |
| Retry (F13) | `RestartB` | Orange "go back" arrow: the key you press most, and the brightest |
| Go to drill (F14) | `Map_FastTravel01` | The game's own fast-travel marker; it means the same thing |
| Previous drill (F15) | `Dir_LeftA1` | Plain arrows read as "browse", not as driving inputs |
| Next drill (F16) | `Dir_RightA1` | |
| Menu (F17) | `Menu3` | A stack of cards with an orange one: the drill cards in the Academy |
| Move course here (F18) | `Home_Set2` | "Set home here", with an orange touch |
| Venue start (F19) | `HomeA` | Back to the venue's home spot |
| Mark finish (F20) | `Atlas_StartFinish` | An arrow up to a chequered line: finish, stop zone or stop line |
| + Gate (F21) | `cone1` | Gates are what cones mark |
| Clear gates (F22) | `delete1` | Bin with a cross |
| Pass (F23) | `pass2` | Green tick |
| Miss (F24) | `fail2` | Red cross |
| Auto-retry (Shift+F13) | `Reset1a` | A loop: "keep going round". A plain Hotkey can't show on/off; a Hotkey Switch with `Toggle_On` / `Toggle_Off` can, but drifts out of step if you also toggle it in the HUD |
| Save spot (Shift+F14) | `Map_Marker` | A map pin: bookmark this place |
| Line (Shift+F15) | our own (red, yellow and green ribbon) | The racing line in its own colours; BEAM.deck has nothing like it |

Alternatives if you prefer: `Reset1b` (orange loop) for Retry, `FastTravel1` (plain chevrons) for
Go to drill, `Dir_LeftB1` / `Dir_RightB1` (bold arrows), `flagB1` (chequered flag) for Mark
finish, `cone2` (orange cone) for + Gate.

## Setting up the Stream Deck

**Quickest:** double-click `extras/streamdeck/rally_academy.streamDeckProfile` to import the
ready-made profile (this layout, these icons, built-in Hotkey actions only). See
[its README](../extras/streamdeck/README.md) for auto-switching on another PC.

To build it yourself instead (about five minutes):

1. Open the Stream Deck app and create a profile, e.g. "Rally Academy". Optionally link it to
   `BeamNG.drive.exe` (profile settings → "Switch to this profile when this app is active").
2. For each key in the layout: drag **System → Hotkey** onto it, open the hotkey's key list,
   and pick the key from the **F-keys** section (F13–F24; for Shift+F13, also tick Shift).
3. Give each key a title (the action name) or an icon. The
   [BEAM.deck icon pack](https://beamng.com/posts/1487204) has BeamNG-styled icons.
4. In the game, with a drill selected, press the keys: Next drill shows the drill's name,
   Retry puts you back at the start.

### Updating the shared profile

Change it in the Stream Deck app, export it (Stream Deck preferences → Profiles → right-click →
Export) over `extras/streamdeck/rally_academy.streamDeckProfile`, and check the keys still match
the default bindings (`tests/python/test_streamdeck.py` checks). Elgato documents profiles as made in the app and
exported, not hand-written, so we keep the exported file rather than generating one; a small change can be made in
the export's `manifest.json` by copying a key of the same kind, as the Line key was.

## Troubleshooting

- **Keys do nothing:** the game window must have focus (Stream Deck sends ordinary key
  presses). Check Options → Controls → search "Rally Academy" for the bindings.
- **You changed a binding in Controls:** your change is saved in the user folder's
  `settings/inputmaps/keyboard.diff` and wins over the mod's default.
- **Live state on the keys** (timer, medal, countdown) needs a Stream Deck plugin; it's in
  [IDEAS](IDEAS.md).
