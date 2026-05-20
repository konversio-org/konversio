class Pilot::SummaryService < Pilot::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!, :previous_output, :refinement_instruction]

  def perform
    make_api_call(
      model: GPT_MODEL,
      messages: build_messages
    )
  end

  private

  # See Pilot::ReplySuggestionService#build_messages — same refinement
  # pattern: when previous_output + refinement_instruction are supplied,
  # treat them as a continuation of the conversation so the LLM refines
  # the prior summary instead of starting over.
  def build_messages
    messages = [
      { role: 'system', content: system_prompt },
      { role: 'user', content: conversation.to_llm_text(include_contact_details: false) }
    ]
    if previous_output.present? && refinement_instruction.present?
      messages << { role: 'assistant', content: previous_output }
      messages << { role: 'user', content: refinement_instruction }
    end
    messages
  end

  def system_prompt
    <<~PROMPT
      #{prompt_from_file('summary')}

      Reply in #{account.locale_english_name}.
    PROMPT
  end

  def event_name
    'summarize'
  end
end
