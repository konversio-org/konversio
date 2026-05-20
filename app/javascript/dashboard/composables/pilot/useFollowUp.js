import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import PilotFollowUpsAPI from 'dashboard/api/pilot/followUps';

/**
 * Pilot Follow-up composable.
 *
 * Wraps the `POST /api/v2/accounts/:id/pilot/follow_ups` endpoint and
 * exposes reactive `loading`, `error`, and `suggestions` state plus a
 * `generate(conversationId)` action returning an Array of strings.
 */
export function useFollowUp() {
  const currentAccount = useMapGetter('getCurrentAccount');

  const loading = ref(false);
  const error = ref(null);
  const suggestions = ref([]);

  const followUpEnabled = () => {
    const account = currentAccount.value || {};
    const features = account.features || {};
    return Boolean(features.pilot && features.pilot_follow_up);
  };

  const reset = () => {
    loading.value = false;
    error.value = null;
    suggestions.value = [];
  };

  const generate = async conversationId => {
    if (!conversationId) return [];

    loading.value = true;
    error.value = null;
    suggestions.value = [];

    try {
      const response = await PilotFollowUpsAPI.generate(conversationId);
      suggestions.value = response?.data?.suggestions || [];
      return suggestions.value;
    } catch (err) {
      const message =
        err?.response?.data?.error ||
        err?.message ||
        'Failed to fetch follow-up suggestions';
      error.value = message;
      return [];
    } finally {
      loading.value = false;
    }
  };

  return {
    loading,
    error,
    suggestions,
    followUpEnabled,
    generate,
    reset,
  };
}
