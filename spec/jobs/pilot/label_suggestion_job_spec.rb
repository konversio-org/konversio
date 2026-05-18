require 'rails_helper'

RSpec.describe Pilot::LabelSuggestionJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:billing_label) { create(:label, account: account, title: 'billing') }

  before do
    account.update!(pilot_enabled: true, pilot_label_suggestion_enabled: true)
  end

  describe '#perform' do
    it 'persists suggested_label_ids' do
      allow_any_instance_of(Custom::Pilot::LabelSuggestionService).to receive(:perform).and_return([billing_label.id])

      described_class.perform_now(conversation.id)
      conversation.reload

      expect(conversation.suggested_label_ids).to eq([billing_label.id])
    end

    it 'no-ops when the feature flag is off' do
      account.update!(pilot_label_suggestion_enabled: false)
      expect(Custom::Pilot::LabelSuggestionService).not_to receive(:new)
      described_class.perform_now(conversation.id)
    end
  end
end
