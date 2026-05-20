import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

export function usePilot() {
  const { currentAccount } = useAccount();

  const pilotCopilotEnabled = computed(() => {
    const account = currentAccount.value || {};
    return Boolean(account.pilot_enabled && account.pilot_copilot_enabled);
  });

  return {
    pilotCopilotEnabled,
  };
}
