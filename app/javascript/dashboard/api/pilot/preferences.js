/* global axios */
import ApiClient from '../ApiClient';

class PilotPreferencesAPI extends ApiClient {
  constructor() {
    super('pilot/preferences', { accountScoped: true });
  }

  fetch() {
    return axios.get(this.url);
  }
}

export default new PilotPreferencesAPI();
