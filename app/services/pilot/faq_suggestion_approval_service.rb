# Converts an open FAQ suggestion into an approved knowledge entry.
#
# Runs under a row lock so the open → approved transition is exactly-once:
# refuses non-open suggestions by raising ActiveRecord::RecordNotFound
# (safe for idempotent retries), applies any final reviewer edits, creates
# the approved `Pilot::AssistantResponse` from the final question/answer,
# and marks the suggestion approved in the same transaction.
class Pilot::FaqSuggestionApprovalService
  def initialize(suggestion:, question: nil, answer: nil)
    @suggestion = suggestion
    @question = question
    @answer = answer
  end

  def perform
    response = nil
    @suggestion.with_lock do
      raise ActiveRecord::RecordNotFound, 'FAQ suggestion is not open' unless @suggestion.open?

      apply_edits
      response = create_knowledge_entry
      @suggestion.update!(status: :approved)
    end
    response
  end

  private

  def apply_edits
    @suggestion.question = @question if @question.present?
    @suggestion.answer = @answer if @answer.present?
    @suggestion.save! if @suggestion.changed?
  end

  def create_knowledge_entry
    ::Pilot::AssistantResponse.create!(
      assistant: @suggestion.assistant,
      account: @suggestion.account,
      question: @suggestion.question,
      answer: @suggestion.answer,
      status: :approved
    )
  end
end
