import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import PilotSummariesAPI from 'dashboard/api/pilot/summaries';

/**
 * Pilot Summary composable.
 *
 * Wraps the `POST /api/v2/accounts/:id/pilot/summaries` endpoint and
 * exposes reactive `loading`, `error`, and `summary` state plus a
 * `generate(conversationId)` action.
 */
export function useSummary() {
  const currentAccount = useMapGetter('getCurrentAccount');

  const loading = ref(false);
  const error = ref(null);
  const summary = ref(null);

  const summaryEnabled = () => {
    const account = currentAccount.value || {};
    const features = account.features || {};
    return Boolean(features.pilot && features.pilot_summary);
  };

  const reset = () => {
    loading.value = false;
    error.value = null;
    summary.value = null;
  };

  const generate = async (conversationId, opts = {}) => {
    if (!conversationId) return null;

    loading.value = true;
    error.value = null;
    summary.value = null;

    try {
      const response = await PilotSummariesAPI.generate(conversationId, opts);
      summary.value = response?.data?.summary || '';
      return summary.value;
    } catch (err) {
      const message =
        err?.response?.data?.error ||
        err?.message ||
        'Failed to generate summary';
      error.value = message;
      return null;
    } finally {
      loading.value = false;
    }
  };

  return {
    loading,
    error,
    summary,
    summaryEnabled,
    generate,
    reset,
  };
}
