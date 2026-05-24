<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import DoughnutChart from 'shared/components/charts/DoughnutChart.vue';

const { t } = useI18n();

const csatResponses = useMapGetter('csat/getCSATResponses');

const sentimentCounts = computed(() => {
  const counts = { positive: 0, neutral: 0, negative: 0 };
  const responses = csatResponses.value || [];
  responses.forEach(r => {
    const sentiment = r.pilot_sentiment;
    if (counts[sentiment] !== undefined) {
      counts[sentiment] += 1;
    }
  });
  return counts;
});

const hasData = computed(() => {
  const { positive, neutral, negative } = sentimentCounts.value;
  return positive + neutral + negative > 0;
});

const chartData = computed(() => {
  return {
    labels: [
      t('PILOT.CSAT.SENTIMENT.POSITIVE'),
      t('PILOT.CSAT.SENTIMENT.NEUTRAL'),
      t('PILOT.CSAT.SENTIMENT.NEGATIVE'),
    ],
    datasets: [
      {
        data: [
          sentimentCounts.value.positive,
          sentimentCounts.value.neutral,
          sentimentCounts.value.negative,
        ],
        backgroundColor: ['#22c55e', '#eab308', '#ef4444'],
        borderWidth: 0,
      },
    ],
  };
});
</script>

<template>
  <div
    v-if="hasData"
    class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 overflow-hidden"
  >
    <div class="px-6 py-4 border-b border-n-container">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('PILOT.CSAT.SENTIMENT.TITLE') }}
      </h3>
    </div>
    <div class="flex items-center gap-6 p-6">
      <div class="w-40 h-40 shrink-0">
        <DoughnutChart :collection="chartData" />
      </div>
      <div class="flex flex-col gap-2">
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-full bg-green-500 shrink-0" />
          <span class="text-sm text-n-slate-11">
            {{ t('PILOT.CSAT.SENTIMENT.POSITIVE') }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ sentimentCounts.positive }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-full bg-yellow-500 shrink-0" />
          <span class="text-sm text-n-slate-11">
            {{ t('PILOT.CSAT.SENTIMENT.NEUTRAL') }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ sentimentCounts.neutral }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-full bg-red-500 shrink-0" />
          <span class="text-sm text-n-slate-11">
            {{ t('PILOT.CSAT.SENTIMENT.NEGATIVE') }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ sentimentCounts.negative }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
