module Custom
  module Pilot
    # Judges whether a customer's need in a Pilot conversation is complete, so
    # the evaluated (smart) auto-resolve mode can decide resolve-vs-handoff.
    #
    # Mirrors `CsatAnalysisService`: same MIT `BaseTaskService` transport, same
    # fenced-JSON parse with a neutral fallback. Runs on the install-wide
    # system LLM credential as internal housekeeping (not a customer-facing
    # chat turn). Returns a `Result` with `#complete?` and a short `reason`.
    class ResolutionEvaluator < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      Result = Struct.new(:complete, :reason, keyword_init: true) do
        def complete?
          complete == true
        end
      end

      attr_reader :conversation

      def initialize(conversation:, account:)
        @conversation = conversation
        super(account: account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot Auto-resolve is not enabled for this account' unless feature_enabled?(:autoresolve)

        response = run_llm
        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        parse_response(response)
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.resolution_evaluator] LLM error: #{e.class}: #{e.message}")
        raise Error, e.message
      end

      private

      def run_llm
        chat_messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: transcript }
        ]
        AdHocTaskService.new(account: account, messages: chat_messages).perform
      end

      # Domain-agnostic: never bakes in any customer's domain. Judges purely
      # from the transcript.
      def system_prompt
        <<~PROMPT
          You are reviewing a customer-support conversation between a customer and an AI assistant to decide whether the customer's need has been fully handled and the conversation can be closed.

          Return a single JSON object with exactly these keys:
            "complete": true if the customer's request appears fully resolved and they need nothing further (their question was answered and they did not ask anything else, or they signalled they are done), else false
            "reason": a short explanation (max ~20 words) of your decision

          Treat an unanswered question, a pending request, an unresolved problem, or a customer still waiting on an action as NOT complete. Judge only from the transcript; do not assume facts that are not present. Reply with ONLY the JSON object, no preamble.
        PROMPT
      end

      def transcript
        conversation.messages
                    .where(message_type: %i[incoming outgoing])
                    .where(private: false)
                    .order(:created_at)
                    .filter_map do |msg|
          content = msg.content_for_llm.to_s
          next if content.blank?

          label = msg.message_type == 'incoming' ? 'Customer' : 'Assistant'
          "#{label}: #{content}"
        end.join("\n")
      end

      # On unparseable output we default to NOT complete — handing off to a
      # human is the safe fallback over wrongly closing a live conversation.
      def parse_response(response)
        raw = response.is_a?(Hash) ? response[:message].to_s : response.to_s
        json = raw.match(/```json\s*(.*?)\s*```/m)&.captures&.first || raw
        parsed = JSON.parse(json)

        Result.new(
          complete: parsed['complete'] == true,
          reason: parsed['reason'].to_s.strip.presence || 'no reason given'
        )
      rescue JSON::ParserError => e
        Rails.logger.warn("[pilot.resolution_evaluator] LLM returned non-JSON: #{e.message}")
        Result.new(complete: false, reason: 'evaluator returned unparseable output')
      end

      # Thin one-off task service reusing the MIT BaseTaskService pipeline
      # (system credential resolution, instrumentation) with our own prompt.
      class AdHocTaskService < ::Pilot::BaseTaskService
        pattr_initialize [:account!, :messages!]

        def perform
          make_api_call(model: ::Llm::Config.model_for(:autoresolve), messages: messages)
        end

        private

        def event_name
          'autoresolve'
        end

        def build_follow_up_context?
          false
        end
      end
    end
  end
end
