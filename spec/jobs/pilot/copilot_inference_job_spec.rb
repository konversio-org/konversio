require 'rails_helper'

RSpec.describe Pilot::CopilotInferenceJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: agent) }

  before do
    account.update!(pilot_enabled: true, pilot_copilot_enabled: true)
    create(:captain_copilot_message, copilot_thread: thread, account: account, message_type: :user, message: { content: 'hi' })
  end

  it 'invokes CopilotService and persists the assistant reply' do
    allow_any_instance_of(Custom::Pilot::CopilotService)
      .to receive(:perform).and_return('Hello, agent.')

    expect do
      described_class.perform_now(thread_id: thread.id, conversation_id: nil)
    end.to change { thread.copilot_messages.assistant.count }.by(1)

    last_assistant = thread.copilot_messages.assistant.order(:created_at).last
    expect(last_assistant.message['content']).to eq('Hello, agent.')
  end

  it 'dispatches COPILOT_MESSAGE_CREATED for the persisted assistant message' do
    allow_any_instance_of(Custom::Pilot::CopilotService)
      .to receive(:perform).and_return('Hello, agent.')

    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with('copilot.message.created', anything, hash_including(:copilot_message))
      .at_least(:once)
      .and_call_original

    described_class.perform_now(thread_id: thread.id)
  end

  it 'is a no-op when the thread does not exist' do
    expect { described_class.perform_now(thread_id: -1) }.not_to raise_error
  end

  it 'swallows CopilotService errors and logs them' do
    allow_any_instance_of(Custom::Pilot::CopilotService)
      .to receive(:perform).and_raise(Custom::Pilot::CopilotService::Error, 'upstream down')

    expect(Rails.logger).to receive(:error).with(/LLM failure/)

    expect do
      described_class.perform_now(thread_id: thread.id)
    end.not_to change(Captain::CopilotMessage, :count)
  end
end
