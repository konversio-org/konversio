# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::ConversationOutcomeRecorder do
  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pilot_inbox) { Pilot::Inbox.create!(assistant: assistant, inbox: inbox) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:recorder) { described_class.new(conversation: conversation) }

  def create_ai_reply(at:)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: assistant,
      message_type: 'outgoing',
      private: false,
      content: 'AI reply',
      created_at: at
    )
  end

  def create_human_reply(at:, **attrs)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: create(:user, account: account),
      message_type: 'outgoing',
      private: false,
      content: 'Human reply',
      created_at: at,
      **attrs
    )
  end

  describe '#record_eligibility' do
    it 'opens a single initial episode however often eligibility is recorded' do
      at = 3.hours.ago

      recorder.record_eligibility(at: at)
      recorder.record_eligibility(at: at + 1.minute)

      episodes = conversation.conversation_outcomes
      expect(episodes.count).to eq(1)
      expect(episodes.first).to be_initial
      expect(episodes.first.started_at).to be_within(1.second).of(at)
    end

    it 'records nothing when no assistant is attached' do
      pilot_inbox.destroy

      described_class.new(conversation: conversation).record_eligibility(at: Time.current)

      expect(conversation.conversation_outcomes).to be_empty
    end
  end

  describe '#record_reopen' do
    it 'closes the predecessor and opens a reopen episode for the attached assistant' do
      recorder.record_eligibility(at: 2.hours.ago)
      predecessor = conversation.conversation_outcomes.first

      replacement = create(:pilot_assistant, account: account)
      pilot_inbox.update!(assistant: replacement)

      reopened_at = 1.hour.ago
      described_class.new(conversation: conversation).record_reopen(at: reopened_at)

      episodes = conversation.conversation_outcomes.chronological
      expect(episodes.count).to eq(2)
      expect(predecessor.reload.ended_at).to be_within(1.second).of(reopened_at)

      successor = episodes.last
      expect(successor).to be_reopen
      expect(successor.assistant).to eq(replacement)
      expect(successor.started_at).to be_within(1.second).of(reopened_at)
    end

    it 'is a no-op when no episode history exists' do
      expect { recorder.record_reopen(at: Time.current) }.not_to change(Pilot::ConversationOutcome, :count)
    end
  end

  describe '#record_handoff' do
    it 'records the timestamp and reason and snapshots AI replies within the window' do
      recorder.record_eligibility(at: 3.hours.ago)
      create_ai_reply(at: 5.hours.ago)
      first_reply_at = 2.hours.ago
      create_ai_reply(at: first_reply_at)
      create_ai_reply(at: 1.hour.ago)

      recorder.record_handoff(at: Time.current, reason_category: 'customer_escalation')

      episode = conversation.conversation_outcomes.first
      expect(episode.handoff_reason_category).to eq('customer_escalation')
      expect(episode.handoff_at).to be_present
      expect(episode.ai_reply_count).to eq(2)
      expect(episode.first_ai_reply_at).to be_within(1.second).of(first_reply_at)
    end

    it 'is a no-op when no episode covers the handoff time' do
      expect { recorder.record_handoff(at: Time.current, reason_category: 'knowledge_gap') }
        .not_to change(Pilot::ConversationOutcome, :count)
    end
  end

  describe '#record_resolution' do
    it 'recomputes reply facts to include replies after an earlier handoff' do
      recorder.record_eligibility(at: 3.hours.ago)
      create_ai_reply(at: 2.hours.ago)
      recorder.record_handoff(at: 90.minutes.ago, reason_category: 'knowledge_gap')
      later_reply_at = 30.minutes.ago
      create_ai_reply(at: later_reply_at)

      recorder.record_resolution(at: Time.current)

      episode = conversation.conversation_outcomes.first
      expect(episode.resolved_at).to be_present
      expect(episode.ai_reply_count).to eq(2)
      expect(episode.last_ai_reply_at).to be_within(1.second).of(later_reply_at)
    end

    it 'is a no-op when no episode covers the resolution time' do
      expect { recorder.record_resolution(at: Time.current) }.not_to change(Pilot::ConversationOutcome, :count)
    end
  end

  describe '#record_human_reply' do
    before { recorder.record_eligibility(at: 2.hours.ago) }

    it 'records the first qualifying reply once' do
      first_reply = create_human_reply(at: 1.hour.ago)
      recorder.record_human_reply(message: first_reply)
      recorder.record_human_reply(message: create_human_reply(at: 30.minutes.ago))

      episode = conversation.conversation_outcomes.first
      expect(episode.first_human_reply_at).to be_within(1.second).of(first_reply.created_at)
    end

    it 'ignores automation-rule and campaign messages' do
      automation = create_human_reply(at: 1.hour.ago, content_attributes: { 'automation_rule_id' => 1 })
      campaign = create_human_reply(at: 30.minutes.ago, additional_attributes: { 'campaign_id' => 1 })

      recorder.record_human_reply(message: automation)
      recorder.record_human_reply(message: campaign)

      expect(conversation.conversation_outcomes.first.first_human_reply_at).to be_nil
    end

    it 'records an external echo of a human reply' do
      echoed = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: create(:agent_bot, account: account),
        message_type: 'outgoing',
        private: false,
        content: 'Echoed reply',
        content_attributes: { 'external_echo' => true },
        created_at: 1.hour.ago
      )

      recorder.record_human_reply(message: echoed)

      expect(conversation.conversation_outcomes.first.first_human_reply_at).to be_within(1.second).of(echoed.created_at)
    end
  end

  describe '#record_csat' do
    before { recorder.record_eligibility(at: 2.hours.ago) }

    it 'records the rating and receipt time on the covering episode' do
      survey_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        sender: assistant,
        message_type: 'outgoing',
        content_type: 'input_csat',
        created_at: 1.hour.ago
      )
      response = create(
        :csat_survey_response,
        account: account,
        conversation: conversation,
        contact: contact,
        message: survey_message,
        rating: 4,
        feedback_message: nil,
        created_at: 30.minutes.ago
      )

      recorder.record_csat(response: response)

      episode = conversation.conversation_outcomes.first
      expect(episode.csat_rating).to eq(4)
      expect(episode.csat_received_at).to be_within(1.second).of(response.created_at)
    end

    it 'is a no-op when no episode covers the survey message' do
      empty_conversation = create(:conversation, account: account, inbox: inbox)
      survey_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: empty_conversation,
        message_type: 'outgoing',
        content_type: 'input_csat'
      )
      response = create(
        :csat_survey_response,
        account: account,
        conversation: empty_conversation,
        contact: empty_conversation.contact,
        message: survey_message,
        feedback_message: nil
      )

      described_class.new(conversation: empty_conversation).record_csat(response: response)

      expect(empty_conversation.conversation_outcomes).to be_empty
    end
  end

  describe 'failure isolation' do
    it 'swallows and reports recording errors' do
      allow(conversation).to receive(:conversation_outcomes).and_raise(StandardError, 'recording exploded')
      tracker = instance_double(KonversioExceptionTracker, capture_exception: true)
      allow(KonversioExceptionTracker).to receive(:new).and_return(tracker)

      expect { recorder.record_eligibility(at: Time.current) }.not_to raise_error
      expect(tracker).to have_received(:capture_exception)
    end
  end
end
