import PilotAutopilotAPI from 'dashboard/api/pilot/autopilot';

const types = {
  SET_UI_FLAG: 'pilot/autopilot/SET_UI_FLAG',
  SET_SCENARIOS: 'pilot/autopilot/SET_SCENARIOS',
  ADD_SCENARIO: 'pilot/autopilot/ADD_SCENARIO',
  UPDATE_SCENARIO: 'pilot/autopilot/UPDATE_SCENARIO',
  REMOVE_SCENARIO: 'pilot/autopilot/REMOVE_SCENARIO',
  SET_INBOXES: 'pilot/autopilot/SET_INBOXES',
  ADD_INBOX: 'pilot/autopilot/ADD_INBOX',
  REMOVE_INBOX: 'pilot/autopilot/REMOVE_INBOX',
  SET_LAST_ERROR: 'pilot/autopilot/SET_LAST_ERROR',
};

export const state = {
  scenarios: [],
  inboxes: [],
  lastError: null,
  uiFlags: {
    isFetchingScenarios: false,
    isCreatingScenario: false,
    isUpdatingScenario: false,
    isDeletingScenario: false,
    isFetchingInboxes: false,
    isCreatingInbox: false,
    isDeletingInbox: false,
    isSendingPlayground: false,
  },
};

export const getters = {
  getScenarios: _state => _state.scenarios,
  getInboxes: _state => _state.inboxes,
  getUIFlags: _state => _state.uiFlags,
  getLastError: _state => _state.lastError,
};

export const actions = {
  // Scenarios
  async fetchScenarios({ commit }, assistantId) {
    if (!assistantId) return;
    commit(types.SET_UI_FLAG, { isFetchingScenarios: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.getScenarios(assistantId);
      commit(types.SET_SCENARIOS, data?.data || data || []);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isFetchingScenarios: false });
    }
  },

  async createScenario({ commit }, { assistantId, scenario }) {
    commit(types.SET_UI_FLAG, { isCreatingScenario: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.createScenario(
        assistantId,
        scenario
      );
      const record = data?.data || data;
      commit(types.ADD_SCENARIO, record);
      return record;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isCreatingScenario: false });
    }
  },

  async updateScenario({ commit }, { assistantId, id, scenario }) {
    commit(types.SET_UI_FLAG, { isUpdatingScenario: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.updateScenario(
        assistantId,
        id,
        scenario
      );
      const record = data?.data || data;
      commit(types.UPDATE_SCENARIO, record);
      return record;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isUpdatingScenario: false });
    }
  },

  async deleteScenario({ commit }, { assistantId, id }) {
    commit(types.SET_UI_FLAG, { isDeletingScenario: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotAutopilotAPI.deleteScenario(assistantId, id);
      commit(types.REMOVE_SCENARIO, id);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isDeletingScenario: false });
    }
  },

  // Inboxes
  async fetchInboxes({ commit }, assistantId) {
    if (!assistantId) return;
    commit(types.SET_UI_FLAG, { isFetchingInboxes: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.getInboxes(assistantId);
      commit(types.SET_INBOXES, data?.data || data || []);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isFetchingInboxes: false });
    }
  },

  async createInbox({ commit }, { assistantId, inboxId }) {
    commit(types.SET_UI_FLAG, { isCreatingInbox: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.createInbox(
        assistantId,
        inboxId
      );
      const record = data?.data || data;
      commit(types.ADD_INBOX, record);
      return record;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isCreatingInbox: false });
    }
  },

  async deleteInbox({ commit }, { assistantId, inboxId }) {
    commit(types.SET_UI_FLAG, { isDeletingInbox: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      await PilotAutopilotAPI.deleteInbox(assistantId, inboxId);
      commit(types.REMOVE_INBOX, inboxId);
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isDeletingInbox: false });
    }
  },

  // Playground
  async sendPlaygroundMessage(
    { commit },
    { assistantId, messageContent, messageHistory }
  ) {
    commit(types.SET_UI_FLAG, { isSendingPlayground: true });
    commit(types.SET_LAST_ERROR, null);
    try {
      const { data } = await PilotAutopilotAPI.playground(assistantId, {
        messageContent,
        messageHistory,
      });
      return data;
    } catch (err) {
      commit(types.SET_LAST_ERROR, err);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isSendingPlayground: false });
    }
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_SCENARIOS]($state, scenarios) {
    $state.scenarios = Array.isArray(scenarios) ? scenarios : [];
  },

  [types.ADD_SCENARIO]($state, scenario) {
    if (!scenario) return;
    $state.scenarios = [...$state.scenarios, scenario];
  },

  [types.UPDATE_SCENARIO]($state, scenario) {
    if (!scenario) return;
    $state.scenarios = $state.scenarios.map(s =>
      s.id === scenario.id ? scenario : s
    );
  },

  [types.REMOVE_SCENARIO]($state, id) {
    $state.scenarios = $state.scenarios.filter(s => s.id !== id);
  },

  [types.SET_INBOXES]($state, inboxes) {
    $state.inboxes = Array.isArray(inboxes) ? inboxes : [];
  },

  [types.ADD_INBOX]($state, inbox) {
    if (!inbox) return;
    $state.inboxes = [...$state.inboxes, inbox];
  },

  [types.REMOVE_INBOX]($state, inboxId) {
    $state.inboxes = $state.inboxes.filter(
      i => i.inbox_id !== inboxId && i.id !== inboxId
    );
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
