require 'rails_helper'

RSpec.describe Pilot::EventsRetentionJob do
  let(:account) { create(:account) }

  it 'enqueues the job on the scheduled_jobs queue' do
    expect { described_class.perform_later }
      .to have_enqueued_job(described_class)
      .on_queue('scheduled_jobs')
  end

  describe 'pilot_events retention' do
    it 'deletes pilot_events rows older than 30 days' do
      Pilot::Event.create!(account_id: account.id, event_name: 'pilot.briefing.completed', payload: {}, created_at: 31.days.ago)
      Pilot::Event.create!(account_id: account.id, event_name: 'pilot.briefing.completed', payload: {}, created_at: 60.days.ago)

      expect { described_class.perform_now }.to change(Pilot::Event, :count).by(-2)
    end

    it 'retains pilot_events rows within the 30-day window' do
      recent = Pilot::Event.create!(account_id: account.id, event_name: 'pilot.briefing.completed', payload: {},
                                    created_at: 1.day.ago)
      borderline = Pilot::Event.create!(account_id: account.id, event_name: 'pilot.briefing.completed', payload: {},
                                        created_at: 29.days.ago)

      expect { described_class.perform_now }.not_to change(Pilot::Event, :count)
      expect(Pilot::Event.where(id: [recent.id, borderline.id]).count).to eq(2)
    end

    it 'does not touch pilot_reporting_events (handled by host retention)' do
      conversation = create(:conversation, account: account)
      Pilot::ReportingEvent.create!(
        account_id: account.id,
        conversation_id: conversation.id,
        inbox_id: conversation.inbox_id,
        name: 'pilot.autopilot.autoresolved',
        event_start_at: 90.days.ago,
        event_end_at: 90.days.ago,
        value: 0.0,
        value_in_business_hours: 0.0,
        created_at: 90.days.ago
      )

      expect { described_class.perform_now }.not_to change(Pilot::ReportingEvent, :count)
    end
  end

  it 'exposes the retention window as a constant' do
    expect(described_class::PILOT_EVENTS_RETENTION_DAYS).to eq(30)
  end
end
