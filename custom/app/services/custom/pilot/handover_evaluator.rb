module Custom
  module Pilot
    # Decides whether an Autopilot reply should be handed off to a human
    # agent. Three trigger paths per the pilot-autopilot spec:
    #
    #   1. The assistant reply contains a `[handover]` sentinel string.
    #   2. The most recent customer message contains a known "speak to a
    #      human" phrase.
    #   3. Any tool the model invoked has a name starting with `handoff_`.
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
        return Result.new(handover?: true, reason: 'sentinel') if assistant_reply.to_s.downcase.include?(HANDOVER_SENTINEL)

        if customer_message.present? && HUMAN_REQUEST_PATTERN.match?(customer_message.to_s)
          return Result.new(handover?: true, reason: 'customer_request')
        end

        return Result.new(handover?: true, reason: 'handoff_tool') if Array(invoked_tool_names).any? { |name| name.to_s.start_with?('handoff_') }

        Result.new(handover?: false, reason: nil)
      end
    end
  end
end
