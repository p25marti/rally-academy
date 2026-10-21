// What every Rally Academy HUD app needs (ADR 0012): the extension's published state, merged as it updates, and, for
// the apps the panel can leave things to ('inputs', 'coach'), telling Lua they're on screen.
import { onMounted, onUnmounted, reactive } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"

// Lua is authoritative: this only follows "rallyAcademyState" (partial updates, so they're merged; Lua sends `false`
// to clear a value). `onData(data, state)` sees each update after the merge. Returns the reactive state and `lua`,
// which runs a command on the extension.
export function useAcademyState(part, onData) {
  const { api } = useBridge()
  const events = useEvents() // listeners are removed when the app unmounts
  const state = reactive({ lessons: [], phase: "loading", successes: 0, attempts: 0 })
  const lua = code => api.engineLua(`if extensions.rallyAcademy then extensions.rallyAcademy.${code} end`)

  events.on("rallyAcademyState", data => {
    Object.assign(state, data)
    // a reloaded extension forgets which apps are up: say so again
    if (part && data.hudParts && !data.hudParts[part]) lua(`hudPart('${part}', true)`)
    if (onData) onData(data, state)
  })
  onMounted(() => {
    // keeping Lua authoritative also lets an app be closed and reopened without losing the session
    api.engineLua("extensions.load('rallyAcademy')")
    if (part) lua(`hudPart('${part}', true)`)
    lua("publish()")
  })
  if (part) onUnmounted(() => lua(`hudPart('${part}', false)`))
  return { state, lua }
}
