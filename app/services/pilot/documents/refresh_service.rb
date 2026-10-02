module Pilot
  module Documents
    # Refreshes a single URL-backed `Pilot::Document` from its own source link.
    #
    # Unlike `CrawlJob` (which fans a seed URL out into many child documents
    # during first ingestion), a refresh fetches exactly the document's own
    # page, hashes the whitespace-normalized body, and only writes new content
    # when the fingerprint changed — which is what triggers the existing
    # knowledge-rebuild callback. Failures are classified permanent (mark the
    # document failed, no retry) or transient (raise so the job retries on a
    # bounded backoff).
    class RefreshService
      # Raised for transient fetch failures so the caller can retry.
      class TransientRefreshError < StandardError
        attr_reader :error_code, :failure_category

        def initialize(message, error_code:, failure_category:)
          super(message)
          @error_code = error_code
          @failure_category = failure_category
        end
      end

      Result = Struct.new(:outcome, :failure_category, :content_changed, keyword_init: true) do
        def skipped?
          outcome == :skipped
        end

        def baseline?
          outcome == :baseline
        end

        def unchanged?
          outcome == :unchanged
        end

        def updated?
          outcome == :updated
        end

        def failed?
          outcome == :failed
        end
      end

      # Internal normalized fetch result. `transient` mirrors the ingestion
      # service's taxonomy so both the HTTP and Firecrawl paths feed one
      # classification point.
      FetchResult = Struct.new(:success, :content, :title, :failure_category, :error_code, :transient, keyword_init: true) do
        def success?
          success == true
        end

        def transient?
          transient == true
        end
      end

      def initialize(document)
        @document = document
      end

      def perform
        return Result.new(outcome: :skipped) unless document.syncable?

        mark_phase('fetching')
        fetch_result = fetch
        raise_transient_error!(fetch_result) if fetch_result.transient?
        return mark_failed(:empty_body) if fetch_result.success? && fetch_result.content.to_s.strip.blank?
        return mark_failed(fetch_result.failure_category || :unexpected) unless fetch_result.success?

        apply_success(fetch_result)
      end

      private

      attr_reader :document

      def fetch
        return firecrawl_fetch if firecrawl_api_key.present?

        http_fetch
      end

      def firecrawl_fetch
        result = ::Custom::Pilot::DocumentCrawlService.new(account: document.account).scrape(document.external_link)
        FetchResult.new(
          success: result.success?,
          content: result.content,
          title: result.title,
          failure_category: result.failure_category,
          error_code: result.error_code,
          transient: result.transient?
        )
      end

      def http_fetch
        result = ::Custom::Pilot::DocumentIngestionService.new(document: document, account: document.account).perform
        FetchResult.new(
          success: result.success?,
          content: result.content,
          failure_category: result.failure_category,
          error_code: result.error_code,
          transient: result.transient?
        )
      rescue ::Custom::Pilot::DocumentIngestionService::TransientFetchError => e
        FetchResult.new(success: false, failure_category: e.failure_category, error_code: e.error_code, transient: true)
      end

      # Success path: record the fingerprint on the first refresh without
      # emitting an update, skip a whitespace-only-equivalent page, and write
      # content (which triggers the knowledge rebuild) only on a real change.
      def apply_success(fetch_result)
        new_fingerprint = fingerprint(fetch_result.content)
        return record_baseline(new_fingerprint) if document.content_fingerprint.blank?
        return record_unchanged if document.content_fingerprint == new_fingerprint

        record_update(fetch_result, new_fingerprint)
      end

      def record_baseline(new_fingerprint)
        mark_phase('comparing')
        document.content_fingerprint = new_fingerprint
        save_synced
        Result.new(outcome: :baseline, content_changed: false)
      end

      def record_unchanged
        mark_phase('comparing')
        save_synced
        Result.new(outcome: :unchanged, content_changed: false)
      end

      def record_update(fetch_result, new_fingerprint)
        mark_phase('updating')
        document.content = fetch_result.content
        document.name = fetch_result.title if fetch_result.title.present?
        document.content_fingerprint = new_fingerprint
        save_synced
        Result.new(outcome: :updated, content_changed: true)
      end

      def mark_failed(category)
        document.sync_status = :failed
        document.last_sync_failure_category = category.to_s
        document.refresh_phase = nil
        document.last_sync_attempted_at = Time.current
        document.save! if document.changed?
        Result.new(outcome: :failed, failure_category: category, content_changed: false)
      end

      def save_synced
        now = Time.current
        document.sync_status = :synced
        document.last_sync_failure_category = nil
        document.refresh_phase = nil
        document.last_synced_at = now
        document.last_sync_attempted_at = now
        document.save!
      end

      def mark_phase(phase)
        document.update!(refresh_phase: phase)
      end

      def fingerprint(content)
        Digest::SHA256.hexdigest(normalize(content))
      end

      def normalize(content)
        content.to_s.gsub(/\s+/, ' ').strip
      end

      def raise_transient_error!(fetch_result)
        raise TransientRefreshError.new(
          "Transient refresh failure: #{fetch_result.error_code}",
          error_code: fetch_result.error_code,
          failure_category: fetch_result.failure_category
        )
      end

      def firecrawl_api_key
        ::GlobalConfigService.load('PILOT_FIRECRAWL_API_KEY', nil)
      end
    end
  end
end
