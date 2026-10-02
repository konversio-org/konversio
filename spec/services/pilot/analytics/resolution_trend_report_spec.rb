# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::ResolutionTrendReport do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-10-02 12:00:00') }

  before do
    Redis::Alfred.delete(Pilot::OutcomeTrackingHistory::CACHE_KEY)
    travel_to(now)
  end

  def window(range: '7', at: now)
    Pilot::Analytics::ReportingWindow.new(range: range, timezone_offset: '0', now: at)
  end

  def episode(overrides = {})
    create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox,
                                        conversation: create(:conversation, account: account, inbox: inbox), **overrides)
  end

  describe 'daily bucketing for short windows' do
    it 'partitions a 7-day window into gapless daily buckets' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(report[:granularity]).to eq('day')
      expect(report[:buckets].size).to eq(7)
      expect(report[:buckets].first[:start_date]).to eq('2026-09-26')
      expect(report[:buckets].last[:end_date]).to eq('2026-10-02')
      report[:buckets].each_cons(2) do |first, second|
        expect(first[:end_date].to_date.next_day).to eq(second[:start_date].to_date)
      end
    end

    it 'counts involved and autonomous episodes per bucket with null rates for empty buckets' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 11:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 11:05'),
              handoff_at: Time.zone.parse('2026-09-28 11:00'), handoff_reason_category: 'knowledge_gap',
              created_at: Time.zone.parse('2026-09-27 11:00'))

      report = described_class.new(assistant: assistant, window: window).report
      bucket = report[:buckets].find { |entry| entry[:start_date] == '2026-09-27' }
      empty = report[:buckets].find { |entry| entry[:start_date] == '2026-09-29' }

      expect(bucket[:involved]).to eq(2)
      expect(bucket[:autonomous]).to eq(1)
      expect(bucket[:resolution_rate]).to eq(0.5)
      expect(empty[:resolution_rate]).to be_nil
    end
  end

  describe 'weekly bucketing for long windows' do
    it 'buckets a 90-day window by Sunday-start weeks' do
      report = described_class.new(assistant: assistant, window: window(range: '90')).report

      expect(report[:granularity]).to eq('week')
      interior = report[:buckets][1..-2]
      expect(interior).to all(satisfy { |bucket| Date.parse(bucket[:start_date]).sunday? })
      expect(report[:buckets].size).to be >= 13
    end
  end

  describe 'comparison series' do
    it 'shifts daily buckets back by whole weeks, preserving weekdays' do
      report = described_class.new(assistant: assistant, window: window).report
      bucket = report[:buckets].find { |entry| entry[:start_date] == '2026-09-29' } # a Tuesday

      expect(Date.parse(bucket[:comparison][:start_date])).to eq(Date.parse('2026-09-22'))
      expect(Date.parse(bucket[:comparison][:start_date]).tuesday?).to be(true)
    end

    it 'returns null comparison rates when the comparison period predates tracking' do
      # Tracking begins inside the comparison period (one week before the window).
      episode(started_at: Time.zone.parse('2026-09-21 10:00'), created_at: Time.zone.parse('2026-09-21 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))

      report = described_class.new(assistant: assistant, window: window).report

      expect(report[:buckets].map { |entry| entry[:comparison][:resolution_rate] }).to all(be_nil)
      current_bucket = report[:buckets].find { |entry| entry[:start_date] == '2026-09-27' }
      expect(current_bucket[:involved]).to eq(1)
      expect(current_bucket[:resolution_rate]).to eq(1.0)
    end

    it 'reports comparison rates when the comparison period is tracked' do
      episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
      # Comparison bucket (one week earlier): involved but not autonomous.
      episode(started_at: Time.zone.parse('2026-09-20 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-20 10:05'),
              handoff_at: Time.zone.parse('2026-09-21 10:00'), handoff_reason_category: 'knowledge_gap',
              created_at: Time.zone.parse('2026-09-20 10:00'))
      # Current bucket: autonomous.
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))

      report = described_class.new(assistant: assistant, window: window).report
      bucket = report[:buckets].find { |entry| entry[:start_date] == '2026-09-27' }

      expect(bucket[:comparison][:resolution_rate]).to eq(0.0)
      expect(bucket[:resolution_rate]).to eq(1.0)
    end
  end
end
