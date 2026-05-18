/* global axios */
import ApiClient from '../ApiClient';

class PilotBriefingsAPI extends ApiClient {
  constructor() {
    super('pilot/briefings', { accountScoped: true, apiVersion: 'v2' });
  }

  generate(conversationId, { previousOutput, refinementInstruction } = {}) {
    return axios.post(this.url, {
      conversation_id: conversationId,
      previous_output: previousOutput,
      refinement_instruction: refinementInstruction,
    });
  }
}

export default new PilotBriefingsAPI();
