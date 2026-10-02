/* global axios */
import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  getWhatsappAnalyticsMetrics(campaignId) {
    return axios.get(`${this.url}/${campaignId}/analytics/metrics`);
  }

  getWhatsappAnalyticsContacts(campaignId, params = {}) {
    return axios.get(`${this.url}/${campaignId}/analytics/contacts`, {
      params,
    });
  }
}

export default new CampaignsAPI();
