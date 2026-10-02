/* global axios */
import ApiClient from '../ApiClient';

class PilotFaqSuggestionsAPI extends ApiClient {
  constructor() {
    super('pilot/faq_suggestions', { accountScoped: true, apiVersion: 'v1' });
  }

  list({
    page = 1,
    search = '',
    assistantId = null,
    status = 'open',
    signal,
  } = {}) {
    const params = { page, status };
    if (search) params.search = search;
    if (assistantId) params.assistant_id = assistantId;
    return axios.get(this.url, { params, signal });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  update(id, { question, answer } = {}) {
    const payload = {};
    if (question !== undefined) payload.question = question;
    if (answer !== undefined) payload.answer = answer;
    return axios.patch(`${this.url}/${id}`, payload);
  }

  approve(id, { question, answer } = {}) {
    const payload = {};
    if (question !== undefined) payload.question = question;
    if (answer !== undefined) payload.answer = answer;
    return axios.post(`${this.url}/${id}/approve`, payload);
  }

  dismiss(id) {
    return axios.post(`${this.url}/${id}/dismiss`);
  }
}

export default new PilotFaqSuggestionsAPI();
