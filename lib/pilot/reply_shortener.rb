# Single-pass, deterministic shortener for over-budget Pilot replies.
#
# Runs one single-turn agent run at temperature 0 with an instruction to make
# each part's text shorter while preserving part count, part order, factual
# content, markdown validity, and citation assignment. The result is verified
# programmatically: a changed part count or changed per-part citation indexes
# raises, and the original per-part citations are re-attached regardless of
# what the shortening run returned. The shortened output replaces the final
# assistant output on the run result so the recorded transcript matches what
# is delivered.
class Pilot::ReplyShortener
  class Error < StandardError; end

  SHORTENER_AGENT_NAME = 'reply_shortener'.freeze

  INSTRUCTIONS = <<~PROMPT.freeze
    You shorten an assistant reply so it fits a strict character budget.

    You receive a JSON object with a character budget and an ordered list of reply parts. Return ONLY a JSON object in this exact shape:
      {"parts":[{"text":"<shortened text>","source_indexes":[1,2]}]}

    Rules:
    - Return exactly the same number of parts, in the same order.
    - Only make each part's text shorter. Never add facts, names, numbers, dates, links, or warnings that were not already present, and never drop a completed action the reply reported.
    - Keep every part's source_indexes exactly as given.
    - Keep the markdown valid: no unclosed emphasis, lists, links, or code blocks.
    - The part texts joined with a single blank line must fit the character budget.
    - Output the JSON and nothing else.
  PROMPT

  def self.call(**)
    new(**).call
  end

  def initialize(run_result:, structured_reply:, text_budget:, model:, citations_enabled: false)
    @run_result = run_result
    @structured_reply = structured_reply
    @text_budget = text_budget
    @model = model
    @citations_enabled = citations_enabled
  end

  # Returns the shortened reply as a `Pilot::StructuredReply` carrying the
  # ORIGINAL per-part citations.
  def call
    shortened = run_shortening_pass
    verify_preservation!(shortened)
    final = reattach_citations(shortened)
    replace_run_output(final)
    final
  end

  private

  attr_reader :run_result, :structured_reply, :text_budget, :model

  def citations_enabled?
    @citations_enabled == true
  end

  def run_shortening_pass
    agent = ::Agents::Agent.new(
      name: SHORTENER_AGENT_NAME,
      instructions: INSTRUCTIONS,
      model: model,
      temperature: 0,
      tools: []
    )
    result = ::Agents::Runner.with_agents(agent).run(shortening_input, max_turns: 1)
    raise Error, result.error&.message.presence || 'shortening run failed' if result.failed?

    parsed = ::Pilot::StructuredReply.parse(result.output)
    raise Error, 'shortening run returned no usable parts' if parsed.empty?

    parsed
  end

  def shortening_input
    {
      character_budget: text_budget,
      parts: structured_reply.parts.map { |part| { text: part.text, source_indexes: part.citations } }
    }.to_json
  end

  def verify_preservation!(shortened)
    if shortened.parts.size != structured_reply.parts.size
      raise Error, "shortening changed the part count (#{structured_reply.parts.size} -> #{shortened.parts.size})"
    end
    return unless citations_enabled?

    structured_reply.parts.zip(shortened.parts).each_with_index do |(original, shortened_part), index|
      next if original.citations == shortened_part.citations

      raise Error, "shortening changed the citation indexes of part #{index + 1}"
    end
  end

  def reattach_citations(shortened)
    ::Pilot::StructuredReply.new(
      structured_reply.parts.zip(shortened.parts).map do |original, shortened_part|
        { text: shortened_part.text, citations: original.citations }
      end
    )
  end

  # The run's final output and its last assistant transcript entry now carry
  # the shortened form, so session recording and any downstream reader see
  # what was actually delivered.
  def replace_run_output(final)
    serialized = { 'parts' => final.as_message_parts.map { |part| { 'text' => part['text'], 'source_indexes' => part['citations'] } } }.to_json
    run_result.output = serialized if run_result.respond_to?(:output=)

    messages = run_result.respond_to?(:messages) ? Array(run_result.messages) : []
    last_assistant = messages.reverse.find { |message| message_role(message) == 'assistant' }
    last_assistant[:content] = serialized if last_assistant.is_a?(Hash)
  end

  def message_role(message)
    return message[:role].to_s if message.is_a?(Hash)
    return message.role.to_s if message.respond_to?(:role)

    nil
  end
end
