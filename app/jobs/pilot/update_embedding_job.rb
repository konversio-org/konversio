module Pilot
  # Refreshes the pgvector embedding on a `Pilot::AssistantResponse` after
  # its question/answer text changes. Uses the `low` Sidekiq queue per
  # design D17 — embeddings refresh is non-blocking and can backlog without
  # impacting customer-facing inference.
  class UpdateEmbeddingJob < ApplicationJob
    queue_as :low

    def perform(assistant_response_id)
      response = ::Pilot::AssistantResponse.find_by(id: assistant_response_id)
      return if response.blank?

      content = "#{response.question}\n\n#{response.answer}"
      embedding = ::Custom::Pilot::EmbeddingService.new(account: response.account).embed(content)
      return if embedding.blank?

      response.update_column(:embedding, embedding)
    end
  end
end
