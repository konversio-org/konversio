require 'rails_helper'

RSpec.describe Pilot::LabelSuggestionJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:billing_label) { create(:label, account: account, title: 'billing') }

  before do
    account.enable_features!(:pilot, :pilot_label_suggestion)
  end

  describe '#perform' do
    it 'persists suggested_label_ids' do
      allow_any_instance_of(Custom::Pilot::LabelSuggestionService).to receive(:perform).and_return([billing_label.id])

      described_class.perform_now(conversation.id)
      conversation.reload

      expect(conversation.suggested_label_ids).to eq([billing_label.id])
    end

    it 'no-ops when the feature flag is off' do
      account.disable_features!(:pilot_label_suggestion)
      expect(Custom::Pilot::LabelSuggestionService).not_to receive(:new)
      described_class.perform_now(conversation.id)
    end
  end
end
