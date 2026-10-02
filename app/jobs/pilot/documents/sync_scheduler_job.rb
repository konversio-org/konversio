# frozen_string_literal: true

module Pilot
  module Documents
    # Hourly cron job that enqueues refreshes for URL-backed `Pilot::Document`
    # sources whose account cadence window has elapsed.
    #
    #   * Eligibility is a three-branch disjunction over (sync_status,
    #     recency-timestamp): synced past the due window, failed past the due
    #     window, or stuck `syncing` past STALE_TIMEOUT (the recovery path).
    #   * The due window is half of the account's configured cadence so a
    #     document whose jittered execution landed late does not skip its next
    #     cycle.
    #   * Selection order is `last_sync_attempted_at ASC NULLS FIRST, id ASC`
    #     so never-attempted rows go first.
    #   * Per-account and global caps (installation-config overridable) bound
    #     runaway load.
    #   * Pre-mark `sync_status = "syncing"` AND stamp
    #     `last_sync_attempted_at` in one transactional update so racing ticks
    #     can't double-enqueue, then enqueue each reserved row with a
    #     cadence-scaled random delay.
    #   * File-backed (PDF/markdown) and initial-crawl rows are filtered out.
    #
    # The per-document refresh is delegated to `Pilot::Documents::RefreshJob`.
    class SyncSchedulerJob < ApplicationJob
      queue_as :scheduled_jobs

      ELIGIBLE_SYNC_STATUS_SQL = <<~SQL.squish
        (
          (sync_status = :synced AND (last_synced_at IS NULL OR last_synced_at < :interval_cutoff))
          OR
          (sync_status = :failed AND (last_sync_attempted_at IS NULL OR last_sync_attempted_at < :interval_cutoff))
          OR
          (sync_status = :syncing AND last_sync_attempted_at < :stale_cutoff)
        )
      SQL

      def perform
        tick_start = Time.current
        counters = { accounts_scanned: 0, sources_enqueued: 0, sources_skipped_capped: 0, global_cap_hit: false }
        global_remaining = ::Pilot::SyncLimits.global_cap

        accounts = ::Account.where(id: eligible_account_ids).index_by(&:id)

        accounts.each_value do |account|
          counters[:accounts_scanned] += 1
          if global_remaining <= 0
            counters[:global_cap_hit] = true
            break
          end
          global_remaining -= step_account(account, global_remaining, tick_start, counters)
        end

        log_tick(counters)
      end

      private

      def step_account(account, global_remaining, tick_start, counters)
        enqueued = enqueue_for_account(account, global_remaining, tick_start)
        counters[:sources_enqueued] += enqueued
        over_account_cap = account_over_cap_count(account, tick_start)
        counters[:sources_skipped_capped] += over_account_cap if over_account_cap.positive?
        enqueued
      end

      def log_tick(counters)
        Rails.logger.info(
          '[pilot.sync_scheduler] tick complete ' \
          "accounts_scanned=#{counters[:accounts_scanned]} " \
          "sources_enqueued=#{counters[:sources_enqueued]} " \
          "sources_skipped_capped=#{counters[:sources_skipped_capped]} " \
          "global_cap_hit=#{counters[:global_cap_hit]}"
        )
      end

      # Accounts that (a) have Pilot Autopilot enabled and (b) have at least
      # one available document.
      def eligible_account_ids
        ::Account
          .feature_pilot
          .feature_pilot_autopilot
          .where(
            id: ::Pilot::Document.where(status: ::Pilot::Document.statuses[:available]).select(:account_id)
          )
          .pluck(:id)
      end

      # Three-branch disjunction over (sync_status, recency-timestamp), plus
      # the structural filters (`status = available`, URL-backed). File-backed
      # rows are excluded by their synthetic `PDF:`/`MD:` link prefixes.
      def eligible_scope(account, tick_start)
        interval = account.pilot_document_sync_interval_hours.hours
        interval_cutoff = tick_start - (interval / 2)
        stale_cutoff = tick_start - ::Pilot::SyncLimits::STALE_TIMEOUT

        ::Pilot::Document
          .where(account_id: account.id, status: ::Pilot::Document.statuses[:available])
          .where('external_link NOT LIKE ? AND external_link NOT LIKE ?', 'PDF:%', "#{::Pilot::Document::MARKDOWN_LINK_PREFIX}%")
          .where(
            ELIGIBLE_SYNC_STATUS_SQL,
            synced: ::Pilot::Document.sync_statuses[:synced],
            failed: ::Pilot::Document.sync_statuses[:failed],
            syncing: ::Pilot::Document.sync_statuses[:syncing],
            interval_cutoff: interval_cutoff,
            stale_cutoff: stale_cutoff
          )
          .order(Arel.sql('last_sync_attempted_at ASC NULLS FIRST, id ASC'))
      end

      def enqueue_for_account(account, global_remaining, tick_start)
        cap = [::Pilot::SyncLimits.per_account_cap, global_remaining].min
        return 0 if cap <= 0

        candidate_ids = eligible_scope(account, tick_start).limit(cap).pluck(:id)
        return 0 if candidate_ids.empty?

        reserved_ids = reserve_slots(candidate_ids, tick_start)
        delay = jitter_delay(account)
        reserved_ids.each { |id| ::Pilot::Documents::RefreshJob.set(wait: delay).perform_later(id) }
        reserved_ids.size
      end

      def jitter_delay(account)
        max_seconds = account.pilot_document_sync_jitter_hours.hours.to_i
        return 0 if max_seconds <= 0

        rand(max_seconds)
      end

      # Atomic bulk update with a recency guard: only rows whose
      # `last_sync_attempted_at` hasn't moved since the candidate scan get
      # claimed. Stuck-syncing rows (old `last_sync_attempted_at`) pass the
      # guard and get re-reserved.
      def reserve_slots(ids, tick_start)
        return [] if ids.blank?

        reserved = ::Pilot::Document
                   .where(id: ids)
                   .where('last_sync_attempted_at IS NULL OR last_sync_attempted_at < ?', tick_start)
        actually_reserved_ids = reserved.pluck(:id)
        reserved.update_all(
          sync_status: ::Pilot::Document.sync_statuses[:syncing],
          last_sync_attempted_at: tick_start
        )
        actually_reserved_ids
      end

      def account_over_cap_count(account, tick_start)
        eligible_scope(account, tick_start).count - ::Pilot::SyncLimits.per_account_cap
      end
    end
  end
end
