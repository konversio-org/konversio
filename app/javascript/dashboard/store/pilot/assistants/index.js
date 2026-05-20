import PilotAssistantsAPI from 'dashboard/api/pilot/assistants';

const types = {
  SET_UI_FLAG: 'pilot/assistants/SET_UI_FLAG',
  SET_RECORDS: 'pilot/assistants/SET_RECORDS',
  ADD_RECORD: 'pilot/assistants/ADD_RECORD',
  UPDATE_RECORD: 'pilot/assistants/UPDATE_RECORD',
  REMOVE_RECORD: 'pilot/assistants/REMOVE_RECORD',
  SET_ACTIVE_ID: 'pilot/assistants/SET_ACTIVE_ID',
  SET_LAST_ERROR: 'pilot/assistants/SET_LAST_ERROR',
};

export const state = {
  records: [],
  activeId: null,
  lastError: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getRecords: _state => _state.records,
  getActiveId: _state => _state.activeId,
  getActiveAssistant: _state =>
    _state.records.find(r => r.id === _state.activeId) || null,
  getUIFlags: _state => _state.uiFlags,
  getLastError: _state => _state.lastError,
};

export const actions = {
  async fetch({ commit }) {
    commit(types.SET_UI_FLAG, { isFetching: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantsAPI.get();
      commit(types.SET_RECORDS, Array.isArray(data) ? data : data?.data || []);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  setActive({ commit }, id) {
    commit(types.SET_ACTIVE_ID, id ?? null);
  },

  async create({ commit }, payload) {
    commit(types.SET_UI_FLAG, { isCreating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantsAPI.create(payload);
      const record = data?.data || data;
      commit(types.ADD_RECORD, record);
      return record;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isCreating: false });
    }
  },

  async update({ commit }, { id, ...payload }) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantsAPI.update(id, payload);
      const record = data?.data || data;
      commit(types.UPDATE_RECORD, record);
      return record;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },

  async delete({ commit }, id) {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotAssistantsAPI.delete(id);
      commit(types.REMOVE_RECORD, id);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
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

  [types.ADD_RECORD]($state, record) {
    if (!record) return;
    $state.records = [record, ...$state.records];
  },

  [types.UPDATE_RECORD]($state, record) {
    if (!record) return;
    $state.records = $state.records.map(r => (r.id === record.id ? record : r));
  },

  [types.REMOVE_RECORD]($state, id) {
    $state.records = $state.records.filter(r => r.id !== id);
    if ($state.activeId === id) $state.activeId = null;
  },

  [types.SET_ACTIVE_ID]($state, id) {
    $state.activeId = id;
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
