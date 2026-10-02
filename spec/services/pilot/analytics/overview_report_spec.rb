# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::OverviewReport do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-10-02 12:00:00') }
  let(:window) { Pilot::Analytics::ReportingWindow.new(range: '7', timezone_offset: '0', now: now) }

  # Current window: 2026-09-26 00:00 .. 2026-10-02 12:00
  # Previous window: 2026-09-19 00:00 .. 2026-09-26 00:00

  before do
    Redis::Alfred.delete(Pilot::OutcomeTrackingHistory::CACHE_KEY)
    travel_to(now)
  end

  def episode(overrides = {})
    create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox,
                                        conversation: create(:conversation, account: account, inbox: inbox), **overrides)
  end

  # Installation-wide tracking history predating both windows, so the windows
  # under test are tracked. Counts in neither window and matches no
  # classification.
  def seed_tracking!
    episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
  end

  def ai_reply(conversation, at)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, private: false, sender: assistant, created_at: at)
  end

  describe 'metric packing and trend semantics' do
    before do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))
      episode(started_at: Time.zone.parse('2026-09-20 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-20 10:05'),
              resolved_at: Time.zone.parse('2026-09-20 12:00'), created_at: Time.zone.parse('2026-09-20 10:00'))
      episode(started_at: Time.zone.parse('2026-09-21 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-21 10:05'),
              resolved_at: Time.zone.parse('2026-09-21 12:00'), created_at: Time.zone.parse('2026-09-21 10:00'))
    end

    it 'packs every metric as current/previous/trend and exposes the tracking start' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(report[:tracking_started_at]).to eq(Time.zone.parse('2026-09-01 10:00'))
      report[:metrics].each_value do |pack|
        expect(pack).to include(:current, :previous, :trend)
      end
    end

    it 'uses percent change for count metrics, zero when the previous value is zero' do
      report = described_class.new(assistant: assistant, window: window).report
      involved = report[:metrics][:conversations_involved]

      expect(involved[:current]).to eq(1)
      expect(involved[:previous]).to eq(2)
      expect(involved[:trend]).to eq(-50.0)
    end

    it 'uses point difference for rate metrics' do
      episode(started_at: Time.zone.parse('2026-09-28 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-28 10:05'),
              handoff_at: Time.zone.parse('2026-09-29 10:00'), handoff_reason_category: 'knowledge_gap',
              created_at: Time.zone.parse('2026-09-28 10:00'))
      report = described_class.new(assistant: assistant, window: window).report
      rate = report[:metrics][:autonomous_resolution_rate]

      expect(rate[:current]).to eq(0.5)
      expect(rate[:previous]).to eq(1.0)
      expect(rate[:trend]).to eq(-0.5)
    end

    it 'uses absolute difference for duration metrics' do
      report = described_class.new(assistant: assistant, window: window).report
      median = report[:metrics][:median_resolution_seconds]

      expect(median[:current]).to eq(86_400)
      expect(median[:previous]).to eq(7200)
      expect(median[:trend]).to eq(79_200)
    end
  end

  describe 'episode classification rules' do
    it 'does not count a quota-blocked episode without an AI reply as involved' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), handoff_at: Time.zone.parse('2026-09-27 10:01'),
              handoff_reason_category: 'quota_exhausted', created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:conversations_involved][:current]).to eq(0)
      expect(metrics[:handoffs][:current]).to eq(0)
    end

    it 'counts a quota transfer after AI participation as a real handoff' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              handoff_at: Time.zone.parse('2026-09-28 10:00'), handoff_reason_category: 'quota_exhausted',
              created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:conversations_involved][:current]).to eq(1)
      expect(metrics[:handoffs][:current]).to eq(1)
    end

    it 'treats a human reply before the resolution as assisted, not autonomous' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              first_human_reply_at: Time.zone.parse('2026-09-28 09:00'), resolved_at: Time.zone.parse('2026-09-28 10:00'),
              csat_rating: 3, created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:conversations_involved][:current]).to eq(1)
      expect(metrics[:autonomous_resolutions][:current]).to eq(0)
      expect(metrics[:assisted_csat][:current]).to eq(3.0)
    end
  end

  describe 'reopen and durable resolution rates' do
    it 'shares the autonomy cohort and counts reopens inside the window' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-26 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-26 10:05'),
              resolved_at: Time.zone.parse('2026-09-27 10:00'), created_at: Time.zone.parse('2026-09-26 10:00'))
      episode(started_at: Time.zone.parse('2026-09-26 11:00'), first_ai_reply_at: Time.zone.parse('2026-09-26 11:05'),
              resolved_at: Time.zone.parse('2026-09-27 11:00'), ended_at: Time.zone.parse('2026-09-30 11:00'),
              created_at: Time.zone.parse('2026-09-26 11:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:autonomous_resolutions][:current]).to eq(2)
      expect(metrics[:reopen_after_resolution_rate][:current]).to eq(0.5)
    end

    it 'judges only resolutions at least seven days old for the durable rate' do
      seed_tracking!
      # Too recent to judge: resolved 5 days before `now`.
      episode(started_at: Time.zone.parse('2026-09-26 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-26 10:05'),
              resolved_at: Time.zone.parse('2026-09-27 10:00'), created_at: Time.zone.parse('2026-09-26 10:00'))
      # Old enough, held.
      episode(started_at: Time.zone.parse('2026-09-19 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-19 10:05'),
              resolved_at: Time.zone.parse('2026-09-20 10:00'), created_at: Time.zone.parse('2026-09-19 10:00'))
      # Old enough, reopened within the durability window.
      episode(started_at: Time.zone.parse('2026-09-19 12:00'), first_ai_reply_at: Time.zone.parse('2026-09-19 12:05'),
              resolved_at: Time.zone.parse('2026-09-20 12:00'), ended_at: Time.zone.parse('2026-09-23 12:00'),
              created_at: Time.zone.parse('2026-09-19 12:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:durable_resolution_rate][:previous]).to eq(0.5)
      expect(metrics[:durable_resolution_rate][:current]).to be_nil
    end
  end

  describe 'reply-activity metrics' do
    it 'derives hours saved and depth from public AI replies' do
      seed_tracking!
      conversations = create_list(:conversation, 2, account: account, inbox: inbox)
      4.times { |i| ai_reply(conversations.first, Time.zone.parse("2026-09-27 10:0#{i}")) }
      2.times { |i| ai_reply(conversations.second, Time.zone.parse("2026-09-28 10:0#{i}")) }
      ai_reply(conversations.first, Time.zone.parse('2026-09-20 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:estimated_hours_saved][:current]).to eq(0.2)
      expect(metrics[:conversation_depth][:current]).to eq(3.0)
      expect(metrics[:estimated_hours_saved][:previous]).to eq(0.0)
      expect(metrics[:conversation_depth][:previous]).to eq(1.0)
    end

    it 'reports zero depth when no conversation received a reply' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:conversation_depth][:current]).to eq(0)
    end
  end

  describe 'CSAT comparison metrics' do
    it 'keeps cohort averages separate and excludes AI-involved conversations from the baseline' do
      seed_tracking!
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), csat_rating: 5, created_at: Time.zone.parse('2026-09-27 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 11:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 11:05'),
              first_human_reply_at: Time.zone.parse('2026-09-28 09:00'), resolved_at: Time.zone.parse('2026-09-28 11:00'),
              csat_rating: 3, created_at: Time.zone.parse('2026-09-27 11:00'))
      ai_touched = create(:conversation, account: account, inbox: inbox)
      create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox, conversation: ai_touched,
                                          started_at: Time.zone.parse('2026-09-27 12:00'), created_at: Time.zone.parse('2026-09-27 12:00'))
      create(:csat_survey_response, account: account, conversation: ai_touched, rating: 1,
                                    created_at: Time.zone.parse('2026-09-29 10:00'))
      human_only = create(:conversation, account: account, inbox: inbox)
      create(:csat_survey_response, account: account, conversation: human_only, rating: 4,
                                    created_at: Time.zone.parse('2026-09-29 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:autonomous_csat][:current]).to eq(5.0)
      expect(metrics[:assisted_csat][:current]).to eq(3.0)
      expect(metrics[:human_only_csat][:current]).to eq(4.0)
    end
  end

  describe 'untracked windows' do
    it 'returns null values and null trends for windows that predate tracking' do
      # Tracking begins mid-week: the current window is tracked, the previous
      # window starts before tracking began.
      episode(started_at: Time.zone.parse('2026-09-22 10:00'), created_at: Time.zone.parse('2026-09-22 10:00'))
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              created_at: Time.zone.parse('2026-09-27 10:00'))

      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]
      expect(metrics[:conversations_involved][:current]).to eq(1)
      expect(metrics[:conversations_involved][:previous]).to be_nil
      expect(metrics[:conversations_involved][:trend]).to be_nil
    end

    it 'returns nulls everywhere when no episodes exist at all' do
      metrics = described_class.new(assistant: assistant, window: window).report[:metrics]

      expect(metrics[:conversations_involved]).to eq(current: nil, previous: nil, trend: nil)
    end
  end
end
