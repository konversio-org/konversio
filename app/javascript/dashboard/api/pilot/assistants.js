/* global axios */
import ApiClient from '../ApiClient';

class PilotAssistantsAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true });
  }

  getTools() {
    return axios.get(`${this.url}/tools`);
  }

  uploadAvatar(id, file) {
    const formData = new FormData();
    formData.append('avatar', file);
    return axios.patch(`${this.url}/${id}`, formData);
  }

  deleteAvatar(id) {
    return axios.delete(`${this.url}/${id}/avatar`);
  }
}

export default new PilotAssistantsAPI();
