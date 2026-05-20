/* global axios */
import ApiClient from '../ApiClient';

class PilotSummariesAPI extends ApiClient {
  constructor() {
    super('pilot/summaries', { accountScoped: true, apiVersion: 'v2' });
  }

  generate(conversationId, { previousOutput, refinementInstruction } = {}) {
    return axios.post(this.url, {
      conversation_id: conversationId,
      previous_output: previousOutput,
      refinement_instruction: refinementInstruction,
    });
  }
}

export default new PilotSummariesAPI();
