/* global axios */
import ApiClient from '../ApiClient';

class PilotAutopilotAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true });
  }

  // Scenarios
  getScenarios(assistantId) {
    return axios.get(`${this.url}/${assistantId}/scenarios`);
  }

  createScenario(assistantId, scenario) {
    return axios.post(`${this.url}/${assistantId}/scenarios`, { scenario });
  }

  updateScenario(assistantId, id, scenario) {
    return axios.patch(`${this.url}/${assistantId}/scenarios/${id}`, {
      scenario,
    });
  }

  deleteScenario(assistantId, id) {
    return axios.delete(`${this.url}/${assistantId}/scenarios/${id}`);
  }

  // Inboxes
  getInboxes(assistantId) {
    return axios.get(`${this.url}/${assistantId}/inboxes`);
  }

  createInbox(assistantId, inboxId) {
    return axios.post(`${this.url}/${assistantId}/inboxes`, {
      inbox_id: inboxId,
    });
  }

  deleteInbox(assistantId, inboxId) {
    return axios.delete(`${this.url}/${assistantId}/inboxes/${inboxId}`);
  }

  // Playground
  playground(assistantId, { messageContent, messageHistory }) {
    return axios.post(`${this.url}/${assistantId}/playground`, {
      message_content: messageContent,
      message_history: messageHistory,
    });
  }
}

export default new PilotAutopilotAPI();
