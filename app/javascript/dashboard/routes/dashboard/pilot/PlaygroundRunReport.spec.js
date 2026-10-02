import { shallowMount } from '@vue/test-utils';
import PlaygroundRunReport from './PlaygroundRunReport.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const report = {
  handler: { name: 'Refund flow', type: 'scenario', temporary: true },
  knowledge_attached: true,
  duration_ms: 1234,
  events: [
    {
      type: 'tool',
      tool: 'lookup',
      status: 'completed',
      arguments: { id: '1' },
      result_preview: 'lookup-ok',
    },
    {
      type: 'handoff',
      from: { name: 'Support Bot' },
      to: { name: 'Refund flow', temporary: true },
      reason_preview: 'refund-request',
    },
  ],
};

describe('PlaygroundRunReport.vue', () => {
  const mount = () => shallowMount(PlaygroundRunReport, { props: { report } });

  it('shows the handler and duration in the summary and is collapsed by default', () => {
    const wrapper = mount();

    expect(wrapper.text()).toContain('Refund flow');
    expect(wrapper.text()).toContain('1234');
    expect(wrapper.text()).toContain(
      'PILOT.PLAYGROUND.RUN_REPORT.TEMPORARY_BADGE'
    );
    expect(wrapper.text()).not.toContain('lookup-ok');
    expect(wrapper.text()).not.toContain('refund-request');
  });

  it('renders the ordered event log once expanded', async () => {
    const wrapper = mount();

    await wrapper.find('button').trigger('click');

    expect(wrapper.text()).toContain('lookup');
    expect(wrapper.text()).toContain('lookup-ok');
    expect(wrapper.text()).toContain('Support Bot');
    expect(wrapper.text()).toContain('refund-request');
    expect(wrapper.text()).toContain(
      'PILOT.PLAYGROUND.RUN_REPORT.KNOWLEDGE_ATTACHED'
    );
  });

  it('reports when no events were recorded', async () => {
    const wrapper = shallowMount(PlaygroundRunReport, {
      props: {
        report: { ...report, events: [], knowledge_attached: false },
      },
    });

    await wrapper.find('button').trigger('click');

    expect(wrapper.text()).toContain('PILOT.PLAYGROUND.RUN_REPORT.NO_EVENTS');
    expect(wrapper.text()).toContain(
      'PILOT.PLAYGROUND.RUN_REPORT.KNOWLEDGE_NONE'
    );
  });
});
