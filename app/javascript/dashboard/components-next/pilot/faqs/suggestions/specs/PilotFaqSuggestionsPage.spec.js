import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import PilotFaqSuggestionsPage from '../PilotFaqSuggestionsPage.vue';
import faqSuggestionsModule from 'dashboard/store/pilot/faqSuggestions';
import PilotFaqSuggestionsAPI from 'dashboard/api/pilot/faqSuggestions';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router');

const alertMock = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alertMock(...args),
}));

vi.mock('dashboard/api/pilot/faqSuggestions', () => ({
  default: {
    list: vi.fn(),
    show: vi.fn(),
    update: vi.fn(),
    approve: vi.fn(),
    dismiss: vi.fn(),
  },
}));

const assistantsStub = {
  namespaced: true,
  state: { records: [] },
  getters: {
    getRecords: _state => _state.records,
    getUIFlags: () => ({ isFetching: false }),
  },
};

const buildStore = assistants =>
  createStore({
    modules: {
      'pilot/faqSuggestions': faqSuggestionsModule,
      'pilot/assistants': { ...assistantsStub, state: { records: assistants } },
    },
  });

const listResponse = (records, meta = {}) => ({
  data: {
    data: records,
    meta: {
      current_page: 1,
      per_page: 25,
      total_count: records.length,
      total_pages: 1,
      ...meta,
    },
  },
});

const mount = store =>
  shallowMount(PilotFaqSuggestionsPage, {
    global: {
      plugins: [store],
      stubs: {
        Button: true,
        AssistantPicker: true,
        FaqSearchInput: true,
        FaqPagerFooter: true,
        SuggestionCard: true,
        SuggestionReviewDialog: true,
      },
    },
  });

const flush = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

describe('PilotFaqSuggestionsPage.vue', () => {
  const replaceMock = vi.fn();
  const pushMock = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    replaceMock.mockResolvedValue(undefined);
    useRoute.mockReturnValue({ query: {}, name: 'pilot_faq_suggestions' });
    useRouter.mockReturnValue({ push: pushMock, replace: replaceMock });
  });

  it('fetches open suggestions for the default assistant on mount', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(
      listResponse([{ id: 1, question: 'Q?' }])
    );
    const store = buildStore([{ id: 5, name: 'Support' }]);

    const wrapper = mount(store);
    await flush();

    expect(PilotFaqSuggestionsAPI.list).toHaveBeenCalledWith({
      assistantId: 5,
      page: 1,
      search: '',
      status: 'open',
      signal: undefined,
    });
    expect(wrapper.findAllComponents({ name: 'SuggestionCard' })).toHaveLength(
      1
    );
  });

  it('refetches with the search term and resets the page on search change', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(listResponse([]));
    const store = buildStore([{ id: 5 }]);
    const wrapper = mount(store);
    await flush();

    wrapper.vm.onSearchChange('refund');
    await flush();

    expect(PilotFaqSuggestionsAPI.list).toHaveBeenLastCalledWith({
      assistantId: 5,
      page: 1,
      search: 'refund',
      status: 'open',
      signal: undefined,
    });
    expect(replaceMock).toHaveBeenCalledWith({
      query: expect.objectContaining({ search: 'refund' }),
    });
  });

  it('fetches the requested page and syncs the URL on page change', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(
      listResponse([{ id: 9 }], { total_count: 30, total_pages: 2 })
    );
    const store = buildStore([{ id: 5 }]);
    const wrapper = mount(store);
    await flush();

    wrapper.vm.onPageChange(2);
    await flush();

    expect(PilotFaqSuggestionsAPI.list).toHaveBeenLastCalledWith({
      assistantId: 5,
      page: 2,
      search: '',
      status: 'open',
      signal: undefined,
    });
    expect(replaceMock).toHaveBeenCalledWith({
      query: expect.objectContaining({ page: '2' }),
    });
  });

  it('quick-approves a suggestion, alerts, and refreshes the list', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(
      listResponse([{ id: 1 }, { id: 2 }], { total_count: 2 })
    );
    PilotFaqSuggestionsAPI.approve.mockResolvedValue({ data: { id: 10 } });
    const store = buildStore([{ id: 5 }]);
    const wrapper = mount(store);
    await flush();

    await wrapper.vm.onQuickApprove({ id: 1 });

    expect(PilotFaqSuggestionsAPI.approve).toHaveBeenCalledWith(1, {
      question: undefined,
      answer: undefined,
    });
    expect(alertMock).toHaveBeenCalledWith(
      'PILOT.FAQ_SUGGESTIONS.SUCCESS.APPROVED'
    );
  });

  it('dismisses a suggestion, alerts, and refreshes the list', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(
      listResponse([{ id: 1 }], { total_count: 1 })
    );
    PilotFaqSuggestionsAPI.dismiss.mockResolvedValue({});
    const store = buildStore([{ id: 5 }]);
    const wrapper = mount(store);
    await flush();

    await wrapper.vm.onDismiss({ id: 1 });

    expect(PilotFaqSuggestionsAPI.dismiss).toHaveBeenCalledWith(1);
    expect(alertMock).toHaveBeenCalledWith(
      'PILOT.FAQ_SUGGESTIONS.SUCCESS.DISMISSED'
    );
  });

  it('approves with dialog edits and refreshes the list', async () => {
    PilotFaqSuggestionsAPI.list.mockResolvedValue(
      listResponse([{ id: 1 }], { total_count: 1 })
    );
    PilotFaqSuggestionsAPI.approve.mockResolvedValue({ data: { id: 10 } });
    const store = buildStore([{ id: 5 }]);
    const wrapper = mount(store);
    await flush();

    await wrapper.vm.onDialogApprove({
      id: 1,
      question: 'Q?',
      answer: 'Edited.',
    });

    expect(PilotFaqSuggestionsAPI.approve).toHaveBeenCalledWith(1, {
      question: 'Q?',
      answer: 'Edited.',
    });
    expect(alertMock).toHaveBeenCalledWith(
      'PILOT.FAQ_SUGGESTIONS.SUCCESS.APPROVED'
    );
  });
});
