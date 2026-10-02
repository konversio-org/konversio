require 'rails_helper'

RSpec.describe Pilot::Documents::RefreshJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:document) do
    create(:pilot_document,
           assistant: assistant,
           account: account,
           external_link: 'https://example.com/help',
           status: :available,
           sync_status: :synced,
           content: 'stored body')
  end

  before do
    document
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Redis::LockManager).to receive(:new).and_return(instance_double(Redis::LockManager, lock: true, unlock: true))
  end

  describe '#perform' do
    it 'retries transient failures on the bounded backoff then marks the document failed' do
      error = Pilot::Documents::RefreshService::TransientRefreshError.new(
        'boom', error_code: 'ingestion.timeout', failure_category: :timeout
      )
      service = instance_double(Pilot::Documents::RefreshService)
      allow(Pilot::Documents::RefreshService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(error)

      perform_enqueued_jobs do
        described_class.perform_later(document.id)
      end

      expect(service).to have_received(:perform).at_least(4).times
      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.last_sync_failure_category).to eq('timeout')
      expect(document.content).to eq('stored body')
    end

    it 'does not retry a permanent failure already recorded by the service' do
      service = instance_double(
        Pilot::Documents::RefreshService,
        perform: Pilot::Documents::RefreshService::Result.new(outcome: :failed, failure_category: :not_found)
      )
      allow(Pilot::Documents::RefreshService).to receive(:new).and_return(service)

      described_class.perform_now(document.id)

      expect(service).to have_received(:perform).once
    end

    it 'marks unexpected errors with a generic category and reports once' do
      service = instance_double(Pilot::Documents::RefreshService)
      allow(Pilot::Documents::RefreshService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(ArgumentError, 'parser crashed')
      tracker = instance_double(KonversioExceptionTracker, capture_exception: true)
      allow(KonversioExceptionTracker).to receive(:new).and_return(tracker)

      described_class.perform_now(document.id)

      document.reload
      expect(document.sync_status).to eq('failed')
      expect(document.last_sync_failure_category).to eq('unexpected')
      expect(tracker).to have_received(:capture_exception).once
    end

    it 'skips documents that are no longer syncable' do
      document.update!(external_link: 'MD: notes.md')
      expect(Pilot::Documents::RefreshService).not_to receive(:new)

      described_class.perform_now(document.id)
    end

    it 'reschedules when the per-document lock is held' do
      allow(Redis::LockManager).to receive(:new).and_return(instance_double(Redis::LockManager, lock: false))
      expect(Pilot::Documents::RefreshService).not_to receive(:new)

      expect do
        described_class.perform_now(document.id)
      end.to have_enqueued_job(described_class).with(document.id)
    end
  end
end
