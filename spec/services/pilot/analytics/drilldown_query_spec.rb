# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::DrilldownQuery do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-10-02 12:00:00') }
  let(:window) { Pilot::Analytics::ReportingWindow.new(range: '7', timezone_offset: '0', now: now) }

  # Current window: 2026-09-26 00:00 .. 2026-10-02 12:00

  before { travel_to(now) }

  def conversation_with_ai_reply(at: Time.zone.parse('2026-09-27 10:00'))
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, private: false, sender: assistant, created_at: at)
    conversation
  end

  def reporting_event(name, conversation, at, end_time: nil)
    create(:reporting_event, account: account, inbox: inbox, conversation: conversation, name: name,
                             created_at: at, event_end_time: end_time || at)
  end

  def build(metric:, page: nil, per_page: nil)
    described_class.new(assistant: assistant, window: window, metric: metric, page: page, per_page: per_page).build
  end

  describe 'supported-metric guard' do
    it 'rejects unsupported metrics' do
      expect { build(metric: 'durable_resolution_rate') }.to raise_error(described_class::UnsupportedMetricError)
    end
  end

  describe 'conversations involved cohort' do
    it 'lists conversations with an AI-authored message in the window' do
      involved = conversation_with_ai_reply
      conversation_with_ai_reply(at: Time.zone.parse('2026-09-01 10:00'))
      create(:conversation, account: account, inbox: inbox)

      result = build(metric: 'conversations_involved')

      expect(result[:meta][:total_count]).to eq(1)
      expect(result[:payload].first[:conversation][:id]).to eq(involved.id)
      expect(result[:payload].first[:record_type]).to eq('conversation')
    end
  end

  describe 'auto-resolution cohort' do
    it 'excludes time-based bot resolutions on conversations that were also handed off' do
      clean = conversation_with_ai_reply
      reporting_event('conversation_pilot_inference_resolved', clean, Time.zone.parse('2026-09-28 10:00'))
      handed_off = conversation_with_ai_reply
      reporting_event('conversation_pilot_inference_handoff', handed_off, Time.zone.parse('2026-09-28 11:00'))
      reporting_event('conversation_bot_resolved', handed_off, Time.zone.parse('2026-09-29 10:00'))

      result = build(metric: 'autonomous_resolution_rate')

      ids = result[:payload].map { |record| record[:conversation][:id] }
      expect(ids).to contain_exactly(clean.id)
    end
  end

  describe 'handoff cohort' do
    it 'lists involved conversations with a handoff event in the window' do
      handed_off = conversation_with_ai_reply
      reporting_event('conversation_pilot_inference_handoff', handed_off, Time.zone.parse('2026-09-28 10:00'))
      conversation_with_ai_reply

      result = build(metric: 'handoff_rate')

      ids = result[:payload].map { |record| record[:conversation][:id] }
      expect(ids).to contain_exactly(handed_off.id)
    end
  end

  describe 'reopen cohort' do
    it 'requires an AI resolution before the reopen' do
      ai_resolved = conversation_with_ai_reply
      reporting_event('conversation_pilot_inference_resolved', ai_resolved, Time.zone.parse('2026-09-27 10:00'),
                      end_time: Time.zone.parse('2026-09-27 10:00'))
      reporting_event('conversation_opened', ai_resolved, Time.zone.parse('2026-09-29 10:00'),
                      end_time: Time.zone.parse('2026-09-29 10:00'))
      human_resolved = conversation_with_ai_reply
      reporting_event('conversation_opened', human_resolved, Time.zone.parse('2026-09-29 11:00'),
                      end_time: Time.zone.parse('2026-09-29 11:00'))

      result = build(metric: 'reopen_after_resolution_rate')

      ids = result[:payload].map { |record| record[:conversation][:id] }
      expect(ids).to contain_exactly(ai_resolved.id)
    end
  end

  describe 'pagination and meta' do
    before do
      3.times { conversation_with_ai_reply }
    end

    it 'clamps per_page at 100 and reports the clamped size' do
      result = build(metric: 'conversations_involved', per_page: 500)

      expect(result[:meta][:per_page]).to eq(100)
    end

    it 'paginates with the requested page size and reports the total' do
      result = build(metric: 'conversations_involved', per_page: 2, page: 2)

      expect(result[:meta][:total_count]).to eq(3)
      expect(result[:meta][:current_page]).to eq(2)
      expect(result[:payload].size).to eq(1)
    end

    it 'describes the resolved window as epoch bounds' do
      result = build(metric: 'conversations_involved')

      expect(result[:meta][:since]).to eq(Time.zone.parse('2026-09-26 00:00:00').to_i)
      expect(result[:meta][:until]).to eq(now.to_i)
      expect(result[:meta][:metric]).to eq('conversations_involved')
    end
  end
end
