require 'rails_helper'

RSpec.describe Pilot::Documents::SyncSchedulerJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:fresh_time) { Time.current }
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

  def crawl_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Pilot::Documents::CrawlJob }
  end

  describe 'eligibility filter' do
    it 'enqueues synced docs whose refresh window has elapsed' do
      doc = make_synced_doc(last_synced_at: stale_attempt_time)

      described_class.perform_now

      expect(crawl_jobs.map { |j| j[:args].first }).to include(doc.id)
      expect(doc.reload.sync_status).to eq('syncing')
      expect(doc.last_sync_attempted_at).to be > stale_attempt_time
    end

    it 'skips synced docs still within the refresh window' do
      doc = make_synced_doc(last_synced_at: 5.minutes.ago)

      described_class.perform_now

      expect(crawl_jobs.map { |j| j[:args].first }).not_to include(doc.id)
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

      expect(crawl_jobs.map { |j| j[:args].first }).to include(doc.id)
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

      expect(crawl_jobs.map { |j| j[:args].first }).to include(doc.id)
    end

    it 'leaves syncing rows alone when they are still within STALE_TIMEOUT' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :available, sync_status: :syncing,
        last_sync_attempted_at: 30.minutes.ago
      )

      described_class.perform_now

      expect(crawl_jobs.map { |j| j[:args].first }).not_to include(doc.id)
    end

    it 'skips initial-crawl (in_progress) rows regardless of sync_status' do
      doc = create(
        :pilot_document,
        assistant: assistant, account: account,
        status: :in_progress, sync_status: :synced,
        last_synced_at: stale_attempt_time
      )
      # The Pilot::Document model auto-enqueues CrawlJob for in_progress
      # rows on create. Clear that out so we can assert the scheduler
      # itself does NOT additionally pick up the row.
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now

      expect(crawl_jobs.map { |j| j[:args].first }).not_to include(doc.id)
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

      expect(crawl_jobs.map { |j| j[:args].first }).not_to include(doc.id)
    end

    it 'skips accounts without pilot_autopilot' do
      doc = make_synced_doc(last_synced_at: stale_attempt_time)
      account.disable_features!(:pilot_autopilot)

      described_class.perform_now

      expect(crawl_jobs.map { |j| j[:args].first }).not_to include(doc.id)
    end
  end

  describe 'rate limiting' do
    it 'enforces the per-account hourly cap' do
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 3)
      5.times { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now

      expect(crawl_jobs.size).to eq(3)
    end

    it 'enforces the global hourly cap across accounts' do
      stub_const('Pilot::SyncLimits::GLOBAL_HOURLY_CAP', 2)
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 50)
      3.times { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now

      expect(crawl_jobs.size).to eq(2)
    end
  end

  describe 'selection order and double-enqueue guard' do
    it 'orders by last_sync_attempted_at ASC NULLS FIRST (never-attempted first)' do
      stub_const('Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP', 2)

      # Three candidates: one never attempted (NULL), one attempted long ago,
      # one attempted more recently but still past the refresh window.
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

      enqueued_ids = crawl_jobs.map { |j| j[:args].first }
      expect(enqueued_ids).to include(never_attempted.id, attempted_long_ago.id)
      expect(enqueued_ids.size).to eq(2)
    end

    it 'pre-marks docs as syncing in the same transactional update so a second tick is a no-op' do
      docs = Array.new(2) { make_synced_doc(last_synced_at: stale_attempt_time) }

      described_class.perform_now
      first_tick_count = crawl_jobs.size

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.perform_now

      expect(first_tick_count).to eq(2)
      expect(crawl_jobs).to be_empty
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
