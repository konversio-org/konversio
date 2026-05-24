# frozen_string_literal: true

require 'agents'
require 'json'

# Bridges a `Pilot::CustomTool` row into the `ai-agents` SDK tool interface so
# the Autopilot runner can invoke account-defined HTTP tools during inference.
#
# Each adapter instance wraps a single tool row. Per-row metadata (name,
# description, parameter schema) is exposed dynamically — the SDK's underlying
# `RubyLLM::Tool` API reads `#name`, `#description`, and `#parameters` from
# the instance, so a single class can serve every row.
#
# On invocation, the adapter delegates to `Pilot::Tools::Executor.new(tool)
# .call(arguments)` and returns the executor's value verbatim. Successful
# responses are strings; structured failures are `{ error:, message: }`
# hashes which the adapter JSON-serializes so the LLM sees them as tool
# results rather than provoking an SDK type error.
class Pilot::Tools::AgentToolAdapter < Agents::Tool
  TYPE_FALLBACK = 'string'

  attr_reader :tool

  def initialize(tool)
    super()
    @tool = tool
  end

  def name
    @tool.slug.to_s
  end

  def description
    @tool.description.to_s
  end

  def parameters
    @parameters ||= build_parameters
  end

  def execute(_tool_context = nil, **params)
    result = Pilot::Tools::Executor.new(@tool).call(params)
    serialize(result)
  end

  private

  def build_parameters
    Array(@tool.param_schema).each_with_object({}) do |entry, acc|
      param = parameter_from_entry(entry)
      acc[param.name] = param if param
    end
  end

  def parameter_from_entry(entry)
    name = fetch(entry, :name).to_s
    return nil if name.blank?

    RubyLLM::Parameter.new(
      name.to_sym,
      type: fetch(entry, :type).to_s.presence || TYPE_FALLBACK,
      desc: fetch(entry, :description),
      required: fetch(entry, :required) ? true : false
    )
  end

  def fetch(entry, key)
    entry[key.to_s] || entry[key.to_sym]
  end

  def serialize(result)
    return result if result.is_a?(String)
    return result.to_json if result.is_a?(Hash)

    result.to_s
  end
end
