require 'rails_helper'

RSpec.describe Pilot::DocumentResponseBuilderJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:document) do
    create(:pilot_document, assistant: assistant, account: account, content: 'Refunds are processed within 30 days. Shipping takes 5 days.')
  end

  describe '#perform' do
    it 'persists AssistantResponse rows with status pending for each LLM-emitted FAQ' do
      faqs_json = {
        faqs: [
          { question: 'How long do refunds take?', answer: 'Refunds are processed within 30 days.' },
          { question: 'How long does shipping take?', answer: 'Shipping takes 5 days.' }
        ]
      }.to_json

      stub_llm_response(faqs_json)

      expect { described_class.perform_now(document.id) }
        .to change { Pilot::AssistantResponse.where(documentable: document).count }.by(2)

      created = Pilot::AssistantResponse.where(documentable: document)
      expect(created.map(&:status).uniq).to eq(['pending'])
    end

    it 'no-ops when document content is blank' do
      document.update!(content: nil)
      expect { described_class.perform_now(document.id) }
        .not_to(change(Pilot::AssistantResponse, :count))
    end

    it 'tolerates fenced JSON in the LLM response' do
      fenced = "```json\n#{{ faqs: [{ question: 'Q', answer: 'A' }] }.to_json}\n```"
      stub_llm_response(fenced)

      expect { described_class.perform_now(document.id) }
        .to change { Pilot::AssistantResponse.where(documentable: document).count }.by(1)
    end

    it 'dedups LLM pairs against responses from other documents' do
      other_document = create(:pilot_document, assistant: assistant, account: account, content: 'Existing refund policy')
      create(:pilot_assistant_response,
             assistant: assistant,
             account: account,
             documentable: other_document,
             question: 'How long do refunds take?',
             answer: 'Refunds are processed within 30 days.',
             status: :pending)

      faqs_json = {
        faqs: [
          { question: 'How long do refunds take?', answer: 'Refunds are processed within 30 days.' }
        ]
      }.to_json

      stub_llm_response(faqs_json)

      deduper = instance_double(Custom::Pilot::FaqMiningDeduper, filter: [])
      expect(Custom::Pilot::FaqMiningDeduper).to receive(:new)
        .with(assistant: assistant, account: account)
        .and_return(deduper)

      expect { described_class.perform_now(document.id) }
        .not_to(change(Pilot::AssistantResponse, :count))
    end
  end

  def stub_llm_response(content)
    response = instance_double(RubyLLM::Message, content: content)
    chat = instance_double(RubyLLM::Chat, with_instructions: nil, ask: response)
    context = instance_double(RubyLLM::Context, chat: chat)
    allow(Llm::Config).to receive(:with_api_key).and_yield(context)
    allow(Llm::Config).to receive(:api_key).and_return('test-key')
  end
end
