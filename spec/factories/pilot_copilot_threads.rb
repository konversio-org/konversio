# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_copilot_thread, class: 'Pilot::CopilotThread' do
    account
    user
    sequence(:title) { |n| "Copilot thread #{n}" }
  end
end
