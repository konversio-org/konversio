/* global axios */
import ApiClient from '../ApiClient';

class PilotAssistantsAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true });
  }

  getTools() {
    return axios.get(`${this.url}/tools`);
  }
}

export default new PilotAssistantsAPI();
