module Pilot
  # Given a `Pilot::Document` with populated `content`, asks the LLM to
  # produce a list of question/answer pairs covering the document and
  # persists each pair as a `Pilot::AssistantResponse` with status
  # `pending`. The after_commit hook on AssistantResponse then enqueues
  # `Pilot::UpdateEmbeddingJob` to populate the embedding column.
  class DocumentResponseBuilderJob < ApplicationJob
    queue_as :low

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a content writer specializing in creating FAQ sections from source documents.

      ## Requirements
      - Extract ALL information from the source content into question/answer pairs.
      - Base answers strictly on the provided text. Do NOT invent facts.
      - Return valid JSON with this exact structure:

      ```json
      { "faqs": [ { "question": "...", "answer": "..." } ] }
      ```

      ## Guidelines
      - Questions should sound natural ("What is...?", "How do I...?").
      - Answers should be complete and self-contained.
      - Generate between 1 and 25 FAQ pairs depending on content size.
      - Always return valid JSON.
    PROMPT

    def perform(document_id)
      document = ::Pilot::Document.find_by(id: document_id)
      return if document.blank? || document.content.blank?

      faqs = generate_faqs(document)
      return if faqs.blank?

      # Replace any previously-derived responses to keep the knowledge base
      # in sync with the latest document content.
      document.responses.destroy_all

      faqs.each do |faq|
        next if faq['question'].blank? || faq['answer'].blank?

        document.responses.create!(
          assistant: document.assistant,
          account: document.account,
          question: faq['question'].to_s,
          answer: faq['answer'].to_s,
          status: :pending
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[pilot.document_response_builder] invalid faq for doc=#{document.id}: #{e.message}")
      end
    end

    private

    def generate_faqs(document)
      content = call_llm(document)
      return [] if content.blank?

      parsed = JSON.parse(sanitize_json(content))
      Array(parsed['faqs'] || parsed[:faqs] || [])
    rescue JSON::ParserError => e
      Rails.logger.error("[pilot.document_response_builder] JSON parse error for doc=#{document.id}: #{e.message}")
      []
    end

    def call_llm(document)
      api_key = ::Llm::Config.api_key
      return nil if api_key.blank?

      ::Llm::Config.with_api_key(api_key, api_base: ::Llm::Config.api_base) do |context|
        chat_options = { model: ::Llm::Config.model_for(:autopilot) }
        if ::Llm::Config.openai_compatible?
          chat_options[:provider] = :openai
          chat_options[:assume_model_exists] = true
        end
        chat = context.chat(**chat_options)
        chat.with_instructions(SYSTEM_PROMPT)
        chat.ask(document.content.to_s).content.to_s
      end
    end

    def sanitize_json(content)
      # Strip a leading ```json fence and trailing ``` if the model wrapped its output.
      content.sub(/\A```(?:json)?\s*/m, '').sub(/```\s*\z/m, '').strip
    end
  end
end
