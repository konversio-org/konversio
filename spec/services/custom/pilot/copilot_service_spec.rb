require 'rails_helper'

RSpec.describe Custom::Pilot::CopilotService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thread) { create(:pilot_copilot_thread, account: account, user: agent) }

  before do
    account.update!(pilot_enabled: true, pilot_copilot_enabled: true)
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

    it 'returns the assistant content built from the thread history' do
      create(:pilot_copilot_message, copilot_thread: thread, account: account, message_type: :user, message: { content: 'Hello' })

      service = described_class.new(thread: thread)

      fake_chat = double('chat')
      fake_response = double('response', content: 'Hi back!')
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:add_message)
      allow(fake_chat).to receive(:ask).and_return(fake_response)

      fake_context = double('context')
      allow(fake_context).to receive(:chat).and_return(fake_chat)

      allow(service).to receive(:chat_context).and_yield(fake_context)

      expect(service.perform).to eq('Hi back!')
    end

    it 'raises Error when no user message exists in the thread' do
      service = described_class.new(thread: thread)
      expect { service.perform }.to raise_error(described_class::Error, /No user message/)
    end
  end
end
