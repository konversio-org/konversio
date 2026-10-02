# Records a `Pilot::AgentSession` for a completed Pilot AI run.
#
# Invoked after a successful run has delivered its customer-facing reply (or
# handoff note). Capture is deliberately failure-isolated: it runs outside the
# delivery transaction and swallows every error (log + exception tracker) so a
# recording bug can never affect the message the customer already received.
#
# Only successful runs are recorded; failed runs have no session semantics yet.
class Pilot::AgentSessionRecorder
  def self.call(**)
    new(**).call
  end

  # rubocop:disable Metrics/ParameterLists
  def initialize(assistant:, subject:, result_message:, run_result: nil, llm_model: nil, handoff_note: nil)
    @assistant = assistant
    @subject = subject
    @result_message = result_message
    @run_result = run_result
    @llm_model = llm_model
    @handoff_note = handoff_note
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return if assistant.blank? || subject.blank? || result_message.blank?
    return unless successful_run?

    ::Pilot::AgentSession.create!(session_attributes)
  rescue StandardError => e
    handle_failure(e)
    nil
  end

  private

  attr_reader :assistant, :subject, :result_message, :run_result, :llm_model, :handoff_note

  def session_attributes
    {
      assistant: assistant,
      account: assistant.account,
      session_kind: session_kind,
      subject: subject,
      result: handoff_note.presence || result_message,
      llm_model: llm_model,
      offered_faq_ids: source_info[:offered_faq_ids],
      used_faq_ids: used_faq_ids,
      consulted_document_ids: source_info[:consulted_document_ids],
      cited_document_ids: cited_document_ids,
      scenario_ids: scenario_ids,
      run_context: { 'entries' => turn_entries }
    }
  end

  def successful_run?
    return false if run_result.blank?
    return run_result.success? if run_result.respond_to?(:success?)
    return !run_result.failed? if run_result.respond_to?(:failed?)

    false
  end

  def session_kind
    subject.is_a?(::Pilot::CopilotThread) ? :copilot : :autopilot
  end

  # The knowledge sources the run offered the model, keyed by source index.
  def sources_by_index
    @sources_by_index ||= assistant.citation_sources(run_result).each_with_object({}) do |source, acc|
      index = fetch(source, :index)
      next if index.blank?

      acc[index.to_i] = source
    end
  end

  def source_info
    @source_info ||= begin
      sources = sources_by_index.values
      {
        offered_faq_ids: sources.filter_map { |s| fetch(s, :faq_id) }.uniq,
        consulted_document_ids: sources.filter_map { |s| fetch(s, :document_id) }.uniq
      }
    end
  end

  # Indexes actually referenced by the delivered parts (read from the message's
  # additional attributes so we record what the customer received).
  def used_indexes
    @used_indexes ||= delivered_parts.flat_map { |part| Array(fetch(part, :citations)) }.map(&:to_i).uniq
  end

  def delivered_parts
    attributes = result_message.try(:additional_attributes) || {}
    Array(fetch(attributes, :pilot_response_parts))
  end

  def eligible_url_indexes
    mapping = sources_by_index.transform_values { |source| fetch(source, :document_id) }.compact
    assistant.trusted_citation_urls(mapping).keys
  end

  def used_faq_ids
    used_indexes.filter_map { |index| fetch(sources_by_index[index], :faq_id) }.uniq
  end

  def cited_document_ids
    (used_indexes & eligible_url_indexes).filter_map { |index| fetch(sources_by_index[index], :document_id) }.uniq
  end

  # Scenarios that acted during the turn, derived from assistant-role entries in
  # the run transcript and constrained to this assistant's own scenarios.
  def scenario_ids
    @scenario_ids ||= begin
      acted_names = turn_entries.select { |entry| entry['role'] == 'assistant' }.filter_map { |entry| entry['agent_name'] }
      assistant.scenarios.select { |scenario| acted_names.include?(scenario.handoff_key) }.map(&:id).uniq
    end
  end

  # Turn-scoped transcript: the latest customer message and everything after it.
  # Rich content objects are normalised to plain serializable values.
  def turn_entries
    messages = Array(run_result.respond_to?(:messages) ? run_result.messages : nil)
    messages = Array(run_result.context[:conversation_history]) if messages.empty? && run_result.respond_to?(:context)

    last_user = messages.rindex { |message| fetch(message, :role).to_s == 'user' }
    turn = last_user.nil? ? messages : messages[last_user..]
    turn.map { |message| normalize_entry(message) }
  end

  def normalize_entry(message)
    {
      'role' => fetch(message, :role).to_s,
      'content' => normalize_content(fetch(message, :content)),
      'agent_name' => fetch(message, :agent_name),
      'tool_calls' => normalize_value(fetch(message, :tool_calls)),
      'tool_call_id' => fetch(message, :tool_call_id)
    }.compact
  end

  def normalize_content(content)
    normalize_value(content)
  end

  def normalize_value(value)
    case value
    when nil then nil
    when String, Integer, Float, TrueClass, FalseClass then value
    when Array, Hash then JSON.parse(value.to_json)
    else value.to_s
    end
  rescue StandardError
    value.to_s
  end

  def fetch(collection, key)
    return nil if collection.blank?
    return collection[key] if collection.respond_to?(:key?) && collection.key?(key)
    return collection[key.to_s] if collection.respond_to?(:key?) && collection.key?(key.to_s)

    nil
  end

  def handle_failure(error)
    Rails.logger.error("[pilot.agent_session_recorder] capture failed: #{error.class}: #{error.message}")
    if defined?(::KonversioExceptionTracker)
      ::KonversioExceptionTracker.new(error).capture_exception
    elsif Rails.respond_to?(:error) && Rails.error.respond_to?(:report)
      Rails.error.report(error, context: { source: 'pilot.agent_session_recorder' })
    end
  end
end
