import PilotAssistantResponsesAPI from 'dashboard/api/pilot/assistantResponses';
import PilotBulkActionsAPI from 'dashboard/api/pilot/bulkActions';

const types = {
  SET_UI_FLAG: 'pilot/faqs/SET_UI_FLAG',
  SET_RECORDS: 'pilot/faqs/SET_RECORDS',
  SET_META: 'pilot/faqs/SET_META',
  ADD_RECORD: 'pilot/faqs/ADD_RECORD',
  UPDATE_RECORD: 'pilot/faqs/UPDATE_RECORD',
  REMOVE_RECORD: 'pilot/faqs/REMOVE_RECORD',
  SET_ASSISTANT_ID: 'pilot/faqs/SET_ASSISTANT_ID',
  SET_SEARCH: 'pilot/faqs/SET_SEARCH',
  SET_STATUS: 'pilot/faqs/SET_STATUS',
  SET_LAST_ERROR: 'pilot/faqs/SET_LAST_ERROR',
  SET_PENDING_COUNT: 'pilot/faqs/SET_PENDING_COUNT',
  UPDATE_BULK_RESPONSES: 'pilot/faqs/UPDATE_BULK_RESPONSES',
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
  statusFilter: '',
  lastError: null,
  pendingCount: 0,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getRecords: _state => _state.records,
  getMeta: _state => _state.meta,
  getActiveAssistantId: _state => _state.activeAssistantId,
  getSearch: _state => _state.search,
  getStatus: _state => _state.statusFilter,
  getUIFlags: _state => _state.uiFlags,
  getLastError: _state => _state.lastError,
  getPendingCount: _state => _state.pendingCount,
};

export const actions = {
  setAssistant({ commit }, id) {
    commit(types.SET_ASSISTANT_ID, id ?? null);
  },

  setSearch({ commit }, value) {
    commit(types.SET_SEARCH, value || '');
  },

  setStatus({ commit }, value) {
    commit(types.SET_STATUS, value || '');
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
    const status = payload.status ?? _state.statusFilter;

    commit(types.SET_UI_FLAG, { isFetching: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantResponsesAPI.list({
        assistantId,
        page,
        search,
        status,
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

  async createRow({ commit }, payload) {
    commit(types.SET_UI_FLAG, { isCreating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantResponsesAPI.create(payload);
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

  async updateRow({ commit, state: _state }, { id, assistantId, ...attrs }) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAssistantResponsesAPI.update({
        assistantId: assistantId ?? _state.activeAssistantId,
        id,
        ...attrs,
      });
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

  async destroyRow({ commit, state: _state }, payload) {
    const id = typeof payload === 'object' ? payload.id : payload;
    const assistantId =
      (typeof payload === 'object' ? payload.assistantId : null) ??
      _state.activeAssistantId;

    commit(types.SET_UI_FLAG, { isDeleting: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotAssistantResponsesAPI.destroy({ assistantId, id });
      commit(types.REMOVE_RECORD, id);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
    }
  },

  async fetchPendingCount({ commit, state: _state }, payload = {}) {
    const assistantId = payload.assistantId ?? _state.activeAssistantId;
    if (!assistantId) return 0;
    try {
      const { data } = await PilotAssistantResponsesAPI.list({
        assistantId,
        page: 1,
        status: 'pending',
      });
      const count = data?.meta?.total_count || 0;
      commit(types.SET_PENDING_COUNT, count);
      return count;
    } catch (err) {
      return 0;
    }
  },

  async bulkApprove({ commit }, ids) {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotBulkActionsAPI.create({
        type: 'AssistantResponse',
        ids,
        fields: { status: 'approve' },
      });
      commit(types.UPDATE_BULK_RESPONSES, data);
      return data;
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

  [types.ADD_RECORD]($state, record) {
    if (!record) return;
    $state.records = [record, ...$state.records];
    $state.meta = {
      ...$state.meta,
      total_count: ($state.meta.total_count || 0) + 1,
    };
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
  },

  [types.SET_ASSISTANT_ID]($state, id) {
    $state.activeAssistantId = id;
  },

  [types.SET_SEARCH]($state, value) {
    $state.search = value || '';
  },

  [types.SET_STATUS]($state, value) {
    $state.statusFilter = value || '';
  },

  [types.SET_LAST_ERROR]($state, err) {
    $state.lastError = err;
  },

  [types.SET_PENDING_COUNT]($state, count) {
    $state.pendingCount = count;
  },

  [types.UPDATE_BULK_RESPONSES]($state, approvedList) {
    const list = Array.isArray(approvedList)
      ? approvedList
      : approvedList?.data || [];
    const map = {};
    list.forEach(r => {
      map[r.id] = r;
    });
    $state.records = $state.records.map(r => map[r.id] ?? r);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
