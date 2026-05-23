require 'rails_helper'

describe PilotResolveListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account, config: { 'feature_faq' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pilot_inbox) { Pilot::Inbox.create!(assistant: assistant, inbox: inbox) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:event_name) { 'conversation.resolved' }
  let(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

  before do
    # Disable both per-feature flags upfront so each context can opt in
    # explicitly. The host's `features.yml` defaults `pilot_autopilot` to
    # enabled and `pilot_logbook` to disabled — we override both to a
    # known-false baseline so the negative cases are crisp.
    account.disable_features!(:pilot_autopilot, :pilot_logbook)
    account.enable_features!(:pilot)
  end

  describe '#conversation_resolved — FAQ mining' do
    context 'when autopilot + assistant + FAQ flag all on' do
      before { account.enable_features!(:pilot_autopilot) }

      it 'enqueues the FAQ mining job' do
        expect(Pilot::Conversations::FaqMiningJob).to receive(:perform_later).with(conversation.id)
        listener.conversation_resolved(event)
      end
    end

    context 'when assistant FAQ-learning is off' do
      before do
        account.enable_features!(:pilot_autopilot)
        assistant.update!(config: { 'feature_faq' => false })
      end

      it 'does NOT enqueue the FAQ mining job' do
        expect(Pilot::Conversations::FaqMiningJob).not_to receive(:perform_later)
        listener.conversation_resolved(event)
      end
    end

    context 'when pilot_autopilot is off' do
      it 'does NOT enqueue the FAQ mining job' do
        expect(Pilot::Conversations::FaqMiningJob).not_to receive(:perform_later)
        listener.conversation_resolved(event)
      end
    end

    context 'when inbox has no Pilot::Inbox attached' do
      before do
        account.enable_features!(:pilot_autopilot)
        pilot_inbox.destroy
      end

      it 'does NOT enqueue the FAQ mining job' do
        expect(Pilot::Conversations::FaqMiningJob).not_to receive(:perform_later)
        listener.conversation_resolved(event)
      end
    end
  end

  describe '#conversation_resolved — Logbook' do
    context 'when pilot_logbook on' do
      before { account.enable_features!(:pilot_logbook) }

      it 'enqueues the logbook extraction job' do
        expect(Pilot::LogbookExtractionJob).to receive(:perform_later).with(conversation.id)
        listener.conversation_resolved(event)
      end
    end

    context 'when pilot_logbook off' do
      it 'does NOT enqueue the logbook extraction job' do
        expect(Pilot::LogbookExtractionJob).not_to receive(:perform_later)
        listener.conversation_resolved(event)
      end
    end
  end

  describe '#conversation_resolved — pilot master off' do
    before { account.disable_features!(:pilot) }

    it 'is a no-op' do
      expect(Pilot::Conversations::FaqMiningJob).not_to receive(:perform_later)
      expect(Pilot::LogbookExtractionJob).not_to receive(:perform_later)
      listener.conversation_resolved(event)
    end
  end
end
