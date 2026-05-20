/* global axios */
import ApiClient from '../ApiClient';

class PilotDocumentsAPI extends ApiClient {
  constructor() {
    super('pilot/documents', { accountScoped: true });
  }

  get({ assistantId, status, page } = {}) {
    const params = {};
    if (assistantId) params.assistant_id = assistantId;
    if (status) params.status = status;
    if (page) params.page = page;
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // Accepts either:
  //   - a plain object { assistantId, externalLink } (JSON body)
  //   - a plain object { assistantId, pdfFile: File } (multipart body)
  // Returns the axios promise.
  create(payload = {}) {
    const { assistantId, externalLink, pdfFile } = payload;

    if (pdfFile) {
      const formData = new FormData();
      if (assistantId) formData.append('document[assistant_id]', assistantId);
      formData.append('document[pdf_file]', pdfFile);
      return axios.post(this.url, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }

    const body = { document: {} };
    if (assistantId) body.document.assistant_id = assistantId;
    if (externalLink) body.document.external_link = externalLink;
    return axios.post(this.url, body);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PilotDocumentsAPI();
