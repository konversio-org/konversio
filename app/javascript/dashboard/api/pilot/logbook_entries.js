/* global axios */
import ApiClient from '../ApiClient';

class PilotLogbookEntriesAPI extends ApiClient {
  constructor() {
    super('pilot/logbook_entries', { accountScoped: true, apiVersion: 'v2' });
  }

  list(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }

  create(contactId, content) {
    return axios.post(this.url, { contact_id: contactId, content });
  }

  update(id, content) {
    return axios.patch(`${this.url}/${id}`, { content });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PilotLogbookEntriesAPI();
