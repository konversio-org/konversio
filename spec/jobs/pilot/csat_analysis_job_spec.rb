require 'rails_helper'

RSpec.describe Pilot::CsatAnalysisJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, conversation: conversation, account: account) }
  let(:contact) { conversation.contact }

  before do
    account.enable_features!(:pilot, :pilot_csat_analysis)
  end

  describe '#perform' do
    it 'persists sentiment, themes and escalation_recommended' do
      csat = create(:csat_survey_response, account: account, conversation: conversation,
                                           message: message, contact: contact,
                                           feedback_message: 'It took ages')

      allow_any_instance_of(Custom::Pilot::CsatAnalysisService).to receive(:perform).and_return(
        sentiment: 'negative', themes: %w[slow refund], escalation_recommended: true
      )

      described_class.perform_now(csat.id)
      csat.reload

      expect(csat.pilot_sentiment).to eq('negative')
      expect(csat.pilot_themes).to eq(%w[slow refund])
      expect(csat.pilot_escalation_recommended).to be(true)
    end

    it 'no-ops when feedback_message is blank' do
      csat = build(:csat_survey_response, account: account, conversation: conversation,
                                          message: message, contact: contact,
                                          feedback_message: nil)
      csat.save!(validate: false)

      expect(Custom::Pilot::CsatAnalysisService).not_to receive(:new)
      described_class.perform_now(csat.id)
    end

    it 'no-ops when the feature flag is off' do
      account.disable_features!(:pilot_csat_analysis)
      csat = create(:csat_survey_response, account: account, conversation: conversation,
                                           message: message, contact: contact,
                                           feedback_message: 'slow')

      expect(Custom::Pilot::CsatAnalysisService).not_to receive(:new)
      described_class.perform_now(csat.id)
    end
  end
end
