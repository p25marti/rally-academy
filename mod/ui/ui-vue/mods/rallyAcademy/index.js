// Rally Academy in the game's menus (BeamNG 0.39 Vue UI mods: ui/ui-vue/mods/README.md
// in the game folder):
// - a main-menu button (under More...) opening the full-screen Academy route;
// - a "Rally Academy" pause-menu tab (Esc in a map) with one rail button per page.
// The key binding "Rally Academy: Open menu" opens the same route from inside a map
// (extensions.rallyAcademy.toggleMenu).
import { useBridge } from "@/bridge"
import AcademyMenu from "./AcademyMenu.vue"

const { lua, events } = useBridge()
const sourceId = "rallyAcademy.routes"
const ROUTE = "menu.rallyAcademy"
const routes = [
  {
    path: "/rally-academy",
    name: ROUTE,
    component: AcademyMenu,
    meta: {
      luaRoute: {
        title: "Rally Academy",
        backTarget: "menu",
        // however the screen is left, resume physics if opening it paused them
        onLeave: "rallyAcademy.onMenuLeave",
      },
    },
  },
]

const PAUSE_TAB = "rallyAcademy"
const PAUSE_PAGE = "/ui/ui-vue/mods/rallyAcademy/pause/PausePage.vue"
// Every rail button needs a valid bngIcons name: the pause menu renders `icon` with BngIcon,
// which reads `.glyph` of a null icon and throws, corrupting the whole Vue UI (0.39.4).
const pausePages = [
  { id: "exercises", label: "Exercises", icon: "listBig" },
  { id: "analysis", label: "Analysis", icon: "chartBars" },
  { id: "about", label: "About", icon: "info" },
  { id: "credits", label: "Credits", icon: "peopleOutline" },
]

function toLuaRoutes(records) {
  return records.map(record => ({
    name: record.name,
    path: record.path,
    meta: record.meta,
    ...(record.children ? { children: toLuaRoutes(record.children) } : {}),
  }))
}

function addMenuButton(addButton) {
  addButton({
    title: "Rally Academy",
    iconId: "raceFlag",
    action: () => lua.extensions.ui_router.navigate(ROUTE),
  })
}

async function registerPauseTab() {
  const pause = lua.extensions.ui_pause_actions
  // Registrations live in Lua and survive UI reloads; re-registering a button keeps its old
  // position, so start from an empty tab to get the buttons in this order every time.
  await pause.unregisterModTab(PAUSE_TAB)
  const tab = await pause.registerModTab({ id: PAUSE_TAB, label: "Rally Academy", icon: "raceFlag" })
  if (!tab?.success) {
    console.error("Rally Academy: failed to add the pause-menu tab", tab)
    return
  }
  for (const p of pausePages) {
    await pause.registerModButton({
      id: `${PAUSE_TAB}-${p.id}`,
      tabId: PAUSE_TAB,
      label: p.label,
      icon: p.icon,
      componentName: PAUSE_PAGE,
      props: { page: p.id },
    })
  }
}

export async function onLoad() {
  window.bngRoutes.add([{ path: sourceId, routes }])
  const result = await lua.extensions.ui_router_routeManager.registerModRoutes(sourceId, toLuaRoutes(routes))
  if (!result?.success) {
    window.bngRoutes.remove([sourceId])
    console.error("Rally Academy: failed to register routes", result?.errors)
  } else {
    events.on("MainMenuButtons", addMenuButton)
    events.emit("BroadcastMainMenuButtons") // the menu may already be showing
  }
  await registerPauseTab()
}

export async function onUnload() {
  events.off("MainMenuButtons", addMenuButton)
  await lua.extensions.ui_pause_actions.unregisterModTab(PAUSE_TAB)
  window.bngRoutes.remove([sourceId])
  await lua.extensions.ui_router_routeManager.unregisterModRoutes(sourceId, { fallbackRoute: "menu" })
}
