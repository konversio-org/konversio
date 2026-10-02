require 'rails_helper'

RSpec.describe Pilot::Documents::SyncSchedulerJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:fresh_time) { Time.current }
  # Daily cadence (default): due window is half the interval (12h). 25h ago is
  # comfortably past it.
  let(:stale_attempt_time) { fresh_time - (Pilot::SyncLimits::DEFAULT_REFRESH_INTERVAL + 1.hour) }

  before do
    # Sanitize sibling test accounts (factories from other examples leave
    # accounts behind) so the scheduler only sees ours.
    Account.where.not(id: account.id).find_each do |a|
      a.disable_features!(:pilot_autopilot)
    end

    account.enable_features!(:pilot, :pilot_autopilot)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def make_synced_doc(last_synced_at:, account_override: nil, assistant_override: nil)
    create(
      :pilot_document,
      assistant: assistant_override || assistant,
      account: account_override || account,
      status: :available,
      sync_status: :synced,
      last_synced_at: last_synced_at,
      last_sync_attempted_at: last_synced_at
    )
  end

  def refresh_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Pilot::Documents::RefreshJob }
  end

  def refresh_job_ids
    refresh_jobs.map { |j| j[:args].first }
  end

  describe 'eligibility filter' do
    it 'enqueues synced docs whose cadence window has elapsed' do
      doc = make_synced_doc(last_synced_at: stale_attempt_time)

      described_class.perform_now

      expect(refresh_job_ids).to include(doc.id)
      expect(doc.reload.sync_status).to eq('syncing')
      expect(doc.last_sync_attempted_at).to be > stale_attempt_time
    end

    it 'skips synced docs still within the due window' do
      doc = make_synced_doc(last_synced_at: 5.minutes.ago)

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
      expect(doc.reload.sync_status).to eq('synced')
    end

    it 'enqueues failed docs whose retry window has elapsed' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :available, sync_status: :failed,
        last_sync_attempted_at: stale_attempt_time
      )

      described_class.perform_now

      expect(refresh_job_ids).to include(doc.id)
    end

    it 'recovers stuck syncing rows past STALE_TIMEOUT' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :available, sync_status: :syncing,
        last_sync_attempted_at: fresh_time - (Pilot::SyncLimits::STALE_TIMEOUT + 5.minutes)
      )
      # Re-clear after the doc's after_commit response-builder enqueue.
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now

      expect(refresh_job_ids).to include(doc.id)
    end

    it 'leaves syncing rows alone when they are still within STALE_TIMEOUT' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :available, sync_status: :syncing,
        last_sync_attempted_at: 30.minutes.ago
      )

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end

    it 'skips initial-crawl (in_progress) rows regardless of sync_status' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :in_progress, sync_status: :synced,
        last_synced_at: stale_attempt_time
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end

    it 'skips PDF-backed sources' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        external_link: 'PDF: handbook_2026-01-01.pdf',
        status: :available, sync_status: :synced,
        last_synced_at: stale_attempt_time
      )

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end

    it 'skips markdown-backed sources' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        external_link: 'MD: notes_2026-01-01.md',
        status: :available, sync_status: :synced,
        last_synced_at: stale_attempt_time
      )

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end

    it 'skips accounts without pilot_autopilot' do
      doc = make_synced_doc(last_synced_at: stale_attempt_time)
      account.disable_features!(:pilot_autopilot)

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end
  end

  describe 'per-account cadence' do
    it 'does not enqueue a weekly account document synced two days ago' do
      account.pilot_document_sync_interval = 'weekly'
      account.save!
      doc = make_synced_doc(last_synced_at: 2.days.ago)

      described_class.perform_now

      expect(refresh_job_ids).not_to include(doc.id)
    end

    it 'enqueues a weekly account document past the half-interval due window' do
      account.pilot_document_sync_interval = 'weekly'
      account.save!
      doc = make_synced_doc(last_synced_at: 5.days.ago)

      described_class.perform_now

      expect(refresh_job_ids).to include(doc.id)
    end

    it 'renders a late jittered execution eligible again at the next cadence window' do
      account.pilot_document_sync_interval = 'daily'
      account.save!
      # Executed late in the previous daily window and is now just past the 12h
      # half-interval due window, so it is due again on the next tick instead
      # of waiting a full 24h.
      doc = make_synced_doc(last_synced_at: 13.hours.ago)

      described_class.perform_now

      expect(refresh_job_ids).to include(doc.id)
    end

    it 'enqueues refreshes with a delay bounded by the cadence jitter window' do
      account.pilot_document_sync_interval = 'daily'
      account.save!
      make_synced_doc(last_synced_at: stale_attempt_time)

      described_class.perform_now

      max_seconds = account.pilot_document_sync_jitter_hours.hours.to_i
      delay = refresh_jobs.first[:at].to_f - Time.current.to_f
      expect(delay).to be >= 0
      expect(delay).to be <= max_seconds
    end
  end

  describe 'rate limiting' do
    it 'enforces the per-account hourly cap' do
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 3)
      5.times { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now

      expect(refresh_jobs.size).to eq(3)
    end

    it 'enforces the global hourly cap across accounts' do
      stub_const('Pilot::SyncLimits::GLOBAL_HOURLY_CAP', 2)
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 50)
      3.times { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now

      expect(refresh_jobs.size).to eq(2)
    end
  end

  describe 'selection order and double-enqueue guard' do
    it 'orders by last_sync_attempted_at ASC NULLS FIRST (never-attempted first)' do
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 2)

      never_attempted = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :available, sync_status: :synced,
        last_synced_at: stale_attempt_time, last_sync_attempted_at: nil
      )
      attempted_long_ago = make_synced_doc(last_synced_at: stale_attempt_time - 2.days)
      Pilot::Document.where(id: attempted_long_ago.id).update_all(last_sync_attempted_at: stale_attempt_time - 2.days)
      _attempted_recently = make_synced_doc(last_synced_at: stale_attempt_time + 0.minutes)

      described_class.perform_now

      enqueued_ids = refresh_job_ids
      expect(enqueued_ids).to include(never_attempted.id, attempted_long_ago.id)
      expect(enqueued_ids.size).to eq(2)
    end

    it 'pre-marks docs as syncing in the same transactional update so a second tick is a no-op' do
      docs = Array.new(2) { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now
      first_tick_count = refresh_jobs.size

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.perform_now

      expect(first_tick_count).to eq(2)
      expect(refresh_jobs).to be_empty
      docs.each { |d| expect(d.reload.sync_status).to eq('syncing') }
    end
  end

  describe 'logging' do
    it 'emits a single structured tick-complete log line' do
      make_synced_doc(last_synced_at: stale_attempt_time)
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg }

      described_class.perform_now

      expect(logged.compact).to include(a_string_matching(/\[pilot.sync_scheduler\] tick complete/))
    end
  end
end
