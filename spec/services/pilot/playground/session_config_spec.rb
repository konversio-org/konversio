require 'rails_helper'

RSpec.describe Pilot::Playground::SessionConfig do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  def build_config(payload)
    described_class.build(payload, assistant: assistant)
  end

  describe 'object shape' do
    it 'accepts an empty configuration' do
      config = build_config({})

      expect(config.scenario_ids).to be_nil
      expect(config.response_guidelines).to be_nil
      expect(config.knowledge?).to be(false)
    end

    it 'rejects a non-object configuration keyed to the configuration field' do
      expect { build_config('not-an-object') }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('playground_config') }
    end
  end

  describe 'scenario selection' do
    let!(:scenario_a) { create(:pilot_scenario, assistant: assistant, account: account, title: 'Alpha') }
    let!(:scenario_b) { create(:pilot_scenario, assistant: assistant, account: account, title: 'Beta') }

    it 'limits participating scenarios to the supplied ids' do
      config = build_config(scenario_ids: [scenario_a.id])

      expect(config.persisted_scenarios).to contain_exactly(scenario_a)
      expect(config.scenario_specs.map(&:runtime_name)).not_to include(scenario_b.handoff_key)
    end

    it 'uses all enabled persisted scenarios when the key is absent' do
      config = build_config({})

      expect(config.persisted_scenarios).to contain_exactly(scenario_a, scenario_b)
    end

    it 'rejects foreign scenario ids' do
      foreign = create(:pilot_scenario, account: create(:account))

      expect { build_config(scenario_ids: [foreign.id]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors['scenario_ids'].join).to include(foreign.id.to_s) }
    end

    it 'rejects duplicate ids' do
      expect { build_config(scenario_ids: [scenario_a.id, scenario_a.id]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('scenario_ids') }
    end

    it 'rejects non-positive ids' do
      expect { build_config(scenario_ids: [0]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('scenario_ids') }
    end
  end

  describe 'temporary scenarios' do
    let(:draft) do
      {
        client_id: 'draft-1',
        title: 'Refund flow',
        description: 'Handles refunds',
        instruction: 'Walk the customer through a refund.'
      }
    end

    it 'builds unsaved scenarios without persisting them' do
      expect { build_config(temporary_scenarios: [draft]) }.not_to change(Pilot::Scenario, :count)

      config = build_config(temporary_scenarios: [draft])
      expect(config.temporary_scenarios.size).to eq(1)
      expect(config.temporary_scenarios.first.scenario).not_to be_persisted
      expect(config.scenario_specs.last.temporary).to be(true)
    end

    it 'derives deterministic runtime names namespaced away from persisted scenarios' do
      first = build_config(temporary_scenarios: [draft]).temporary_scenarios.first
      second = build_config(temporary_scenarios: [draft]).temporary_scenarios.first

      expect(first.runtime_name).to eq(second.runtime_name)
      expect(first.runtime_name).to start_with(described_class::RUNTIME_NAME_PREFIX)
      expect(first.runtime_name).not_to eq(create(:pilot_scenario, assistant: assistant, account: account).handoff_key)
      expect("handoff_to_#{first.runtime_name}".length).to be <= Pilot::Scenario::MAX_HANDOFF_TOOL_NAME_LENGTH
    end

    it 'resolves tool references in temporary instructions' do
      tool = create(:pilot_custom_tool, account: account, title: 'Lookup order')
      assistant.update!(enabled_tool_slugs: [tool.slug])

      config = build_config(temporary_scenarios: [draft.merge(instruction: "Use [Lookup order](tool://#{tool.slug}).")])

      expect(config.temporary_scenarios.first.scenario.tools).to include(tool.slug)
    end

    it 'reports per-field errors for a blank title' do
      expect { build_config(temporary_scenarios: [draft.merge(title: '')]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('temporary_scenarios.0.title') }
    end

    it 'requires a client identifier' do
      expect { build_config(temporary_scenarios: [draft.merge(client_id: '')]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('temporary_scenarios.0.client_id') }
    end

    it 'rejects duplicate client identifiers' do
      expect { build_config(temporary_scenarios: [draft, draft]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('temporary_scenarios') }
    end
  end

  describe 'rule lists' do
    it 'replaces the persisted guidelines when the key is present' do
      config = build_config(response_guidelines: ['Be concise'])

      expect(config.response_guidelines).to eq(['Be concise'])
    end

    it 'treats an explicit empty list as no rules' do
      config = build_config(guardrails: [])

      expect(config.guardrails).to eq([])
    end

    it 'leaves an absent key unset so persisted rules apply' do
      expect(build_config({}).guardrails).to be_nil
    end

    it 'trims and de-duplicates entries' do
      config = build_config(response_guidelines: ['  Be concise  ', 'Be concise', 'Be kind'])

      expect(config.response_guidelines).to eq(['Be concise', 'Be kind'])
    end

    it 'rejects blank or non-string entries' do
      expect { build_config(guardrails: ['ok', nil]) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('guardrails') }
    end
  end

  describe 'knowledge text' do
    it 'exposes a supplied snippet' do
      config = build_config(knowledge_text: 'Refunds take 30 days.')

      expect(config.knowledge?).to be(true)
      expect(config.knowledge_text).to eq('Refunds take 30 days.')
    end

    it 'rejects a snippet over the cap' do
      expect { build_config(knowledge_text: 'x' * (described_class::KNOWLEDGE_TEXT_LIMIT + 1)) }
        .to raise_error(described_class::Invalid) do |error|
          expect(error.errors['knowledge_text'].join).to include(described_class::KNOWLEDGE_TEXT_LIMIT.to_s)
        end
    end

    it 'rejects a non-string snippet' do
      expect { build_config(knowledge_text: ['nope']) }
        .to raise_error(described_class::Invalid) { |error| expect(error.errors).to have_key('knowledge_text') }
    end
  end

  describe 'aggregation' do
    it 'reports multiple failures together' do
      foreign = create(:pilot_scenario, account: create(:account))

      expect { build_config(scenario_ids: [foreign.id], temporary_scenarios: [{ client_id: '' }]) }
        .to raise_error(described_class::Invalid) do |error|
          expect(error.errors).to have_key('scenario_ids')
          expect(error.errors).to have_key('temporary_scenarios.0.client_id')
        end
    end
  end
end
