import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationCard from '../ConversationCard.vue';

const store = createStore({
  getters: {
    getSelectedChat: () => ({}),
    getSelectedInbox: () => null,
    getCurrentAccountId: () => 1,
    'inboxes/getInboxes': () => [{ id: 1 }],
    'inboxes/getInbox': () => () => ({ id: 1 }),
    'contacts/getContact': () => () => ({}),
  },
});

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
};

const mountComponent = (chat, currentContact = {}, props = {}) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      inbox: { id: 1 },
      ...props,
    },
    global: {
      plugins: [store],
      stubs: {
        'fluent-icon': true,
      },
    },
  });

describe('ConversationCard', () => {
  it('does not reserve the labels row when only a persisted SLA policy id is present', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the labels row when an active applied SLA is present', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the labels row when the contact is blocked', () => {
    const wrapper = mountComponent(
      {
        sla_policy_id: 1,
        applied_sla: { id: 1 },
      },
      { blocked: true }
    );

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('uses the bot icon for an AI assignee', () => {
    const wrapper = mountComponent(
      { meta: { assignee_type: 'Pilot::Assistant' } },
      {},
      { showAssignee: true, assignee: { name: 'Pilot' } }
    );

    expect(wrapper.findComponent({ name: 'Icon' }).props('icon')).toBe(
      'i-lucide-bot'
    );
  });
});
