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

      # English defaults; can be overridden per-account via account settings
      # later. We compare lowercased substrings; phrase order doesn't matter.
      DEFAULT_HUMAN_REQUEST_PHRASES = [
        'speak to a human',
        'talk to a human',
        'real person',
        'human agent',
        'talk to someone',
        'speak to someone',
        'human being',
        'live agent',
        'live person',
        'real human'
      ].freeze

      def initialize(human_request_phrases: nil)
        @phrases = human_request_phrases.presence || DEFAULT_HUMAN_REQUEST_PHRASES
      end

      # @param assistant_reply [String, nil] the LLM-produced reply text
      # @param customer_message [String, nil] the most recent customer message
      # @param invoked_tool_names [Array<String>] names of tools that fired
      def evaluate(assistant_reply: nil, customer_message: nil, invoked_tool_names: [])
        if assistant_reply.to_s.downcase.include?(HANDOVER_SENTINEL)
          return Result.new(handover?: true, reason: 'sentinel')
        end

        if customer_message.present? && matches_human_request?(customer_message)
          return Result.new(handover?: true, reason: 'customer_request')
        end

        if Array(invoked_tool_names).any? { |name| name.to_s.start_with?('handoff_') }
          return Result.new(handover?: true, reason: 'handoff_tool')
        end

        Result.new(handover?: false, reason: nil)
      end

      private

      def matches_human_request?(message)
        normalized = message.to_s.downcase
        @phrases.any? { |phrase| normalized.include?(phrase.downcase) }
      end
    end
  end
end
