# frozen_string_literal: true

FactoryBot.define do
  factory :captain_copilot_thread, class: 'Captain::CopilotThread' do
    account
    user
    sequence(:title) { |n| "Copilot thread #{n}" }
  end
end
