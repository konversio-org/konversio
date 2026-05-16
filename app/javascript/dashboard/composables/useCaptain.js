import { computed } from 'vue';

// Stubbed in Pilot fork: Captain feature is disabled until Pilot AI lands.
// Returns inactive state; downstream code paths skip AI features cleanly.
export function useCaptain() {
  const captainTasksEnabled = computed(() => false);

  return {
    captainTasksEnabled,
  };
}
