/* global axios */
import ApiClient from '../ApiClient';

class PilotRewritesAPI extends ApiClient {
  constructor() {
    super('pilot/rewrites', { accountScoped: true, apiVersion: 'v2' });
  }

  generate({ text, tone }) {
    return axios.post(this.url, { text, tone });
  }
}

export default new PilotRewritesAPI();
