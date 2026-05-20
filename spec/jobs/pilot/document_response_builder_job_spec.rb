require 'rails_helper'

RSpec.describe Pilot::DocumentResponseBuilderJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:document) { create(:pilot_document, assistant: assistant, account: account, content: 'Refunds are processed within 30 days. Shipping takes 5 days.') }

  describe '#perform' do
    it 'persists AssistantResponse rows with status pending for each LLM-emitted FAQ' do
      faqs_json = {
        faqs: [
          { question: 'How long do refunds take?', answer: 'Refunds are processed within 30 days.' },
          { question: 'How long does shipping take?', answer: 'Shipping takes 5 days.' }
        ]
      }.to_json

      fake_response = double('chat_response', content: faqs_json)
      fake_chat = double('chat')
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)

      fake_context = double('context')
      allow(fake_context).to receive(:chat).and_return(fake_chat)
      allow(::Llm::Config).to receive(:with_api_key).and_yield(fake_context)
      allow(::Llm::Config).to receive(:api_key).and_return('test-key')

      expect { described_class.perform_now(document.id) }
        .to change { Pilot::AssistantResponse.where(documentable: document).count }.by(2)

      created = Pilot::AssistantResponse.where(documentable: document)
      expect(created.map(&:status).uniq).to eq(['pending'])
    end

    it 'no-ops when document content is blank' do
      document.update!(content: nil)
      expect { described_class.perform_now(document.id) }
        .not_to(change { Pilot::AssistantResponse.count })
    end

    it 'tolerates fenced JSON in the LLM response' do
      fenced = "```json\n#{{ faqs: [{ question: 'Q', answer: 'A' }] }.to_json}\n```"
      fake_response = double('chat_response', content: fenced)
      fake_chat = double('chat')
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)

      fake_context = double('context')
      allow(fake_context).to receive(:chat).and_return(fake_chat)
      allow(::Llm::Config).to receive(:with_api_key).and_yield(fake_context)
      allow(::Llm::Config).to receive(:api_key).and_return('test-key')

      expect { described_class.perform_now(document.id) }
        .to change { Pilot::AssistantResponse.where(documentable: document).count }.by(1)
    end
  end
end
