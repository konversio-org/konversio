/* global axios */
import ApiClient from '../ApiClient';

class PilotEventsAPI extends ApiClient {
  constructor() {
    super('pilot/events', { accountScoped: true, apiVersion: 'v2' });
  }

  list({ page = 1 } = {}) {
    return axios.get(this.url, { params: { page } });
  }
}

export default new PilotEventsAPI();
