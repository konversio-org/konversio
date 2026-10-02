module Pilot
  module Documents
    # Per-document refresh worker. Delegates the actual single-page fetch,
    # fingerprint comparison, and failure classification to
    # `Pilot::Documents::RefreshService`.
    #
    # Transient failures retry on the same bounded backoff as the crawl path
    # ([30s, 2m, 5m]) and only mark the document failed once attempts are
    # exhausted. Permanent failures are already recorded by the service, so
    # the job does not retry them. Anything outside the taxonomy is contained
    # by the safety net: mark failed with a generic category and report once.
    class RefreshJob < ApplicationJob
      queue_as :low

      RETRY_WAITS = [30.seconds, 2.minutes, 5.minutes].freeze
      LOCK_TIMEOUT = 30.minutes
      LOCK_RETRY_WAIT = 1.minute

      retry_on ::Pilot::Documents::RefreshService::TransientRefreshError,
               attempts: RETRY_WAITS.length + 1,
               wait: ->(executions) { RETRY_WAITS[executions - 1] || RETRY_WAITS.last } do |job, error|
        job.send(:mark_failed_after_retries, error)
      end

      def perform(document_id)
        @document = ::Pilot::Document.find_by(id: document_id)
        return if @document.blank?
        return unless @document.syncable?

        with_document_lock do
          ::Pilot::Documents::RefreshService.new(@document).perform
        end
      rescue ::Pilot::Documents::RefreshService::TransientRefreshError
        # Let ActiveJob's retry_on handle the backoff.
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.refresh_job] unexpected #{e.class}: #{e.message}")
        report_exception(e)
        mark_failed(:unexpected)
      end

      private

      def with_document_lock
        lock_manager = ::Redis::LockManager.new
        key = "pilot:documents:refresh:#{@document.id}"
        locked = lock_manager.lock(key, LOCK_TIMEOUT)
        unless locked
          reschedule_locked
          return
        end

        yield
      ensure
        lock_manager&.unlock(key) if locked
      end

      def reschedule_locked
        Rails.logger.info("[pilot.refresh_job] lock busy document=#{@document.id}")
        self.class.set(wait: LOCK_RETRY_WAIT).perform_later(@document.id)
      end

      def mark_failed_after_retries(error)
        @document ||= ::Pilot::Document.find_by(id: arguments.first)
        return if @document.blank?

        category = error.respond_to?(:failure_category) ? error.failure_category : :unexpected
        mark_failed(category)
      end

      def mark_failed(category)
        return if @document.blank?

        @document.update!(
          sync_status: :failed,
          metadata: (@document.metadata || {}).merge(
            'last_sync_failure_category' => category.to_s,
            'refresh_phase' => nil
          )
        )
      end

      def report_exception(error)
        ::KonversioExceptionTracker.new(error, account: @document&.account).capture_exception
      end
    end
  end
end
