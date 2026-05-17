import { computed } from 'vue';

// Stubbed in Konversio fork: Pilot Copilot menu is disabled until
// the Pilot Copilot sub-feature lands. Returns inactive state so
// downstream code paths skip the legacy Pilot editor menu cleanly.
export function usePilot() {
  const pilotCopilotEnabled = computed(() => false);

  return {
    pilotCopilotEnabled,
  };
}
