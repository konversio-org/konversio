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
    # Pilot assistant, with a contact, idle past the fixed window, and not
    # already routed to a human. Capped per run so a backlog drains over
    # several cycles.
    class ResolutionJob < ApplicationJob
      queue_as :low

      def perform(account:)
        return unless eligible_account?(account)

        conversation_scope(account).each { |conversation| process(conversation, account) }
      end

      private

      def process(conversation, account)
        assistant = assistant_for(conversation.inbox)
        return if assistant.blank?

        ::Custom::Pilot::AutoResolveService.new(
          conversation: conversation,
          assistant: assistant,
          account: account
        ).perform
      rescue StandardError => e
        Rails.logger.error("[pilot.conversations.resolution_job] conv=#{conversation.id} failed: #{e.class}: #{e.message}")
      end

      def eligible_account?(account)
        account.present? &&
          account.feature_enabled?('pilot') &&
          account.feature_enabled?('pilot_autoresolve') &&
          !account.pilot_auto_resolve_disabled?
      end

      def conversation_scope(account)
        inbox_ids = pilot_inbox_ids(account)
        return ::Conversation.none if inbox_ids.empty?

        account.conversations
               .pending
               .where(inbox_id: inbox_ids)
               .where.not(contact_id: nil)
               .where('last_activity_at < ?', ::Custom::Pilot::AutoResolveService.idle_cutoff)
               .where("COALESCE(additional_attributes -> 'pilot_handoff' ->> 'state', '') NOT IN (?)",
                      %w[handoff_requested offline_acknowledged])
               .limit(Limits::BULK_ACTIONS_LIMIT)
      end

      def pilot_inbox_ids(account)
        ::Pilot::Inbox
          .joins(:inbox)
          .where(inboxes: { account_id: account.id })
          .where.not(inboxes: { channel_type: 'Channel::Email' })
          .pluck(:inbox_id)
      end

      def assistant_for(inbox)
        return nil if inbox.blank?

        ::Pilot::Inbox.find_by(inbox_id: inbox.id)&.assistant
      end
    end
  end
end
