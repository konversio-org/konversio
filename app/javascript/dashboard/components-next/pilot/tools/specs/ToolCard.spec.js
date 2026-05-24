import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ToolCard from '../ToolCard.vue';
import { createStore } from 'vuex';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

describe('ToolCard.vue', () => {
  let store;
  let actions;

  beforeEach(() => {
    actions = {
      'pilotCustomTools/setEnabled': vi.fn(),
    };
    store = createStore({
      actions,
    });
  });

  const globalConfig = {
    global: {
      stubs: {
        Switch: true,
      },
    },
  };

  it('calls setEnabled action and alerts success on successful toggle', async () => {
    const row = {
      id: 1,
      title: 'Test Tool',
      enabled: false,
      auth_type: 'none',
    };
    const wrapper = shallowMount(ToolCard, {
      props: {
        row,
        isAdmin: true,
      },
      global: {
        ...globalConfig.global,
        plugins: [store],
      },
    });

    actions['pilotCustomTools/setEnabled'].mockResolvedValueOnce();

    await wrapper.vm.onToggleEnabled(true);

    expect(actions['pilotCustomTools/setEnabled']).toHaveBeenCalledWith(
      expect.any(Object),
      { id: 1, enabled: true }
    );
  });
});
