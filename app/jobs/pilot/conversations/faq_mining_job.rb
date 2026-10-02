# frozen_string_literal: true

module Pilot
  module Conversations
    # Resolve-time Q&A mining for a single conversation.
    #
    #   * filter out bot/assistant turns — only customer + human-agent
    #     messages feed the prompt
    #   * short-circuit before the LLM call when no human reply exists
    #   * each mined candidate is routed by `Custom::Pilot::FaqSuggestionMatcher`:
    #       - matches approved knowledge        → discarded observation
    #       - matches a dismissed suggestion    → discarded observation
    #       - matches an open suggestion        → attached observation,
    #         source_count incremented under a row lock
    #       - no match                          → new open suggestion with an
    #         attached observation
    #   * idempotency by SHA-256 over the transcript text
    #   * malformed output / LLM exceptions → zero rows, no raise
    class FaqMiningJob < ApplicationJob
      queue_as :low

      FAQ_DEDUP_DISTANCE_THRESHOLD = 0.3
      TRANSCRIPT_DIGEST_KEY = 'pilot_faq_transcript_digest'
      MAX_ROUTE_ATTEMPTS = 3

      def perform(conversation_id)
        conversation = ::Conversation.find_by(id: conversation_id)
        return if conversation.blank?

        assistant = resolve_assistant(conversation)
        return if assistant.blank?

        # Bot-only conversations would just recycle bot output back into
        # the FAQ store, so skip them before the LLM call.
        return if conversation.first_reply_created_at.blank?

        transcript = build_transcript(conversation)
        return if transcript.blank?

        digest = ::Digest::SHA256.hexdigest(transcript)
        return if already_mined?(conversation, digest)

        pairs = extract_pairs(assistant, conversation, transcript)
        route_candidates(assistant, conversation, pairs)
        record_digest(conversation, digest)
      rescue StandardError => e
        # Mining failures MUST NOT bubble into the resolution path.
        # Log + swallow; the digest is only recorded on success, so a
        # later resolution re-mines the conversation.
        Rails.logger.error("[pilot.faq_mining] #{e.class}: #{e.message}")
        nil
      end

      private

      def resolve_assistant(conversation)
        inbox = conversation.inbox
        return nil if inbox.blank?

        pilot_inbox = ::Pilot::Inbox.find_by(inbox_id: inbox.id)
        pilot_inbox&.assistant
      end

      # Human-agent and customer turns only. Messages whose `sender_type`
      # is the Pilot assistant or whose `message_type` is
      # `activity`/`template` never feed candidate generation.
      def build_transcript(conversation)
        conversation.messages
                    .where(message_type: %i[incoming outgoing])
                    .where(private: false)
                    .where.not(sender_type: 'Pilot::Assistant')
                    .order(:created_at)
                    .filter_map do |msg|
                      content = msg.content.to_s.strip
                      next if content.blank?

                      role = msg.message_type == 'incoming' ? 'CUSTOMER' : 'AGENT'
                      "[#{role}] #{content}"
                    end.join("\n")
      end

      def already_mined?(conversation, digest)
        prior = (conversation.additional_attributes || {})[TRANSCRIPT_DIGEST_KEY]
        prior == digest
      end

      def record_digest(conversation, digest)
        attrs = (conversation.additional_attributes || {}).merge(TRANSCRIPT_DIGEST_KEY => digest)
        conversation.update_columns(additional_attributes: attrs)
      end

      def extract_pairs(assistant, conversation, transcript)
        ::Custom::Pilot::TraceSpan.wrap(
          name: 'pilot.faq.mine',
          attributes: span_attributes(assistant, conversation)
        ) do |_span|
          service = ::Custom::Pilot::FaqMiningService.new(
            assistant: assistant, account: assistant.account, transcript: transcript
          )
          service.call
        end
      end

      def span_attributes(assistant, conversation)
        {
          account_id: assistant&.account_id,
          assistant_id: assistant&.id,
          conversation_id: conversation&.id,
          conversation_display_id: conversation&.display_id,
          channel_type: conversation&.inbox&.channel_type,
          source: 'production',
          credit_used: true
        }
      end

      def route_candidates(assistant, conversation, pairs)
        return if pairs.blank?

        language = ::Pilot::FaqSuggestion.language_for(conversation)
        matcher = ::Custom::Pilot::FaqSuggestionMatcher.new(assistant: assistant, account: assistant.account)
        pairs.each do |pair|
          route_candidate(matcher, assistant, conversation, pair_value(pair, :question), pair_value(pair, :answer), language)
        end
      end

      def pair_value(pair, key)
        return pair.public_send(key) if pair.respond_to?(key)

        pair[key] || pair[key.to_s]
      end

      def route_candidate(matcher, assistant, conversation, question, answer, language)
        MAX_ROUTE_ATTEMPTS.times do
          result = matcher.match(question: question, answer: answer, language: language)
          case result.route
          when :duplicate
            return
          when :knowledge, :dismissed
            record_discarded_observation(conversation, question, answer, language)
            return
          when :attach
            # false means the suggestion changed or was decided between the
            # match and the attach — re-route the candidate.
            return if attach_observation(result.record, conversation, question, answer, language)
          when :create
            create_suggestion(assistant, conversation, question, answer, language)
            return
          end
        end
        Rails.logger.warn("[pilot.faq_mining] route conflict loop for conversation=#{conversation.id}, candidate dropped")
      end

      # Attaches an observation under a row lock, re-verifying that the
      # suggestion is still open and its text has not changed since the
      # match was computed. Returns false when re-verification fails so the
      # caller re-routes the candidate. Idempotent per conversation: a
      # conversation contributes at most one attached observation per
      # suggestion (also enforced by a partial unique index).
      def attach_observation(suggestion, conversation, question, answer, language)
        matched_question = suggestion.question
        matched_answer = suggestion.answer

        suggestion.with_lock do
          return false unless suggestion.open?
          return false unless suggestion.question == matched_question && suggestion.answer == matched_answer
          return true if suggestion.observations.attached.exists?(conversation_id: conversation.id)

          suggestion.observations.create!(
            conversation: conversation,
            generated_question: question,
            generated_answer: answer,
            language: language,
            status: :attached
          )
          suggestion.increment!(:source_count)
        end
        true
      rescue ActiveRecord::RecordNotUnique
        true
      end

      def create_suggestion(assistant, conversation, question, answer, language)
        suggestion = ::Pilot::FaqSuggestion.new(
          assistant: assistant, question: question, answer: answer, language: language, source_count: 1
        )
        ActiveRecord::Base.transaction do
          suggestion.save!
          suggestion.observations.create!(
            conversation: conversation,
            generated_question: question,
            generated_answer: answer,
            language: language,
            status: :attached
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[pilot.faq_mining] invalid candidate: #{e.message}")
      end

      def record_discarded_observation(conversation, question, answer, language)
        ::Pilot::FaqObservation.create!(
          conversation: conversation,
          generated_question: question,
          generated_answer: answer,
          language: language,
          status: :discarded
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[pilot.faq_mining] invalid candidate: #{e.message}")
      end
    end
  end
end
