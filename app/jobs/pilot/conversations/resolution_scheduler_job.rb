# frozen_string_literal: true

module Pilot
  module Conversations
    # Fans out the System B auto-resolve sweep: enqueues a per-account
    # `Pilot::Conversations::ResolutionJob` for every account whose Pilot
    # feature and `pilot_autoresolve` flag are enabled and whose auto-resolve
    # mode is not `disabled`. Mirrors the cadence of the native
    # `Account::ConversationsResolutionSchedulerJob`.
    class ResolutionSchedulerJob < ApplicationJob
      queue_as :scheduled_jobs

      def perform
        Account.find_each(batch_size: 100) do |account|
          next unless eligible?(account)

          Pilot::Conversations::ResolutionJob.perform_later(account: account)
        end
      end

      private

      def eligible?(account)
        account.feature_enabled?('pilot') &&
          account.feature_enabled?('pilot_autoresolve') &&
          !account.pilot_auto_resolve_disabled?
      end
    end
  end
end
