# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Pilot::QuotaHandoffService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: 'pending') }

  before do
    Pilot::Inbox.create!(assistant: assistant, inbox: inbox)
    account.enable_features!(:pilot)
  end

  it 'delegates to the handoff service with the quota source and reason category' do
    allow(Custom::Pilot::HandoffService).to receive(:call)

    described_class.call(conversation: conversation, assistant: assistant)

    expect(Custom::Pilot::HandoffService).to have_received(:call).with(
      hash_including(
        conversation: conversation,
        assistant: assistant,
        reason: 'quota_exhausted',
        source: 'quota',
        reason_category: 'quota_exhausted'
      )
    )
  end

  it 'hands the conversation off and records the episode as a quota-driven transfer' do
    Pilot::ConversationOutcomeRecorder.new(conversation: conversation, assistant: assistant).record_eligibility(at: 1.hour.ago)

    perform_enqueued_jobs { described_class.call(conversation: conversation, assistant: assistant) }

    expect(conversation.reload.status).to eq('open')
    expect(conversation.additional_attributes.dig('pilot_handoff', 'state')).to eq('handoff_requested')

    episode = conversation.conversation_outcomes.first
    expect(episode.handoff_at).to be_present
    expect(episode.handoff_reason_category).to eq('quota_exhausted')
    expect(episode.ai_reply_count).to eq(0)
    expect(episode.first_ai_reply_at).to be_nil
  end
end
