# frozen_string_literal: true

module Pilot
  module Conversations
    # System B — the AI auto-resolve sweep for a single account. Resolves (or,
    # in evaluated mode, hands off) idle `pending` Pilot conversations. A
    # purely bot-handled conversation never becomes `open`, so the native
    # open-only auto-resolve never touches it; this is what closes those
    # threads instead.
    #
    # Eligibility: `pending` conversations in non-email inboxes that have a
    # Pilot assistant whose auto-resolve mode is not `disabled`, with a
    # contact, idle past the assistant's own inactivity threshold, and not
    # already routed to a human. Capped per run so a backlog drains over
    # several cycles. Each transition re-checks eligibility inside a row lock
    # (see Custom::Pilot::AutoResolveService).
    class ResolutionJob < ApplicationJob
      queue_as :low

      def perform(account:)
        return unless eligible_account?(account)

        assistants_by_inbox = assistants_by_inbox(account)
        return if assistants_by_inbox.empty?

        conversation_scope(account, assistants_by_inbox).each do |conversation|
          process(conversation, account, assistants_by_inbox[conversation.inbox_id])
        end
      end

      private

      def process(conversation, account, assistant)
        return if assistant.blank?

        ::Custom::Pilot::AutoResolveService.new(
          conversation: conversation,
          assistant: assistant,
          account: account
        ).perform
      rescue ActiveRecord::RecordNotFound
        # Deleted mid-sweep — skip silently and keep draining the backlog.
      rescue StandardError => e
        Rails.logger.error("[pilot.conversations.resolution_job] conv=#{conversation.id} failed: #{e.class}: #{e.message}")
      end

      def eligible_account?(account)
        account.present? &&
          account.feature_enabled?('pilot') &&
          account.feature_enabled?('pilot_autoresolve') &&
          !account.pilot_auto_resolve_disabled?
      end

      # Maps inbox_id → assistant for every Pilot inbox of the account whose
      # assistant participates in the sweep (present and not mode `disabled`).
      def assistants_by_inbox(account)
        ::Pilot::Inbox
          .joins(:inbox)
          .includes(:assistant)
          .where(inboxes: { account_id: account.id })
          .where.not(inboxes: { channel_type: 'Channel::Email' })
          .each_with_object({}) do |pilot_inbox, mapping|
            assistant = pilot_inbox.assistant
            next if assistant.blank? || assistant.auto_resolve_mode == 'disabled'

            mapping[pilot_inbox.inbox_id] = assistant
          end
      end

      def conversation_scope(account, assistants_by_inbox)
        account.conversations
               .pending
               .where(inbox_id: assistants_by_inbox.keys)
               .where.not(contact_id: nil)
               .where('last_activity_at < ?', earliest_cutoff(assistants_by_inbox.values))
               .where("COALESCE(additional_attributes -> 'pilot_handoff' ->> 'state', '') NOT IN (?)",
                      %w[handoff_requested offline_acknowledged])
               .limit(Limits::BULK_ACTIONS_LIMIT)
      end

      # SQL prefilter cutoff: the smallest per-assistant threshold, so every
      # potentially eligible conversation is selected; the exact per-assistant
      # threshold is re-checked inside the locked transition.
      def earliest_cutoff(assistants)
        Time.now.utc - assistants.map(&:inactivity_threshold_minutes).min.minutes
      end
    end
  end
end
