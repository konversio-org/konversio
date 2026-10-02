# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Conversations::ResolutionJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account, config: { 'auto_resolve_mode' => 'legacy' }) }

  before do
    account.enable_features!(:pilot, :pilot_autoresolve)
    account.update!(settings: { pilot_auto_resolve_mode: 'legacy' })
    Pilot::Inbox.create!(assistant: assistant, inbox: inbox)
  end

  def create_idle_conversation(idle_for:, status: :pending)
    create(:conversation, account: account, inbox: inbox, status: status, last_activity_at: idle_for.ago).reload
  end

  it 'resolves a conversation idle past the assistant threshold' do
    assistant.update!(config: { 'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 30 })
    conversation = create_idle_conversation(idle_for: 45.minutes)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('resolved')
  end

  it 'leaves a conversation idle less than the assistant threshold' do
    assistant.update!(config: { 'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 30 })
    conversation = create_idle_conversation(idle_for: 10.minutes)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'selects a conversation whose short-threshold assistant qualifies even when others require longer idleness' do
    assistant.update!(config: { 'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 30 })
    other_inbox = create(:inbox, account: account)
    other_assistant = create(:pilot_assistant, account: account, config: { 'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 1440 })
    Pilot::Inbox.create!(assistant: other_assistant, inbox: other_inbox)
    conversation = create_idle_conversation(idle_for: 45.minutes)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('resolved')
  end

  it 'skips assistants whose mode is disabled' do
    assistant.update!(config: { 'auto_resolve_mode' => 'disabled' })
    conversation = create_idle_conversation(idle_for: 3.hours)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'skips conversations already routed to a human' do
    conversation = create_idle_conversation(idle_for: 3.hours)
    conversation.update!(additional_attributes: { 'pilot_handoff' => { 'state' => 'handoff_requested' } })

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'does not touch open conversations' do
    conversation = create_idle_conversation(idle_for: 3.hours)
    conversation.update!(status: :open)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('open')
  end

  it 'skips email inboxes' do
    email_channel = create(:channel_email, account: account)
    email_inbox = create(:inbox, account: account, channel: email_channel)
    Pilot::Inbox.create!(assistant: assistant, inbox: email_inbox)
    conversation = create(:conversation, account: account, inbox: email_inbox, status: :pending, last_activity_at: 3.hours.ago)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'does nothing when the account mode is disabled' do
    account.update!(settings: { pilot_auto_resolve_mode: 'disabled' })
    conversation = create_idle_conversation(idle_for: 3.hours)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('pending')
  end

  it 'continues with remaining conversations when one is deleted mid-sweep' do
    deleted = create_idle_conversation(idle_for: 3.hours)
    create_idle_conversation(idle_for: 3.hours)
    allow(Custom::Pilot::AutoResolveService).to receive(:new) do |conversation:, **_kwargs|
      raise ActiveRecord::RecordNotFound if conversation.id == deleted.id

      instance_double(Custom::Pilot::AutoResolveService, perform: nil)
    end

    expect { described_class.perform_now(account: account) }.not_to raise_error
  end
end
