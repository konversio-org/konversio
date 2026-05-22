# frozen_string_literal: true

# Bridges standard `Agents::Tool` instances to the `RubyLLM::Tool` runtime.
#
# Since `Agents::Tool` subclasses expect an `Agents::ToolContext` and implement
# `perform(tool_context, **params)` / `execute(tool_context, **params)`, they cannot
# be called directly by RubyLLM's tool calling mechanism (which invokes
# `tool.execute(**params)`).
#
# This adapter maps RubyLLM parameter calls to the target tool's perform method
# by constructing the necessary context on the fly.
class Pilot::RubyLlmToolAdapter < RubyLLM::Tool
  def initialize(agents_tool, account:, context: {})
    super()
    @agents_tool = agents_tool
    @account = account
    @context = context
  end

  def name
    @agents_tool.name
  end

  def description
    @agents_tool.description
  end

  def parameters
    @agents_tool.parameters
  end

  def provider_params
    if @agents_tool.respond_to?(:provider_params)
      @agents_tool.provider_params
    elsif @agents_tool.class.respond_to?(:provider_params)
      @agents_tool.class.provider_params
    else
      super
    end
  end

  def execute(**params)
    run_ctx = Agents::RunContext.new({ account_id: @account.id }.merge(@context))
    tool_context = Agents::ToolContext.new(run_context: run_ctx)
    @agents_tool.perform(tool_context, **params)
  end
end
