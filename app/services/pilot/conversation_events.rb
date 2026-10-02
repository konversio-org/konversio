# frozen_string_literal: true

module Pilot
  # Emits Pilot conversation lifecycle domain events on the internal event bus
  # so outcome recording — and future consumers such as reporting and webhooks —
  # stay decoupled from the customer-facing flows that trigger them.
  #
  # Emission is a secondary effect of that flow: a dispatch failure is logged
  # and reported to the exception tracker, never raised into the escalation or
  # resolution that triggered it.
  class ConversationEvents
    class << self
      # @param conversation [Conversation]
      # @param assistant [Pilot::Assistant] the attributed assistant
      # @param source [String] which path triggered the handoff
      #   (e.g. "ai_tool", "inference", "inactivity", "quota", "system")
      # @param reason_category [String] a value from
      #   {Pilot::ConversationOutcome::HANDOFF_REASON_CATEGORIES}
      # @param at [Time] the handoff timestamp
      def handed_off(conversation:, assistant:, source:, reason_category:, at: Time.zone.now)
        dispatch(
          Events::Types::PILOT_CONVERSATION_HANDED_OFF,
          conversation: conversation,
          assistant: assistant,
          source: source,
          reason_category: reason_category,
          at: at
        )
      end

      private

      def dispatch(name, conversation:, at:, **payload)
        return if conversation.blank?

        data = payload.merge(conversation: conversation, timestamp: at).compact
        Rails.configuration.dispatcher.dispatch(name, at, data)
      rescue StandardError => e
        Rails.logger.error("[pilot.conversation_events] #{name} dispatch failed: #{e.class}: #{e.message}")
        KonversioExceptionTracker.new(e, account: conversation&.account).capture_exception
        nil
      end
    end
  end
end
