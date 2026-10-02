# frozen_string_literal: true

# Generates a short list of natural-language observations over the assistant's
# structured overview report (period descriptor, overview metrics, resolution
# flow, resolution trend) with an LLM task service. The model output is
# constrained by a structured-output schema to at most three short strings,
# and each returned point is stripped and blank-filtered. When the report
# shows no activity in either window, the generator returns an empty point
# list without calling the model. Results are cached by the controller.
class Pilot::Analytics::OverviewSummaryGenerator < Pilot::BaseTaskService
  MAX_POINTS = 3
  PROMPT_PATH = Rails.root.join('lib/pilot/prompts/assistant_overview_summary.liquid').freeze

  pattr_initialize [:account!, :assistant!, :window!]

  def perform
    payload = structured_report
    return { points: [] } unless activity?(payload)

    response = make_api_call(model: GPT_MODEL, messages: build_messages(payload), schema: output_schema)
    return response if response[:error]

    { points: extract_points(response[:message]) }
  end

  private

  def structured_report
    @structured_report ||= {
      period: window.period,
      overview: Pilot::Analytics::OverviewReport.new(assistant: assistant, window: window).report[:metrics],
      resolution_flow: Pilot::Analytics::ResolutionFlowReport.new(assistant: assistant, window: window).report,
      resolution_trend: Pilot::Analytics::ResolutionTrendReport.new(assistant: assistant, window: window).report
    }
  end

  # No LLM call when the assistant handled no conversations in either window.
  def activity?(payload)
    overview = payload[:overview] || {}
    involved = overview[:conversations_involved] || {}
    involved[:current].to_i.positive? || involved[:previous].to_i.positive?
  end

  def build_messages(payload)
    [
      { role: 'system', content: system_prompt(payload) },
      { role: 'user', content: user_prompt }
    ]
  end

  def system_prompt(payload)
    Liquid::Template.parse(PROMPT_PATH.read).render(
      'assistant_name' => assistant.name.to_s,
      'language' => account.locale_english_name,
      'period_label' => payload[:period][:label],
      'period_start' => payload[:period][:start_date],
      'period_end' => payload[:period][:end_date],
      'report_json' => JSON.pretty_generate(payload)
    )
  end

  # The RubyLLM request requires at least one non-system message; the report
  # itself is carried by the system prompt, so this is only the ask.
  def user_prompt
    'List the most decision-useful observations from this report.'
  end

  def output_schema
    {
      type: 'object',
      properties: {
        points: {
          type: 'array',
          items: { type: 'string' },
          maxItems: MAX_POINTS
        }
      },
      required: ['points'],
      additionalProperties: false
    }
  end

  def extract_points(message)
    parsed = message.is_a?(Hash) ? message : parse_json(message)
    return [] if parsed.blank?

    Array(parsed['points']).filter_map { |point| point.to_s.strip.presence }.first(MAX_POINTS)
  end

  def parse_json(content)
    raw = content.to_s.strip
    JSON.parse(raw.match(/```json\s*(.*?)\s*```/m)&.captures&.first || raw)
  rescue JSON::ParserError
    nil
  end

  def event_name
    'assistant_overview_summary'
  end
end
