module Pilot
  # Refreshes the pgvector embedding on a `Pilot::FaqSuggestion` after its
  # question/answer text changes while open. Mirrors UpdateEmbeddingJob's
  # shape (low queue, non-blocking) but embeds the suggestion's
  # `"<question>: <answer>"` matching text.
  class UpdateFaqSuggestionEmbeddingJob < ApplicationJob
    queue_as :low

    def perform(faq_suggestion_id)
      suggestion = ::Pilot::FaqSuggestion.find_by(id: faq_suggestion_id)
      return if suggestion.blank?

      embedding = ::Custom::Pilot::EmbeddingService.new(account: suggestion.account).embed(suggestion.embeddable_text)
      return if embedding.blank?

      suggestion.update_column(:embedding, embedding)
    end
  end
end
