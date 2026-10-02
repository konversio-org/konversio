/* global axios */
import ApiClient from '../ApiClient';

class PilotPreferencesAPI extends ApiClient {
  constructor() {
    super('pilot/preferences', { accountScoped: true });
  }

  fetch() {
    return axios.get(this.url);
  }

  update(payload) {
    return axios.patch(this.url, payload);
  }
}

export default new PilotPreferencesAPI();
