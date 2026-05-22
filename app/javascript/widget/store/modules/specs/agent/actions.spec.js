import { actions } from '../../agent';
import { agents } from './data';
import { getAvailableAgents } from 'widget/api/agent';

let commit = vi.fn();
vi.mock('widget/helpers/axios');

vi.mock('widget/api/agent');

describe('#actions', () => {
  describe('#fetchAvailableAgents', () => {
    const websiteToken = 'test-token';

    beforeEach(() => {
      commit = vi.fn();
      vi.clearAllMocks();
    });

    it('fetches available agents', async () => {
      getAvailableAgents.mockReturnValue({ data: { payload: agents } });

      await actions.fetchAvailableAgents({ commit }, websiteToken);

      expect(getAvailableAgents).toHaveBeenCalledWith(websiteToken);
      expect(commit).toHaveBeenCalledWith('setAgents', agents);
      expect(commit).toHaveBeenCalledWith('setError', false);
      expect(commit).toHaveBeenCalledWith('setHasFetched', true);
    });

    it('sends correct actions if API is success', async () => {
      getAvailableAgents.mockReturnValue({ data: { payload: agents } });
      await actions.fetchAvailableAgents({ commit }, 'Hi');
      expect(commit.mock.calls).toEqual([
        ['setAgents', agents],
        ['setError', false],
        ['setHasFetched', true],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      getAvailableAgents.mockRejectedValue({
        message: 'Authentication required',
      });
      await actions.fetchAvailableAgents({ commit }, 'Hi');
      expect(commit.mock.calls).toEqual([
        ['setError', true],
        ['setHasFetched', true],
      ]);
    });
  });

  describe('#updatePresence', () => {
    it('commits the correct presence value', () => {
      actions.updatePresence({ commit }, { 1: 'online' });
      expect(commit.mock.calls).toEqual([['updatePresence', { 1: 'online' }]]);
    });
  });
});
