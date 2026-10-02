require 'rails_helper'

RSpec.describe Pilot::Playground::SessionRunner do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  it 'invokes the autopilot service with the runtime config and report callbacks' do
    captured = nil
    result = Custom::Pilot::AutopilotService::Result.new(reply: 'Hello', invoked_tool_names: ['search_documentation'])
    service = instance_double(Custom::Pilot::AutopilotService, perform: result)
    allow(Custom::Pilot::AutopilotService).to receive(:new) do |**kwargs|
      captured = kwargs
      service
    end

    response = described_class.call(
      assistant: assistant,
      payload: { knowledge_text: 'Refunds take 30 days.' },
      message: 'How do refunds work?',
      message_history: [{ role: 'user', content: 'How do refunds work?' }],
      account: account
    )

    expect(captured[:runtime_config]).to be_a(Pilot::Playground::SessionConfig)
    expect(captured[:source]).to eq('playground')
    expect(captured[:run_callbacks].keys).to include(:tool_start, :tool_complete, :agent_handoff, :run_complete)

    expect(response[:reply]).to eq('Hello')
    expect(response[:invoked_tool_names]).to eq(['search_documentation'])
    expect(response[:run_report]).to include(:handler, :knowledge_attached, :duration_ms, :events)
    expect(response[:run_report][:knowledge_attached]).to be(true)
  end

  it 'raises a validation error before any inference when the config is malformed' do
    expect(Custom::Pilot::AutopilotService).not_to receive(:new)

    expect { described_class.call(assistant: assistant, payload: 'not-an-object', message: 'hi') }
      .to raise_error(Pilot::Playground::SessionConfig::Invalid)
  end
end
