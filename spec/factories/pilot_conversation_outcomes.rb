# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_conversation_outcome, class: 'Pilot::ConversationOutcome' do
    account
    inbox { association :inbox, account: account }
    assistant { association :pilot_assistant, account: account }
    conversation { association :conversation, account: account, inbox: inbox }
    episode_trigger { 'initial' }
    started_at { Time.current }
  end
end
