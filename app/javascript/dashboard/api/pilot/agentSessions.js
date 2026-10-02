/* global axios */
import ApiClient from '../ApiClient';

// Session detail for an AI-authored message. The endpoint is addressed by the
// message id, so there is no list/create surface.
class PilotAgentSessionsAPI extends ApiClient {
  constructor() {
    super('pilot/agent_sessions', { accountScoped: true });
  }

  show(messageId) {
    return axios.get(`${this.url}/${messageId}`);
  }
}

export default new PilotAgentSessionsAPI();
