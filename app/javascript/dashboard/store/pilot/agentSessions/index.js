import PilotAgentSessionsAPI from 'dashboard/api/pilot/agentSessions';

// A 404 for a message created moments ago likely means the session has not been
// written yet (message broadcast races session capture), so it must not be
// cached. Older 404s are permanent misses and are cached as empty.
const RECENT_MESSAGE_MAX_AGE_MS = 60 * 1000;

const isRecentMessage = createdAt => {
  if (!createdAt) return false;

  // The message prop is unix seconds; tolerate millisecond timestamps too.
  const millis = createdAt > 1e12 ? createdAt : createdAt * 1000;
  return Date.now() - millis < RECENT_MESSAGE_MAX_AGE_MS;
};

const types = {
  SET_SESSION: 'pilot/agentSessions/SET_SESSION',
  SET_EMPTY: 'pilot/agentSessions/SET_EMPTY',
  SET_LOADING: 'pilot/agentSessions/SET_LOADING',
  SET_LAST_ERROR: 'pilot/agentSessions/SET_LAST_ERROR',
};

export const state = {
  byMessageId: {},
  loadingByMessageId: {},
  lastError: null,
};

export const getters = {
  getSession: _state => messageId =>
    _state.byMessageId[messageId]?.data || null,
  getStatus: _state => messageId =>
    _state.byMessageId[messageId]?.status || null,
  isLoading: _state => messageId => !!_state.loadingByMessageId[messageId],
  getLastError: _state => _state.lastError,
};

export const actions = {
  async fetch({ commit, state: $state }, { messageId, createdAt } = {}) {
    if (!messageId) return null;

    const cached = $state.byMessageId[messageId];
    if (cached?.status === 'loaded') return cached.data;
    if (cached?.status === 'empty') return null;

    commit(types.SET_LOADING, { messageId, loading: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAgentSessionsAPI.show(messageId);
      commit(types.SET_SESSION, { messageId, data });
      return data;
    } catch (err) {
      if (err.response?.status === 404) {
        if (!isRecentMessage(createdAt)) {
          commit(types.SET_EMPTY, { messageId });
        }
        return null;
      }
      // Transient/server failures are never cached so a later interaction
      // retries.
      commit(types.SET_LAST_ERROR, err);
      return null;
    } finally {
      commit(types.SET_LOADING, { messageId, loading: false });
    }
  },
};

export const mutations = {
  [types.SET_SESSION]($state, { messageId, data }) {
    $state.byMessageId = {
      ...$state.byMessageId,
      [messageId]: { status: 'loaded', data },
    };
  },

  [types.SET_EMPTY]($state, { messageId }) {
    $state.byMessageId = {
      ...$state.byMessageId,
      [messageId]: { status: 'empty', data: null },
    };
  },

  [types.SET_LOADING]($state, { messageId, loading }) {
    $state.loadingByMessageId = {
      ...$state.loadingByMessageId,
      [messageId]: loading,
    };
  },

  [types.SET_LAST_ERROR]($state, err) {
    $state.lastError = err;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
