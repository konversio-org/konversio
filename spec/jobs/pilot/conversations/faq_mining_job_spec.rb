require 'rails_helper'

RSpec.describe Pilot::Conversations::FaqMiningJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account, config: { 'feature_faq' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pilot_inbox) { Pilot::Inbox.create!(assistant: assistant, inbox: inbox) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(
      :conversation,
      account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
      first_reply_created_at: 5.minutes.ago
    )
  end
  let(:incoming_message) do
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :incoming, content: 'How do I cancel my subscription?')
  end
  let(:outgoing_message) do
    user = create(:user, account: account)
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :outgoing, sender: user,
                     content: 'You can cancel from Settings > Billing > Cancel Subscription.')
  end

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    incoming_message
    outgoing_message
  end

  describe '#perform happy path' do
    let(:pair) do
      Custom::Pilot::FaqMiningService::Pair.new(
        question: 'How do I cancel my subscription?',
        answer: 'Settings > Billing > Cancel Subscription.'
      )
    end
    let(:service_double) { instance_double(Custom::Pilot::FaqMiningService, call: [pair]) }
    let(:deduper_double) do
      d = instance_double(Custom::Pilot::FaqMiningDeduper)
      allow(d).to receive(:filter) { |pairs| pairs.map { |p| { question: p.question, answer: p.answer } } }
      d
    end

    before do
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(service_double)
      allow(Custom::Pilot::FaqMiningDeduper).to receive(:new).and_return(deduper_double)
    end

    it 'creates pending AssistantResponse rows for extracted pairs' do
      expect do
        described_class.perform_now(conversation.id)
      end.to change { Pilot::AssistantResponse.where(assistant: assistant).count }.by(1)

      response = Pilot::AssistantResponse.where(assistant: assistant).last
      expect(response.status).to eq('pending')
      expect(response.documentable_id).to be_nil
      expect(response.documentable_type).to be_nil
    end

    it 'records the transcript digest for idempotency' do
      allow(service_double).to receive(:call).and_return([])

      described_class.perform_now(conversation.id)

      digest = conversation.reload.additional_attributes['pilot_faq_transcript_digest']
      expect(digest).to be_present
    end

    it 'passes the assistant, account, and filtered transcript to the service' do
      described_class.perform_now(conversation.id)

      expect(Custom::Pilot::FaqMiningService).to have_received(:new).with(
        assistant: assistant,
        account: account,
        transcript: include('[CUSTOMER] How do I cancel my subscription?', '[AGENT] You can cancel from Settings')
      )
    end
  end

  describe 'idempotency by transcript hash' do
    it 'skips a second run when the transcript hash is unchanged' do
      pair = Custom::Pilot::FaqMiningService::Pair.new(question: 'Q', answer: 'A')
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [pair])
      deduper_double = instance_double(Custom::Pilot::FaqMiningDeduper)
      allow(deduper_double).to receive(:filter) { |pairs| pairs.map { |p| { question: p.question, answer: p.answer } } }
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)
      allow(Custom::Pilot::FaqMiningDeduper).to receive(:new).and_return(deduper_double)

      described_class.perform_now(conversation.id)
      expect(svc_double).to have_received(:call).once

      described_class.perform_now(conversation.id)
      expect(svc_double).to have_received(:call).once # not called again
    end

    it 're-runs when new messages arrived between resolutions' do
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      described_class.perform_now(conversation.id)

      create(:message, account: account, conversation: conversation, inbox: inbox,
                       message_type: :incoming, content: 'Follow-up question?')

      described_class.perform_now(conversation.id)
      expect(svc_double).to have_received(:call).twice
    end
  end

  describe 'short-circuit on no human reply' do
    it 'returns early without calling the LLM when first_reply_created_at is nil' do
      conversation.update!(first_reply_created_at: nil)
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      described_class.perform_now(conversation.id)

      expect(svc_double).not_to have_received(:call)
    end
  end

  describe 'failure tolerance' do
    it 'swallows LLM errors and does not raise' do
      svc_double = instance_double(Custom::Pilot::FaqMiningService)
      allow(svc_double).to receive(:call).and_raise(StandardError, 'boom')
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      expect { described_class.perform_now(conversation.id) }.not_to raise_error
      expect(Pilot::AssistantResponse.where(assistant: assistant).count).to eq(0)
    end

    it 'returns zero rows on empty LLM output' do
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      expect { described_class.perform_now(conversation.id) }.not_to(change(Pilot::AssistantResponse, :count))
    end
  end

  describe 'no assistant attached' do
    it 'is a no-op when the conversation is gone' do
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      described_class.perform_now(0)

      expect(svc_double).not_to have_received(:call)
    end

    it 'is a no-op when the inbox has no Pilot::Inbox link' do
      pilot_inbox.destroy
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)

      described_class.perform_now(conversation.id)

      expect(svc_double).not_to have_received(:call)
    end
  end

  describe 'trace span emission' do
    it 'wraps the LLM call in pilot.faq.mine with credit_used=true' do
      svc_double = instance_double(Custom::Pilot::FaqMiningService, call: [])
      allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(svc_double)
      allow(Custom::Pilot::TraceSpan).to receive(:wrap).and_call_original

      described_class.perform_now(conversation.id)

      expect(Custom::Pilot::TraceSpan).to have_received(:wrap).with(
        name: 'pilot.faq.mine',
        attributes: hash_including(
          account_id: account.id,
          assistant_id: assistant.id,
          conversation_id: conversation.id,
          source: 'production',
          credit_used: true
        )
      )
    end
  end
end
