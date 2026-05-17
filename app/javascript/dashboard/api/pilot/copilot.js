/* global axios */
import ApiClient from '../ApiClient';

class PilotCopilotAPI extends ApiClient {
  constructor() {
    super('pilot/copilot_threads', { accountScoped: true, apiVersion: 'v2' });
  }

  fetchThreads() {
    return axios.get(this.url);
  }

  createThread({ message, assistantId, conversationId }) {
    const payload = { message };
    if (assistantId) payload.assistant_id = assistantId;
    if (conversationId) payload.conversation_id = conversationId;
    return axios.post(this.url, payload);
  }

  fetchMessages(threadId) {
    return axios.get(`${this.url}/${threadId}/copilot_messages`);
  }

  postMessage(threadId, { message, conversationId }) {
    const payload = { message };
    if (conversationId) payload.conversation_id = conversationId;
    return axios.post(`${this.url}/${threadId}/copilot_messages`, payload);
  }
}

export default new PilotCopilotAPI();
