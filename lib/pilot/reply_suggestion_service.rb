class Pilot::ReplySuggestionService < Pilot::BaseTaskService
  pattr_initialize [:account!, :conversation_display_id!, :user!, :previous_output, :refinement_instruction]

  def perform
    tools = []
    if doc_search_available?
      raw_tool = ::Custom::Pilot::Tools::SearchDocumentation.new
      tools << ::Pilot::RubyLlmToolAdapter.new(raw_tool, account: account)
    end

    make_api_call(
      model: GPT_MODEL,
      messages: build_messages,
      tools: tools
    )
  end

  private

  def doc_search_available?
    !!(defined?(::Custom::Pilot::Tools::SearchDocumentation) && ::Custom::Pilot::Tools::SearchDocumentation.available?)
  end

  # When the agent asks for a refinement ("make it shorter", "add the
  # refund link"), append the previous draft as an assistant turn and
  # the agent's instruction as the next user turn. The LLM treats the
  # whole array as a conversation and refines accordingly. Empty
  # refinement params fall through to the original single-shot flow.
  def build_messages
    messages = [
      { role: 'system', content: system_prompt },
      { role: 'user', content: formatted_conversation }
    ]
    if previous_output.present? && refinement_instruction.present?
      messages << { role: 'assistant', content: previous_output }
      messages << { role: 'user', content: refinement_instruction }
    end
    messages
  end

  def system_prompt
    template = prompt_from_file('reply')
    render_liquid_template(template, prompt_variables)
  end

  def prompt_variables
    {
      'channel_type' => conversation.inbox.channel_type,
      'agent_name' => user.name,
      'agent_signature' => user.message_signature.presence,
      'has_search_tool' => doc_search_available?
    }
  end

  def render_liquid_template(template_content, variables = {})
    Liquid::Template.parse(template_content).render(variables)
  end

  def formatted_conversation
    LlmFormatter::ConversationLlmFormatter.new(conversation).format(token_limit: TOKEN_LIMIT)
  end

  def event_name
    'reply_suggestion'
  end
end

Pilot::ReplySuggestionService.prepend_mod_with('Pilot::ReplySuggestionService')
