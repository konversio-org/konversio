# frozen_string_literal: true

FactoryBot.define do
  factory :captain_copilot_message, class: 'Captain::CopilotMessage' do
    account
    association :copilot_thread, factory: :captain_copilot_thread
    message_type { :user }
    message { { content: 'Hello' } }
  end
end
