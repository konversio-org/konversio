# frozen_string_literal: true

module Pilot
  module Conversations
    # Resolve-time Q&A mining for a single conversation. Pulled directly
    # from the deepdive's section 2 behavioural spec:
    #
    #   * filter out bot/assistant turns — only customer + human-agent
    #     messages feed the prompt
    #   * short-circuit before the LLM call when no human reply exists
    #   * dedup against the assistant's ENTIRE response corpus
    #     (approved + pending) via cosine similarity, threshold
    #     `1 - 0.7 = 0.3` cosine distance
    #   * survivors persisted as `Pilot::AssistantResponse` with
    #     `status = pending` and `documentable = nil` (conversation-mined)
    #   * idempotency by SHA-256 over the transcript text
    #   * malformed output / LLM exceptions → zero rows, no raise
    class FaqMiningJob < ApplicationJob
      queue_as :low

      FAQ_DEDUP_DISTANCE_THRESHOLD = 0.3
      TRANSCRIPT_DIGEST_KEY = 'pilot_faq_transcript_digest'

      def perform(conversation_id)
        conversation = ::Conversation.find_by(id: conversation_id)
        return if conversation.blank?

        assistant = resolve_assistant(conversation)
        return if assistant.blank?

        # Per the deepdive's 2.6 "no human reply" rule: bot-only
        # conversations would just recycle bot output back into the FAQ
        # store, so skip them before the LLM call.
        return if conversation.first_reply_created_at.blank?

        transcript = build_transcript(conversation)
        return if transcript.blank?

        digest = ::Digest::SHA256.hexdigest(transcript)
        return if already_mined?(conversation, digest)

        pairs = extract_pairs(assistant, conversation, transcript)
        persist_survivors(assistant, conversation, pairs)
        record_digest(conversation, digest)
      rescue StandardError => e
        # The deepdive's cross-cutting "listener decoupling" rule: mining
        # failures MUST NOT bubble into the resolution path. Log + swallow.
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

      # Human-agent and customer turns only. The reference product
      # filters bot output by sender_type / source_id — we follow the
      # same shape by excluding messages whose `sender_type` is the
      # Pilot assistant or whose `message_type` is `activity`/`template`.
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

      def persist_survivors(assistant, conversation, pairs)
        return if pairs.blank?

        deduper = ::Custom::Pilot::FaqMiningDeduper.new(assistant: assistant, account: assistant.account)
        survivors = deduper.filter(pairs)
        return if survivors.empty?

        survivors.each do |pair|
          create_response(assistant, conversation, pair)
        end
      end

      def create_response(assistant, _conversation, pair)
        ::Pilot::AssistantResponse.create!(
          assistant: assistant,
          account: assistant.account,
          question: pair[:question].to_s,
          answer: pair[:answer].to_s,
          status: :pending
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[pilot.faq_mining] invalid candidate: #{e.message}")
      end
    end
  end
end
