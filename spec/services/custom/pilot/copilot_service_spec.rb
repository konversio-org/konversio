require 'rails_helper'

# Tests for the ai-agents SDK runner pattern (D21). We mock the runner at
# its public boundary (`Agents::Runner.with_agents` → AgentRunner#run) so
# nothing in the suite ever hits a real LLM provider.
RSpec.describe Custom::Pilot::CopilotService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thread) { create(:pilot_copilot_thread, account: account, user: agent) }
  let(:fake_runner) { instance_double(Agents::AgentRunner) }

  before do
    account.update!(pilot_enabled: true, pilot_copilot_enabled: true)
    create(:pilot_copilot_message, copilot_thread: thread, account: account,
                                   message_type: :user, message: { content: 'Refund question' })
    # Stub the runner factory so we can drive tool-start callbacks + final result manually.
    allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)
    allow(fake_runner).to receive(:on_tool_start) do |&block|
      @tool_start_callback = block
      fake_runner
    end
  end

  def stub_runner_success(content)
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(output: content, messages: [], usage: nil, context: {})
    )
  end

  def stub_runner_max_steps
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(
        output: 'Conversation ended: max turns',
        messages: [], usage: nil,
        error: Agents::Runner::MaxTurnsExceeded.new('Exceeded maximum turns: 8'),
        context: {}
      )
    )
  end

  describe '#perform' do
    it 'raises FeatureDisabledError when the copilot flag is off' do
      account.update!(pilot_copilot_enabled: false)
      expect { described_class.new(thread: thread).perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'raises FeatureDisabledError when the master pilot flag is off' do
      account.update!(pilot_enabled: false)
      expect { described_class.new(thread: thread).perform }
        .to raise_error(described_class::FeatureDisabledError)
    end

    it 'invokes the runner with the configured copilot model and registered tools' do
      stub_runner_success('Final reply.')
      expect(Agents::Runner).to receive(:with_agents) do |agent_arg|
        expect(agent_arg).to be_a(Agents::Agent)
        expect(agent_arg.model).to eq(Llm::Config.model_for(:copilot))
        tool_names = agent_arg.tools.map(&:name)
        expect(tool_names).to include('search_conversation', 'get_conversation', 'get_contact')
        fake_runner
      end
      described_class.new(thread: thread).perform
    end

    it 'persists the final assistant message with message_type=assistant' do
      stub_runner_success('All set.')
      expect { described_class.new(thread: thread).perform }
        .to change { thread.copilot_messages.assistant.count }.by(1)
      last = thread.copilot_messages.assistant.order(:created_at).last
      expect(last.message['content']).to eq('All set.')
    end

    it 'persists assistant_thinking messages for each tool call emitted during the run' do
      allow(fake_runner).to receive(:run) do
        @tool_start_callback.call('search_conversation', { status: 'open' })
        Agents::RunResult.new(output: 'Done.', messages: [], usage: nil, context: {})
      end
      expect { described_class.new(thread: thread).perform }
        .to change { thread.copilot_messages.assistant_thinking.count }.by(1)
      thinking = thread.copilot_messages.assistant_thinking.order(:created_at).last
      expect(thinking.message['content']).to eq('Using search_conversation')
      expect(thinking.message['function_name']).to eq('search_conversation')
    end

    it 'persists a fallback message and fires copilot_inference_failed on max-steps exhaustion' do
      stub_runner_max_steps
      service = described_class.new(thread: thread)
      expect(service).to receive(:dispatch_event)
        .with(:copilot_inference_failed, hash_including(reason: 'max_steps_exhausted'))
      expect(service).to receive(:dispatch_event)
        .with(:copilot_inference_started, anything).and_call_original

      result = service.perform
      fallback = thread.copilot_messages.assistant.order(:created_at).last
      expect(fallback.message['content']).to match(/couldn't complete/)
      expect(result).to match(/couldn't complete/)
    end

    it 'raises Error when no user message exists in the thread' do
      thread.copilot_messages.destroy_all
      service = described_class.new(thread: thread)
      expect { service.perform }.to raise_error(described_class::Error, /No user message/)
    end

    it 'wraps unexpected runner exceptions as Error and fires copilot_inference_failed' do
      allow(fake_runner).to receive(:run).and_raise(RuntimeError, 'boom')
      service = described_class.new(thread: thread)
      expect(service).to receive(:dispatch_event)
        .with(:copilot_inference_started, anything).and_call_original
      expect(service).to receive(:dispatch_event)
        .with(:copilot_inference_failed, hash_including(reason: 'RuntimeError'))
      expect { service.perform }.to raise_error(described_class::Error, /boom/)
    end
  end
end
