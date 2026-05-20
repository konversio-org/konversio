import PilotDocumentsAPI from 'dashboard/api/pilot/documents';

const types = {
  SET_UI_FLAG: 'pilot/documents/SET_UI_FLAG',
  SET_RECORDS: 'pilot/documents/SET_RECORDS',
  ADD_RECORD: 'pilot/documents/ADD_RECORD',
  REMOVE_RECORD: 'pilot/documents/REMOVE_RECORD',
  SET_META: 'pilot/documents/SET_META',
  SET_ACTIVE_ASSISTANT: 'pilot/documents/SET_ACTIVE_ASSISTANT',
  SET_STATUS_FILTER: 'pilot/documents/SET_STATUS_FILTER',
  SET_LAST_ERROR: 'pilot/documents/SET_LAST_ERROR',
};

const DEFAULT_META = {
  current_page: 1,
  total_count: 0,
  total_pages: 1,
};

export const state = {
  records: [],
  meta: { ...DEFAULT_META },
  activeAssistantId: null,
  statusFilter: null,
  lastError: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
  },
};

export const getters = {
  getRecords: _state => _state.records,
  getMeta: _state => _state.meta,
  getActiveAssistantId: _state => _state.activeAssistantId,
  getStatusFilter: _state => _state.statusFilter,
  getUIFlags: _state => _state.uiFlags,
  getLastError: _state => _state.lastError,
};

const normalizeListResponse = data => {
  if (Array.isArray(data)) {
    return {
      records: data,
      meta: { ...DEFAULT_META, total_count: data.length },
    };
  }
  return {
    records: Array.isArray(data?.data) ? data.data : [],
    meta: { ...DEFAULT_META, ...(data?.meta || {}) },
  };
};

export const actions = {
  setAssistant({ commit }, id) {
    commit(types.SET_ACTIVE_ASSISTANT, id ?? null);
  },

  setStatus({ commit }, status) {
    commit(types.SET_STATUS_FILTER, status ?? null);
  },

  async fetch({ commit, state: $state }, params = {}) {
    const assistantId = params.assistantId ?? $state.activeAssistantId;
    const status = params.status ?? $state.statusFilter;
    const page = params.page ?? $state.meta.current_page ?? 1;

    commit(types.SET_UI_FLAG, { isFetching: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotDocumentsAPI.get({
        assistantId,
        status,
        page,
      });
      const { records, meta } = normalizeListResponse(data);
      commit(types.SET_RECORDS, records);
      commit(types.SET_META, meta);
      return records;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  async create({ commit }, payload) {
    commit(types.SET_UI_FLAG, { isCreating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotDocumentsAPI.create(payload);
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

  async delete({ commit }, id) {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotDocumentsAPI.delete(id);
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
    $state.meta = {
      ...$state.meta,
      total_count: ($state.meta.total_count || 0) + 1,
    };
  },

  [types.REMOVE_RECORD]($state, id) {
    const existed = $state.records.some(r => r.id === id);
    $state.records = $state.records.filter(r => r.id !== id);
    if (existed) {
      $state.meta = {
        ...$state.meta,
        total_count: Math.max(0, ($state.meta.total_count || 0) - 1),
      };
    }
  },

  [types.SET_META]($state, meta) {
    $state.meta = { ...DEFAULT_META, ...(meta || {}) };
  },

  [types.SET_ACTIVE_ASSISTANT]($state, id) {
    $state.activeAssistantId = id;
  },

  [types.SET_STATUS_FILTER]($state, status) {
    $state.statusFilter = status;
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
