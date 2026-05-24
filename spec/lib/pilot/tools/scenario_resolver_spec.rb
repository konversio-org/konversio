# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Tools::ScenarioResolver do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:lookup_tool) { create(:pilot_custom_tool, account: account, title: 'Lookup order') }

  def build_scenario(tools:, instruction: 'Be helpful.')
    scenario = create(:pilot_scenario, assistant: assistant, account: account, instruction: instruction)
    scenario.update_column(:tools, tools) # rubocop:disable Rails/SkipsModelValidations
    scenario.reload
  end

  it 'returns adapter instances for slugs that resolve to enabled tools' do
    scenario = build_scenario(tools: [lookup_tool.slug])
    assistant.update!(enabled_tool_slugs: [lookup_tool.slug])

    result = described_class.call(scenario, account: account, assistant: assistant)

    expect(result.size).to eq(1)
    expect(result.first).to be_a(Pilot::Tools::AgentToolAdapter)
    expect(result.first.tool).to eq(lookup_tool)
  end

  it 'skips unresolved slugs without raising and emits telemetry' do
    scenario = build_scenario(tools: [lookup_tool.slug, 'missing_slug'])
    assistant.update!(enabled_tool_slugs: [lookup_tool.slug])

    expect(Custom::Pilot::EventDispatcher).to receive(:dispatch).with(
      'pilot.scenario.tool_unresolved',
      hash_including(scenario_id: scenario.id, tool_slug: 'missing_slug', account_id: account.id),
      account: account
    )

    result = described_class.call(scenario, account: account, assistant: assistant)

    expect(result.size).to eq(1)
    expect(result.first.tool).to eq(lookup_tool)
  end

  it 'skips tools that are enabled on the account but disabled for the assistant' do
    scenario = build_scenario(tools: [lookup_tool.slug])

    expect(Custom::Pilot::EventDispatcher).to receive(:dispatch).with(
      'pilot.scenario.tool_unresolved',
      hash_including(scenario_id: scenario.id, tool_slug: lookup_tool.slug, account_id: account.id),
      account: account
    )

    expect(described_class.call(scenario, account: account, assistant: assistant)).to eq([])
  end

  it 'returns an empty array when the scenario has no tool references' do
    scenario = build_scenario(tools: [])

    expect(described_class.call(scenario, account: account, assistant: assistant)).to eq([])
  end
end
