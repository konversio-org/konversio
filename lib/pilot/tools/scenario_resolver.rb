# frozen_string_literal: true

# Resolves a `Pilot::Scenario`'s persisted `tools` JSONB column (an array of
# `Pilot::CustomTool` slugs) into ready-to-register `AgentToolAdapter`
# instances scoped to the scenario's account.
#
# Unresolved slugs do NOT raise — they emit a `pilot.scenario.tool_unresolved`
# telemetry event and are silently dropped. This keeps a scenario whose
# instruction references a since-disabled tool runnable instead of failing
# the inference entirely.
class Pilot::Tools::ScenarioResolver
  UNRESOLVED_EVENT = 'pilot.scenario.tool_unresolved'

  def self.call(scenario, account:, assistant: nil)
    new(scenario, account: account, assistant: assistant).call
  end

  def initialize(scenario, account:, assistant: nil)
    @scenario = scenario
    @account = account
    @assistant = assistant
  end

  def call
    slugs = Array(@scenario.tools).map(&:to_s).reject(&:blank?)
    return [] if slugs.empty? || @account.blank?

    available = available_tools.where(slug: slugs).index_by(&:slug)
    slugs.filter_map do |slug|
      tool = available[slug]
      if tool
        Pilot::Tools::AgentToolAdapter.new(tool)
      else
        dispatch_unresolved(slug)
        nil
      end
    end
  end

  private

  def available_tools
    return @assistant.enabled_custom_tools if @assistant.present?

    @account.pilot_custom_tools.enabled
  end

  def dispatch_unresolved(slug)
    ::Custom::Pilot::EventDispatcher.dispatch(
      UNRESOLVED_EVENT,
      {
        account_id: @account&.id,
        assistant_id: @assistant&.id,
        scenario_id: @scenario.id,
        tool_slug: slug
      },
      account: @account
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.tools.scenario_resolver] dispatch failed: #{e.class}: #{e.message}")
  end
end
