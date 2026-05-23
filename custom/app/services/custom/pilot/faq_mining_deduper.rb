# frozen_string_literal: true

module Custom
  module Pilot
    # Dedups newly mined FAQ candidates against the assistant's existing
    # response corpus. Per the deepdive's 2.3/2.4:
    #
    #   * compare candidate against BOTH approved AND pending rows
    #     (prevents flood-prone questions from creating duplicate pending
    #     rows in the queue)
    #   * candidate side is embedded as the concatenated string
    #     `"<question>: <answer>"`
    #   * threshold: cosine distance < 0.3 (similarity > 0.7) → drop
    #   * drops are debug-logged (silent in production logs by default)
    class FaqMiningDeduper < BaseService
      THRESHOLD = ::Pilot::Conversations::FaqMiningJob::FAQ_DEDUP_DISTANCE_THRESHOLD

      attr_reader :assistant

      def initialize(assistant:, account: nil)
        @assistant = assistant
        super(account: account || assistant&.account)
      end

      def filter(pairs)
        return [] if pairs.blank?

        embedder = ::Custom::Pilot::EmbeddingService.new(account: account)
        survivors = []
        survivor_vectors = []
        pairs.each { |pair| consider_pair(pair, embedder, survivors, survivor_vectors) }
        survivors
      end

      private

      def consider_pair(pair, embedder, survivors, survivor_vectors)
        q = pair.respond_to?(:question) ? pair.question : pair[:question]
        a = pair.respond_to?(:answer) ? pair.answer : pair[:answer]
        vec = safely_embed(embedder, "#{q}: #{a}")
        return if vec.nil?
        return if duplicate_in_corpus?(vec)
        return if duplicate_in_batch?(vec, survivor_vectors)

        survivors << { question: q, answer: a }
        survivor_vectors << vec
      end

      # Compare against the assistant's entire response corpus (approved +
      # pending). The deepdive deliberately uses the full corpus — matching
      # a pending entry still counts as a duplicate so the queue doesn't
      # fill with identical drafts of the same question.
      def duplicate_in_corpus?(vec)
        nearest = ::Pilot::AssistantResponse
                  .by_assistant(assistant.id)
                  .nearest_neighbors(:embedding, vec, distance: 'cosine')
                  .limit(1)
                  .first
        return false if nearest.blank?
        return false unless nearest.respond_to?(:neighbor_distance) && nearest.neighbor_distance.present?

        if nearest.neighbor_distance < THRESHOLD
          Rails.logger.debug do
            "[pilot.faq_mining_deduper] drop candidate, near neighbor id=#{nearest.id} dist=#{nearest.neighbor_distance.round(4)}"
          end
          return true
        end
        false
      end

      # In-batch dedup: two LLM-emitted pairs in the same call that are
      # near-duplicates of each other should only persist once.
      def duplicate_in_batch?(vec, survivor_vectors)
        survivor_vectors.any? { |existing| cosine_distance(vec, existing) < THRESHOLD }
      end

      def safely_embed(embedder, text)
        embedder.embed(text)
      rescue StandardError => e
        Rails.logger.error("[pilot.faq_mining_deduper] embed error: #{e.class}: #{e.message}")
        nil
      end

      def cosine_distance(vec_a, vec_b)
        dot = 0.0
        norm_a = 0.0
        norm_b = 0.0
        vec_a.each_with_index do |val, i|
          bval = vec_b[i] || 0.0
          dot += val * bval
          norm_a += val * val
          norm_b += bval * bval
        end
        return 1.0 if norm_a.zero? || norm_b.zero?

        1.0 - (dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b)))
      end
    end
  end
end
