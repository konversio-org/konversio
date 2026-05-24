require 'rails_helper'

RSpec.describe Pilot::LabelSuggestionJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:billing_label) { create(:label, account: account, title: 'billing') }
  let(:service) { instance_double(Custom::Pilot::LabelSuggestionService, perform: [billing_label.id]) }

  before do
    account.enable_features!(:pilot, :pilot_label_suggestion)
    allow(Custom::Pilot::LabelSuggestionService).to receive(:new).and_return(service)
  end

  describe '#perform' do
    it 'persists suggested_label_ids' do
      described_class.perform_now(conversation.id)
      conversation.reload

      expect(conversation.suggested_label_ids).to eq([billing_label.id])
    end

    it 'passes the conversation and account to the service' do
      described_class.perform_now(conversation.id)

      expect(Custom::Pilot::LabelSuggestionService).to have_received(:new)
        .with(conversation: conversation, account: account)
    end

    it 'no-ops when the conversation is gone' do
      expect(Custom::Pilot::LabelSuggestionService).not_to receive(:new)

      described_class.perform_now(0)
    end

    it 'no-ops when Pilot is off' do
      account.disable_features!(:pilot)
      expect(Custom::Pilot::LabelSuggestionService).not_to receive(:new)

      described_class.perform_now(conversation.id)
    end

    it 'no-ops when label suggestion is off' do
      account.disable_features!(:pilot_label_suggestion)
      expect(Custom::Pilot::LabelSuggestionService).not_to receive(:new)

      described_class.perform_now(conversation.id)
    end

    it 'swallows service feature-disabled errors' do
      allow(service).to receive(:perform).and_raise(Custom::Pilot::LabelSuggestionService::FeatureDisabledError, 'disabled')

      expect { described_class.perform_now(conversation.id) }
        .not_to(change { conversation.reload.suggested_label_ids })
    end

    it 'swallows service LLM errors' do
      allow(service).to receive(:perform).and_raise(Custom::Pilot::LabelSuggestionService::Error, 'boom')

      expect { described_class.perform_now(conversation.id) }
        .not_to(change { conversation.reload.suggested_label_ids })
    end

    it 'does not apply labels directly' do
      described_class.perform_now(conversation.id)

      expect(conversation.reload.labels).to be_empty
    end
  end
end
