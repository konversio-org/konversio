import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref, nextTick } from 'vue';
import { createStore } from 'vuex';
import { useRoute } from 'vue-router';
import CopilotDrawer from '../CopilotDrawer.vue';
import CopilotMessageList from '../CopilotMessageList.vue';
import copilotModule from 'dashboard/store/pilot/copilot';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const route = reactive({
    path: '/app/accounts/1/conversations/5',
    params: { conversationId: '5' },
  });
  return { useRoute: () => route };
});

vi.mock('dashboard/composables/pilot/useCopilotDrawer', () => ({
  useCopilotDrawer: () => ({ isOpen: ref(true), close: vi.fn() }),
}));

vi.mock('dashboard/api/pilot/copilot', () => ({
  default: {
    fetchThreads: vi.fn().mockResolvedValue({ data: { data: [] } }),
    fetchMessages: vi.fn().mockResolvedValue({ data: { data: [] } }),
    createThread: vi.fn().mockResolvedValue({ data: { id: 1 } }),
    postMessage: vi.fn(),
  },
}));

const buildStore = () =>
  createStore({
    state: { selectedChat: { messages: [] } },
    getters: { getSelectedChat: state => state.selectedChat },
    modules: {
      pilot: {
        namespaced: true,
        modules: {
          copilot: {
            ...copilotModule,
            actions: { ...copilotModule.actions, fetchThreads: vi.fn() },
          },
        },
      },
    },
  });

describe('CopilotDrawer.vue reply suggestion', () => {
  let store;
  let wrapper;

  beforeEach(() => {
    store = buildStore();
    wrapper = mount(CopilotDrawer, {
      global: { plugins: [store] },
    });
  });

  it('shows the suggest-reply action only when the latest public message is incoming', async () => {
    const list = wrapper.findComponent(CopilotMessageList);
    expect(list.props('canSuggestReply')).toBe(false);

    store.state.selectedChat.messages = [{ message_type: 0, private: false }];
    await nextTick();
    expect(list.props('canSuggestReply')).toBe(true);

    store.state.selectedChat.messages = [{ message_type: 1, private: false }];
    await nextTick();
    expect(list.props('canSuggestReply')).toBe(false);
  });

  it('resets the active thread when the viewed conversation changes', async () => {
    const dispatchSpy = vi.spyOn(store, 'dispatch');

    useRoute().params.conversationId = '6';
    await nextTick();

    expect(dispatchSpy).toHaveBeenCalledWith('pilot/copilot/resetActiveThread');
    expect(dispatchSpy).toHaveBeenCalledWith(
      'pilot/copilot/setBoundConversation',
      '6'
    );
  });
});
