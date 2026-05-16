import { computed } from 'vue';

export function useLabelSuggestions() {
  const captainTasksEnabled = computed(() => false);
  const isLabelSuggestionFeatureEnabled = computed(() => false);

  const getLabelSuggestions = async () => {
    return [];
  };

  return {
    captainTasksEnabled,
    isLabelSuggestionFeatureEnabled,
    getLabelSuggestions,
  };
}
