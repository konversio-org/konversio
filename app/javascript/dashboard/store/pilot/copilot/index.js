import PilotCopilotAPI from 'dashboard/api/pilot/copilot';

const types = {
  SET_UI_FLAG: 'pilot/copilot/SET_UI_FLAG',
  SET_DRAWER_OPEN: 'pilot/copilot/SET_DRAWER_OPEN',
  SET_THREADS: 'pilot/copilot/SET_THREADS',
  ADD_THREAD: 'pilot/copilot/ADD_THREAD',
  SET_ACTIVE_THREAD_ID: 'pilot/copilot/SET_ACTIVE_THREAD_ID',
  SET_MESSAGES: 'pilot/copilot/SET_MESSAGES',
  ADD_MESSAGE: 'pilot/copilot/ADD_MESSAGE',
  REMOVE_THREAD_MESSAGES: 'pilot/copilot/REMOVE_THREAD_MESSAGES',
  SET_AWAITING_RESPONSE: 'pilot/copilot/SET_AWAITING_RESPONSE',
  SET_BOUND_CONVERSATION_ID: 'pilot/copilot/SET_BOUND_CONVERSATION_ID',
  RESET: 'pilot/copilot/RESET',
};

export const state = {
  drawerOpen: false,
  threads: [],
  activeThreadId: null,
  messagesByThread: {},
  isAwaitingResponse: false,
  boundConversationId: null,
  uiFlags: {
    isFetchingThreads: false,
    isCreatingThread: false,
    isFetchingMessages: false,
    isPostingMessage: false,
  },
};

