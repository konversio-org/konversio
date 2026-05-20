/* global axios */
import ApiClient from '../ApiClient';

class PilotAssistantResponsesAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true, apiVersion: 'v2' });
  }

  nestedUrl(assistantId) {
    return `${this.url}/${assistantId}/responses`;
  }

  list({ assistantId, page = 1, search = '', status = '' } = {}) {
    const params = { page };
    if (search) params.search = search;
    if (status) params.status = status;
    return axios.get(this.nestedUrl(assistantId), { params });
  }

  create({ assistantId, question, answer, status } = {}) {
    const payload = { question, answer };
    if (status) payload.status = status;
    return axios.post(this.nestedUrl(assistantId), payload);
  }

  update({ assistantId, id, question, answer, status } = {}) {
    const payload = {};
    if (question !== undefined) payload.question = question;
    if (answer !== undefined) payload.answer = answer;
    if (status !== undefined) payload.status = status;
    return axios.patch(`${this.nestedUrl(assistantId)}/${id}`, payload);
  }

  destroy({ assistantId, id } = {}) {
    return axios.delete(`${this.nestedUrl(assistantId)}/${id}`);
  }
}

export default new PilotAssistantResponsesAPI();
