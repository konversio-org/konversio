# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_assistant, class: 'Pilot::Assistant' do
    account
    sequence(:name) { |n| "Assistant #{n}" }
    description { 'A helpful test assistant.' }
    config { {} }
  end
end
