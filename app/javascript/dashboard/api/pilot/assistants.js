import ApiClient from '../ApiClient';

class PilotAssistantsAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true });
  }
}

export default new PilotAssistantsAPI();
