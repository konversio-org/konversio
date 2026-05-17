/* global axios */
import ApiClient from '../ApiClient';

class PilotBriefingsAPI extends ApiClient {
  constructor() {
    super('pilot/briefings', { accountScoped: true, apiVersion: 'v2' });
  }

  generate(conversationId) {
    return axios.post(this.url, { conversation_id: conversationId });
  }
}

export default new PilotBriefingsAPI();
