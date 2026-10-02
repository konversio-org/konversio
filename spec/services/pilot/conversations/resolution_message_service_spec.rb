# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pilot::Conversations::ResolutionMessageService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }

  it 'posts the assistant configured message authored by the assistant' do
    assistant = create(:pilot_assistant, account: account, config: { 'resolution_message' => 'All set!' })

    described_class.call(conversation: conversation, assistant: assistant)

    message = conversation.messages.outgoing.last
    expect(message.content).to eq('All set!')
    expect(message.sender).to eq(assistant)
  end

  it 'posts the localized default when no custom message is set' do
    assistant = create(:pilot_assistant, account: account, config: {})

    described_class.call(conversation: conversation, assistant: assistant)

    expect(conversation.messages.outgoing.last.content).to eq(I18n.t('conversations.pilot.resolution'))
  end

  it 'uses the account locale for the default message' do
    account.update!(locale: 'nl')
    assistant = create(:pilot_assistant, account: account, config: {})

    described_class.call(conversation: conversation, assistant: assistant)

    expected = I18n.with_locale('nl') { I18n.t('conversations.pilot.resolution') }
    expect(conversation.messages.outgoing.last.content).to eq(expected)
  end

  it 'posts nothing when the toggle is off' do
    assistant = create(:pilot_assistant, account: account, config: { 'send_inactivity_resolution_message' => false })

    expect { described_class.call(conversation: conversation, assistant: assistant) }
      .not_to(change { conversation.messages.count })
  end
end
