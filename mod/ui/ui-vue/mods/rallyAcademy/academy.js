// Helpers shared by the Academy screen's pages.
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

// Saved progress for one drill, or null: {totalAttempts, totalPasses, bestTime, lastSessionPassed}
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