export const getters = {
  isDrawerOpen: _state => _state.drawerOpen,
  getThreads: _state => _state.threads,
  getActiveThreadId: _state => _state.activeThreadId,
  getActiveThread: _state =>
    _state.threads.find(t => t.id === _state.activeThreadId) || null,
  getActiveThreadMessages: _state => {
    const id = _state.activeThreadId;
    if (!id) return [];
    return _state.messagesByThread[id] || [];
  },
  getIsAwaitingResponse: _state => _state.isAwaitingResponse,
  getBoundConversationId: _state => _state.boundConversationId,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  openDrawer({ commit }) {
    commit(types.SET_DRAWER_OPEN, true);
  },

  closeDrawer({ commit }) {
    commit(types.SET_DRAWER_OPEN, false);
  },

  toggleDrawer({ commit, state: $state }) {
    commit(types.SET_DRAWER_OPEN, !$state.drawerOpen);
  },

  setBoundConversation({ commit }, conversationId) {
    commit(types.SET_BOUND_CONVERSATION_ID, conversationId || null);
  },

  setActiveThread({ commit, dispatch }, threadId) {
    commit(types.SET_ACTIVE_THREAD_ID, threadId);
    if (threadId) dispatch('fetchMessages', threadId);
  },

  resetActiveThread({ commit, state: $state }) {
    const id = $state.activeThreadId;
    commit(types.SET_ACTIVE_THREAD_ID, null);
    if (id) commit(types.REMOVE_THREAD_MESSAGES, id);
    commit(types.SET_AWAITING_RESPONSE, false);
  },

  async fetchThreads({ commit }) {
    commit(types.SET_UI_FLAG, { isFetchingThreads: true });
    try {
      const { data } = await PilotCopilotAPI.fetchThreads();
      commit(types.SET_THREADS, data?.data || data || []);
    } finally {
      commit(types.SET_UI_FLAG, { isFetchingThreads: false });
    }
  },

  async createThread(
    { commit, dispatch },
    { message, assistantId, conversationId }
  ) {
    commit(types.SET_UI_FLAG, { isCreatingThread: true });
    commit(types.SET_AWAITING_RESPONSE, true);
    try {
      const { data } = await PilotCopilotAPI.createThread({
        message,
        assistantId,
        conversationId,
      });
      const thread = data?.data || data;
      commit(types.ADD_THREAD, thread);
      commit(types.SET_ACTIVE_THREAD_ID, thread.id);
      // start polling for the assistant reply via fetchMessages
      dispatch('fetchMessages', thread.id);
      return thread;
    } catch (err) {
      commit(types.SET_AWAITING_RESPONSE, false);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isCreatingThread: false });
    }
  },

  async fetchMessages({ commit, state: $state }, threadId) {
    commit(types.SET_UI_FLAG, { isFetchingMessages: true });
    try {
      const { data } = await PilotCopilotAPI.fetchMessages(threadId);
      const messages = data?.data || data || [];
      commit(types.SET_MESSAGES, { threadId, messages });
      // If the latest message is an assistant message, we're no longer awaiting
      const hasAssistantReply = messages.some(m => m.message_type === 1);
      const lastMessage = messages[messages.length - 1];
      if (
        $state.isAwaitingResponse &&
        hasAssistantReply &&
        lastMessage &&
        lastMessage.message_type !== 0
      ) {
        commit(types.SET_AWAITING_RESPONSE, false);
      }
      return messages;
    } finally {
      commit(types.SET_UI_FLAG, { isFetchingMessages: false });
    }
  },

  async postMessage(
    { commit, dispatch },
    { threadId, message, conversationId }
  ) {
    commit(types.SET_UI_FLAG, { isPostingMessage: true });
    commit(types.SET_AWAITING_RESPONSE, true);
    try {
      const { data } = await PilotCopilotAPI.postMessage(threadId, {
        message,
        conversationId,
      });
      const userMessage = data?.data || data;
      commit(types.ADD_MESSAGE, { threadId, message: userMessage });
      // Kick off a refetch so the UI can poll for the assistant reply
      dispatch('fetchMessages', threadId);
      return userMessage;
    } catch (err) {
      commit(types.SET_AWAITING_RESPONSE, false);
      throw err;
    } finally {
      commit(types.SET_UI_FLAG, { isPostingMessage: false });
    }
  },

  reset({ commit }) {
    commit(types.RESET);
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  [types.SET_DRAWER_OPEN]($state, value) {
    $state.drawerOpen = Boolean(value);
  },

  [types.SET_THREADS]($state, threads) {
    $state.threads = Array.isArray(threads) ? threads : [];
  },

  [types.ADD_THREAD]($state, thread) {
    if (!thread) return;
    const existingIndex = $state.threads.findIndex(t => t.id === thread.id);
    if (existingIndex >= 0) {
      $state.threads = [
        thread,
        ...$state.threads.slice(0, existingIndex),
        ...$state.threads.slice(existingIndex + 1),
      ];
    } else {
      $state.threads = [thread, ...$state.threads];
    }
  },

  [types.SET_ACTIVE_THREAD_ID]($state, id) {
    $state.activeThreadId = id;
  },

  [types.SET_MESSAGES]($state, { threadId, messages }) {
    $state.messagesByThread = {
      ...$state.messagesByThread,
      [threadId]: Array.isArray(messages) ? messages : [],
    };
  },

  [types.ADD_MESSAGE]($state, { threadId, message }) {
    if (!message) return;
    const current = $state.messagesByThread[threadId] || [];
    $state.messagesByThread = {
      ...$state.messagesByThread,
      [threadId]: [...current, message],
    };
  },

  [types.REMOVE_THREAD_MESSAGES]($state, threadId) {
    if (!threadId || !(threadId in $state.messagesByThread)) return;
    const { [threadId]: _removed, ...rest } = $state.messagesByThread;
    $state.messagesByThread = rest;
  },

  [types.SET_AWAITING_RESPONSE]($state, value) {
    $state.isAwaitingResponse = Boolean(value);
  },

  [types.SET_BOUND_CONVERSATION_ID]($state, id) {
    $state.boundConversationId = id;
  },

  [types.RESET]($state) {
    $state.drawerOpen = false;
    $state.threads = [];
    $state.activeThreadId = null;
    $state.messagesByThread = {};
    $state.isAwaitingResponse = false;
    $state.boundConversationId = null;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
