import AssignableAgentsAPI from '../../api/assignableAgents';

const state = {
  records: {},
  aiAssigneeRecords: {},
  uiFlags: {
    isFetching: false,
  },
};

export const types = {
  SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG: 'SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG',
  SET_INBOX_ASSIGNABLE_AGENTS: 'SET_INBOX_ASSIGNABLE_AGENTS',
  SET_INBOX_ASSIGNABLE_AI_ASSIGNEES: 'SET_INBOX_ASSIGNABLE_AI_ASSIGNEES',
};

export const getters = {
  getAssignableAgents: $state => inboxId => {
    const allAgents = $state.records[inboxId] || [];
    const verifiedAgents = allAgents.filter(record => record.confirmed);
    return verifiedAgents;
  },
  // Opt-in AI assignees (Pilot assistants and agent bots), kept out of the
  // human agent records so consumers that assume users are unaffected.
  getAssignableAiAssignees: $state => inboxId => {
    return $state.aiAssigneeRecords[inboxId] || [];
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  async fetch({ commit }, inboxIds) {
    commit(types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload, ai_assignees: aiAssignees = [] },
      } = await AssignableAgentsAPI.get(inboxIds, { includeAiAssignees: true });
      commit(types.SET_INBOX_ASSIGNABLE_AGENTS, {
        inboxId: inboxIds.join(','),
        members: payload,
      });
      commit(types.SET_INBOX_ASSIGNABLE_AI_ASSIGNEES, {
        inboxId: inboxIds.join(','),
        members: aiAssignees,
      });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG, { isFetching: false });
    }
  },
};

export const mutations = {
  [types.SET_INBOX_ASSIGNABLE_AGENTS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.SET_INBOX_ASSIGNABLE_AGENTS]: ($state, { inboxId, members }) => {
    $state.records = {
      ...$state.records,
      [inboxId]: members,
    };
  },
  [types.SET_INBOX_ASSIGNABLE_AI_ASSIGNEES]: ($state, { inboxId, members }) => {
    $state.aiAssigneeRecords = {
      ...$state.aiAssigneeRecords,
      [inboxId]: members,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
