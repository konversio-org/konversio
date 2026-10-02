module Pilot
  # Generates the suggested reply for a reply-suggestion copilot thread.
  #
  # Enqueued by `Api::V2::Accounts::Pilot::CopilotThreadsController#create`
  # when the request type selects reply-suggestion mode. Delegates generation
  # and persistence to `Custom::Pilot::CopilotReplySuggestionService`, retrying
  # recoverable generation errors with backoff. Once retries are exhausted it
  # persists the localized failure response so the drawer settles.
  class CopilotReplySuggestionJob < ApplicationJob
    queue_as :default

    retry_on Custom::Pilot::CopilotReplySuggestionService::Error,
             wait: 3.seconds, attempts: 3 do |job, _error|
      job.persist_failure_response
    end

    def perform(thread_id:, conversation_id: nil)
      thread = Pilot::CopilotThread.find_by(id: thread_id)
      return if thread.blank?

      Custom::Pilot::CopilotReplySuggestionService.new(
        thread: thread,
        conversation_id: conversation_id,
        account: thread.account
      ).perform
    end

    # Invoked by the retry policy's exhaustion block.
    def persist_failure_response
      kwargs = arguments.last.is_a?(Hash) ? arguments.last : {}
      thread = Pilot::CopilotThread.find_by(id: kwargs[:thread_id] || kwargs['thread_id'])
      return if thread.blank?

      Custom::Pilot::CopilotReplySuggestionService.new(
        thread: thread,
        conversation_id: kwargs[:conversation_id] || kwargs['conversation_id'],
        account: thread.account
      ).persist_failure_response
    end
  end
end
