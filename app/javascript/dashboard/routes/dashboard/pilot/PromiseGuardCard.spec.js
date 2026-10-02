import { mount, flushPromises } from '@vue/test-utils';
import PromiseGuardCard from './PromiseGuardCard.vue';
import PilotPreferencesAPI from 'dashboard/api/pilot/preferences';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/api/pilot/preferences', () => ({
  default: {
    fetch: vi.fn(() =>
      Promise.resolve({ data: { false_promise_guard_enabled: false } })
    ),
    update: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));

describe('PromiseGuardCard.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    PilotPreferencesAPI.fetch.mockResolvedValue({
      data: { false_promise_guard_enabled: false },
    });
    PilotPreferencesAPI.update.mockResolvedValue({ data: {} });
  });

  const mountCard = () => mount(PromiseGuardCard);

  it('loads the current preference on mount', async () => {
    PilotPreferencesAPI.fetch.mockResolvedValue({
      data: { false_promise_guard_enabled: true },
    });
    const wrapper = mountCard();
    await flushPromises();

    expect(PilotPreferencesAPI.fetch).toHaveBeenCalled();
    expect(
      wrapper.find('button[role="switch"]').attributes('aria-checked')
    ).toBe('true');
  });

  it('enables the guard and persists the preference on toggle', async () => {
    const wrapper = mountCard();
    await flushPromises();

    await wrapper.find('button[role="switch"]').trigger('click');

    expect(PilotPreferencesAPI.update).toHaveBeenCalledWith({
      pilot_false_promise_guard_enabled: true,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'PILOT.SETTINGS.PROMISE_GUARD.UPDATED'
    );
  });

  it('reverts the toggle when the update fails', async () => {
    PilotPreferencesAPI.update.mockRejectedValue(new Error('nope'));
    const wrapper = mountCard();
    await flushPromises();

    await wrapper.find('button[role="switch"]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('button[role="switch"]').attributes('aria-checked')
    ).toBe('false');
    expect(useAlert).toHaveBeenCalledWith(
      'PILOT.SETTINGS.PROMISE_GUARD.UPDATE_FAILED'
    );
  });
});
