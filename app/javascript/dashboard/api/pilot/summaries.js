/* global axios */
import ApiClient from '../ApiClient';

class PilotSummariesAPI extends ApiClient {
  constructor() {
    super('pilot/summaries', { accountScoped: true, apiVersion: 'v2' });
  }

  generate(conversationId) {
    return axios.post(this.url, { conversation_id: conversationId });
  }
}

export default new PilotSummariesAPI();
