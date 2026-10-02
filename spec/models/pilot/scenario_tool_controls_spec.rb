# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pilot scenario and tool enablement', type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:tool) { create(:pilot_custom_tool, account: account, title: 'Order lookup') }

  describe 'disabled tool exclusion' do
    it 'excludes disabled tools from the assistant live toolset' do
      assistant.update!(enabled_tool_slugs: [tool.slug])
      expect(assistant.enabled_custom_tools).to include(tool)

      tool.update!(enabled: false)

      expect(assistant.reload.enabled_custom_tools).to be_empty
    end

    it 'does not satisfy scenario tool-reference validation for new references' do
      tool.update!(enabled: false)
      scenario = build(:pilot_scenario, assistant: assistant, account: account,
                                        instruction: "Use [orders](tool://#{tool.slug}) to check")

      expect(scenario).not_to be_valid
      expect(scenario.errors[:instruction]).to be_present
    end

    it 'keeps the stored reference so re-enabling restores behavior without edits' do
      assistant.update!(enabled_tool_slugs: [tool.slug])
      scenario = create(:pilot_scenario, assistant: assistant, account: account,
                                         instruction: "Use [orders](tool://#{tool.slug}) to check")
      tool.update!(enabled: false)

      expect(scenario.reload.tools).to include(tool.slug)

      tool.update!(enabled: true)
      resolved = Pilot::Tools::ScenarioResolver.call(scenario, account: account, assistant: assistant.reload)

      expect(resolved).not_to be_empty
    end
  end

  describe '#referencing_enabled_scenarios_count' do
    it 'counts only enabled scenarios referencing the tool' do
      create(:pilot_scenario, assistant: assistant, account: account, enabled: true,
                              instruction: "Use [orders](tool://#{tool.slug})")
      create(:pilot_scenario, assistant: assistant, account: account, enabled: true,
                              instruction: "Also [orders](tool://#{tool.slug})")
      create(:pilot_scenario, assistant: assistant, account: account, enabled: false,
                              instruction: "Disabled [orders](tool://#{tool.slug})")

      expect(tool.referencing_enabled_scenarios_count).to eq(2)
    end

    it 'is zero when nothing references the tool' do
      expect(tool.referencing_enabled_scenarios_count).to eq(0)
    end
  end

  describe 'scenario enablement at run time' do
    it 'registers only enabled scenarios with the agent framework' do
      enabled = create(:pilot_scenario, assistant: assistant, account: account, enabled: true)
      disabled = create(:pilot_scenario, assistant: assistant, account: account, enabled: false)

      expect(assistant.scenarios.enabled).to include(enabled)
      expect(assistant.scenarios.enabled).not_to include(disabled)
    end

    it 'keeps content intact when toggled off and on' do
      scenario = create(:pilot_scenario, assistant: assistant, account: account,
                                         instruction: "Use [orders](tool://#{tool.slug})")
      original = scenario.attributes.slice('title', 'description', 'instruction', 'tools')

      scenario.update!(enabled: false)
      scenario.update!(enabled: true)

      expect(scenario.attributes.slice('title', 'description', 'instruction', 'tools')).to eq(original)
    end
  end
end
