# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PilotOutcomeListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:recorder) do
    instance_double(
      Pilot::ConversationOutcomeRecorder,
      record_human_reply: nil,
      record_resolution: nil,
      record_reopen: nil,
      record_handoff: nil,
      record_csat: nil
    )
  end

  before do
    account.enable_features!(:pilot)
    allow(Pilot::ConversationOutcomeRecorder).to receive(:new).and_return(recorder)
  end

  describe '#message_created' do
    it 'routes an outgoing human message to record_human_reply' do
      message = create(
        :message, account: account, inbox: inbox, conversation: conversation,
                  sender: create(:user, account: account), message_type: 'outgoing'
      )
      event = Events::Base.new('message.created', Time.zone.now, message: message)

      expect(recorder).to receive(:record_human_reply).with(message: message)
      listener.message_created(event)
    end

    it 'ignores incoming messages' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming')
      event = Events::Base.new('message.created', Time.zone.now, message: message)

      expect(recorder).not_to receive(:record_human_reply)
      listener.message_created(event)
    end
  end

  describe '#conversation_resolved' do
    it 'routes the resolution to the recorder' do
      event = Events::Base.new('conversation.resolved', Time.zone.now, conversation: conversation)

      expect(recorder).to receive(:record_resolution).with(at: event.timestamp)
      listener.conversation_resolved(event)
    end
  end

  describe '#conversation_updated' do
    it 'routes a transition away from resolved to record_reopen' do
      event = Events::Base.new(
        'conversation.updated',
        Time.zone.now,
        conversation: conversation,
        changed_attributes: { 'status' => %w[resolved open] }
      )

      expect(recorder).to receive(:record_reopen).with(at: event.timestamp)
      listener.conversation_updated(event)
    end

    it 'ignores updates that do not leave the resolved status' do
      event = Events::Base.new(
        'conversation.updated',
        Time.zone.now,
        conversation: conversation,
        changed_attributes: { 'status' => %w[open resolved] }
      )

      expect(recorder).not_to receive(:record_reopen)
      listener.conversation_updated(event)
    end
  end

  describe '#message_updated' do
    it 'routes a CSAT survey response to record_csat' do
      message = create(
        :message, account: account, inbox: inbox, conversation: conversation,
                  message_type: 'outgoing', content_type: 'input_csat'
      )
      response = create(
        :csat_survey_response,
        account: account,
        conversation: conversation,
        contact: conversation.contact,
        message: message,
        feedback_message: nil
      )
      event = Events::Base.new('message.updated', Time.zone.now, message: message)

      expect(recorder).to receive(:record_csat).with(response: response)
      listener.message_updated(event)
    end

    it 'ignores non-CSAT message updates' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      event = Events::Base.new('message.updated', Time.zone.now, message: message)

      expect(recorder).not_to receive(:record_csat)
      listener.message_updated(event)
    end
  end

  describe '#pilot_conversation_handed_off' do
    it 'routes the handoff to record_handoff with its reason category' do
      event = Events::Base.new(
        'pilot.conversation.handed_off',
        Time.zone.now,
        conversation: conversation,
        assistant: assistant,
        source: 'inference',
        reason_category: 'knowledge_gap'
      )

      expect(recorder).to receive(:record_handoff).with(at: event.timestamp, reason_category: 'knowledge_gap')
      listener.pilot_conversation_handed_off(event)
    end
  end

  describe 'feature gating' do
    before { account.disable_features!(:pilot) }

    it 'ignores every event when the pilot feature is off' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming')
      resolved = Events::Base.new('conversation.resolved', Time.zone.now, conversation: conversation)
      handoff = Events::Base.new(
        'pilot.conversation.handed_off',
        Time.zone.now,
        conversation: conversation,
        assistant: assistant,
        source: 'inference',
        reason_category: 'other'
      )

      expect(recorder).not_to receive(:record_human_reply)
      expect(recorder).not_to receive(:record_resolution)
      expect(recorder).not_to receive(:record_handoff)

      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      listener.conversation_resolved(resolved)
      listener.pilot_conversation_handed_off(handoff)
    end
  end
end
