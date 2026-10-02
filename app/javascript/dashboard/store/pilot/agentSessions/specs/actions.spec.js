import { createStore } from 'vuex';
import PilotAgentSessionsAPI from 'dashboard/api/pilot/agentSessions';
import module from 'dashboard/store/pilot/agentSessions';

vi.mock('dashboard/api/pilot/agentSessions', () => ({
  default: { show: vi.fn() },
}));

const buildStore = () => createStore({ modules: { agentSessions: module } });

const secondsAgo = ms => (Date.now() - ms) / 1000;

describe('pilot/agentSessions actions', () => {
  let store;

  beforeEach(() => {
    vi.clearAllMocks();
    store = buildStore();
  });

  it('caches a loaded session and does not refetch', async () => {
    const session = { id: 7, message_id: 1 };
    PilotAgentSessionsAPI.show.mockResolvedValue({ data: session });

    const first = await store.dispatch('agentSessions/fetch', {
      messageId: 1,
      createdAt: secondsAgo(10 * 60 * 1000),
    });
    const second = await store.dispatch('agentSessions/fetch', {
      messageId: 1,
      createdAt: secondsAgo(10 * 60 * 1000),
    });

    expect(first).toEqual(session);
    expect(second).toEqual(session);
    expect(PilotAgentSessionsAPI.show).toHaveBeenCalledTimes(1);
    expect(store.getters['agentSessions/getStatus'](1)).toBe('loaded');
  });

  it('does not permanently cache a 404 for a recent message', async () => {
    PilotAgentSessionsAPI.show.mockRejectedValue({ response: { status: 404 } });

    await store.dispatch('agentSessions/fetch', {
      messageId: 2,
      createdAt: secondsAgo(1_000),
    });
    await store.dispatch('agentSessions/fetch', {
      messageId: 2,
      createdAt: secondsAgo(1_000),
    });

    expect(PilotAgentSessionsAPI.show).toHaveBeenCalledTimes(2);
    expect(store.getters['agentSessions/getStatus'](2)).toBeNull();
  });

  it('caches an old 404 as empty and skips later fetches', async () => {
    PilotAgentSessionsAPI.show.mockRejectedValue({ response: { status: 404 } });

    await store.dispatch('agentSessions/fetch', {
      messageId: 3,
      createdAt: secondsAgo(10 * 60 * 1000),
    });
    await store.dispatch('agentSessions/fetch', {
      messageId: 3,
      createdAt: secondsAgo(10 * 60 * 1000),
    });

    expect(PilotAgentSessionsAPI.show).toHaveBeenCalledTimes(1);
    expect(store.getters['agentSessions/getStatus'](3)).toBe('empty');
    expect(store.getters['agentSessions/getSession'](3)).toBeNull();
  });

  it('never caches transient failures', async () => {
    PilotAgentSessionsAPI.show.mockRejectedValue({ response: { status: 500 } });

    await store.dispatch('agentSessions/fetch', {
      messageId: 4,
      createdAt: secondsAgo(10 * 60 * 1000),
    });
    await store.dispatch('agentSessions/fetch', {
      messageId: 4,
      createdAt: secondsAgo(10 * 60 * 1000),
    });

    expect(PilotAgentSessionsAPI.show).toHaveBeenCalledTimes(2);
    expect(store.getters['agentSessions/getStatus'](4)).toBeNull();
  });
});
