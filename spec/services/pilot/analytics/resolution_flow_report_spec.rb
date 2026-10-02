# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::ResolutionFlowReport do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-10-02 12:00:00') }
  let(:window) { Pilot::Analytics::ReportingWindow.new(range: '7', timezone_offset: '0', now: now) }

  before do
    Redis::Alfred.delete(Pilot::OutcomeTrackingHistory::CACHE_KEY)
    travel_to(now)
  end

  def episode(overrides = {})
    create(:pilot_conversation_outcome, account: account, assistant: assistant, inbox: inbox,
                                        conversation: create(:conversation, account: account, inbox: inbox), **overrides)
  end

  def seed_tracking!
    episode(started_at: Time.zone.parse('2026-09-01 10:00'), created_at: Time.zone.parse('2026-09-01 10:00'))
  end

  def link(report, source, target)
    report[:links].find { |entry| entry[:source] == source && entry[:target] == target }
  end

  describe 'balanced branches' do
    before do
      seed_tracking!
      # Autonomous, stayed closed.
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              resolved_at: Time.zone.parse('2026-09-28 10:00'), created_at: Time.zone.parse('2026-09-27 10:00'))
      # Autonomous, reopened within the durability window.
      episode(started_at: Time.zone.parse('2026-09-27 11:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 11:05'),
              resolved_at: Time.zone.parse('2026-09-28 11:00'), ended_at: Time.zone.parse('2026-09-30 11:00'),
              created_at: Time.zone.parse('2026-09-27 11:00'))
      # Handed off.
      episode(started_at: Time.zone.parse('2026-09-28 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-28 10:05'),
              handoff_at: Time.zone.parse('2026-09-29 10:00'), handoff_reason_category: 'knowledge_gap',
              created_at: Time.zone.parse('2026-09-28 10:00'))
      # Closed with the team (involved, neither autonomous nor handed off).
      episode(started_at: Time.zone.parse('2026-09-29 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-29 10:05'),
              first_human_reply_at: Time.zone.parse('2026-09-29 11:00'), created_at: Time.zone.parse('2026-09-29 10:00'))
      # Not involved at all (quota block before any AI reply) — excluded everywhere.
      episode(started_at: Time.zone.parse('2026-09-29 12:00'), handoff_at: Time.zone.parse('2026-09-29 12:01'),
              handoff_reason_category: 'quota_exhausted', created_at: Time.zone.parse('2026-09-29 12:00'))
    end

    it 'splits the involved cohort into three branches summing to the cohort total' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(link(report, 'involved', 'autonomous')[:value]).to eq(2)
      expect(link(report, 'involved', 'handed_off')[:value]).to eq(1)
      expect(link(report, 'involved', 'closed_with_team')[:value]).to eq(1)
      expect(report[:nodes].find { |node| node[:id] == 'involved' }[:value]).to eq(4)
    end

    it 'splits autonomous resolutions into stayed closed and reopened' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(link(report, 'autonomous', 'stayed_closed')[:value]).to eq(1)
      expect(link(report, 'autonomous', 'reopened')[:value]).to eq(1)
    end
  end

  describe 'handoff-reason distribution' do
    before do
      seed_tracking!
      2.times do |index|
        episode(started_at: Time.zone.parse("2026-09-27 1#{index}:00"), first_ai_reply_at: Time.zone.parse("2026-09-27 1#{index}:05"),
                handoff_at: Time.zone.parse("2026-09-28 1#{index}:00"), handoff_reason_category: 'knowledge_gap',
                created_at: Time.zone.parse("2026-09-27 1#{index}:00"))
      end
      episode(started_at: Time.zone.parse('2026-09-28 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-28 10:05'),
              handoff_at: Time.zone.parse('2026-09-28 11:00'), handoff_reason_category: nil,
              created_at: Time.zone.parse('2026-09-28 10:00'))
    end

    it 'groups uncategorized handoffs into a single bucket with counts and percentages, sorted by count' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(report[:handoff_reasons]).to eq(
        [
          { category: 'knowledge_gap', count: 2, percentage: 66.7 },
          { category: 'uncategorized', count: 1, percentage: 33.3 }
        ]
      )
    end
  end

  describe 'diagram aggregation of the long tail' do
    before do
      seed_tracking!
      categories = %w[customer_escalation knowledge_gap policy_refusal system_failure other]
      categories.each_with_index do |category, index|
        episode(started_at: Time.zone.parse("2026-09-27 1#{index}:00"), first_ai_reply_at: Time.zone.parse("2026-09-27 1#{index}:05"),
                handoff_at: Time.zone.parse("2026-09-28 1#{index}:00"), handoff_reason_category: category,
                created_at: Time.zone.parse("2026-09-27 1#{index}:00"))
      end
    end

    it 'highlights the top reasons and aggregates the rest into a balanced other-reasons branch' do
      report = described_class.new(assistant: assistant, window: window).report

      reason_links = report[:links].select { |entry| entry[:source] == 'handed_off' }
      expect(reason_links.size).to eq(4)
      expect(reason_links.sum { |entry| entry[:value] }).to eq(5)
      expect(link(report, 'handed_off', 'other_reasons')[:value]).to eq(2)
    end
  end

  describe 'untracked periods' do
    it 'returns empty nodes, links, and distribution when the window predates tracking' do
      episode(started_at: Time.zone.parse('2026-09-27 10:00'), first_ai_reply_at: Time.zone.parse('2026-09-27 10:05'),
              handoff_at: Time.zone.parse('2026-09-28 10:00'), handoff_reason_category: 'knowledge_gap',
              created_at: Time.zone.parse('2026-09-27 10:00'))
      early_window = Pilot::Analytics::ReportingWindow.new(range: '7', timezone_offset: '0', now: Time.zone.parse('2026-09-24 12:00:00'))

      report = described_class.new(assistant: assistant, window: early_window).report
      expect(report).to eq(nodes: [], links: [], handoff_reasons: [])
    end

    it 'returns an empty flow when no episodes exist' do
      report = described_class.new(assistant: assistant, window: window).report

      expect(report).to eq(nodes: [], links: [], handoff_reasons: [])
    end
  end
end
