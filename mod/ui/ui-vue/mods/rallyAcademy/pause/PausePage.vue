<template>
  <!-- One page of the Academy, shown as the pause menu's main card (index.js registers a
       "Rally Academy" pause tab with one rail button per page). -->
  <div class="ra-pause-page">
    <div v-if="error" class="ra-error">{{ error }}</div>
    <div v-else-if="!loaded" class="ra-loading">Loading…</div>
    <ExercisesPage v-else-if="page === 'exercises'" :lessons="lessons" :progress="progress" :selected="selected" :show-back="false" compact />
    <AnalysisPage v-else-if="page === 'analysis'" :lessons="lessons" :progress="progress" />
    <AboutPage v-else-if="page === 'about'" :info="info" />
    <CreditsPage v-else-if="page === 'credits'" :info="info" />
  </div>
</template>

<script setup>
import { useAcademyData } from "../academy.js"
import ExercisesPage from "../pages/ExercisesPage.vue"
import AnalysisPage from "../pages/AnalysisPage.vue"
import AboutPage from "../pages/AboutPage.vue"
import CreditsPage from "../pages/CreditsPage.vue"

defineProps({
  page: { type: String, default: "exercises" },
})

const { lessons, progress, selected, info, error, loaded } = useAcademyData()
</script>

<style scoped lang="scss">
.ra-pause-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  padding: 0.75rem;
  color: var(--bng-off-white);
}

.ra-loading {
  padding: 1rem;
  color: var(--bng-cool-gray-100);
}

.ra-error {
  padding: 1rem;
  color: var(--bng-add-red-400);
}
</style>
