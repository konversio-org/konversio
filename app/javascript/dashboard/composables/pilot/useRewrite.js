import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import PilotRewritesAPI from 'dashboard/api/pilot/rewrites';

/**
 * Pilot Rewrite composable.
 *
 * Wraps the `POST /api/v2/accounts/:id/pilot/rewrites` endpoint and
 * exposes reactive `loading`, `error`, and `rewritten` state plus a
 * `generate({ text, tone })` action.
 */
export function useRewrite() {
  const currentAccount = useMapGetter('getCurrentAccount');

  const loading = ref(false);
  const error = ref(null);
  const rewritten = ref(null);

  const rewriteEnabled = () => {
    const account = currentAccount.value || {};
    return Boolean(account.pilot_enabled && account.pilot_rewrite_enabled);
  };

  const reset = () => {
    loading.value = false;
    error.value = null;
    rewritten.value = null;
  };

  const generate = async ({ text, tone }) => {
    if (!text || !tone) return null;

    loading.value = true;
    error.value = null;
    rewritten.value = null;

    try {
      const response = await PilotRewritesAPI.generate({ text, tone });
      rewritten.value = response?.data?.rewritten || '';
      return rewritten.value;
    } catch (err) {
      const message =
        err?.response?.data?.error || err?.message || 'Failed to rewrite text';
      error.value = message;
      return null;
    } finally {
      loading.value = false;
    }
  };

  return {
    loading,
    error,
    rewritten,
    rewriteEnabled,
    generate,
    reset,
  };
}
