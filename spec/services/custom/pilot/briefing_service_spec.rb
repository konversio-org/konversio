require 'rails_helper'

RSpec.describe Custom::Pilot::BriefingService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

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
        .with(account: account, conversation_display_id: conversation.display_id, user: user)
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
      it 'skips Logbook context injection when pilot_logbook_enabled is false' do
        fake_suggestion = instance_double(Pilot::ReplySuggestionService)
        allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
        allow(fake_suggestion).to receive(:perform).and_return({ message: 'ok' })

        service = described_class.new(conversation: conversation, user: user)

        # logbook injection helper should never be invoked when feature off
        expect(service).not_to receive(:inject_logbook_context!)
        service.perform
      end

      it 'invokes Logbook context injection when feature is on AND model is defined' do
        account.enable_features!(:pilot_logbook)

        stub_const('Pilot::LogbookEntry', Class.new) unless defined?(Pilot::LogbookEntry)

        fake_suggestion = instance_double(Pilot::ReplySuggestionService)
        allow(Pilot::ReplySuggestionService).to receive(:new).and_return(fake_suggestion)
        allow(fake_suggestion).to receive(:perform).and_return({ message: 'ok' })

        service = described_class.new(conversation: conversation, user: user)

        expect(service).to receive(:inject_logbook_context!).and_call_original
        service.perform
      end
    end
  end
end
