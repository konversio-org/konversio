/* global axios */
import ApiClient from '../ApiClient';

class PilotBulkActionsAPI extends ApiClient {
  constructor() {
    super('pilot/bulk_actions', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, payload);
  }
}

export default new PilotBulkActionsAPI();
