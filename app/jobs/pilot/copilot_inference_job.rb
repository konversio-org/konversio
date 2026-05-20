module Pilot
  # Generates and persists the assistant reply for a Copilot thread.
  #
  # Enqueued by `Api::V2::Accounts::Pilot::CopilotMessagesController#create`
  # right after the user message is persisted.
  #
  # Note on persistence: `Custom::Pilot::CopilotService` runs the ai-agents
  # SDK loop and persists BOTH the intermediate `assistant_thinking`
  # messages (one per tool call) AND the final assistant message inside the
  # service. This job's responsibility is therefore narrow: invoke the
  # service, log errors, and rely on the service's own persistence + event
  # dispatch. See pilot-copilot spec "Copilot uses the ai-agents SDK runner
  # with full tool execution" + design.md D21.
  class CopilotInferenceJob < ApplicationJob
    queue_as :default

    def perform(thread_id:, conversation_id: nil)
      thread = Pilot::CopilotThread.find_by(id: thread_id)
      return if thread.blank?

      Custom::Pilot::CopilotService.new(
        thread: thread,
        conversation_id: conversation_id,
        account: thread.account
      ).perform
    rescue Custom::Pilot::CopilotService::FeatureDisabledError => e
      Rails.logger.warn("[pilot.copilot_inference_job] feature disabled for thread=#{thread_id}: #{e.message}")
    rescue Custom::Pilot::CopilotService::Error => e
      Rails.logger.error("[pilot.copilot_inference_job] LLM failure for thread=#{thread_id}: #{e.message}")
    end
  end
end
