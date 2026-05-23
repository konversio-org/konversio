module Custom
  module Pilot
    # Decides whether an Autopilot reply should be handed off to a human
    # agent. Three trigger paths per the pilot-autopilot spec, evaluated in
    # this strict precedence order:
    #
    #   1. An explicit scenario handoff tool call (any tool name starting
    #      with `handoff_`) emitted by the LLM during this turn.
    #   2. The `[handover]` sentinel string in the assistant reply.
    #   3. A customer-phrase match (e.g. "speak to a human").
    #
    # The first matching signal wins; subsequent signals do NOT also fire
    # (per the "Handover trigger precedence" requirement). The caller
    # (`Pilot::AutopilotInferenceJob`) is responsible for producing exactly
    # one handoff message + one bot-handoff side effect per turn.
    #
    # Returns a `Result` value object with `#handover?` and `#reason`.
    class HandoverEvaluator
      Result = Struct.new(:handover?, :reason, keyword_init: true)

      HANDOVER_SENTINEL = '[handover]'.freeze

      # Matches common ways a user asks for a human across preposition / article
      # variants ("speak to a human", "speak with a human", "talk to someone",
      # "real person", "live agent", "human being", "I need a human").
      HUMAN_REQUEST_PATTERN = /
        \b(?:
          (?:speak|talk|chat|connect)\s+(?:to|with)\s+(?:an?\s+|the\s+)?(?:human|person|agent|someone|operator|representative)
          |
          (?:real|live|actual)\s+(?:human|person|agent)
          |
          human\s+(?:being|agent)
          |
          (?:need|want|get)\s+(?:a\s+|an\s+)?(?:human|real\s+person|live\s+agent)
        )\b
      /ix

      # @param assistant_reply [String, nil] the LLM-produced reply text
      # @param customer_message [String, nil] the most recent customer message
      # @param invoked_tool_names [Array<String>] names of tools that fired
      def evaluate(assistant_reply: nil, customer_message: nil, invoked_tool_names: [])
        # 1. Explicit scenario handoff tool call — highest precedence.
        return Result.new(handover?: true, reason: 'handoff_tool') if handoff_tool_invoked?(invoked_tool_names)

        # 2. LLM sentinel.
        return Result.new(handover?: true, reason: 'sentinel') if sentinel_present?(assistant_reply)

        # 3. Customer-phrase trigger.
        return Result.new(handover?: true, reason: 'customer_request') if customer_phrase_present?(customer_message)

        Result.new(handover?: false, reason: nil)
      end

      private

      def handoff_tool_invoked?(invoked_tool_names)
        Array(invoked_tool_names).any? { |name| name.to_s.start_with?('handoff_') }
      end

      def sentinel_present?(assistant_reply)
        assistant_reply.to_s.downcase.include?(HANDOVER_SENTINEL)
      end

      def customer_phrase_present?(customer_message)
        customer_message.present? && HUMAN_REQUEST_PATTERN.match?(customer_message.to_s)
      end
    end
  end
end
