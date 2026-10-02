import { mount } from '@vue/test-utils';
import OverviewMetricCard from './OverviewMetricCard.vue';

const mountCard = (props = {}) =>
  mount(OverviewMetricCard, {
    props: {
      label: 'Auto-resolution rate',
      pack: { current: 0.5, previous: 0.4, trend: 0.1 },
      format: 'rate',
      ...props,
    },
    global: {
      mocks: {
        $t: (key, params) =>
          params ? `${key} ${JSON.stringify(params)}` : key,
      },
      stubs: { Icon: true },
    },
  });

describe('OverviewMetricCard', () => {
  it('formats rate values as percentages with a point-difference trend', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('50.0%');
    expect(wrapper.text()).toContain('40.0%');
    expect(wrapper.text()).toContain('+10.0 pt');
  });

  it('colors the trend by whether the movement is favorable', () => {
    const favorable = mountCard({ trendDirection: 'higher-is-better' });
    expect(favorable.html()).toContain('text-n-teal-11');

    const unfavorable = mountCard({
      pack: { current: 0.5, previous: 0.6, trend: -0.1 },
      trendDirection: 'higher-is-better',
    });
    expect(unfavorable.html()).toContain('text-n-ruby-11');

    const lowerIsBetter = mountCard({
      pack: { current: 0.5, previous: 0.6, trend: -0.1 },
      trendDirection: 'lower-is-better',
    });
    expect(lowerIsBetter.html()).toContain('text-n-teal-11');
  });

  it('renders an insufficient-history hint and no trend for null values', () => {
    const wrapper = mountCard({
      pack: { current: null, previous: null, trend: null },
    });

    expect(wrapper.text()).toContain(
      'PILOT.OVERVIEW.METRICS.INSUFFICIENT_HISTORY'
    );
    expect(wrapper.text()).not.toContain('pt');
    expect(wrapper.find('[role="img"]').exists()).toBe(false);
  });

  it('labels hours saved as an estimate', () => {
    const wrapper = mountCard({
      pack: { current: 10, previous: 5, trend: 100 },
      format: 'hours',
      estimateHint: 'Estimate hint',
    });

    expect(wrapper.text()).toContain('10h');
    expect(wrapper.find('[aria-label="Estimate hint"]').exists()).toBe(true);
  });

  it('emits drilldown only when the affordance is enabled', async () => {
    const enabled = mountCard({ drilldownEnabled: true });
    await enabled.trigger('click');
    expect(enabled.emitted('drilldown')).toHaveLength(1);

    const disabled = mountCard({ drilldownEnabled: false });
    await disabled.trigger('click');
    expect(disabled.emitted('drilldown')).toBeUndefined();
  });
});
