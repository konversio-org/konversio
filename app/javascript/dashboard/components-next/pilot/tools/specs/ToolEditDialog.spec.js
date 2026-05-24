import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ToolEditDialog from '../ToolEditDialog.vue';
import { createStore } from 'vuex';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

describe('ToolEditDialog.vue', () => {
  let store;
  let actions;
  let getters;

  beforeEach(() => {
    actions = {
      'pilotCustomTools/createRow': vi.fn(),
      'pilotCustomTools/updateRow': vi.fn(),
    };
    getters = {
      'pilotCustomTools/getSaving': () => false,
      'pilotCustomTools/getTesting': () => false,
    };
    store = createStore({
      actions,
      getters,
    });
  });

  const globalConfig = {
    global: {
      stubs: {
        Dialog: true,
        Switch: true,
        Input: true,
        Button: true,
        AuthConfigFields: true,
        ParamSchemaEditor: true,
        LiquidTemplateField: true,
      },
    },
  };

  it('maps server-side 422 validation errors to fields and parameters', async () => {
    const wrapper = shallowMount(ToolEditDialog, {
      props: {
        mode: 'create',
      },
      global: {
        ...globalConfig.global,
        plugins: [store],
      },
    });

    // Populate initial draft
    wrapper.vm.form.title = 'Valid Tool Name';
    wrapper.vm.form.endpoint_url = 'https://api.example.com';

    // Simulate server 422 throw
    const errorObj = {
      response: {
        data: {
          errors: [
            { field: 'title', message: 'Title already taken' },
            { param_index: 2, message: 'Type is invalid' },
          ],
        },
      },
    };
    actions['pilotCustomTools/createRow'].mockRejectedValueOnce(errorObj);

    await wrapper.vm.onSubmit();

    expect(wrapper.vm.serverFieldErrors.title).toBe('Title already taken');
    expect(wrapper.vm.serverParamErrors[2]).toBe('Type is invalid');
  });

  it('shows account-level soft cap error inside general error banner', async () => {
    const wrapper = shallowMount(ToolEditDialog, {
      props: {
        mode: 'create',
      },
      global: {
        ...globalConfig.global,
        plugins: [store],
      },
    });

    wrapper.vm.form.title = 'My Tool';
    wrapper.vm.form.endpoint_url = 'https://api.example.com';

    const errorObj = {
      response: {
        data: {
          message: 'Account has reached the maximum of 15 tools',
        },
      },
    };
    actions['pilotCustomTools/createRow'].mockRejectedValueOnce(errorObj);

    await wrapper.vm.onSubmit();

    expect(wrapper.vm.generalError).toBe(
      'Account has reached the maximum of 15 tools'
    );
  });

  it('emits success event and closes dialog on successful creation', async () => {
    const wrapper = shallowMount(ToolEditDialog, {
      props: {
        mode: 'create',
      },
      global: {
        ...globalConfig.global,
        plugins: [store],
      },
    });

    wrapper.vm.form.title = 'Successful Tool';
    wrapper.vm.form.endpoint_url = 'https://api.example.com';
    actions['pilotCustomTools/createRow'].mockResolvedValueOnce({ id: 1 });

    // Mock Dialog ref close
    wrapper.vm.dialogRef = {
      close: vi.fn(),
    };

    await wrapper.vm.onSubmit();

    expect(actions['pilotCustomTools/createRow']).toHaveBeenCalled();
    expect(wrapper.emitted('success')).toBeTruthy();
  });
});
