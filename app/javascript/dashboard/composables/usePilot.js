import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

export function usePilot() {
  const { currentAccount } = useAccount();

  const pilotCopilotEnabled = computed(() => {
    const account = currentAccount.value || {};
    const features = account.features || {};
    return Boolean(features.pilot && features.pilot_copilot);
  });

  return {
    pilotCopilotEnabled,
  };
}
