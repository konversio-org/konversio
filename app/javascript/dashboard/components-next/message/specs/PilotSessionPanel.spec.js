import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import PilotSessionPanel from '../PilotSessionPanel.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      PILOT: {
        PILOT_SESSION: {
          LOADING: 'Loading run details...',
          EMPTY: 'No run details are available for this message.',
          SOURCES: 'Sources cited',
          NO_SOURCES: 'No knowledge sources were cited.',
          SCENARIOS: 'Scenarios involved',
          STEPS: 'Run steps',
          NO_STEPS: 'No steps were recorded.',
          TOOL_CALL: 'Called {tool}',
        },
      },
    },
  },
});

const mountPanel = props =>
  mount(PilotSessionPanel, {
    props,
    global: { plugins: [i18n] },
  });

const session = {
  id: 7,
  message_id: 42,
  cited_sources: [
    { id: 1, title: 'Refund policy', link: 'https://example.com/refunds' },
    { id: 2, title: 'Shipping', link: null },
  ],
  used_faqs: [{ id: 9, title: 'How do refunds work?' }],
  scenarios: [{ id: 3, title: 'Billing flow' }],
  run_context: [
    { role: 'assistant', content: 'SECRET BODY', tool_calls: [] },
    {
      role: 'assistant',
      content: '',
      tool_calls: [
        { name: 'search_documentation', arguments: { query: 'refunds' } },
        { name: 'handoff_to_billing', arguments: {} },
      ],
    },
    { role: 'tool', content: 'SECRET TOOL OUTPUT' },
  ],
};

describe('PilotSessionPanel', () => {
  it('renders cited sources, FAQs, scenarios, and the steps timeline', () => {
    const wrapper = mountPanel({ session, isLoading: false });

    expect(wrapper.text()).toContain('Refund policy');
    expect(wrapper.find('a[href="https://example.com/refunds"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('Shipping');
    expect(wrapper.text()).toContain('How do refunds work?');
    expect(wrapper.text()).toContain('Billing flow');
    expect(wrapper.text()).toContain('Called search_documentation');
    expect(wrapper.text()).toContain('refunds');
    expect(wrapper.text()).toContain('Called handoff_to_billing');
  });

  it('does not echo message bodies or raw tool output', () => {
    const wrapper = mountPanel({ session, isLoading: false });

    expect(wrapper.text()).not.toContain('SECRET BODY');
    expect(wrapper.text()).not.toContain('SECRET TOOL OUTPUT');
  });

  it('shows a loading state', () => {
    const wrapper = mountPanel({ session: null, isLoading: true });

    expect(wrapper.text()).toContain('Loading run details...');
  });

  it('shows an empty state without a session', () => {
    const wrapper = mountPanel({ session: null, isLoading: false });

    expect(wrapper.text()).toContain(
      'No run details are available for this message.'
    );
  });
});
