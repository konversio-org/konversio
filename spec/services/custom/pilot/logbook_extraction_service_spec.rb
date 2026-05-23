require 'rails_helper'

RSpec.describe Custom::Pilot::LogbookExtractionService do
  let(:account) { create(:account) }
  let(:service) do
    described_class.new(conversation: conversation, contact: contact, account: account)
  end
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :incoming, content: 'I prefer email over phone.')
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :outgoing, content: 'Noted. We will email you for updates.')
  end

  describe '#call — well-formed output' do
    it 'parses a JSON `facts` array into strings' do
      allow(service).to receive(:invoke_llm).and_return('{"facts":["Prefers email","Has corporate account"]}')

      facts = service.call

      expect(facts).to eq(['Prefers email', 'Has corporate account'])
    end

    it 'strips ```json fences if the model wraps its output' do
      allow(service).to receive(:invoke_llm).and_return("```json\n{\"facts\":[\"X\"]}\n```")

      expect(service.call).to eq(['X'])
    end

    it 'returns an empty array when facts is empty' do
      allow(service).to receive(:invoke_llm).and_return('{"facts":[]}')

      expect(service.call).to eq([])
    end
  end

  describe '#call — failure modes' do
    it 'returns empty array and reports to exception tracker on malformed JSON' do
      allow(service).to receive(:invoke_llm).and_return('not actually json at all')
      tracker = instance_double(KonversioExceptionTracker)
      allow(KonversioExceptionTracker).to receive(:new).with(an_instance_of(JSON::ParserError)).and_return(tracker)
      expect(tracker).to receive(:capture_exception)

      expect(service.call).to eq([])
    end

    it 'returns empty array and reports when the LLM call itself raises' do
      allow(service).to receive(:invoke_llm).and_raise(StandardError, 'gateway timeout')
      tracker = instance_double(KonversioExceptionTracker)
      allow(KonversioExceptionTracker).to receive(:new).with(an_instance_of(StandardError)).and_return(tracker)
      expect(tracker).to receive(:capture_exception).at_least(:once)

      expect { service.call }.not_to raise_error
    end

    it 'returns empty array when JSON lacks the facts key' do
      allow(service).to receive(:invoke_llm).and_return('{"other":[]}')

      expect(service.call).to eq([])
    end
  end

  describe '#call — no post-extraction sanity filter' do
    it 'iterates verbatim — short fragments are still returned as candidates' do
      allow(service).to receive(:invoke_llm).and_return('{"facts":["x","Has account?","Prefers email"]}')

      # All three pass through; no length or question-mark filter.
      expect(service.call).to eq(['x', 'Has account?', 'Prefers email'])
    end
  end

  describe '#call — no transcript' do
    it 'returns empty array without calling the LLM when there are no messages' do
      empty_conv = create(:conversation, account: account, inbox: inbox,
                                         contact: contact, contact_inbox: contact_inbox)
      svc = described_class.new(conversation: empty_conv, contact: contact, account: account)
      expect(svc).not_to receive(:invoke_llm)

      expect(svc.call).to eq([])
    end
  end

  describe '#call — trace span emission' do
    it 'wraps the LLM call in pilot.logbook.extract with credit_used=true' do
      fake_message = instance_double(RubyLLM::Message, content: '{"facts":["x"]}')
      fake_chat = instance_double(RubyLLM::Chat, with_instructions: nil, ask: fake_message)
      fake_context = instance_double(RubyLLM::Context, chat: fake_chat)
      allow(Llm::Config).to receive(:with_api_key).and_yield(fake_context)
      allow(Llm::Config).to receive(:openai_compatible?).and_return(false)
      allow(Custom::Pilot::TraceSpan).to receive(:wrap).and_call_original

      service.call

      expect(Custom::Pilot::TraceSpan).to have_received(:wrap).with(
        name: 'pilot.logbook.extract',
        attributes: hash_including(
          account_id: account.id,
          conversation_id: conversation.id,
          contact_id: contact.id,
          source: 'production',
          credit_used: true
        )
      )
    end
  end
end
