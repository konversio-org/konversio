import { useStore, useMapGetter } from 'dashboard/composables/store';

/**
 * Pilot Copilot drawer composable.
 *
 * Thin wrapper around the `pilot/copilot` Vuex module that exposes
 * imperative helpers (open, close, openBound) used by sidebar entries,
 * composer affordances, and the drawer itself.
 */
export function useCopilotDrawer() {
  const store = useStore();
  const isOpen = useMapGetter('pilot/copilot/isDrawerOpen');
  const boundConversationId = useMapGetter(
    'pilot/copilot/getBoundConversationId'
  );

  const clearBoundConversation = () =>
    store.dispatch('pilot/copilot/setBoundConversation', null);

  const open = () => {
    clearBoundConversation();
    return store.dispatch('pilot/copilot/openDrawer');
  };
  const close = () => store.dispatch('pilot/copilot/closeDrawer');
  const toggle = () => {
    if (!isOpen.value) {
      clearBoundConversation();
    }
    return store.dispatch('pilot/copilot/toggleDrawer');
  };

  /**
   * Open the drawer pre-bound to a customer conversation.
   * Sets `boundConversationId` in the store so the drawer can seed
   * `conversation_id` on the next created thread / posted message.
   */
  const openBoundToConversation = conversationId => {
    store.dispatch(
      'pilot/copilot/setBoundConversation',
      conversationId || null
    );
    return store.dispatch('pilot/copilot/openDrawer');
  };

  return {
    isOpen,
    boundConversationId,
    open,
    close,
    toggle,
    openBoundToConversation,
  };
}
