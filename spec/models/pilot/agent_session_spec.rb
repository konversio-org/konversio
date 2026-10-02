require 'rails_helper'

RSpec.describe Pilot::AgentSession do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }

  describe 'associations and account derivation' do
    it 'derives the account from the assistant when absent' do
      conversation = create(:conversation, account: account)
      session = described_class.new(
        assistant: assistant,
        subject: conversation,
        session_kind: :autopilot
      )

      session.validate

      expect(session.account).to eq(account)
    end

    it 'accepts an autopilot session with a conversation subject and message result' do
      conversation = create(:conversation, account: account)
      message = create(:message, account: account, conversation: conversation)

      session = described_class.new(
        assistant: assistant,
        account: account,
        session_kind: :autopilot,
        subject: conversation,
        result: message
      )

      expect(session).to be_valid
    end

    it 'accepts a copilot session with a thread subject and copilot message result' do
      thread = create(:pilot_copilot_thread, account: account)
      message = create(:pilot_copilot_message, account: account, copilot_thread: thread)

      session = described_class.new(
        assistant: assistant,
        account: account,
        session_kind: :copilot,
        subject: thread,
        result: message
      )

      expect(session).to be_valid
    end

    it 'allows a session without a result' do
      conversation = create(:conversation, account: account)
      session = build(:pilot_agent_session, assistant: assistant, account: account, subject: conversation, result: nil)

      expect(session).to be_valid
    end
  end

  describe 'validations' do
    it 'rejects a subject type that does not match the kind' do
      conversation = create(:conversation, account: account)
      session = build(:pilot_agent_session,
                      assistant: assistant,
                      account: account,
                      session_kind: :copilot,
                      subject: conversation,
                      result: nil)

      expect(session).not_to be_valid
      expect(session.errors[:subject_type]).to be_present
    end

    it 'rejects a result type that does not match the kind' do
      conversation = create(:conversation, account: account)
      message = create(:message, account: account, conversation: conversation)
      session = build(:pilot_agent_session,
                      assistant: assistant,
                      account: account,
                      session_kind: :copilot,
                      subject: create(:pilot_copilot_thread, account: account),
                      result: message)

      expect(session).not_to be_valid
      expect(session.errors[:result_type]).to be_present
    end

    it 'rejects a subject from another account' do
      foreign = create(:conversation, account: create(:account))
      session = build(:pilot_agent_session,
                      assistant: assistant,
                      account: account,
                      subject: foreign,
                      result: nil)

      expect(session).not_to be_valid
      expect(session.errors[:subject]).to be_present
    end

    it 'rejects a result from another account' do
      foreign_conversation = create(:conversation, account: create(:account))
      foreign_message = create(:message, account: foreign_conversation.account, conversation: foreign_conversation)
      session = build(:pilot_agent_session,
                      assistant: assistant,
                      account: account,
                      subject: create(:conversation, account: account),
                      result: foreign_message)

      expect(session).not_to be_valid
      expect(session.errors[:result]).to be_present
    end

    it 'skips result validations when no result is present' do
      conversation = create(:conversation, account: account)
      session = build(:pilot_agent_session, assistant: assistant, account: account, subject: conversation, result: nil)

      expect(session).to be_valid
    end
  end

  describe 'ownership' do
    it 'cleans up the assistant sessions asynchronously on destroy' do
      reflection = Pilot::Assistant.reflect_on_association(:agent_sessions)

      expect(reflection.options[:dependent]).to eq(:destroy_async)
    end

    it 'cleans up the account sessions asynchronously on destroy' do
      reflection = Account.reflect_on_association(:pilot_agent_sessions)

      expect(reflection.options[:dependent]).to eq(:destroy_async)
    end
  end
end
