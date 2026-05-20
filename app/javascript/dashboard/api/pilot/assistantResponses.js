/* global axios */
import ApiClient from '../ApiClient';

class PilotAssistantResponsesAPI extends ApiClient {
  constructor() {
    super('pilot/assistant_responses', { accountScoped: true });
  }

  list({ assistantId, page = 1, search = '', status = '' } = {}) {
    const params = { assistant_id: assistantId, page };
    if (search) params.search = search;
    if (status) params.status = status;
    return axios.get(this.url, { params });
  }

  create({ assistantId, question, answer, status } = {}) {
    const payload = { assistant_id: assistantId, question, answer };
    if (status) payload.status = status;
    return axios.post(this.url, payload);
  }

  update({ id, question, answer, status } = {}) {
    const payload = {};
    if (question !== undefined) payload.question = question;
    if (answer !== undefined) payload.answer = answer;
    if (status !== undefined) payload.status = status;
    return axios.patch(`${this.url}/${id}`, payload);
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PilotAssistantResponsesAPI();
