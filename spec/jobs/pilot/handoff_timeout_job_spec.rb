require 'rails_helper'

# Covers the guarded resume path of the warm-bot handoff timer.
# The happy path flips the conversation back to `pending`, posts the
# configured fallback message, and stamps a timeline activity. Every
# guard (stale token, state change, assignment, human reply, resolved)
# must short-circuit silently.
RSpec.describe Pilot::HandoffTimeoutJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:requested_at) { Time.zone.parse('2026-05-26 12:00:00').iso8601 }
  let(:conversation) do
    convo = create(:conversation, account: account, inbox: inbox)
    # An attached Pilot::Inbox triggers `determine_conversation_status`
    # to mark new conversations as `pending`. Force `open` to model the
    # warm-bot window the job is meant to time out.
    convo.update!(
      status: :open,
      additional_attributes: {
        'pilot_handoff' => {
          'state' => 'handoff_requested',
          'requested_at' => requested_at,
          'mode' => 'keep_pilot_warm',
          'resume_count' => 0
        }
      }
    )
    convo
  end

  before do
    Pilot::Inbox.create!(assistant: assistant, inbox: inbox)
  end

  describe 'happy path' do
    it 'transitions the conversation to pending' do
      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.to change { conversation.reload.status }.from('open').to('pending')
    end

    it 'flips the pilot_handoff state to pilot_resumed and bumps resume_count' do
      described_class.perform_now(conversation.id, requested_at)

      handoff = conversation.reload.additional_attributes['pilot_handoff']
      expect(handoff['state']).to eq('pilot_resumed')
      expect(handoff['resume_count']).to eq(1)
    end

    it 'posts the configured timeout message as an outgoing assistant message' do
      assistant.update!(config: assistant.config.merge('handoff_timeout_message' => 'Still here for you.'))

      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.to change { conversation.messages.outgoing.count }.by(1)

      reply = conversation.messages.outgoing.last
      expect(reply.sender).to eq(assistant)
      expect(reply.content).to eq('Still here for you.')
    end

    it 'falls back to the i18n default message when none is configured' do
      described_class.perform_now(conversation.id, requested_at)

      expect(conversation.messages.outgoing.last.content)
        .to eq(I18n.t('conversations.pilot.handoff_timeout'))
    end

    it 'appends a timeout activity row to the timeline' do
      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.to change { conversation.messages.activity.count }.by(1)

      expect(conversation.messages.activity.last.content)
        .to eq(I18n.t('pilot.activity.handoff_timeout_triggered'))
    end
  end

  describe 'guards' do
    it 'no-ops when the conversation is missing' do
      expect do
        described_class.perform_now(-1, requested_at)
      end.not_to(change(Message, :count))
    end

    it 'no-ops when the requested_at token does not match (stale job)' do
      stale = (Time.zone.parse(requested_at) - 1.minute).iso8601

      expect do
        described_class.perform_now(conversation.id, stale)
      end.not_to(change { conversation.reload.status })

      expect(conversation.messages.outgoing).to be_empty
    end

    it 'no-ops when the state has moved away from handoff_requested' do
      conversation.update!(
        additional_attributes: conversation.additional_attributes.deep_merge(
          'pilot_handoff' => { 'state' => 'pilot_resumed' }
        )
      )

      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.not_to(change { conversation.reload.status })
    end

    it 'no-ops when an assignee has taken ownership' do
      agent = create(:user, account: account, role: :agent)
      conversation.update!(assignee: agent)

      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.not_to(change { conversation.reload.status })

      expect(conversation.messages.outgoing).to be_empty
    end

    it 'no-ops when a human agent has replied since requested_at' do
      agent = create(:user, account: account, role: :agent)
      create(:message,
             account: account,
             inbox: inbox,
             conversation: conversation,
             message_type: :outgoing,
             sender: agent,
             created_at: Time.zone.parse(requested_at) + 30.seconds)

      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.not_to(change { conversation.reload.status })
    end

    it 'no-ops when the conversation is resolved' do
      conversation.update!(status: :resolved)

      expect do
        described_class.perform_now(conversation.id, requested_at)
      end.not_to(change { conversation.reload.status })
    end
  end
end
