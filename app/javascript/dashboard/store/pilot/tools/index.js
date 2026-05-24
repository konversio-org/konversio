import PilotCustomToolsAPI from 'dashboard/api/pilot/customTools';

const types = {
  SET_LOADING: 'pilot/tools/SET_LOADING',
  SET_SAVING: 'pilot/tools/SET_SAVING',
  SET_TESTING: 'pilot/tools/SET_TESTING',
  SET_ROWS: 'pilot/tools/SET_ROWS',
  SET_META: 'pilot/tools/SET_META',
  ADD_ROW: 'pilot/tools/ADD_ROW',
  UPDATE_ROW: 'pilot/tools/UPDATE_ROW',
  REMOVE_ROW: 'pilot/tools/REMOVE_ROW',
  SET_ERROR: 'pilot/tools/SET_ERROR',
  SET_TEST_RESULT: 'pilot/tools/SET_TEST_RESULT',
};

const DEFAULT_META = {
  current_page: 1,
  per_page: 25,
  total_count: 0,
  total_pages: 1,
};

export const state = {
  rows: [],
  meta: { ...DEFAULT_META },
  loading: false,
  error: null,
  saving: false,
  testing: false,
  testResult: null,
};

export const getters = {
  getRows: _state => _state.rows,
  getMeta: _state => _state.meta,
  getLoading: _state => _state.loading,
  getError: _state => _state.error,
  getSaving: _state => _state.saving,
  getTesting: _state => _state.testing,
  getTestResult: _state => _state.testResult,
};

export const actions = {
  async fetchPage({ commit, state: _state }, payload = {}) {
    const page = payload.page ?? _state.meta.current_page ?? 1;
    commit(types.SET_LOADING, true);
    commit(types.SET_ERROR, null);
    try {
      const { data } = await PilotCustomToolsAPI.list({ page });
      const rows = Array.isArray(data) ? data : data?.data || [];
      const meta = Array.isArray(data)
        ? { ...DEFAULT_META, total_count: data.length, total_pages: 1 }
        : { ...DEFAULT_META, ...(data?.meta || {}) };

      commit(types.SET_ROWS, rows);
      commit(types.SET_META, meta);
      return data;
    } catch (err) {
      commit(types.SET_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_LOADING, false);
    }
  },

  async createRow({ commit }, payload) {
    commit(types.SET_SAVING, true);
    commit(types.SET_ERROR, null);
    try {
      const { data } = await PilotCustomToolsAPI.create(payload);
      const row = data?.data || data;
      commit(types.ADD_ROW, row);
      return row;
    } catch (err) {
      commit(types.SET_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_SAVING, false);
    }
  },

  async updateRow({ commit }, { id, ...attrs }) {
    commit(types.SET_SAVING, true);
    commit(types.SET_ERROR, null);
    try {
      const { data } = await PilotCustomToolsAPI.update({ id, ...attrs });
      const row = data?.data || data;
      commit(types.UPDATE_ROW, row);
      return row;
    } catch (err) {
      commit(types.SET_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_SAVING, false);
    }
  },

  async destroyRow({ commit }, { id }) {
    commit(types.SET_ERROR, null);
    try {
      await PilotCustomToolsAPI.destroy({ id });
      commit(types.REMOVE_ROW, id);
    } catch (err) {
      commit(types.SET_ERROR, err);
      throw err;
    }
  },

  async setEnabled({ commit, state: _state }, { id, enabled }) {
    const originalRow = _state.rows.find(r => r.id === id);
    if (!originalRow) return;
    const originalEnabled = originalRow.enabled;

    // Optimistically update the UI
    commit(types.UPDATE_ROW, { ...originalRow, enabled });

    try {
      await PilotCustomToolsAPI.setEnabled({ id, enabled });
    } catch (err) {
      // Revert on error
      commit(types.UPDATE_ROW, { ...originalRow, enabled: originalEnabled });
      commit(types.SET_ERROR, err);
      throw err;
    }
  },

  async runTest({ commit }, { id, draft }) {
    commit(types.SET_TESTING, true);
    commit(types.SET_ERROR, null);
    commit(types.SET_TEST_RESULT, null);
    try {
      const { data } = await PilotCustomToolsAPI.test({ id, draft });
      commit(types.SET_TEST_RESULT, data);
      return data;
    } catch (err) {
      commit(types.SET_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_TESTING, false);
    }
  },

  resetTestResult({ commit }) {
    commit(types.SET_TEST_RESULT, null);
  },
};

export const mutations = {
  [types.SET_LOADING]($state, loading) {
    $state.loading = loading;
  },
  [types.SET_SAVING]($state, saving) {
    $state.saving = saving;
  },
  [types.SET_TESTING]($state, testing) {
    $state.testing = testing;
  },
  [types.SET_ROWS]($state, rows) {
    $state.rows = rows;
  },
  [types.SET_META]($state, meta) {
    $state.meta = meta;
  },
  [types.ADD_ROW]($state, row) {
    $state.rows = [row, ...$state.rows];
    $state.meta.total_count = ($state.meta.total_count || 0) + 1;
  },
  [types.UPDATE_ROW]($state, row) {
    $state.rows = $state.rows.map(r => (r.id === row.id ? row : r));
  },
  [types.REMOVE_ROW]($state, id) {
    $state.rows = $state.rows.filter(r => r.id !== id);
    $state.meta.total_count = Math.max(0, ($state.meta.total_count || 0) - 1);
  },
  [types.SET_ERROR]($state, error) {
    $state.error = error;
  },
  [types.SET_TEST_RESULT]($state, result) {
    $state.testResult = result;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
