# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_copilot_message, class: 'Pilot::CopilotMessage' do
    account
    association :copilot_thread, factory: :pilot_copilot_thread
    message_type { :user }
    message { { content: 'Hello' } }
  end
end
