# frozen_string_literal: true

module Custom
  module Pilot
    # Calls the LLM to extract candidate Q&A pairs from a resolved
    # conversation transcript. Mirrors the deepdive's 2.1/2.2 prompt
    # structure:
    #
    #   * positions the model as a support-FAQ summariser
    #   * instructs it to use only transcript content, no outside knowledge
    #   * filters out bot/assistant turns (handled by the caller before
    #     building the transcript)
    #   * returns the per-pair minimum shape: `{ question, answer }` only
    #
    # On any LLM exception or malformed JSON the service returns an
    # empty array — no rows, no exception, only an error-level log line.
    # Cross-cutting rule from the deepdive: mining failures never bubble.
    class FaqMiningService < BaseService
      MAX_PAIRS_PER_CONVERSATION = 10

      Pair = Struct.new(:question, :answer, keyword_init: true)

      attr_reader :assistant, :transcript

      def initialize(assistant:, transcript:, account: nil)
        @assistant = assistant
        @transcript = transcript
        super(account: account || assistant&.account)
      end

      def call
        return [] if transcript.blank?

        raw = invoke_llm
        parse_pairs(raw)
      rescue StandardError => e
        Rails.logger.error("[pilot.faq_mining_service] LLM error: #{e.class}: #{e.message}")
        []
      end

      private

      def invoke_llm
        text = nil
        chat_context do |context|
          chat_options = { model: model_for(:autopilot) }
          if ::Llm::Config.openai_compatible?
            chat_options[:provider] = :openai
            chat_options[:assume_model_exists] = true
          end
          chat = context.chat(**chat_options)
          chat.with_instructions(system_prompt)
          response = chat.ask(user_prompt)
          text = response.respond_to?(:content) ? response.content : response.to_s
        end
        text.to_s
      end

      def system_prompt
        <<~PROMPT.strip
          You convert a customer support conversation into FAQ-style entries for a public help centre.

          Rules:
          - Use ONLY information present in the transcript. Do not invent facts or pull from outside knowledge.
          - Treat lines tagged [AGENT] as the human support agent and [CUSTOMER] as the customer.
          - Ignore any automated/system replies; if a line does not clearly belong to the human agent or the customer, skip it.
          - Each FAQ pair MUST be a natural, self-contained question with a concise standalone answer.
          - If no useful FAQ can be extracted, return an empty pairs array.
          - Generate AT MOST #{MAX_PAIRS_PER_CONVERSATION} pairs.
          - Respond with strict JSON in EXACTLY this shape:
            { "pairs": [ { "question": "...", "answer": "..." } ] }
          - Do not include any text, markdown, or commentary outside the JSON.
        PROMPT
      end

      def user_prompt
        "Conversation transcript (oldest first):\n\n#{transcript}\n\nExtract FAQ pairs as JSON."
      end

      def parse_pairs(raw)
        text = sanitize_json(raw)
        return [] if text.blank?

        json = JSON.parse(text)
        Array(json['pairs'] || json[:pairs]).filter_map { |entry| build_pair(entry) }
      rescue JSON::ParserError => e
        Rails.logger.error("[pilot.faq_mining_service] JSON parse error: #{e.message} raw=#{raw.to_s.first(200).inspect}")
        []
      end

      def sanitize_json(raw)
        text = raw.to_s.strip
        return text if text.blank?

        text.gsub(/\A```(?:json)?\s*/, '').gsub(/\s*```\z/, '')
      end

      def build_pair(entry)
        return nil unless entry.is_a?(Hash)

        q = (entry['question'] || entry[:question]).to_s.strip
        a = (entry['answer'] || entry[:answer]).to_s.strip
        return nil if q.blank? || a.blank?

        Pair.new(question: q, answer: a)
      end
    end
  end
end
