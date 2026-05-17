import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import PilotBriefingsAPI from 'dashboard/api/pilot/briefings';

/**
 * Pilot Briefing composable.
 *
 * Wraps the `POST /api/v2/accounts/:id/pilot/briefings` endpoint and
 * exposes reactive `loading`, `error`, and `draft` state plus a
 * `generate(conversationId)` action.
 *
 * The composer can read `briefingEnabled` directly to decide whether to
 * render the button.
 */
export function useBriefing() {
  const currentAccount = useMapGetter('getCurrentAccount');

  const loading = ref(false);
  const error = ref(null);
  const draft = ref(null);

  const briefingEnabled = () => {
    const account = currentAccount.value || {};
    return Boolean(account.pilot_enabled && account.pilot_briefing_enabled);
  };

  const reset = () => {
    loading.value = false;
    error.value = null;
    draft.value = null;
  };

  const generate = async conversationId => {
    if (!conversationId) return null;

    loading.value = true;
    error.value = null;
    draft.value = null;

    try {
      const response = await PilotBriefingsAPI.generate(conversationId);
      draft.value = response?.data?.draft || '';
      return draft.value;
    } catch (err) {
      const message =
        err?.response?.data?.error ||
        err?.message ||
        'Failed to generate briefing';
      error.value = message;
      return null;
    } finally {
      loading.value = false;
    }
  };

  return {
    loading,
    error,
    draft,
    briefingEnabled,
    generate,
    reset,
  };
}
