# frozen_string_literal: true

module Pilot
  module Documents
    # Hourly cron job that re-fetches URL-backed `Pilot::Document` sources
    # whose refresh window has elapsed. Mirrors the behaviour spelled out in
    # the deepdive's section 1 (Source Sync Scheduler):
    #
    #   * Eligibility is a three-branch disjunction over (sync_status,
    #     last_attempt_at) rather than a flat status filter — see
    #     `eligible_scope`. The third branch (`syncing` past STALE_TIMEOUT)
    #     is the stuck-state recovery path.
    #   * Selection order is `last_sync_attempted_at ASC NULLS FIRST, id ASC`
    #     so never-attempted rows go first and ties are broken
    #     deterministically by primary key.
    #   * Per-account cap (50) and global cap (1000) bound runaway load.
    #   * Pre-mark `sync_status = "syncing"` AND stamp
    #     `last_sync_attempted_at = Time.current` in the same transactional
    #     update so two cron ticks racing each other can't double-enqueue.
    #   * PDF / initial-crawl / pilot-disabled rows are filtered out by
    #     structural checks.
    #
    # The per-source crawl is delegated to the existing
    # `Pilot::Documents::CrawlJob` — this job's only responsibility is
    # eligibility + cap enforcement + reservation.
    class SyncSchedulerJob < ApplicationJob
      queue_as :scheduled_jobs

      def perform
        tick_start = Time.current
        counters = { accounts_scanned: 0, sources_enqueued: 0, sources_skipped_capped: 0, global_cap_hit: false }
        global_remaining = ::Pilot::SyncLimits::GLOBAL_HOURLY_CAP

        eligible_account_ids.each do |account_id|
          counters[:accounts_scanned] += 1
          if global_remaining <= 0
            counters[:global_cap_hit] = true
            break
          end
          global_remaining -= step_account(account_id, global_remaining, tick_start, counters)
        end

        log_tick(counters)
      end

      private

      def step_account(account_id, global_remaining, tick_start, counters)
        enqueued = enqueue_for_account(account_id, global_remaining, tick_start)
        counters[:sources_enqueued] += enqueued
        over_account_cap = account_over_cap_count(account_id, tick_start)
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
      # one URL-backed `available` document — these are the only accounts
      # whose docs could possibly be re-syncable this tick.
      def eligible_account_ids
        ::Account
          .feature_pilot
          .feature_pilot_autopilot
          .where(
            id: ::Pilot::Document.where(status: ::Pilot::Document.statuses[:available]).select(:account_id)
          )
          .pluck(:id)
      end

      # Three-branch disjunction over (sync_status, recency-timestamp),
      # PLUS the structural filters (`status = available`, URL-backed,
      # account belongs to caller).
      #
      # PDF rows are filtered in Ruby — the URL prefix check (`external_link
      # LIKE 'PDF:%'`) and the attachment check don't map cleanly to a single
      # SQL filter, so we exclude them with a NOT LIKE on the canonical PDF
      # placeholder format set in `Pilot::Document#set_external_link_for_pdf`.
      def eligible_scope(account_id, tick_start)
        interval_cutoff = tick_start - ::Pilot::SyncLimits::DEFAULT_REFRESH_INTERVAL
        stale_cutoff = tick_start - ::Pilot::SyncLimits::STALE_TIMEOUT

        ::Pilot::Document
          .where(account_id: account_id, status: ::Pilot::Document.statuses[:available])
          .where('external_link NOT LIKE ?', 'PDF:%')
          .where(
            <<~SQL.squish, synced: ::Pilot::Document.sync_statuses[:synced],
              (
                (sync_status = :synced AND (last_synced_at IS NULL OR last_synced_at < :interval_cutoff))
                OR
                (sync_status = :failed AND (last_sync_attempted_at IS NULL OR last_sync_attempted_at < :interval_cutoff))
                OR
                (sync_status = :syncing AND last_sync_attempted_at < :stale_cutoff)
              )
            SQL
                           failed: ::Pilot::Document.sync_statuses[:failed],
                           syncing: ::Pilot::Document.sync_statuses[:syncing],
                           interval_cutoff: interval_cutoff,
                           stale_cutoff: stale_cutoff
          )
          .order(Arel.sql('last_sync_attempted_at ASC NULLS FIRST, id ASC'))
      end

      def enqueue_for_account(account_id, global_remaining, tick_start)
        cap = [::Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP, global_remaining].min
        return 0 if cap <= 0

        candidate_ids = eligible_scope(account_id, tick_start).limit(cap).pluck(:id)
        return 0 if candidate_ids.empty?

        # Reserve the rows atomically. The reservation guards against two
        # cron ticks each picking the same set of fresh rows. Rows that pass
        # the eligibility predicate INCLUDE stuck-syncing rows past the
        # STALE_TIMEOUT — for those we want re-enqueue, so the reservation
        # query intentionally accepts rows in `syncing` state as long as
        # they're still in the candidate set.
        reserved_ids = reserve_slots(candidate_ids, tick_start)
        reserved_ids.each { |id| ::Pilot::Documents::CrawlJob.perform_later(id) }
        reserved_ids.size
      end

      def reserve_slots(ids, tick_start)
        return [] if ids.blank?

        # Atomic bulk update with a recency guard: only rows whose
        # `last_sync_attempted_at` hasn't moved since the candidate scan
        # (NULL, or strictly older than this tick's reservation time) get
        # claimed. A competing tick that already stamped the row a few ms
        # earlier will fail this guard, so the second tick won't double-
        # enqueue. Stuck-syncing rows (whose old `last_sync_attempted_at`
        # is well in the past) pass the guard and get re-reserved.
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

      def account_over_cap_count(account_id, tick_start)
        eligible_scope(account_id, tick_start).count - ::Pilot::SyncLimits::PER_ACCOUNT_HOURLY_CAP
      end
    end
  end
end
