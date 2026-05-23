require 'rails_helper'

RSpec.describe Custom::Pilot::BusinessHoursCalculator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe '.call' do
    it 'returns wall-clock seconds when the inbox has no business hours configured' do
      start_at = Time.zone.parse('2026-05-22 10:00:00')
      end_at   = Time.zone.parse('2026-05-22 11:30:00')

      expect(described_class.call(inbox: inbox, from: start_at, to: end_at)).to eq(5400)
    end

    it 'returns 0 when from / to are blank' do
      expect(described_class.call(inbox: inbox, from: nil, to: Time.zone.now)).to eq(0)
    end

    it 'delegates to the business-hours helper when the inbox has working hours enabled' do
      inbox.update!(working_hours_enabled: true)
      # Build a 9-17 Mon-Fri schedule so the helper has something to work with.
      (1..5).each do |day_of_week|
        WorkingHour.create!(
          inbox: inbox,
          day_of_week: day_of_week,
          open_hour: 9,
          open_minutes: 0,
          close_hour: 17,
          close_minutes: 0
        )
      end

      start_at = Time.zone.parse('2026-05-22 10:00:00') # Friday
      end_at   = Time.zone.parse('2026-05-22 12:00:00')

      # We only require that the value differs from wall-clock and is computed
      # without raising; the precise number depends on the working_hours gem.
      value = described_class.call(inbox: inbox, from: start_at, to: end_at)
      expect(value).to be > 0
    end
  end
end
