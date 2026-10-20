// Helpers shared by the Academy screen's pages.
import { ref } from "vue"
import { runRaw } from "@/bridge/libs/Lua.js"

// The bridge's `lua.*` only knows the game's own functions (LuaFunctionSignatures.js);
// our extension is called with raw Lua, as game screens do for theirs.
export const academy = (fn, ...args) =>
  runRaw(`extensions.rallyAcademy.${fn}(${args.map(a => JSON.stringify(a)).join(",")})`)

// "01  FOUNDATION & PRECISION" -> "Foundation & precision"
export function moduleName(lesson) {
  const raw = String(lesson.module || "").replace(/^\d+\s*/, "").toLowerCase()
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

// Implemented = graded automatically; everything else is "Coming soon".
export const isAuto = lesson => !!(lesson.assessment && lesson.assessment.mode === "automatic")

// Saved progress for one drill, or null: {totalAttempts, totalPasses, bestTime, lastSessionPassed,
// bestTier, tiers} (the last two for drills with medals)
export const progressOf = (progress, lesson) => (progress && progress[lesson.id]) || null

// Drills grouped by module, in curriculum order (the order Lua sends them).
export function groupByModule(lessons, progress) {
  const out = []
  for (const l of lessons) {
    const letter = l.id.charAt(0)
    let m = out[out.length - 1]
    if (!m || m.letter !== letter) {
      m = { letter, name: moduleName(l), lessons: [], passed: 0, tried: 0, ready: 0 }
      out.push(m)
    }
    m.lessons.push(l)
    const p = progressOf(progress, l)
    if (p && p.totalAttempts) m.tried++
    if (p && p.lastSessionPassed) m.passed++
    if (isAuto(l)) m.ready++
  }
  return out
}

// Load everything the pages show (extensions.rallyAcademy.getMenuData). Returns refs that
// fill in once the data arrives; used by the full screen and the pause-menu cards.
export function useAcademyData() {
  const state = {
    lessons: ref([]),
    variants: ref({}), // surface variants by id ("A01-snow"), ADR 0009
    progress: ref({}),
    selected: ref(null),
    info: ref({}),
    error: ref(""),
    loaded: ref(false),
  }
  ;(async () => {
    try {
      const data = await academy("getMenuData")
      state.lessons.value = Array.isArray(data && data.lessons) ? data.lessons : []
      state.variants.value = data && data.variants && !Array.isArray(data.variants) ? data.variants : {}
      // Lua's empty table arrives as [] rather than {}
      state.progress.value = data && data.progress && !Array.isArray(data.progress) ? data.progress : {}
      state.selected.value = (data && data.selected) || (state.lessons.value[0] && state.lessons.value[0].id) || null
      state.info.value = (data && data.info) || {}
      if (!state.lessons.value.length) state.error.value = "No drills found. Is the Rally Academy mod enabled?"
    } catch (e) {
      state.error.value = "Couldn't reach the Rally Academy extension: " + (e && e.message ? e.message : e)
    }
    state.loaded.value = true
  })()
  return state
}
