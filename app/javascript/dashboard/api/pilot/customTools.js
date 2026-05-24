/* global axios */
import ApiClient from '../ApiClient';

class PilotCustomToolsAPI extends ApiClient {
  constructor() {
    super('pilot/custom_tools', { accountScoped: true, apiVersion: 'v2' });
  }

  list({ page = 1 } = {}) {
    return axios.get(this.url, { params: { page } });
  }

  show({ id }) {
    return axios.get(`${this.url}/${id}`);
  }

  create(attrs) {
    return axios.post(this.url, attrs);
  }

  update({ id, ...attrs }) {
    return axios.patch(`${this.url}/${id}`, attrs);
  }

  destroy({ id }) {
    return axios.delete(`${this.url}/${id}`);
  }

  setEnabled({ id, enabled }) {
    return axios.patch(`${this.url}/${id}`, { enabled });
  }

  test({ draft } = {}) {
    return axios.post(`${this.url}/test`, draft);
  }
}

export default new PilotCustomToolsAPI();
