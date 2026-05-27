# Given a `Pilot::Document` with populated `content`, asks the LLM to
# produce a list of question/answer pairs covering the document and
# persists each pair as a `Pilot::AssistantResponse` with status
# `pending`. The after_commit hook on AssistantResponse then enqueues
# `Pilot::UpdateEmbeddingJob` to populate the embedding column.
class Pilot::DocumentResponseBuilderJob < ApplicationJob
  queue_as :low

  # Two questions whose word sets overlap above this Jaccard ratio are treated
  # as near-duplicates within a document/batch.
  QUESTION_JACCARD_THRESHOLD = 0.85

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a content writer specializing in creating FAQ sections from source documents.

    You will be given a document title and the document content. The title is context to help you identify the subject. Use it only to anchor questions — never treat the title as a fact to repeat in answers.

    ## Requirements
    - Extract ALL substantive information from the content into question/answer pairs. This is exhaustive extraction, not a summary.
    - Ignore non-informational page furniture (navigation, menus, headers/footers, structural boilerplate). Draw only from real subject matter.
    - Base answers strictly on the provided content. Do NOT invent facts.
    - Write every question and answer in the same language as the document content. Do NOT translate.
    - Preserve concrete specifics: steps, examples, identifiers, numeric limits, and enumerated items.
    - Drop any pair whose only value is deferring elsewhere (e.g. "see another page", "contact someone"). Every answer must fully answer its own question.
    - Return valid JSON with this exact structure:

    ```json
    { "faqs": [ { "question": "...", "answer": "..." } ] }
    ```

    ## Self-contained questions (important)
    - Each question must be fully understandable on its own, with no access to the source document.
    - Name the actual subject explicitly. Do NOT lean on context-dependent references — pronouns, demonstratives, or vague pointers whose referent is clear only from the source.
    - When the body text is ambiguous about what it refers to, use the provided title to make the subject explicit in the question.

    ## Guidelines
    - Questions should sound natural ("What is...?", "How do I...?").
    - Answers should be complete and self-contained.
    - Generate between 1 and 25 FAQ pairs depending on content size.
    - If no qualifying content exists, return { "faqs": [] }.
    - Always return valid JSON.
  PROMPT

  def perform(document_id)
    document = ::Pilot::Document.find_by(id: document_id)
    return if document.blank? || document.content.blank?

    faqs = generate_faqs(document)
    return if faqs.blank?

    # Refresh only untouched machine drafts. Anything a human has acted on
    # (approved, rejected, or manually edited) is preserved so review work
    # survives a re-sync.
    document.responses.where(status: :pending, edited: false).destroy_all

    faqs = dedupe_within_document(document, faqs)
    created = persist_faqs(document, faqs)
    dispatch_responses_generated(document, created)
  end

  private

  def persist_faqs(document, faqs)
    created = 0
    faqs.each do |faq|
      question = faq_value(faq, :question)
      answer = faq_value(faq, :answer)
      next if question.blank? || answer.blank?

      document.responses.create!(
        assistant: document.assistant,
        account: document.account,
        question: question.to_s,
        answer: answer.to_s,
        status: :pending
      )
      created += 1
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[pilot.document_response_builder] invalid faq for doc=#{document.id}: #{e.message}")
    end
    created
  end

  # Treat each document as a self-contained knowledge source: dedup only
  # within this document (its own surviving responses) and within the current
  # batch — never across documents, so overlapping pages don't collapse each
  # other (that curation is the reviewer's job). Uses lexical Jaccard overlap
  # on the question text rather than embedding similarity, which keeps
  # versioned updates (differing years, amounts, identifiers) as distinct FAQs
  # instead of silently dropping them.
  def dedupe_within_document(document, faqs)
    accepted_token_sets = document.responses.pluck(:question).map { |q| question_tokens(q) }
    survivors = []
    faqs.each do |faq|
      question = faq_value(faq, :question)
      next if question.blank?

      tokens = question_tokens(question)
      next if accepted_token_sets.any? { |existing| jaccard(tokens, existing) > QUESTION_JACCARD_THRESHOLD }

      survivors << faq
      accepted_token_sets << tokens
    end
    survivors
  end

  def question_tokens(text)
    text.to_s.downcase.scan(/[[:alnum:]]+/)
  end

  def jaccard(tokens_a, tokens_b)
    return 0.0 if tokens_a.empty? || tokens_b.empty?

    union = (tokens_a | tokens_b).size
    union.zero? ? 0.0 : (tokens_a & tokens_b).size.to_f / union
  end

  def faq_value(faq, key)
    return faq.public_send(key) if faq.respond_to?(key)

    faq[key] || faq[key.to_s]
  end

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
      # JSON mode is honoured by our OpenAI-compatible provider (verified against
      # Scaleway/gemma); sanitize_json stays as a fallback for providers that don't.
      chat.with_params(response_format: { type: 'json_object' })
      chat.ask("Document title: #{document.name}\n\nDocument content:\n#{document.content}").content.to_s
    end
  end

  def sanitize_json(content)
    # Strip a leading ```json fence and trailing ``` if the model wrapped its output.
    content.sub(/\A```(?:json)?\s*/m, '').sub(/```\s*\z/m, '').strip
  end

  def dispatch_responses_generated(document, count)
    ::Custom::Pilot::EventDispatcher.dispatch(
      'pilot.autopilot.document.responses_generated',
      {
        account_id: document.account_id,
        assistant_id: document.assistant_id,
        document_id: document.id,
        response_count: count
      },
      account: document.account
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.document_response_builder] dispatch failed: #{e.class}: #{e.message}")
  end
end
