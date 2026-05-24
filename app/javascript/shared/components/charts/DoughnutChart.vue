<script setup>
import { computed } from 'vue';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, Title, Tooltip, ArcElement, Legend } from 'chart.js';

const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  chartOptions: {
    type: Object,
    default: () => ({}),
  },
});

ChartJS.register(Title, Tooltip, ArcElement, Legend);

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      display: false,
    },
  },
  animation: {
    duration: 0,
  },
};

const options = computed(() => {
  return { ...defaultChartOptions, ...props.chartOptions };
});
</script>

<template>
  <Doughnut :data="collection" :options="options" />
</template>
