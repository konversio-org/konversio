module Custom
  module Pilot
    # Orchestrates the opt-in false-promise guard around a completed autopilot
    # run: detect on the final reply text, repair once through the autopilot
    # pipeline, re-verify, and fail safe to a categorized human handoff when
    # the reply cannot be verified safe.
    #
    # Failure isolation in both directions:
    #   - a detected false promise is never delivered (repair, then handoff);
    #   - a guard malfunction before any detection never blocks delivery — the
    #     original reply goes out and the failure is logged.
    class PromiseGuardService < BaseService
      # The repair directive issued with the regeneration run. Internal only;
      # never customer-visible.
      REPAIR_INSTRUCTION = <<~REPAIR.freeze
        Your previous draft reply (the last assistant message in the history) was withheld because it promised work you cannot perform after the reply is sent. Produce a new reply to the customer's latest message. You may call tools again. The new reply MUST do exactly one of these:

          1. Answer from what you can verify in this turn.
          2. Ask the customer one concrete clarifying question.
          3. Offer to connect the customer with a human, without claiming a transfer has already happened.

        Do not commit to any later checking, monitoring, follow-up, notification, or other work that would happen after the reply is sent.
      REPAIR

      # reason_category for guard-triggered handoffs, from
      # Pilot::ConversationOutcome::HANDOFF_REASON_CATEGORIES — distinct from
      # customer_escalation so operators can tell guard bailouts apart.
      GUARD_REASON_CATEGORY = 'policy_refusal'.freeze

      Outcome = Struct.new(:result, :handed_off, keyword_init: true) do
        def handed_off?
          handed_off == true
        end
      end

      def self.call(conversation:, assistant:, run_result:)
        new(conversation: conversation, assistant: assistant, run_result: run_result).call
      end

      def initialize(conversation:, assistant:, run_result:)
        @conversation = conversation
        @assistant = assistant
        @run_result = run_result
        @detection_fired = false
        @first_verdict = nil
        super(account: conversation.account)
      end

      def call
        return outcome(@run_result) unless guard_applies?

        first = detect(@run_result.reply)
        return outcome(@run_result) unless first.promise?

        @detection_fired = true
        @first_verdict = first

        repaired = repair_once
        second = detect(repaired.reply)
        return outcome(repaired) if second.safe?

        guard_handoff(second.promise? ? second : first)
        outcome(nil, handed_off: true)
      rescue StandardError => e
        handle_guard_failure(e)
      end

      private

      attr_reader :conversation, :assistant, :run_result

      def guard_applies?
        return false unless account&.pilot_false_promise_guard_enabled
        return false if run_result.reply.blank?
        return false if run_result.handover&.handover?

        true
      end

      def detect(reply)
        ::Pilot::PromiseGuard.call(conversation: conversation, draft_reply: reply)
      end

      # Exactly one regeneration through the autopilot pipeline: the withheld
      # draft is appended to the run context and the internal repair directive
      # joins the instructions; tools remain available to the run.
      def repair_once
        ::Custom::Pilot::AutopilotService.new(
          assistant: assistant,
          conversation: conversation,
          account: account,
          repair_directive: REPAIR_INSTRUCTION.strip,
          repair_draft: run_result.reply
        ).perform
      end

      def guard_handoff(verdict)
        reason = "promise_guard:#{verdict&.reason_category.presence || 'unverified'}"
        ::Custom::Pilot::HandoffService.call(
          conversation: conversation,
          assistant: assistant,
          reason: reason,
          source: 'system',
          reason_category: GUARD_REASON_CATEGORY,
          message: I18n.t('conversations.pilot.handoff_guard')
        )
        post_guard_note(reason)
      end

      # Operator-facing private note so humans can see WHY the AI bailed.
      def post_guard_note(reason)
        conversation.messages.create!(
          message_type: :outgoing,
          private: true,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          sender: assistant,
          content: I18n.t('conversations.pilot.promise_guard_note', reason: reason)
        )
      rescue StandardError => e
        Rails.logger.warn("[pilot.promise_guard] private note failed: #{e.class}: #{e.message}")
      end

      # A guard failure AFTER a detection fired fails safe to a handoff; a
      # failure before any detection delivers the original reply.
      def handle_guard_failure(error)
        Rails.logger.error("[pilot.promise_guard] guard error: #{error.class}: #{error.message}")
        return outcome(run_result) unless @detection_fired

        begin
          guard_handoff(@first_verdict)
        rescue StandardError => e
          Rails.logger.error("[pilot.promise_guard] fail-safe handoff failed: #{e.class}: #{e.message}")
        end
        outcome(nil, handed_off: true)
      end

      def outcome(result, handed_off: false)
        Outcome.new(result: result, handed_off: handed_off)
      end
    end
  end
end
