# 0012 — The mod ships its own HUD layout

**Date:** 2026-10-21 · **Status:** Accepted

## Context

Rally Academy was one HUD app the player had to add to a layout by hand (Alt+Shift+U → Edit Layout → Add app), and
game updates reset the default layouts it had been added to (0.40 did). Everything lived in that one 390 × 340 panel:
the drill picker, instructions, the grade's checks and, lately, an input trace, so the panel was crowded and the
trace sat wherever the panel was. The owner asked for the mod to bring a layout of its own (2026-10-21), so there's no
set-up, players customise it without editing their other layouts, and parts like the graph and the notes get their
own places on screen.

The game supports this directly (`lua/ge/extensions/ui/appLayouts.lua`, 0.40.0): it lists every
`/settings/ui_apps/originalLayouts/*.uilayout.json` on the virtual file system, a mod's included; a player's edits
go to their own copy under `/settings/ui_apps/layouts/` with ours kept as the Reset original; and
`ui_appLayouts.setUsedLayout(filename)` switches. Choosing a layout also records it as the default for its `type`,
so a layout of type `freeroam` would quietly become the player's Freeroam layout.

## Decision

- The mod ships **Rally Academy HUD** (`settings/ui_apps/originalLayouts/rallyAcademy.uilayout.json`, type
  `rallyAcademy`, its own type so no other layout choice changes): the Rally Academy panel, two new apps, **Rally
  Academy Coach** (the drill's instructions before a run, the medal and every check after it) and **Rally Academy
  Inputs** (throttle and brake over time: live, then the last run with its gates), and the stock dash apps (tacho,
  powertrain controls, damage, minimap, the game's message areas).
- The extension switches to it half a second after the proving ground loads (freeroam applies its own layout as a
  map loads, so ours goes after it), once per load: a player who picks another layout keeps it. Leaving the map
  restores nothing; other modes and maps set their own. The player can turn the switch off (About page; prefs
  `hudLayout`), or switch to it any time.
- The panel stays complete on its own: our other apps tell Lua when they're up (`hudPart`), and the panel then leaves
  the notes to the Coach and the graph to Inputs. In any other layout it shows everything as before.

## Consequences

- No set-up: on the proving ground the HUD is there. Game updates that reset the default layouts don't touch ours.
- Each app carries an `appVersion`, so a later change to the shipped layout reaches players who've customised it
  (the game updates apps whose version rose).
- The owner's hand-made "Rally Academy" layout (type freeroam) stays and is still their Freeroam layout; the shipped
  one is titled "Rally Academy HUD" to tell them apart.
