import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import AuthConfigFields from '../AuthConfigFields.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

describe('AuthConfigFields.vue', () => {
  const globalConfig = {
    global: {
      stubs: {
        FluentIcon: true,
        Input: true,
      },
    },
  };

  it('renders nothing when authType is none', () => {
    const wrapper = shallowMount(AuthConfigFields, {
      props: {
        authType: 'none',
        modelValue: {},
      },
      ...globalConfig,
    });

    expect(wrapper.html()).toContain('<!--v-if-->');
  });

  it('renders Bearer input field when authType is bearer and toggles secret reveal', async () => {
    const wrapper = shallowMount(AuthConfigFields, {
      props: {
        authType: 'bearer',
        modelValue: { token: 'secret-token' },
      },
      ...globalConfig,
    });

    // Verify it renders input with correct prop value
    const input = wrapper.findComponent({ name: 'Input' });
    expect(input.exists()).toBe(true);
    expect(input.props('modelValue')).toBe('secret-token');
    expect(input.props('type')).toBe('password'); // Masked by default

    // Verify secret toggle
    expect(wrapper.vm.showSecret).toBe(false);
    const button = wrapper.find('button');
    await button.trigger('click');
    expect(wrapper.vm.showSecret).toBe(true);
    expect(input.props('type')).toBe('text'); // Revealed
  });

  it('renders basic auth fields correctly', () => {
    const wrapper = shallowMount(AuthConfigFields, {
      props: {
        authType: 'basic',
        modelValue: { username: 'user', password: 'pwd' },
      },
      ...globalConfig,
    });

    const inputs = wrapper.findAllComponents({ name: 'Input' });
    expect(inputs).toHaveLength(2);
    expect(inputs[0].props('modelValue')).toBe('user');
    expect(inputs[1].props('modelValue')).toBe('pwd');
  });
});
