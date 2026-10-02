# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Analytics::ReportingWindow do
  let(:now) { Time.zone.parse('2026-10-02 14:30:00') }

  def build(range:, offset: '0', at: now)
    described_class.new(range: range, timezone_offset: offset, now: at)
  end

  describe 'day-count ranges' do
    it 'resolves two adjacent 7-day windows ending now in the viewer timezone' do
      window = build(range: '7')

      expect(window.current).to eq(Time.zone.parse('2026-09-26 00:00:00')...now.in_time_zone('UTC'))
      expect(window.previous).to eq(Time.zone.parse('2026-09-19 00:00:00')...Time.zone.parse('2026-09-26 00:00:00'))
    end

    it 'aligns the current window start to the viewer day, not the server day' do
      window = build(range: '7', offset: '5.5', at: Time.zone.parse('2026-10-02 01:00:00'))

      viewer = ActiveSupport::TimeZone['New Delhi']
      expect(window.current.begin).to eq(viewer.parse('2026-09-26 00:00:00'))
    end

    it 'supports 30 and 90 day ranges' do
      expect(build(range: '30').current.begin).to eq(Time.zone.parse('2026-09-03 00:00:00'))
      expect(build(range: '90').current.begin).to eq(Time.zone.parse('2026-07-05 00:00:00'))
    end

    it 'excludes the shared boundary from the previous window' do
      window = build(range: '7')

      expect(window.previous).not_to cover(window.current.begin)
      expect(window.current).to cover(window.current.begin)
    end
  end

  describe 'named calendar periods' do
    it 'resolves this_month from the first instant of the viewer month' do
      window = build(range: 'this_month')

      expect(window.current.begin).to eq(Time.zone.parse('2026-10-01 00:00:00'))
      expect(window.current.end).to eq(now)
    end

    it 'mirrors the elapsed offset into the preceding month' do
      window = build(range: 'this_month')

      expect(window.previous.begin).to eq(Time.zone.parse('2026-09-01 00:00:00'))
      expect(window.previous.end).to eq(Time.zone.parse('2026-09-01 00:00:00') + (now - Time.zone.parse('2026-10-01 00:00:00')))
    end

    it 'clamps the comparison window at the previous month end' do
      window = build(range: 'this_month', at: Time.zone.parse('2026-03-31 12:00:00'))

      expect(window.previous.begin).to eq(Time.zone.parse('2026-02-01 00:00:00'))
      expect(window.previous.end).to eq(Time.zone.parse('2026-03-01 00:00:00'))
    end

    it 'resolves last_month as the full preceding calendar month' do
      window = build(range: 'last_month')

      expect(window.current).to eq(Time.zone.parse('2026-09-01 00:00:00')...Time.zone.parse('2026-10-01 00:00:00'))
      expect(window.previous).to eq(Time.zone.parse('2026-08-01 00:00:00')...Time.zone.parse('2026-09-01 00:00:00'))
    end

    it 'resolves this_week starting on Sunday in the viewer timezone' do
      # 2026-10-02 is a Friday; the containing week starts Sunday 2026-09-27.
      window = build(range: 'this_week')

      expect(window.current.begin).to eq(Time.zone.parse('2026-09-27 00:00:00'))
      expect(window.current.end).to eq(now)
    end

    it 'resolves last_week as the full preceding Sunday-start week' do
      window = build(range: 'last_week')

      expect(window.current).to eq(Time.zone.parse('2026-09-20 00:00:00')...Time.zone.parse('2026-09-27 00:00:00'))
      expect(window.previous).to eq(Time.zone.parse('2026-09-13 00:00:00')...Time.zone.parse('2026-09-20 00:00:00'))
    end

    it 'mirrors the elapsed offset into the preceding week for this_week' do
      window = build(range: 'this_week')

      expect(window.previous.begin).to eq(Time.zone.parse('2026-09-20 00:00:00'))
      expect(window.previous.end).to eq(Time.zone.parse('2026-09-20 00:00:00') + (now - Time.zone.parse('2026-09-27 00:00:00')))
    end
  end

  describe 'unknown ranges' do
    it 'falls back to the 7-day window' do
      window = build(range: 'nonsense')

      expect(window.range).to eq('7')
      expect(window.current.begin).to eq(Time.zone.parse('2026-09-26 00:00:00'))
    end
  end

  describe 'timezone offset validation' do
    it 'flags an unparseable offset as invalid and falls back to the unshifted clock' do
      window = build(range: '7', offset: 'not-a-number')

      expect(window.timezone_valid?).to be(false)
      expect(window.current.begin).to eq(Time.zone.parse('2026-09-26 00:00:00'))
    end

    it 'accepts parseable hour offsets including fractional ones' do
      expect(build(range: '7', offset: '5.5').timezone_valid?).to be(true)
      expect(build(range: '7', offset: '-4').timezone_valid?).to be(true)
    end

    it 'treats a blank offset as valid (server timezone fallback)' do
      expect(build(range: '7', offset: nil).timezone_valid?).to be(true)
    end
  end

  describe '#period' do
    it 'exposes a label and start/end dates for the current window' do
      period = build(range: 'this_month').period

      expect(period).to eq(label: 'This month', start_date: '2026-10-01', end_date: '2026-10-02')
    end
  end
end
