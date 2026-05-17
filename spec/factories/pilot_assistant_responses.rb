# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_assistant_response, class: 'Pilot::AssistantResponse' do
    association :assistant, factory: :pilot_assistant
    account { assistant&.account }
    sequence(:question) { |n| "Question #{n}?" }
    answer { 'An answer that explains things.' }
    status { :approved }
  end
end
