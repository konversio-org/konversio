# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_scenario, class: 'Pilot::Scenario' do
    association :assistant, factory: :pilot_assistant
    account { assistant&.account }
    sequence(:title) { |n| "Scenario #{n}" }
    description { 'A test scenario.' }
    instruction { 'Be helpful and polite.' }
    enabled { true }
  end
end
