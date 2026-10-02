<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  points: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
  userName: { type: String, default: '' },
});

const ROTATION_INTERVAL_MS = 6000;

const activeIndex = ref(0);
let rotationTimer = null;

const hasPoints = computed(() => props.points.length > 0);
const hasMultiplePoints = computed(() => props.points.length > 1);
const activePoint = computed(() => props.points[activeIndex.value] || '');

const stopRotation = () => {
  if (rotationTimer) {
    clearInterval(rotationTimer);
    rotationTimer = null;
  }
};

const startRotation = () => {
  stopRotation();
  if (!hasMultiplePoints.value) return;
  rotationTimer = setInterval(() => {
    activeIndex.value = (activeIndex.value + 1) % props.points.length;
  }, ROTATION_INTERVAL_MS);
};

// Manual navigation restarts the rotation interval.
const goTo = direction => {
  if (!hasMultiplePoints.value) return;
  const count = props.points.length;
  activeIndex.value = (activeIndex.value + direction + count) % count;
  startRotation();
};

watch(
  () => props.points,
  () => {
    activeIndex.value = 0;
    startRotation();
  }
);

onMounted(startRotation);
onBeforeUnmount(stopRotation);
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
  >
    <div class="flex items-center gap-2">
      <span
        class="flex size-8 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        <Icon icon="i-lucide-sparkles" class="size-4" />
      </span>
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ $t('PILOT.OVERVIEW.SUMMARY.GREETING', { name: userName }) }}
      </h3>
    </div>

    <div
      v-if="isLoading"
      class="flex flex-col gap-2"
      data-testid="summary-skeleton"
    >
      <div class="h-4 w-3/4 animate-pulse rounded bg-n-alpha-2" />
      <div class="h-4 w-1/2 animate-pulse rounded bg-n-alpha-2" />
      <span class="sr-only">{{ $t('PILOT.OVERVIEW.SUMMARY.LOADING') }}</span>
    </div>

    <p v-else-if="hasError" class="text-sm text-n-ruby-11">
      {{ $t('PILOT.OVERVIEW.SUMMARY.ERROR') }}
    </p>

    <p v-else-if="!hasPoints" class="text-sm text-n-slate-10">
      {{ $t('PILOT.OVERVIEW.SUMMARY.EMPTY') }}
    </p>

    <div v-else class="flex items-start justify-between gap-3">
      <p
        aria-live="polite"
        class="min-h-10 flex-1 text-sm leading-6 text-n-slate-12"
      >
        {{ activePoint }}
      </p>
      <div v-if="hasMultiplePoints" class="flex shrink-0 items-center gap-1">
        <Button
          ghost
          slate
          size="sm"
          icon="i-lucide-chevron-left"
          :aria-label="$t('PILOT.OVERVIEW.SUMMARY.PREVIOUS')"
          @click="goTo(-1)"
        />
        <span class="text-xs text-n-slate-10">
          {{ activeIndex + 1 }}/{{ points.length }}
        </span>
        <Button
          ghost
          slate
          size="sm"
          icon="i-lucide-chevron-right"
          :aria-label="$t('PILOT.OVERVIEW.SUMMARY.NEXT')"
          @click="goTo(1)"
        />
      </div>
    </div>
  </section>
</template>
