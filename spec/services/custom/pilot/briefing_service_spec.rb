require 'rails_helper'

RSpec.describe Custom::Pilot::BriefingService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  before do
    account.enable_features!(:pilot, :pilot_briefing)
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the briefing flag is off' do
      account.disable_features!(:pilot_briefing)

      service = described_class.new(conversation: conversation, user: user)

      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises FeatureDisabledError when the master flag is off' do
      account.disable_features!(:pilot)

      service = described_class.new(conversation: conversation, user: user)

      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end

    it 'delegates to Pilot::ReplySuggestionService and returns the draft' do
      fake_suggestion = instance_double(Pilot::ReplySuggestionService)
      expect(Pilot::ReplySuggestionService)
        .to receive(:new)
        .with(
          account: account,
          conversation_display_id: conversation.display_id,
          user: user,
          previous_output: nil,
          refinement_instruction: nil,
          extra_system_context: nil
        )
        .and_return(fake_suggestion)
      expect(fake_suggestion).to receive(:perform).and_return({ message: 'Hi there!' })

      service = described_class.new(conversation: conversation, user: user)
      expect(service.perform).to eq('Hi there!')
    end

    it 'accepts a plain string response (back-compat for stubs)' do
      fake_suggestion = instance_double(Pilot::ReplySuggestionService)
      allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
      allow(fake_suggestion).to receive(:perform).and_return('Hello!')

      service = described_class.new(conversation: conversation, user: user)
      expect(service.perform).to eq('Hello!')
    end

    it 'adds reply-suggestion token usage to the trace span when present' do
      span = instance_double(Custom::Pilot::TraceSpan::NullSpan, set_attribute: nil)
      fake_suggestion = instance_double(Pilot::ReplySuggestionService)
      allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
      allow(fake_suggestion).to receive(:perform).and_return(
        { message: 'Hi there!', usage: { 'prompt_tokens' => 6, 'completion_tokens' => 3 } }
      )
      allow(Custom::Pilot::TraceSpan).to receive(:wrap) do |**_args, &block|
        block.call(span)
      end

      service = described_class.new(conversation: conversation, user: user)
      service.perform

      expect(span).to have_received(:set_attribute).with('prompt_tokens', 6)
      expect(span).to have_received(:set_attribute).with('completion_tokens', 3)
    end

    it 'raises Custom::Pilot::BriefingService::Error when the pilot service returns an error hash' do
      fake_suggestion = instance_double(Pilot::ReplySuggestionService)
      allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
      allow(fake_suggestion).to receive(:perform).and_return({ error: 'upstream is down', error_code: 500 })

      service = described_class.new(conversation: conversation, user: user)
      expect { service.perform }.to raise_error(described_class::Error, /upstream is down/)
    end

    it 'wraps StandardError from the pilot service in a Pilot::BriefingService::Error' do
      fake_suggestion = instance_double(Pilot::ReplySuggestionService)
      allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
      allow(fake_suggestion).to receive(:perform).and_raise(StandardError, 'connection refused')

      service = described_class.new(conversation: conversation, user: user)
      expect { service.perform }.to raise_error(described_class::Error, /connection refused/)
    end

    context 'with Logbook' do
      it 'does not pass Logbook context when pilot_logbook_enabled is false' do
        account.disable_features!(:pilot_logbook)
        create(:pilot_logbook_entry, contact: conversation.contact, account: account, content: 'Prefers email')

        fake_suggestion = instance_double(Pilot::ReplySuggestionService)
        expect(Pilot::ReplySuggestionService)
          .to receive(:new)
          .with(hash_including(extra_system_context: nil))
          .and_return(fake_suggestion)
        allow(fake_suggestion).to receive(:perform).and_return({ message: 'ok' })

        service = described_class.new(conversation: conversation, user: user)

        service.perform
      end

      it 'passes Logbook context as an extra system message when enabled' do
        account.enable_features!(:pilot_logbook)
        create(:pilot_logbook_entry, contact: conversation.contact, account: account, content: 'Prefers email')

        fake_suggestion = instance_double(Pilot::ReplySuggestionService)
        expect(Pilot::ReplySuggestionService)
          .to receive(:new)
          .with(hash_including(extra_system_context: include('Known facts about this contact:', 'Prefers email')))
          .and_return(fake_suggestion)
        allow(fake_suggestion).to receive(:perform).and_return({ message: 'ok' })

        service = described_class.new(conversation: conversation, user: user)

        service.perform
      end
    end
  end
end
