/* global axios */
import ApiClient from '../ApiClient';

class PilotRewritesAPI extends ApiClient {
  constructor() {
    super('pilot/rewrites', { accountScoped: true, apiVersion: 'v2' });
  }

  generate({ text, operation }) {
    return axios.post(this.url, { text, operation });
  }
}

export default new PilotRewritesAPI();
