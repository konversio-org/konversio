/* global axios */
import ApiClient from '../ApiClient';

const getTimeOffset = () => -new Date().getTimezoneOffset() / 60;

class PilotAssistantAnalyticsAPI extends ApiClient {
  constructor() {
    super('pilot/assistants', { accountScoped: true });
  }

  overview(assistantId, range, { signal } = {}) {
    return axios.get(`${this.url}/${assistantId}/analytics/overview`, {
      params: { range, timezone_offset: getTimeOffset() },
      signal,
    });
  }

  resolutionFlow(assistantId, range, { signal } = {}) {
    return axios.get(`${this.url}/${assistantId}/analytics/resolution_flow`, {
      params: { range, timezone_offset: getTimeOffset() },
      signal,
    });
  }

  resolutionTrend(assistantId, range, { signal } = {}) {
    return axios.get(`${this.url}/${assistantId}/analytics/resolution_trend`, {
      params: { range, timezone_offset: getTimeOffset() },
      signal,
    });
  }

  overviewSummary(assistantId, range, { signal } = {}) {
    return axios.get(`${this.url}/${assistantId}/analytics/overview_summary`, {
      params: { range, timezone_offset: getTimeOffset() },
      signal,
    });
  }

  drilldown(assistantId, { metric, range, page, perPage }, { signal } = {}) {
    return axios.get(`${this.url}/${assistantId}/drilldown`, {
      params: {
        metric,
        range,
        page,
        per_page: perPage,
        timezone_offset: getTimeOffset(),
      },
      signal,
    });
  }
}

export default new PilotAssistantAnalyticsAPI();
