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

  let(:pair) do
    Custom::Pilot::FaqMiningService::Pair.new(
      question: 'How do I cancel my subscription?',
      answer: 'Settings > Billing > Cancel Subscription.'
    )
  end
  let(:service_double) { instance_double(Custom::Pilot::FaqMiningService, call: [pair]) }
  let(:matcher_double) { instance_double(Custom::Pilot::FaqSuggestionMatcher) }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    allow(Pilot::UpdateFaqSuggestionEmbeddingJob).to receive(:perform_later)
    incoming_message
    outgoing_message
    allow(Custom::Pilot::FaqMiningService).to receive(:new).and_return(service_double)
    allow(Custom::Pilot::FaqSuggestionMatcher).to receive(:new).and_return(matcher_double)
    allow(matcher_double).to receive(:match).and_return(
      Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :create)
    )
  end

  describe '#perform happy path' do
    it 'creates an open suggestion with an attached observation and source count of one' do
      expect do
        described_class.perform_now(conversation.id)
      end.to change { Pilot::FaqSuggestion.where(assistant: assistant).count }.by(1)

      suggestion = Pilot::FaqSuggestion.where(assistant: assistant).last
      expect(suggestion.status).to eq('open')
      expect(suggestion.question).to eq(pair.question)
      expect(suggestion.answer).to eq(pair.answer)
      expect(suggestion.language).to eq('en')
      expect(suggestion.source_count).to eq(1)

      observation = suggestion.observations.last
      expect(observation.status).to eq('attached')
      expect(observation.conversation).to eq(conversation)
      expect(observation.generated_question).to eq(pair.question)
      expect(observation.generated_answer).to eq(pair.answer)
    end

    it 'does not write Pilot::AssistantResponse rows' do
      expect do
        described_class.perform_now(conversation.id)
      end.not_to change(Pilot::AssistantResponse, :count)
    end

    it 'routes each candidate through the matcher with the conversation language' do
      described_class.perform_now(conversation.id)

      expect(matcher_double).to have_received(:match).with(
        question: pair.question,
        answer: pair.answer,
        language: 'en'
      )
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

  describe 'candidate routing' do
    it 'records a discarded observation when the candidate matches approved knowledge' do
      allow(matcher_double).to receive(:match).and_return(
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :knowledge, record: nil)
      )

      expect do
        described_class.perform_now(conversation.id)
      end.to not_change(Pilot::FaqSuggestion, :count).and change { Pilot::FaqObservation.where(status: :discarded).count }.by(1)
    end

    it 'records a discarded observation when the candidate matches a dismissed suggestion' do
      dismissed = create(:pilot_faq_suggestion, assistant: assistant, status: :dismissed)
      allow(matcher_double).to receive(:match).and_return(
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :dismissed, record: dismissed)
      )

      expect do
        described_class.perform_now(conversation.id)
      end.to not_change(Pilot::FaqSuggestion, :count).and change { Pilot::FaqObservation.where(status: :discarded).count }.by(1)
    end

    it 'attaches an observation and increments source_count on an open-suggestion match' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, source_count: 2)
      allow(matcher_double).to receive(:match).and_return(
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :attach, record: suggestion)
      )

      described_class.perform_now(conversation.id)

      suggestion.reload
      expect(suggestion.source_count).to eq(3)
      expect(suggestion.observations.attached.where(conversation: conversation).count).to eq(1)
    end

    it 'does not double-count when the conversation already observed the suggestion' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, source_count: 2)
      create(:pilot_faq_observation, conversation: conversation, status: :attached, faq_suggestion: suggestion)
      allow(matcher_double).to receive(:match).and_return(
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :attach, record: suggestion)
      )

      described_class.perform_now(conversation.id)

      suggestion.reload
      expect(suggestion.source_count).to eq(2)
      expect(suggestion.observations.attached.where(conversation: conversation).count).to eq(1)
    end

    it 're-routes when the suggestion was decided between match and attach' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, status: :dismissed)
      allow(matcher_double).to receive(:match).and_return(
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :attach, record: suggestion),
        Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :create)
      )

      described_class.perform_now(conversation.id)

      expect(matcher_double).to have_received(:match).twice
      expect(suggestion.observations.reload).to be_empty
      expect(Pilot::FaqSuggestion.where(assistant: assistant, status: :open).count).to eq(1)
    end

    it 're-routes when the suggestion text changed between match and attach' do
      suggestion = create(:pilot_faq_suggestion, assistant: assistant, question: pair.question, answer: pair.answer)
      calls = 0
      allow(matcher_double).to receive(:match) do
        calls += 1
        if calls == 1
          match_record = Pilot::FaqSuggestion.find(suggestion.id)
          # a reviewer edits the suggestion after the match was computed
          suggestion.update!(question: 'Reworded by reviewer?')
          Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :attach, record: match_record)
        else
          Custom::Pilot::FaqSuggestionMatcher::Match.new(route: :create)
        end
      end

      described_class.perform_now(conversation.id)

      expect(matcher_double).to have_received(:match).twice
      expect(suggestion.reload.observations).to be_empty
    end

    it 'raises no records when the equivalence judgment fails and does not record the digest' do
      allow(matcher_double).to receive(:match).and_raise(Custom::Pilot::FaqSuggestionMatcher::JudgmentError, 'bad verdict')

      expect { described_class.perform_now(conversation.id) }.not_to raise_error
      expect(Pilot::FaqSuggestion.count).to eq(0)
      expect(Pilot::FaqObservation.count).to eq(0)
      expect(conversation.reload.additional_attributes['pilot_faq_transcript_digest']).to be_nil
    end
  end

  describe 'idempotency by transcript hash' do
    it 'skips a second run when the transcript hash is unchanged' do
      described_class.perform_now(conversation.id)
      expect(service_double).to have_received(:call).once

      described_class.perform_now(conversation.id)
      expect(service_double).to have_received(:call).once # not called again
    end

    it 're-runs when new messages arrived between resolutions' do
      allow(service_double).to receive(:call).and_return([])

      described_class.perform_now(conversation.id)

      create(:message, account: account, conversation: conversation, inbox: inbox,
                       message_type: :incoming, content: 'Follow-up question?')

      described_class.perform_now(conversation.id)
      expect(service_double).to have_received(:call).twice
    end
  end

  describe 'short-circuit on no human reply' do
    it 'returns early without calling the LLM when first_reply_created_at is nil' do
      conversation.update!(first_reply_created_at: nil)
      allow(service_double).to receive(:call).and_return([])

      described_class.perform_now(conversation.id)

      expect(service_double).not_to have_received(:call)
    end
  end

  describe 'failure tolerance' do
    it 'swallows LLM errors and does not raise' do
      allow(service_double).to receive(:call).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(conversation.id) }.not_to raise_error
      expect(Pilot::FaqSuggestion.count).to eq(0)
    end

    it 'returns zero rows on empty LLM output' do
      allow(service_double).to receive(:call).and_return([])

      expect { described_class.perform_now(conversation.id) }.not_to(change(Pilot::FaqSuggestion, :count))
    end
  end

  describe 'no assistant attached' do
    it 'is a no-op when the conversation is gone' do
      allow(service_double).to receive(:call).and_return([])

      described_class.perform_now(0)

      expect(service_double).not_to have_received(:call)
    end

    it 'is a no-op when the inbox has no Pilot::Inbox link' do
      pilot_inbox.destroy
      allow(service_double).to receive(:call).and_return([])

      described_class.perform_now(conversation.id)

      expect(service_double).not_to have_received(:call)
    end
  end

  describe 'trace span emission' do
    it 'wraps the LLM call in pilot.faq.mine with credit_used=true' do
      allow(service_double).to receive(:call).and_return([])
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
