import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import ParamRowCard from '../ParamRowCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

describe('ParamRowCard.vue', () => {
  const globalConfig = {
    global: {
      stubs: {
        FluentIcon: true,
        Input: true,
      },
    },
  };

  it('flags card as error and wiggles when validate is called with a blank name', async () => {
    const wrapper = shallowMount(ParamRowCard, {
      props: {
        modelValue: {
          name: '',
          type: 'string',
          description: '',
          required: false,
        },
        index: 0,
      },
      ...globalConfig,
    });

    const isValid = wrapper.vm.validate();
    expect(isValid).toBe(false);
    expect(wrapper.vm.hasError).toBe(true);
    expect(wrapper.vm.isWiggling).toBe(true);
    await wrapper.vm.$nextTick();
    expect(wrapper.classes()).toContain('animate-wiggle');
  });

  it('clears the error state when any field in the row is edited', async () => {
    const wrapper = shallowMount(ParamRowCard, {
      props: {
        modelValue: {
          name: 'param_name',
          type: 'string',
          description: '',
          required: false,
        },
        index: 0,
      },
      ...globalConfig,
    });

    // Artificially trigger error
    wrapper.vm.hasError = true;
    wrapper.vm.errorMsg = 'Some error';

    // Simulate input change
    wrapper.vm.handleFieldChange('description', 'Updated description');

    expect(wrapper.vm.hasError).toBe(false);
    expect(wrapper.vm.errorMsg).toBe('');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      name: 'param_name',
      type: 'string',
      description: 'Updated description',
      required: false,
    });
  });

  it('emits delete event when the trash button is clicked', async () => {
    const wrapper = shallowMount(ParamRowCard, {
      props: {
        modelValue: {
          name: 'param_name',
          type: 'string',
          description: '',
          required: false,
        },
        index: 0,
      },
      ...globalConfig,
    });

    const button = wrapper.find('button');
    await button.trigger('click');

    expect(wrapper.emitted('delete')).toBeTruthy();
  });
});
