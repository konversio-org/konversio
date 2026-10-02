import PilotFaqSuggestionsAPI from 'dashboard/api/pilot/faqSuggestions';

const types = {
  SET_UI_FLAG: 'pilot/faqSuggestions/SET_UI_FLAG',
  SET_RECORDS: 'pilot/faqSuggestions/SET_RECORDS',
  SET_META: 'pilot/faqSuggestions/SET_META',
  UPDATE_RECORD: 'pilot/faqSuggestions/UPDATE_RECORD',
  REMOVE_RECORD: 'pilot/faqSuggestions/REMOVE_RECORD',
  SET_ASSISTANT_ID: 'pilot/faqSuggestions/SET_ASSISTANT_ID',
  SET_SEARCH: 'pilot/faqSuggestions/SET_SEARCH',
  SET_LAST_ERROR: 'pilot/faqSuggestions/SET_LAST_ERROR',
  SET_OPEN_COUNT: 'pilot/faqSuggestions/SET_OPEN_COUNT',
};

const DEFAULT_META = {
  current_page: 1,
  per_page: 25,
  total_count: 0,
  total_pages: 0,
};

export const state = {
  records: [],
  meta: { ...DEFAULT_META },
  activeAssistantId: null,
  search: '',
  lastError: null,
  openCount: 0,
  uiFlags: {
    isFetching: false,
    isUpdating: false,
  },
};

export const getters = {
  getRecords: _state => _state.records,
  getMeta: _state => _state.meta,
  getActiveAssistantId: _state => _state.activeAssistantId,
  getSearch: _state => _state.search,
  getUIFlags: _state => _state.uiFlags,
  getLastError: _state => _state.lastError,
  getOpenCount: _state => _state.openCount,
};

// Monotonic token guarding fetchOpenCount against stale responses landing
// after a newer request (e.g. rapid assistant switching).
let openCountRequestToken = 0;

export const actions = {
  setAssistant({ commit }, id) {
    commit(types.SET_ASSISTANT_ID, id ?? null);
  },

  setSearch({ commit }, value) {
    commit(types.SET_SEARCH, value || '');
  },

  async fetchPage({ commit, state: _state }, payload = {}) {
    const assistantId = payload.assistantId ?? _state.activeAssistantId;
    if (!assistantId) {
      commit(types.SET_RECORDS, []);
      commit(types.SET_META, { ...DEFAULT_META });
      return null;
    }

    const page = payload.page ?? _state.meta.current_page ?? 1;
    const search = payload.search ?? _state.search;
    const status = payload.status ?? 'open';

    commit(types.SET_UI_FLAG, { isFetching: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotFaqSuggestionsAPI.list({
        assistantId,
        page,
        search,
        status,
        signal: payload.signal,
      });
      commit(types.SET_RECORDS, Array.isArray(data?.data) ? data.data : []);
      commit(types.SET_META, { ...DEFAULT_META, ...(data?.meta || {}) });
      return data;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  async fetchOpenCount({ commit }, { assistantId } = {}) {
    if (!assistantId) {
      commit(types.SET_OPEN_COUNT, 0);
      return 0;
    }
    openCountRequestToken += 1;
    const token = openCountRequestToken;
    try {
      const { data } = await PilotFaqSuggestionsAPI.list({
        assistantId,
        page: 1,
        status: 'open',
      });
      if (token !== openCountRequestToken) return null;
      const count = data?.meta?.total_count || 0;
      commit(types.SET_OPEN_COUNT, count);
      return count;
    } catch (err) {
      return null;
    }
  },

  async saveRow({ commit }, { id, question, answer }) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotFaqSuggestionsAPI.update(id, {
        question,
        answer,
      });
      commit(types.UPDATE_RECORD, data);
      return data;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },

  async approve({ commit }, { id, question, answer }) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotFaqSuggestionsAPI.approve(id, {
        question,
        answer,
      });
      commit(types.REMOVE_RECORD, id);
      return data;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },

  async dismiss({ commit }, { id }) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotFaqSuggestionsAPI.dismiss(id);
      commit(types.REMOVE_RECORD, id);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_RECORDS]($state, records) {
    $state.records = Array.isArray(records) ? records : [];
  },

  [types.SET_META]($state, meta) {
    $state.meta = { ...DEFAULT_META, ...(meta || {}) };
  },

  [types.UPDATE_RECORD]($state, record) {
    if (!record) return;
    $state.records = $state.records.map(r => (r.id === record.id ? record : r));
  },

  [types.REMOVE_RECORD]($state, id) {
    $state.records = $state.records.filter(r => r.id !== id);
    $state.meta = {
      ...$state.meta,
      total_count: Math.max(0, ($state.meta.total_count || 0) - 1),
    };
    $state.openCount = Math.max(0, ($state.openCount || 0) - 1);
  },

  [types.SET_ASSISTANT_ID]($state, id) {
    $state.activeAssistantId = id;
  },

  [types.SET_SEARCH]($state, value) {
    $state.search = value || '';
  },

  [types.SET_LAST_ERROR]($state, err) {
    $state.lastError = err;
  },

  [types.SET_OPEN_COUNT]($state, count) {
    $state.openCount = count;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
