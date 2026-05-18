module Custom
  module Pilot
    # Analyses a free-text CSAT comment and returns sentiment + themes +
    # escalation recommendation.
    #
    # Wraps the MIT `::Pilot::CsatUtilityAnalysisService` for use by the
    # `Pilot::CsatAnalysisJob`. The MIT service classifies messages as
    # `LIKELY_UTILITY` / `LIKELY_MARKETING` / `UNCLEAR`; for the Pilot
    # CSAT analysis use-case we use it as the LLM transport and shape
    # the response into the columns the pilot-utilities spec requires
    # (sentiment, themes, escalation_recommended).
    #
    # Returns a Hash: { sentiment:, themes:, escalation_recommended: }.
    # Raises `Custom::Pilot::CsatAnalysisService::Error` on LLM/transport failure.
    class CsatAnalysisService < BaseService
      class Error < StandardError; end
      class FeatureDisabledError < Error; end

      SENTIMENTS = %w[positive neutral negative].freeze

      attr_reader :feedback_message

      def initialize(feedback_message:, account:)
        @feedback_message = feedback_message
        super(account: account)
      end

      def perform
        raise FeatureDisabledError, 'Pilot CSAT analysis is not enabled for this account' unless feature_enabled?(:csat_analysis)

        dispatch_event(:csat_analysis_started)

        response = run_llm

        raise Error, response[:error] if response.is_a?(Hash) && response[:error].present?

        result = parse_response(response)
        dispatch_event(:csat_analysis_completed, sentiment: result[:sentiment], theme_count: result[:themes].length)

        result
      rescue FeatureDisabledError, Error
        raise
      rescue StandardError => e
        Rails.logger.error("[pilot.csat_analysis] LLM error: #{e.class}: #{e.message}")
        dispatch_event(:csat_analysis_failed, error: e.message)
        raise Error, e.message
      end

      private

      def run_llm
        chat_messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: feedback_message.to_s }
        ]

        # Delegate the transport to the MIT base task service via a thin
        # adapter — we want the same instrumentation, credential handling,
        # and error normalization, but a different prompt + parse path
        # than CsatUtilityAnalysisService provides out of the box.
        adapter = AdHocTaskService.new(account: account, messages: chat_messages)
        adapter.perform
      end

      def system_prompt
        <<~PROMPT
          You are analyzing a free-text comment a customer left on a customer-satisfaction (CSAT) survey.
          Return a single JSON object with exactly these keys:
            "sentiment": one of "positive", "neutral", "negative"
            "themes": array of 1-5 short lowercase noun phrases describing the topics raised (e.g. "refund", "slow response")
            "escalation_recommended": true if the comment suggests the customer needs human follow-up (anger, threats, churn risk, urgent unresolved issue), else false

          Reply with ONLY the JSON object, no preamble.
        PROMPT
      end

      def parse_response(response)
        raw = response.is_a?(Hash) ? response[:message].to_s : response.to_s
        json = raw.match(/```json\s*(.*?)\s*```/m)&.captures&.first || raw
        parsed = JSON.parse(json)

        {
          sentiment: normalize_sentiment(parsed['sentiment']),
          themes: Array(parsed['themes']).map(&:to_s).reject(&:blank?),
          escalation_recommended: parsed['escalation_recommended'] == true
        }
      rescue JSON::ParserError => e
        Rails.logger.warn("[pilot.csat_analysis] LLM returned non-JSON: #{e.message}")
        { sentiment: 'neutral', themes: [], escalation_recommended: false }
      end

      def normalize_sentiment(value)
        normalized = value.to_s.downcase
        SENTIMENTS.include?(normalized) ? normalized : 'neutral'
      end

      # Thin one-off task service that lets us call the MIT BaseTaskService
      # pipeline (LLM credential resolution, instrumentation) with arbitrary
      # messages rather than a feature-specific prompt template.
      class AdHocTaskService < ::Pilot::BaseTaskService
        pattr_initialize [:account!, :messages!]

        def perform
          make_api_call(model: self.class.const_get(:GPT_MODEL), messages: messages)
        end

        private

        def event_name
          'csat_analysis'
        end

        def build_follow_up_context?
          false
        end
      end
    end
  end
end
