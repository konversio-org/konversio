require 'rails_helper'

RSpec.describe Pilot::AgentSessionRecorder do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def run_result(success: true, messages: [], sources: [])
    Agents::RunResult.new(
      output: success ? 'reply' : nil,
      error: success ? nil : StandardError.new('boom'),
      messages: messages,
      context: { state: { Pilot::Assistant::KNOWLEDGE_SOURCES_STATE_KEY => sources } }
    )
  end

  def delivered_message(citations: [])
    create(:message,
           account: account,
           conversation: conversation,
           message_type: :outgoing,
           sender: assistant,
           additional_attributes: { 'pilot_response_parts' => [{ 'text' => 'Hi', 'citations' => citations }] })
  end

  describe 'success gating' do
    it 'creates a session for a successful run' do
      message = delivered_message

      expect do
        described_class.call(assistant: assistant, subject: conversation, result_message: message,
                             run_result: run_result, llm_model: 'llm-x')
      end.to change(Pilot::AgentSession, :count).by(1)

      session = Pilot::AgentSession.last
      expect(session.session_kind).to eq('autopilot')
      expect(session.subject).to eq(conversation)
      expect(session.result).to eq(message)
      expect(session.llm_model).to eq('llm-x')
    end

    it 'does not create a session for an unsuccessful run' do
      message = delivered_message

      expect do
        described_class.call(assistant: assistant, subject: conversation, result_message: message,
                             run_result: run_result(success: false))
      end.not_to(change(Pilot::AgentSession, :count))
    end

    it 'does not create a session without a run result' do
      message = delivered_message

      expect do
        described_class.call(assistant: assistant, subject: conversation, result_message: message, run_result: nil)
      end.not_to(change(Pilot::AgentSession, :count))
    end
  end

  describe 'failure isolation' do
    it 'swallows creation errors and reports them' do
      message = delivered_message
      allow(Pilot::AgentSession).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Pilot::AgentSession.new))
      allow(Rails.logger).to receive(:error)

      expect do
        described_class.call(assistant: assistant, subject: conversation, result_message: message, run_result: run_result)
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/capture failed/)
    end
  end

  describe 'knowledge attribution' do
    let(:eligible_doc) do
      create(:pilot_document, assistant: assistant, account: account, external_link: 'https://example.com/eligible')
    end
    let(:ineligible_doc) do
      create(:pilot_document, assistant: assistant, account: account,
                              external_link: 'https://example.com/hidden',
                              metadata: { 'customer_visible' => false })
    end
    let!(:faq_one) do
      create(:pilot_assistant_response, assistant: assistant, account: account, documentable: eligible_doc)
    end
    let!(:faq_two) do
      create(:pilot_assistant_response, assistant: assistant, account: account, documentable: ineligible_doc)
    end
    let!(:faq_three) do
      create(:pilot_assistant_response, assistant: assistant, account: account, documentable: nil)
    end
    let(:sources) do
      [
        { index: 1, faq_id: faq_one.id, document_id: eligible_doc.id },
        { index: 2, faq_id: faq_two.id, document_id: ineligible_doc.id },
        { index: 3, faq_id: faq_three.id, document_id: nil }
      ]
    end

    it 'records offered and used FAQs separately and cited documents as used ∩ eligible' do
      message = delivered_message(citations: [1, 2, 3])

      described_class.call(assistant: assistant, subject: conversation, result_message: message,
                           run_result: run_result(sources: sources))

      session = Pilot::AgentSession.last
      expect(session.offered_faq_ids).to contain_exactly(faq_one.id, faq_two.id, faq_three.id)
      expect(session.used_faq_ids).to contain_exactly(faq_one.id, faq_two.id, faq_three.id)
      expect(session.consulted_document_ids).to contain_exactly(eligible_doc.id, ineligible_doc.id)
      expect(session.cited_document_ids).to contain_exactly(eligible_doc.id)
    end

    it 'leaves cited documents empty when citations are disabled' do
      assistant.update!(config: { 'feature_citation' => false })
      message = delivered_message(citations: [1])

      described_class.call(assistant: assistant, subject: conversation, result_message: message,
                           run_result: run_result(sources: sources))

      expect(Pilot::AgentSession.last.cited_document_ids).to eq([])
    end
  end

  describe 'handoff note linking' do
    it 'uses the handoff note as the session result when provided' do
      reply = delivered_message
      note = create(:message, account: account, conversation: conversation,
                              message_type: :outgoing, private: true, sender: assistant)

      described_class.call(assistant: assistant, subject: conversation, result_message: reply,
                           handoff_note: note, run_result: run_result)

      expect(Pilot::AgentSession.last.result).to eq(note)
    end
  end

  describe 'scenario attribution' do
    it 'records only the assistant scenarios that acted in the turn, deduplicated' do
      scenario = create(:pilot_scenario, assistant: assistant, account: account, title: 'Billing')
      other_scenario = create(:pilot_scenario, assistant: assistant, account: account, title: 'Sales')
      message = delivered_message
      messages = [
        { role: 'user', content: 'first question' },
        { role: 'assistant', content: 'old', agent_name: other_scenario.handoff_key },
        { role: 'user', content: 'latest question' },
        { role: 'assistant', content: 'acting', agent_name: scenario.handoff_key },
        { role: 'assistant', content: 'acting again', agent_name: scenario.handoff_key }
      ]

      described_class.call(assistant: assistant, subject: conversation, result_message: message,
                           run_result: run_result(messages: messages))

      expect(Pilot::AgentSession.last.scenario_ids).to eq([scenario.id])
    end
  end

  describe 'turn-scoped run context' do
    it 'keeps only the latest customer message and everything after it' do
      message = delivered_message
      messages = [
        { role: 'user', content: 'old question' },
        { role: 'assistant', content: 'old answer' },
        { role: 'user', content: 'latest question' },
        { role: 'assistant', content: 'latest answer' },
        { role: 'tool', content: 'tool output', tool_call_id: 'call-1' }
      ]

      described_class.call(assistant: assistant, subject: conversation, result_message: message,
                           run_result: run_result(messages: messages))

      entries = Pilot::AgentSession.last.run_context_entries
      expect(entries.map { |entry| entry['content'] }).to eq(['latest question', 'latest answer', 'tool output'])
    end

    it 'serializes rich multimodal content to a plain representation' do
      message = delivered_message
      messages = [
        { role: 'user', content: [{ type: 'text', text: 'describe' }, { type: 'image_url', image_url: { url: 'https://img' } }] }
      ]

      described_class.call(assistant: assistant, subject: conversation, result_message: message,
                           run_result: run_result(messages: messages))

      content = Pilot::AgentSession.last.run_context_entries.first['content']
      expect(content).to eq([
                              { 'type' => 'text', 'text' => 'describe' },
                              { 'type' => 'image_url', 'image_url' => { 'url' => 'https://img' } }
                            ])
    end
  end
end
