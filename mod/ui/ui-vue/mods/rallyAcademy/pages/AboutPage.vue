<template>
  <div class="ra-text-page">
    <section class="ra-panel">
      <div class="ra-panel-title">What this is</div>
      <p>
        Rally Academy is structured rally-driving practice for BeamNG.drive: 43 drills that build
        from car control basics through braking, rotation, complex corners and changing terrain,
        plus adapting to damage and setups. Each drill is short and repeatable, so you can run it
        many times in a row, then move on.
      </p>
      <p>
        The drills are listed in order, but nothing is locked. Start wherever you like.
      </p>
      <p>
        For full stages, use the game's own Rally mode (main menu → More... → Rally). It has real
        stages, co-driver pacenotes, recce and medals against reference times.
      </p>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">How a drill works</div>
      <ol>
        <li><strong>Start drill</strong> loads the drill's map and car and puts you at its start.</li>
        <li>The first time on a map, drive to where the drill begins and press <strong>Mark start</strong>
          on the in-game panel. Some drills also need a finish, a stop zone or gates: drive to each
          spot and press the matching button. Everything is saved for next time.</li>
        <li><strong>Retry</strong> puts you back at the start and repairs the car. Bind it to a key or
          wheel button in Options → Controls (search "Rally Academy").</li>
        <li>A drill is scored in blocks, for example 8 passes out of 10 attempts.</li>
      </ol>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Grading</div>
      <p>
        <strong>Auto-graded</strong> drills judge each run from your car's telemetry and show a ✓ or ✗
        line for every check, with the numbers. For example, B01 checks your speed, where you
        stopped and whether a wheel locked.
      </p>
      <p>
        Drills marked <strong>Coming soon</strong> don't have automatic grading yet. You can still
        practise them and score each run yourself with Pass/Miss.
      </p>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Your HUD</div>
      <p>
        The mod brings its own HUD layout, <strong>Rally Academy HUD</strong>: the drill panel, a <strong>Coach</strong>
        with the drill's instructions and each run's grade, and an <strong>Inputs</strong> graph of your throttle and
        brake. It switches on when the proving ground loads. Move, resize or swap its apps with Alt+Shift+U
        (HUD Layouts) → Edit Layout; your changes stay yours, and Reset brings ours back.
      </p>
      <div class="ra-hud-buttons">
        <BngButton @click="useNow">Use it now</BngButton>
        <BngButton :accent="hudLayout ? ACCENTS.main : ACCENTS.secondary" @click="toggle">
          Switch on the proving ground: {{ hudLayout ? "on" : "off" }}
        </BngButton>
      </div>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Your runs</div>
      <p>
        Keep a copy of every attempt you score: your inputs and the car's motion, about 60 times a second, with the
        grade. They're saved in your BeamNG user folder under <code>settings/rallyAcademy/runs</code>, about 1 MB a
        minute of driving, for analysing your driving or training a driver later.
      </p>
      <div class="ra-hud-buttons">
        <BngButton :accent="keepRuns ? ACCENTS.main : ACCENTS.secondary" @click="toggleKeepRuns">
          Keep my runs: {{ keepRuns ? "on" : "off" }}
        </BngButton>
      </div>
    </section>

    <section class="ra-panel">
      <div class="ra-panel-title">Version</div>
      <p>Rally Academy {{ info.version || "(unknown)" }}, alpha. Built and tested on BeamNG.drive 0.39.</p>
      <p class="ra-muted">Source and issue tracker: github.com/p25marti/rally-academy</p>
    </section>
  </div>
</template>

<script setup>
import { ref, watch } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { academy } from "../academy.js"

const props = defineProps({
  info: { type: Object, default: () => ({}) },
})

// ADR 0012: the mod's HUD layout, switched to on the proving ground unless the player turns that off.
const hudLayout = ref(props.info.hudLayout !== false)
watch(() => props.info.hudLayout, v => (hudLayout.value = v !== false))
function toggle() {
  hudLayout.value = !hudLayout.value
  academy("setHudLayout", hudLayout.value)
}
function useNow() { academy("useHudLayout") }

// Every scored attempt's run record saved to disk; off unless the player turns it on.
const keepRuns = ref(props.info.keepRuns === true)
watch(() => props.info.keepRuns, v => (keepRuns.value = v === true))
function toggleKeepRuns() {
  keepRuns.value = !keepRuns.value
  academy("setKeepRuns", keepRuns.value)
}
</script>

<style scoped lang="scss">
.ra-hud-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.ra-text-page {
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  padding-right: 0.5rem;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(22rem, 1fr));
  grid-auto-rows: min-content;
  gap: 1rem;
  max-width: 80rem;
}

.ra-panel {
  padding: 1rem 1.25rem;
  border-radius: var(--bng-corners-2);
  background-color: rgb(var(--bng-cool-gray-900-rgb));
  border: 1px solid rgb(var(--bng-cool-gray-700-rgb));
  color: var(--bng-off-white);
  line-height: 1.5;
  p,
  li {
    margin: 0 0 0.5rem;
  }
  ol {
    margin: 0;
    padding-left: 1.25rem;
  }
}

.ra-panel-title {
  margin-bottom: 0.5rem;
  font-size: 0.8em;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bng-orange-400);
}

.ra-muted {
  color: var(--bng-cool-gray-100);
}
</style>
