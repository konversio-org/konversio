import { createStore } from 'vuex';
import PilotFaqSuggestionsAPI from 'dashboard/api/pilot/faqSuggestions';
import module from 'dashboard/store/pilot/faqSuggestions';

vi.mock('dashboard/api/pilot/faqSuggestions', () => ({
  default: {
    list: vi.fn(),
    update: vi.fn(),
    approve: vi.fn(),
    dismiss: vi.fn(),
  },
}));

const NS = 'pilot/faqSuggestions';

const buildStore = () => createStore({ modules: { [NS]: module } });

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

const seedRecords = async (store, records) => {
  PilotFaqSuggestionsAPI.list.mockResolvedValueOnce(listResponse(records));
  await store.dispatch(`${NS}/fetchPage`, { assistantId: 5 });
};

describe('pilot/faqSuggestions store', () => {
  let store;

  beforeEach(() => {
    vi.clearAllMocks();
    store = buildStore();
  });

  describe('fetchPage', () => {
    it('fetches the open page for an assistant and stores records and meta', async () => {
      PilotFaqSuggestionsAPI.list.mockResolvedValue(
        listResponse([{ id: 1, question: 'Q?' }], { total_count: 7 })
      );

      await store.dispatch(`${NS}/fetchPage`, {
        assistantId: 5,
        page: 2,
        search: 'refund',
      });

      expect(PilotFaqSuggestionsAPI.list).toHaveBeenCalledWith({
        assistantId: 5,
        page: 2,
        search: 'refund',
        status: 'open',
        signal: undefined,
      });
      expect(store.getters[`${NS}/getRecords`]).toEqual([
        { id: 1, question: 'Q?' },
      ]);
      expect(store.getters[`${NS}/getMeta`].total_count).toBe(7);
    });

    it('clears records when no assistant is active', async () => {
      const data = await store.dispatch(`${NS}/fetchPage`, {});

      expect(data).toBeNull();
      expect(PilotFaqSuggestionsAPI.list).not.toHaveBeenCalled();
      expect(store.getters[`${NS}/getRecords`]).toEqual([]);
    });
  });

  describe('fetchOpenCount', () => {
    it('stores the total_count from a page-1 open query', async () => {
      PilotFaqSuggestionsAPI.list.mockResolvedValue(
        listResponse([], { total_count: 4 })
      );

      const count = await store.dispatch(`${NS}/fetchOpenCount`, {
        assistantId: 5,
      });

      expect(PilotFaqSuggestionsAPI.list).toHaveBeenCalledWith({
        assistantId: 5,
        page: 1,
        status: 'open',
      });
      expect(count).toBe(4);
      expect(store.getters[`${NS}/getOpenCount`]).toBe(4);
    });

    it('ignores a stale response when a newer count request was issued', async () => {
      let resolveFirst;
      PilotFaqSuggestionsAPI.list
        .mockImplementationOnce(
          () =>
            new Promise(resolve => {
              resolveFirst = resolve;
            })
        )
        .mockResolvedValueOnce(listResponse([], { total_count: 9 }));

      const first = store.dispatch(`${NS}/fetchOpenCount`, { assistantId: 5 });
      await store.dispatch(`${NS}/fetchOpenCount`, { assistantId: 5 });
      resolveFirst(listResponse([], { total_count: 3 }));
      await first;

      expect(store.getters[`${NS}/getOpenCount`]).toBe(9);
    });
  });

  describe('saveRow', () => {
    it('updates the record in place', async () => {
      await seedRecords(store, [{ id: 1, question: 'Old?' }]);
      PilotFaqSuggestionsAPI.update.mockResolvedValue({
        data: { id: 1, question: 'New?' },
      });

      await store.dispatch(`${NS}/saveRow`, {
        id: 1,
        question: 'New?',
        answer: 'A.',
      });

      expect(PilotFaqSuggestionsAPI.update).toHaveBeenCalledWith(1, {
        question: 'New?',
        answer: 'A.',
      });
      expect(store.getters[`${NS}/getRecords`]).toEqual([
        { id: 1, question: 'New?' },
      ]);
    });
  });

  describe('approve', () => {
    it('removes the record locally and decrements counts', async () => {
      await seedRecords(store, [{ id: 1 }, { id: 2 }]);
      PilotFaqSuggestionsAPI.list.mockResolvedValue(
        listResponse([], { total_count: 2 })
      );
      await store.dispatch(`${NS}/fetchOpenCount`, { assistantId: 5 });
      PilotFaqSuggestionsAPI.approve.mockResolvedValue({
        data: { id: 10, status: 'approved' },
      });

      await store.dispatch(`${NS}/approve`, {
        id: 1,
        question: 'Q?',
        answer: 'A.',
      });

      expect(PilotFaqSuggestionsAPI.approve).toHaveBeenCalledWith(1, {
        question: 'Q?',
        answer: 'A.',
      });
      expect(store.getters[`${NS}/getRecords`]).toEqual([{ id: 2 }]);
      expect(store.getters[`${NS}/getMeta`].total_count).toBe(1);
      expect(store.getters[`${NS}/getOpenCount`]).toBe(1);
    });

    it('keeps the record when the request fails', async () => {
      await seedRecords(store, [{ id: 1 }]);
      PilotFaqSuggestionsAPI.approve.mockRejectedValue(new Error('nope'));

      await expect(store.dispatch(`${NS}/approve`, { id: 1 })).rejects.toThrow(
        'nope'
      );
      expect(store.getters[`${NS}/getRecords`]).toEqual([{ id: 1 }]);
    });
  });

  describe('dismiss', () => {
    it('removes the record locally', async () => {
      await seedRecords(store, [{ id: 1 }, { id: 2 }]);
      PilotFaqSuggestionsAPI.list.mockResolvedValue(
        listResponse([], { total_count: 2 })
      );
      await store.dispatch(`${NS}/fetchOpenCount`, { assistantId: 5 });
      PilotFaqSuggestionsAPI.dismiss.mockResolvedValue({});

      await store.dispatch(`${NS}/dismiss`, { id: 2 });

      expect(PilotFaqSuggestionsAPI.dismiss).toHaveBeenCalledWith(2);
      expect(store.getters[`${NS}/getRecords`]).toEqual([{ id: 1 }]);
      expect(store.getters[`${NS}/getOpenCount`]).toBe(1);
    });
  });
});
