module Pilot
  # Suggests labels for a newly created conversation and persists the
  # candidate ids on `conversations.suggested_label_ids` for the UI to
  # surface as one-click apply chips.
  #
  # Non-destructive: the job NEVER applies labels — only suggests them.
  class LabelSuggestionJob < ApplicationJob
    queue_as :low

    def perform(conversation_id)
      conversation = Conversation.find_by(id: conversation_id)
      return if conversation.blank?

      account = conversation.account
      return unless account.feature_enabled?('pilot')
      return unless account.feature_enabled?('pilot_label_suggestion')

      label_ids = Custom::Pilot::LabelSuggestionService.new(
        conversation: conversation,
        account: account
      ).perform

      conversation.update!(suggested_label_ids: label_ids)
    rescue Custom::Pilot::LabelSuggestionService::FeatureDisabledError => e
      Rails.logger.warn("[pilot.label_suggestion_job] feature disabled for conversation=#{conversation_id}: #{e.message}")
    rescue Custom::Pilot::LabelSuggestionService::Error => e
      Rails.logger.error("[pilot.label_suggestion_job] LLM failure for conversation=#{conversation_id}: #{e.message}")
    end
  end
end
