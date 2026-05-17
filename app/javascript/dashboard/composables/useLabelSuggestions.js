import { computed } from 'vue';

export function useLabelSuggestions() {
  const pilotTasksEnabled = computed(() => false);
  const isLabelSuggestionFeatureEnabled = computed(() => false);

  const getLabelSuggestions = async () => {
    return [];
  };

  return {
    pilotTasksEnabled,
    isLabelSuggestionFeatureEnabled,
    getLabelSuggestions,
  };
}
