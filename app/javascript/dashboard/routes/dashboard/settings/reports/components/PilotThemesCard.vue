<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const { t } = useI18n();

const csatResponses = useMapGetter('csat/getCSATResponses');

const topThemes = computed(() => {
  const responses = csatResponses.value || [];
  const themeCounts = {};
  responses.forEach(r => {
    const themes = r.pilot_themes || [];
    themes.forEach(theme => {
      if (theme) {
        themeCounts[theme] = (themeCounts[theme] || 0) + 1;
      }
    });
  });
  return Object.entries(themeCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([theme, count]) => ({ theme, count }));
});

const hasData = computed(() => topThemes.value.length > 0);
</script>

<template>
  <div
    v-if="hasData"
    class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 overflow-hidden"
  >
    <div class="px-6 py-4 border-b border-n-container">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('PILOT.CSAT.THEMES.TITLE') }}
      </h3>
    </div>
    <div class="p-6">
      <div class="flex flex-wrap gap-2">
        <span
          v-for="{ theme, count } in topThemes"
          :key="theme"
          class="inline-flex items-center gap-1.5 rounded-full border border-n-violet-7 bg-n-violet-2 px-3 py-1 text-xs text-n-violet-11"
        >
          {{ theme }}
          <span class="text-n-violet-9">{{ count }}</span>
        </span>
      </div>
    </div>
  </div>
</template>
