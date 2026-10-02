import { mount } from '@vue/test-utils';
import OverviewSummaryCard from './OverviewSummaryCard.vue';

const ButtonStub = {
  template: '<button v-bind="$attrs" />',
};

const mountCard = (props = {}) =>
  mount(OverviewSummaryCard, {
    props: {
      points: [],
      userName: 'Robin',
      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: { Button: ButtonStub, Icon: true },
    },
  });

describe('OverviewSummaryCard', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('greets the current user', () => {
    const wrapper = mountCard({ points: ['One point'] });

    expect(wrapper.text()).toContain('PILOT.OVERVIEW.SUMMARY.GREETING');
  });

  it('auto-rotates through points on an interval', async () => {
    const wrapper = mountCard({ points: ['First', 'Second', 'Third'] });

    expect(wrapper.text()).toContain('First');
    await vi.advanceTimersByTimeAsync(6000);
    expect(wrapper.text()).toContain('Second');
    await vi.advanceTimersByTimeAsync(6000);
    expect(wrapper.text()).toContain('Third');
    await vi.advanceTimersByTimeAsync(6000);
    expect(wrapper.text()).toContain('First');
  });

  it('manual navigation shows the requested point and restarts the rotation', async () => {
    const wrapper = mountCard({ points: ['First', 'Second', 'Third'] });
    const buttons = wrapper.findAll('button');

    await buttons[1].trigger('click');
    expect(wrapper.text()).toContain('Second');

    // Rotation restarts: a partial interval before the click does not count.
    await vi.advanceTimersByTimeAsync(5999);
    expect(wrapper.text()).toContain('Second');
    await vi.advanceTimersByTimeAsync(2);
    expect(wrapper.text()).toContain('Third');

    await buttons[0].trigger('click');
    expect(wrapper.text()).toContain('Second');
  });

  it('shows no navigation controls for a single point', () => {
    const wrapper = mountCard({ points: ['Only point'] });

    expect(wrapper.text()).toContain('Only point');
    expect(wrapper.findAll('button')).toHaveLength(0);
  });

  it('shows a skeleton while loading and a neutral empty state when there are no points', () => {
    const loading = mountCard({ isLoading: true });
    expect(loading.find('[data-testid="summary-skeleton"]').exists()).toBe(
      true
    );
    expect(loading.text()).not.toContain('PILOT.OVERVIEW.SUMMARY.EMPTY');

    const empty = mountCard({ points: [] });
    expect(empty.find('[data-testid="summary-skeleton"]').exists()).toBe(false);
    expect(empty.text()).toContain('PILOT.OVERVIEW.SUMMARY.EMPTY');
  });
});
