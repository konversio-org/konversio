/* global axios */
import ApiClient from '../ApiClient';

class PilotFollowUpsAPI extends ApiClient {
  constructor() {
    super('pilot/follow_ups', { accountScoped: true, apiVersion: 'v2' });
  }

  generate(conversationId) {
    return axios.post(this.url, { conversation_id: conversationId });
  }
}

export default new PilotFollowUpsAPI();
