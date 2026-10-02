require 'rails_helper'

RSpec.describe Pilot::Playground::RunReport do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account, name: 'Support Bot') }
  let(:config) { Pilot::Playground::SessionConfig.build({}, assistant: assistant) }
  let(:report) { described_class.new(assistant: assistant, config: config) }

  describe 'final handler attribution' do
    it 'identifies the assistant when it produces the reply' do
      report.on_run_complete('support_bot')

      expect(report.to_h[:handler]).to eq(name: 'Support Bot', type: 'assistant', temporary: false)
    end

    it 'falls back to the assistant when no completion callback fired' do
      expect(report.to_h[:handler]).to eq(name: 'Support Bot', type: 'assistant', temporary: false)
    end

    it 'identifies a temporary scenario by its draft title with a temporary marker' do
      config = Pilot::Playground::SessionConfig.build(
        {
          temporary_scenarios: [{
            client_id: 'draft-1', title: 'Refund flow', description: 'Desc', instruction: 'Do the refund.'
          }]
        },
        assistant: assistant
      )
      report = described_class.new(assistant: assistant, config: config)
      runtime_name = config.temporary_scenarios.first.runtime_name

      report.on_run_complete(runtime_name)

      expect(report.to_h[:handler]).to eq(name: 'Refund flow', type: 'scenario', temporary: true)
    end
  end

  describe 'knowledge flag' do
    it 'is false without knowledge text' do
      expect(report.to_h[:knowledge_attached]).to be(false)
    end

    it 'is true with knowledge text' do
      config = Pilot::Playground::SessionConfig.build({ knowledge_text: 'Facts.' }, assistant: assistant)
      report = described_class.new(assistant: assistant, config: config)

      expect(report.to_h[:knowledge_attached]).to be(true)
    end
  end

  describe 'duration' do
    it 'reports a non-negative duration per run' do
      first = described_class.new(assistant: assistant, config: config)
      second = described_class.new(assistant: assistant, config: config)
      first.finish!
      second.finish!

      expect(first.duration_ms).to be_a(Integer)
      expect(second.duration_ms).to be >= 0
    end
  end

  describe 'tool events' do
    it 'records a completed tool call with arguments and a result preview' do
      report.on_tool_start('search_documentation', { 'query' => 'refunds' })
      report.on_tool_complete('search_documentation', 'Refunds take 30 days.')

      expect(report.events.size).to eq(1)
      event = report.events.first
      expect(event).to include(type: 'tool', tool: 'search_documentation', status: 'completed')
      expect(event[:arguments]).to eq('query' => 'refunds')
      expect(event[:result_preview]).to eq('Refunds take 30 days.')
    end

    it 'records a failure when a tool returns an error result' do
      report.on_tool_start('custom_lookup', {})
      report.on_tool_complete('custom_lookup', 'ERROR: upstream timeout')

      expect(report.events.first[:status]).to eq('failed')
    end

    it 'treats a serialized error hash as a failure' do
      report.on_tool_start('custom_lookup', {})
      report.on_tool_complete('custom_lookup', { 'error' => 'nope', 'message' => 'bad' })

      expect(report.events.first[:status]).to eq('failed')
    end

    it 'strips internal namespace prefixes from display names' do
      report.on_tool_start('custom_lookup_order', {})

      expect(report.events.first[:tool]).to eq('lookup_order')
    end

    it 'truncates long result previews to the preview limit' do
      report.on_tool_start('search_documentation', {})
      report.on_tool_complete('search_documentation', 'x' * 900)

      expect(report.events.first[:result_preview].length).to be <= described_class::PREVIEW_LIMIT
    end

    it 'ignores handoff tool calls (they surface as handoff events)' do
      report.on_tool_start('handoff_to_scenario_1_agent', {})
      report.on_tool_complete('handoff_to_scenario_1_agent', 'ok')

      expect(report.events).to be_empty
    end
  end

  describe 'handoff events' do
    it 'records source, target, and a truncated reason preview' do
      config = Pilot::Playground::SessionConfig.build(
        {
          temporary_scenarios: [{
            client_id: 'draft-1', title: 'Refund flow', description: 'Desc', instruction: 'Do the refund.'
          }]
        },
        assistant: assistant
      )
      report = described_class.new(assistant: assistant, config: config)
      runtime_name = config.temporary_scenarios.first.runtime_name

      report.on_agent_handoff('support_bot', runtime_name, 'customer asked about refunds')

      event = report.events.first
      expect(event[:type]).to eq('handoff')
      expect(event[:from]).to eq(name: 'Support Bot', type: 'assistant', temporary: false)
      expect(event[:to]).to eq(name: 'Refund flow', type: 'scenario', temporary: true)
      expect(event[:reason_preview]).to eq('customer asked about refunds')
    end
  end

  describe 'event ordering' do
    it 'preserves execution order across tool and handoff events' do
      report.on_tool_start('search_documentation', {})
      report.on_tool_complete('search_documentation', 'result')
      report.on_agent_handoff('support_bot', 'scenario_1_agent', 'reason')
      report.on_tool_start('custom_lookup', {})
      report.on_tool_complete('custom_lookup', 'ok')

      expect(report.events.map { |event| [event[:type], event[:tool] || event[:to][:name]] }).to eq(
        [
          %w[tool search_documentation],
          %w[handoff scenario_1_agent],
          %w[tool lookup]
        ]
      )
    end
  end

  describe 'sanitization' do
    it 'masks credential-named arguments but keeps siblings visible' do
      report.on_tool_start('custom_lookup', { 'account' => 'acme', 'api_token' => 'sekret', 'note' => 'ok' })

      arguments = report.events.first[:arguments]
      expect(arguments['api_token']).to eq('[REDACTED]')
      expect(arguments['account']).to eq('acme')
      expect(arguments['note']).to eq('ok')
    end

    it 'masks credential-named keys recursively at depth' do
      report.on_tool_start('custom_lookup', { 'outer' => { 'nested' => { 'api_key' => 'sekret', 'visible' => 'yes' } } })

      nested = report.events.first[:arguments]['outer']['nested']
      expect(nested['api_key']).to eq('[REDACTED]')
      expect(nested['visible']).to eq('yes')
    end

    it 'masks credentials inside string payloads while keeping the rest readable' do
      payload = "Request finished.\nAuthorization: Bearer abc123\nstatus: ok"
      report.on_tool_start('search_documentation', {})
      report.on_tool_complete('search_documentation', payload)

      preview = report.events.first[:result_preview]
      expect(preview).to include('Authorization: [REDACTED]')
      expect(preview).to include('Request finished.')
      expect(preview).to include('status: ok')
      expect(preview).not_to include('abc123')
    end

    it 'masks credentials inside serialized JSON payloads' do
      payload = '{"token":"abcd","other":"value"}'
      report.on_tool_start('search_documentation', {})
      report.on_tool_complete('search_documentation', payload)

      preview = report.events.first[:result_preview]
      expect(preview).to include('"token":"[REDACTED]"')
      expect(preview).to include('"other":"value"')
      expect(preview).not_to include('abcd')
    end
  end
end
