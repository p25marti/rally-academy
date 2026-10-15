<template>
  <LayoutSingle v-bng-blur class="layout-content-full flex-column ra-menu">
    <!-- LayoutSingle lays its children out in a row: keep everything in one column. -->
    <div class="ra-page">
      <BngScreenHeading divider>Rally Academy</BngScreenHeading>

      <div v-if="error" class="ra-error">{{ error }}</div>

      <BngTabs v-else v-model="activeTab" class="ra-tabs">
        <div class="ra-tab" tab-heading="Exercises">
          <ExercisesPage :lessons="lessons" :progress="progress" :selected="selected" @back="back" />
        </div>
        <div class="ra-tab" tab-heading="Analysis">
          <AnalysisPage :lessons="lessons" :progress="progress" />
        </div>
        <div class="ra-tab" tab-heading="About">
          <AboutPage :info="info" />
        </div>
        <div class="ra-tab" tab-heading="Credits">
          <CreditsPage :info="info" />
        </div>
      </BngTabs>
    </div>
  </LayoutSingle>
</template>

<script setup>
import { onBeforeMount, ref } from "vue"
import { BngScreenHeading, BngTabs } from "@/common/components/base"
import { LayoutSingle } from "@/common/layouts"
import { vBngBlur } from "@/common/directives"
import { useBridge } from "@/bridge"
import { academy } from "./academy.js"
import ExercisesPage from "./pages/ExercisesPage.vue"
import AnalysisPage from "./pages/AnalysisPage.vue"
import AboutPage from "./pages/AboutPage.vue"
import CreditsPage from "./pages/CreditsPage.vue"

const { lua } = useBridge()

const activeTab = ref(0)
const lessons = ref([])
const progress = ref({})
const selected = ref(null)
const info = ref({})
const error = ref("")

const back = () => lua.extensions.ui_router.navigate("menu")

onBeforeMount(async () => {
  try {
    await lua.extensions.load("rallyAcademy") // already loaded by modScript.lua; harmless if so
    const data = await academy("getMenuData")
    lessons.value = Array.isArray(data && data.lessons) ? data.lessons : []
    // Lua's empty table arrives as [] rather than {}
    progress.value = data && data.progress && !Array.isArray(data.progress) ? data.progress : {}
    selected.value = (data && data.selected) || (lessons.value[0] && lessons.value[0].id) || null
    info.value = (data && data.info) || {}
    if (!lessons.value.length) error.value = "No drills found. Is the Rally Academy mod enabled?"
  } catch (e) {
    error.value = "Couldn't reach the Rally Academy extension: " + (e && e.message ? e.message : e)
  }
})
</script>

<style scoped lang="scss">
// Readability: everything sits on one dark backing (never straight on the menu scenery),
// panels are opaque, and secondary text uses the light grey. Auto-graded drills carry the
// orange accent; coming-soon drills are neutral, not faded.
.ra-page {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  min-height: 0;
  min-width: 0;
  background-color: rgba(var(--bng-off-black-rgb), 0.82);
  border-radius: var(--bng-corners-3);
  color: var(--bng-off-white);
}

.ra-tabs {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  padding: 0 1rem 1rem;
}

.ra-tab {
  flex: 1 1 auto;
  min-height: 0;
  height: 100%;
  padding-top: 0.75rem;
  display: flex;
  flex-direction: column;
}

.ra-error {
  padding: 2rem;
  color: var(--bng-add-red-400);
}
</style>
