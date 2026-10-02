import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useRoute } from 'vue-router';
import DurationInput from 'dashboard/components-next/input/DurationInput.vue';
import { DURATION_UNITS } from 'dashboard/components-next/input/constants';
import AgentAssignmentPolicyForm from './AgentAssignmentPolicyForm.vue';

vi.mock('vue-router');

const store = createStore({
  modules: {
    accounts: {
      namespaced: true,
      getters: {
        isFeatureEnabledonAccount: () => () => false,
      },
    },
  },
});

const mountComponent = (initialData = {}) =>
  shallowMount(AgentAssignmentPolicyForm, {
    props: { mode: 'CREATE', initialData },
    global: { plugins: [store] },
  });

describe('AgentAssignmentPolicyForm exclusion threshold', () => {
  beforeEach(() => {
    useRoute.mockReturnValue({ params: { accountId: '1' } });
  });

  it('shows the default 168 hours as 7 days', () => {
    const wrapper = mountComponent();
    const durationInput = wrapper.findComponent(DurationInput);

    expect(durationInput.props('modelValue')).toBe(168 * 60);
    expect(durationInput.props('unit')).toBe(DURATION_UNITS.DAYS);
  });

  it('does not floor a non-day threshold on display', () => {
    const wrapper = mountComponent({ excludeOlderThanHours: 25 });
    const durationInput = wrapper.findComponent(DurationInput);

    expect(durationInput.props('modelValue')).toBe(25 * 60);
    expect(durationInput.props('unit')).toBe(DURATION_UNITS.HOURS);
  });

  it('converts the entered minutes back to hours on submit', async () => {
    const wrapper = mountComponent();
    const durationInput = wrapper.findComponent(DurationInput);

    durationInput.vm.$emit('update:modelValue', 48 * 60);
    await wrapper.find('form').trigger('submit');

    expect(wrapper.emitted('submit').at(-1)[0]).toMatchObject({
      excludeOlderThanHours: 48,
    });
  });
});
