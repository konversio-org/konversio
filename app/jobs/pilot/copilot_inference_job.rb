module Pilot
  # Generates and persists the assistant reply for a Copilot thread.
  #
  # Enqueued by `Api::V2::Accounts::Pilot::CopilotMessagesController#create`
  # right after the user message is persisted. Live token streaming is
  # explicitly deferred — clients refresh / receive the broadcast event
  # when the assistant message is committed.
  class CopilotInferenceJob < ApplicationJob
    queue_as :default

    def perform(thread_id:, conversation_id: nil)
      thread = Captain::CopilotThread.find_by(id: thread_id)
      return if thread.blank?

      reply = Custom::Pilot::CopilotService.new(
        thread: thread,
        conversation_id: conversation_id,
        account: thread.account
      ).perform

      persist_assistant_message(thread, reply)
    rescue Custom::Pilot::CopilotService::FeatureDisabledError => e
      Rails.logger.warn("[pilot.copilot_inference_job] feature disabled for thread=#{thread_id}: #{e.message}")
    rescue Custom::Pilot::CopilotService::Error => e
      Rails.logger.error("[pilot.copilot_inference_job] LLM failure for thread=#{thread_id}: #{e.message}")
    end

    private

    def persist_assistant_message(thread, content)
      return if content.blank?

      Captain::CopilotMessage.create!(
        copilot_thread: thread,
        account: thread.account,
        message_type: :assistant,
        message: { content: content }
      )
    end
  end
end
