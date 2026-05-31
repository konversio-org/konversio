module Custom
  module Pilot
    # Decides what System B does to a single idle `pending` Pilot conversation,
    # per the account's auto-resolve mode:
    #
    #   - legacy    → resolve unconditionally (time-based).
    #   - evaluated → ask the LLM whether the customer's need is complete;
    #                 complete → resolve, otherwise → hand off to a human.
    #   - disabled  → no-op (the scheduler also filters these out).
    #
    # The idle window is a fixed constant (default 60 min), overridable only
    # via global config for ops tuning — it is not admin-configurable.
    class AutoResolveService < BaseService
      DEFAULT_IDLE_MINUTES = 60

      # Fixed idle window before an idle pending conversation is acted on.
      def self.idle_minutes
        GlobalConfigService.load('PILOT_AUTORESOLVE_IDLE_MINUTES', DEFAULT_IDLE_MINUTES).to_i.then do |v|
          v.positive? ? v : DEFAULT_IDLE_MINUTES
        end
      end

      def self.idle_cutoff
        Time.now.utc - idle_minutes.minutes
      end

      attr_reader :conversation, :assistant

      def initialize(conversation:, assistant:, account:)
        @conversation = conversation
        @assistant = assistant
        super(account: account)
      end

      def perform
        case account.pilot_auto_resolve_mode
        when 'legacy'
          resolve!(reason: 'idle_timeout')
        when 'evaluated'
          evaluate_and_act
        end
      end

      private

      def evaluate_and_act
        verdict = ::Custom::Pilot::ResolutionEvaluator.new(conversation: conversation, account: account).perform

        # Re-engagement guard: the LLM call takes wall-clock time, so only act
        # if this is still an idle pending bot thread (the customer may have
        # replied in the meantime).
        conversation.reload
        return unless still_eligible?

        if verdict.complete?
          resolve!(reason: verdict.reason)
        else
          handoff!(reason: verdict.reason)
        end
      rescue ::Custom::Pilot::ResolutionEvaluator::Error => e
        # Transient evaluator failure — leave the conversation pending and let
        # the next sweep retry rather than guessing an outcome.
        Rails.logger.warn("[pilot.auto_resolve] evaluator failed conv=#{conversation.display_id}: #{e.message}")
      end

      def still_eligible?
        conversation.pending? && conversation.last_activity_at < self.class.idle_cutoff
      end

      def resolve!(reason:)
        ::Custom::Pilot::ConversationResolver.resolve!(
          conversation: conversation,
          assistant: assistant,
          reason: reason,
          post_message: resolution_message
        )
      end

      # Reuses the inference handoff machinery. No fallback message — the
      # assistant's handoff copy is posted only when set (HandoffService skips
      # a blank message).
      def handoff!(reason:)
        ::Custom::Pilot::HandoffService.call(
          conversation: conversation,
          assistant: assistant,
          reason: reason,
          message: assistant.handoff_message.presence
        )
      end

      def resolution_message
        assistant.resolution_message.presence || I18n.t('conversations.pilot.resolution')
      end
    end
  end
end
