import * as types from '../mutation-types';

const state = {
  currentPage: {
    me: 0,
    unassigned: 0,
    all: 0,
    appliedFilters: 0,
  },
  hasEndReached: {
    me: false,
    unassigned: false,
    all: false,
  },
};

export const getters = {
  getHasEndReached: $state => filter => {
    // Dynamic filter keys (e.g. ai_agent_<id>_<tab>) are not pre-declared in
    // state, so default missing keys to false instead of undefined.
    return $state.hasEndReached[filter] ?? false;
  },
  getCurrentPageFilter: $state => filter => {
    // Default missing keys to 0 so page math (currentPage + 1) never yields NaN,
    // which would pin requests to page 1 and loop the IntersectionObserver.
    return $state.currentPage[filter] ?? 0;
  },
  getCurrentPage: $state => {
    return $state.currentPage;
  },
};

export const actions = {
  setCurrentPage({ commit }, { filter, page }) {
    commit(types.default.SET_CURRENT_PAGE, { filter, page });
  },
  setEndReached({ commit }, { filter }) {
    commit(types.default.SET_CONVERSATION_END_REACHED, { filter });
  },
  reset({ commit }) {
    commit(types.default.CLEAR_CONVERSATION_PAGE);
  },
};

export const mutations = {
  [types.default.SET_CURRENT_PAGE]: ($state, { filter, page }) => {
    $state.currentPage = {
      ...$state.currentPage,
      [filter]: page,
    };
  },
  [types.default.SET_CONVERSATION_END_REACHED]: ($state, { filter }) => {
    if (filter === 'all') {
      $state.hasEndReached = {
        ...$state.hasEndReached,
        unassigned: true,
        me: true,
      };
    }
    $state.hasEndReached = {
      ...$state.hasEndReached,
      [filter]: true,
    };
  },
  [types.default.CLEAR_CONVERSATION_PAGE]: $state => {
    const defaultPages = { me: 0, unassigned: 0, all: 0, appliedFilters: 0 };
    const defaultEndReached = {
      me: false,
      unassigned: false,
      all: false,
      appliedFilters: false,
    };

    $state.currentPage = {
      ...defaultPages,
      ...$state.currentPage,
    };
    $state.hasEndReached = {
      ...defaultEndReached,
      ...$state.hasEndReached,
    };

    Object.keys($state.currentPage).forEach(key => {
      $state.currentPage[key] = 0;
    });

    Object.keys($state.hasEndReached).forEach(key => {
      $state.hasEndReached[key] = false;
    });
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
