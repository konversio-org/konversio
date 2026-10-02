import { shallowMount } from '@vue/test-utils';
import BarChart from '../charts/BarChart.vue';

vi.mock('vue-chartjs', () => ({
  Bar: {
    name: 'VueBar',
    props: ['data', 'options'],
    template: '<div />',
  },
}));

describe('BarChart.vue', () => {
  const collection = {
    labels: ['20-May'],
    datasets: [{ data: [3] }],
  };

  it('emits the clicked chart item when clickable', () => {
    const wrapper = shallowMount(BarChart, {
      props: {
        collection,
        clickable: true,
      },
    });

    const chart = wrapper.findComponent({ name: 'VueBar' });
    chart.props('options').onClick({}, [{ index: 0 }]);

    expect(wrapper.emitted('itemClick')[0][0]).toEqual({ index: 0 });
  });

  it('does not emit an item click when chart is not clickable', () => {
    const wrapper = shallowMount(BarChart, {
      props: {
        collection,
        clickable: false,
      },
    });

    const chart = wrapper.findComponent({ name: 'VueBar' });
    chart.props('options').onClick({}, [{ index: 0 }]);

    expect(wrapper.emitted('itemClick')).toBeUndefined();
  });

  it('does not emit an item click when clicking empty space', () => {
    const wrapper = shallowMount(BarChart, {
      props: {
        collection,
        clickable: true,
      },
    });

    const chart = wrapper.findComponent({ name: 'VueBar' });
    chart.props('options').onClick({}, []);

    expect(wrapper.emitted('itemClick')).toBeUndefined();
  });
});
