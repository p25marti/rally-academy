// Rally Academy entry in the game's main menu (BeamNG 0.39 Vue UI mods:
// ui/ui-vue/mods/README.md in the game folder). Adds a main-menu button that opens
// the Academy screen, a route registered with both Vue and Lua.
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
      },
    },
  },
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

export async function onLoad() {
  window.bngRoutes.add([{ path: sourceId, routes }])
  const result = await lua.extensions.ui_router_routeManager.registerModRoutes(sourceId, toLuaRoutes(routes))
  if (!result?.success) {
    window.bngRoutes.remove([sourceId])
    console.error("Rally Academy: failed to register routes", result?.errors)
    return
  }
  events.on("MainMenuButtons", addMenuButton)
  events.emit("BroadcastMainMenuButtons") // the menu may already be showing
}

export async function onUnload() {
  events.off("MainMenuButtons", addMenuButton)
  window.bngRoutes.remove([sourceId])
  await lua.extensions.ui_router_routeManager.unregisterModRoutes(sourceId, { fallbackRoute: "menu" })
}
