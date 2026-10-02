# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_faq_suggestion, class: 'Pilot::FaqSuggestion' do
    association :assistant, factory: :pilot_assistant
    account { assistant&.account }
    sequence(:question) { |n| "Suggested question #{n}?" }
    answer { 'A suggested answer.' }
    language { 'en' }
    source_count { 1 }
    status { :open }
  end
end
