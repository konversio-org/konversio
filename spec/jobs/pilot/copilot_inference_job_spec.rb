require 'rails_helper'

# CopilotService now persists messages itself (intermediate + final), so the
# job's responsibility is narrow: invoke the service and log/swallow errors.
# Tests mock the ai-agents Runner at the boundary so the multi-step contract
# is verified without any real LLM call.
RSpec.describe Pilot::CopilotInferenceJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thread) { create(:pilot_copilot_thread, account: account, user: agent) }
  let(:fake_runner) { instance_double(Agents::AgentRunner) }

  before do
    account.enable_features!(:pilot, :pilot_copilot)
    create(:pilot_copilot_message, copilot_thread: thread, account: account,
                                   message_type: :user, message: { content: 'hi' })
    allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)
    allow(fake_runner).to receive(:on_tool_start) do |&block|
      @tool_start_callback = block
      fake_runner
    end
  end

  it 'invokes the runner end-to-end: tool call → result → final assistant message' do
    allow(fake_runner).to receive(:run) do
      @tool_start_callback.call('search_conversation', { status: 'open' })
      Agents::RunResult.new(output: 'Found two open tickets.', messages: [], usage: nil, context: {})
    end

    expect do
      described_class.perform_now(thread_id: thread.id, conversation_id: nil)
    end.to change { thread.copilot_messages.assistant.count }.by(1)
                                                             .and change { thread.copilot_messages.assistant_thinking.count }.by(1)

    last_assistant = thread.copilot_messages.assistant.order(:created_at).last
    expect(last_assistant.message['content']).to eq('Found two open tickets.')
  end

  it 'tolerates extra LLM-emitted keys in the persisted message JSONB (D23)' do
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(output: 'OK', messages: [], usage: nil, context: {})
    )
    expect { described_class.perform_now(thread_id: thread.id) }.not_to raise_error
    # Backfill — sanity check the model itself accepts extra keys
    expect do
      Pilot::CopilotMessage.create!(
        copilot_thread: thread,
        account: account,
        message_type: :assistant,
        message: { 'content' => 'x', 'tool_calls' => [{ 'n' => 1 }], 'finish_reason' => 'stop' }
      )
    end.not_to raise_error
  end

  it 'dispatches COPILOT_MESSAGE_CREATED for the persisted assistant message' do
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(output: 'Hello, agent.', messages: [], usage: nil, context: {})
    )
    # Other dispatcher events (pilot.copilot.inference.started/completed) also fire
    # via the Pilot EventDispatcher — `allow ... and_call_original` lets them through
    # while the strict expectation below pins the COPILOT_MESSAGE_CREATED dispatch.
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with('copilot.message.created', anything, hash_including(:copilot_message))
      .at_least(:once)
      .and_call_original
    described_class.perform_now(thread_id: thread.id)
  end

  it 'persists a fallback assistant message when max_steps is exhausted' do
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(
        output: 'Conversation ended',
        messages: [], usage: nil,
        error: Agents::Runner::MaxTurnsExceeded.new('Exceeded maximum turns: 8'),
        context: {}
      )
    )
    expect { described_class.perform_now(thread_id: thread.id) }
      .to change { thread.copilot_messages.assistant.count }.by(1)
    expect(thread.copilot_messages.assistant.last.message['content']).to match(/couldn't complete/)
  end

  it 'is a no-op when the thread does not exist' do
    expect { described_class.perform_now(thread_id: -1) }.not_to raise_error
  end

  it 'swallows CopilotService errors and logs them' do
    allow(fake_runner).to receive(:run).and_raise(RuntimeError, 'upstream down')

    expect(Rails.logger).to receive(:error).at_least(:once)

    expect do
      described_class.perform_now(thread_id: thread.id)
    end.not_to(change { thread.copilot_messages.assistant.count })
  end
end
