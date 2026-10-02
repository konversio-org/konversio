# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::OverviewSummaryGenerator do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account, name: 'Helper') }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-10-02 12:00:00') }
  let(:window) { Pilot::Analytics::ReportingWindow.new(range: '7', timezone_offset: '0', now: now) }
  let(:service) { described_class.new(account: account, assistant: assistant, window: window) }

  before do
    Redis::Alfred.delete(Pilot::OutcomeTrackingHistory::CACHE_KEY)
    travel_to(now)
  end

  def episode(overrides = {})
    create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox,
                                        conversation: create(:conversation, account: account, inbox: inbox), **overrides)
  end

  context 'when the report shows activity' do
    before do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))
    end

    it 'returns bounded, stripped, non-empty points from the structured response' do
      allow(service).to receive(:make_api_call).and_return(
        { message: { 'points' => ['  Resolution rate rose sharply. ', '', 'Handoffs cluster on one driver.', 'Extra point', 'Another extra'] } }
      )

      expect(service.perform[:points]).to eq(['Resolution rate rose sharply.', 'Handoffs cluster on one driver.', 'Extra point'])
    end

    it 'parses a JSON string response when the model output is not pre-parsed' do
      allow(service).to receive(:make_api_call).and_return(
        { message: "```json\n{\"points\": [\"One observation.\"]}\n```" }
      )

      expect(service.perform[:points]).to eq(['One observation.'])
    end

    it 'bounds the request with a structured-output schema of at most three points' do
      allow(service).to receive(:make_api_call).and_return({ message: { 'points' => [] } })

      service.perform

      expect(service).to have_received(:make_api_call) do |args|
        schema = args[:schema]
        expect(schema[:properties][:points][:maxItems]).to eq(3)
        expect(schema[:required]).to include('points')
      end
    end

    it 'returns LLM failures unmodified so the caller can surface them' do
      allow(service).to receive(:make_api_call).and_return({ error: 'rate limited' })

      expect(service.perform[:error]).to eq('rate limited')
    end
  end

  context 'when there is no activity in either window' do
    it 'returns an empty point list without calling the model' do
      expect(service).not_to receive(:make_api_call)

      expect(service.perform[:points]).to eq([])
    end
  end

  describe 'prompt construction' do
    it 'supplies the assistant name, account language, and period descriptor' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              created_at: Time.zone.parse('2026-09-27 10:00'))
      allow(service).to receive(:make_api_call).and_return({ message: { 'points' => [] } })

      service.perform

      expect(service).to have_received(:make_api_call) do |args|
        system_prompt = args[:messages].find { |message| message[:role] == 'system' }[:content]
        expect(system_prompt).to include('Helper')
        expect(system_prompt).to include(account.locale_english_name)
        expect(system_prompt).to include('Last 7 days')
        expect(system_prompt).to include('2026-09-26')
      end
    end
  end
end
