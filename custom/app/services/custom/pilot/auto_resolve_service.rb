module Custom
  module Pilot
    # Decides what System B does to a single idle `pending` Pilot conversation,
    # per the assistant's auto-resolve mode (falling back to the account
    # setting when the assistant has no explicit mode):
    #
    #   - legacy    → resolve unconditionally (time-based).
    #   - evaluated → ask the LLM whether the customer's need is complete;
    #                 complete → resolve, otherwise → hand off to a human.
    #   - disabled  → no-op (the sweep job also filters these out).
    #
    # The idle threshold comes from the assistant's `auto_resolve_after`
    # config, falling back to the installation-level override, then the
    # built-in default. The customer-facing resolution message is delegated to
    # `Pilot::Conversations::ResolutionMessageService`.
    class AutoResolveService < BaseService
      DEFAULT_IDLE_MINUTES = ::Pilot::Assistant::DEFAULT_INACTIVITY_THRESHOLD_MINUTES

      # Installation-level idle window fallback (used when the assistant has
      # no explicit threshold).
      def self.idle_minutes
        ::Pilot::Assistant.default_inactivity_threshold_minutes
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
        case effective_mode
        when 'legacy'
          resolve!(reason: 'idle_timeout')
        when 'evaluated'
          evaluate_and_act
        end
      end

      private

      def effective_mode
        assistant&.auto_resolve_mode.presence || account.pilot_auto_resolve_mode
      end

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
        conversation.pending? && conversation.last_activity_at < idle_cutoff
      end

      def idle_cutoff
        Time.now.utc - threshold_minutes.minutes
      end

      def threshold_minutes
        assistant&.inactivity_threshold_minutes || self.class.idle_minutes
      end

      # Locked, idempotent transition: re-check inside a row lock that the
      # conversation is still pending and still idle so a concurrent sweep run
      # (or a human resolve) cannot double-post or resurrect the thread.
      def resolve!(reason:)
        conversation.with_lock do
          conversation.reload
          return unless still_eligible?

          ::Pilot::Conversations::ResolutionMessageService.call(conversation: conversation, assistant: assistant)
          ::Custom::Pilot::ConversationResolver.resolve!(
            conversation: conversation,
            assistant: assistant,
            reason: reason
          )
        end
      end

      # Reuses the inference handoff machinery. No fallback message — the
      # assistant's handoff copy is posted only when set (HandoffService skips
      # a blank message).
      def handoff!(reason:)
        conversation.with_lock do
          conversation.reload
          return unless still_eligible?

          ::Custom::Pilot::HandoffService.call(
            conversation: conversation,
            assistant: assistant,
            reason: reason,
            source: 'inactivity',
            reason_category: 'knowledge_gap',
            message: assistant.handoff_message.presence
          )
        end
      end
    end
  end
end
