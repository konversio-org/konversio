/* global axios */
import ApiClient from '../ApiClient';

class PilotDocumentsAPI extends ApiClient {
  constructor() {
    super('pilot/documents', { accountScoped: true });
  }

  get({ assistantId, status, source, syncState, page } = {}) {
    const params = {};
    if (assistantId) params.assistant_id = assistantId;
    if (status) params.status = status;
    if (source) params.source = source;
    if (syncState) params.sync_state = syncState;
    if (page) params.page = page;
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // Accepts either:
  //   - a plain object { assistantId, externalLink } (JSON body)
  //   - a plain object { assistantId, pdfFile: File } (multipart body)
  //   - a plain object { assistantId, markdownFile: File } (multipart body)
  //   - a plain object { assistantId, markdownContent: string } (JSON body)
  // Returns the axios promise.
  create(payload = {}) {
    const {
      assistantId,
      externalLink,
      pdfFile,
      markdownFile,
      markdownContent,
    } = payload;

    if (pdfFile || markdownFile) {
      const formData = new FormData();
      if (assistantId) formData.append('document[assistant_id]', assistantId);
      if (pdfFile) formData.append('document[pdf_file]', pdfFile);
      if (markdownFile) {
        formData.append('document[markdown_file]', markdownFile);
      }
      return axios.post(this.url, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }

    const body = { document: {} };
    if (assistantId) body.document.assistant_id = assistantId;
    if (externalLink) body.document.external_link = externalLink;
    if (markdownContent) body.document.markdown_content = markdownContent;
    return axios.post(this.url, body);
  }

  refresh(id) {
    return axios.post(`${this.url}/${id}/refresh`);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PilotDocumentsAPI();
