# 0005 — Main-menu screen through BeamNG's Vue UI mods

**Date:** 2026-10-15 · **Status:** Accepted (spike verified in-game on 0.39.4)

## Context

The owner wants a native-looking place to browse and start drills from the game's
main menu, not only the HUD panel's drop-down. Our docs said the game's Vue 3 screens
were a precompiled bundle that mods couldn't extend. That's no longer true: 0.39
ships an official Vue UI mod system, documented in the game folder at
`ui/ui-vue/mods/README.md`. Its runtime (`lua/ge/extensions/ui/uiMods.lua` and
`ui/ui-vue/src/services/modManager/`) compiles `.vue` files from
`/ui/ui-vue/mods/<mod>/` at runtime, so no build step is needed.

| Option | Why not (or why) |
| --- | --- |
| Full-screen HUD app (Angular) opened by a key | Not reachable from the main menu; we'd hand-build the menu chrome |
| Register drills as game missions (`gameplay/missions/...`) | Native big-map and star ratings, but needs mission files per map and its own start/finish flow, which fights ours |
| Scenarios | Old system; one scenario per drill per map |
| **Vue UI mod: main-menu button + registered route** | Chosen: official, native components, calls our Lua directly |

## Decision

- `mod/ui/ui-vue/mods/rallyAcademy/index.js` registers a route `menu.rallyAcademy`
  (`/rally-academy`) with both Vue (`window.bngRoutes`) and Lua
  (`ui_router_routeManager.registerModRoutes`). It also adds a main-menu button
  through the `MainMenuButtons` event. The game lists mod buttons under
  **More...**, tagged "Mod".
- `AcademyMenu.vue` uses the game's own components (`LayoutSingle`,
  `BngScreenHeading`, `BngButton`) and colour variables. It lists every drill in
  curriculum order, with no gating, grouped by module, with progress, and a
  details panel with **Start drill**.
- Lua stays authoritative: the screen calls `extensions.rallyAcademy.getMenuData()`
  and `startDrill(id)` with `runRaw`, from `@/bridge/libs/Lua.js`. The bridge's
  `lua.*` object only knows the game's own functions, listed in
  `LuaFunctionSignatures.js`.
- `startDrill` reuses Go to drill. Maps now start through
  `freeroam_freeroam.startFreeroam`, the Freeroam menu's own call, because bare
  `core_levels.startLevel` from the main menu loaded the map without entering
  freeroam (no HUD). After a menu start, Lua navigates the UI to `play` once the car
  is placed, as the game's main-menu exit handler does.
- The HUD panel stays Angular, drop-down included, for now.

## Consequences

- Two UI stacks for a while: Angular HUD and Vue menu. The planned next step is to
  rebuild the HUD in Vue, if the Vue mod system can host HUD apps (to check).
- The Vue mod API is new in 0.39 and may change between game versions. Re-test the
  menu after every game update; the in-game smoke test has a step for it.
- In a map, a pause-menu tab (`ui_pause_actions.registerModTab`) shows the same pages
  (`pause/PausePage.vue`), and a key binding opens the full screen with physics paused.
