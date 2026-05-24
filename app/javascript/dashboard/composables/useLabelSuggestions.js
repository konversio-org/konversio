import { computed } from 'vue';
import { useAccount } from './useAccount';
import { useStore } from './store';

export function useLabelSuggestions() {
  const { currentAccount } = useAccount();
  const store = useStore();

  const pilotTasksEnabled = computed(() => {
    const features = currentAccount.value?.features || {};
    return Boolean(features.pilot);
  });

  const isLabelSuggestionFeatureEnabled = computed(() => {
    const features = currentAccount.value?.features || {};
    return Boolean(features.pilot && features.pilot_label_suggestion);
  });

  const getLabelSuggestions = async conversation => {
    if (!conversation) return [];
    const suggestedLabelIds = conversation.suggested_label_ids || [];
    const allLabels = store.getters['labels/getLabels'] || [];
    return suggestedLabelIds
      .map(id => allLabels.find(l => l.id === id))
      .filter(Boolean)
      .map(l => l.title);
  };

  return {
    pilotTasksEnabled,
    isLabelSuggestionFeatureEnabled,
    getLabelSuggestions,
  };
}
