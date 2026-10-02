# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_faq_observation, class: 'Pilot::FaqObservation' do
    conversation
    account { conversation&.account }
    sequence(:generated_question) { |n| "Generated question #{n}?" }
    generated_answer { 'A generated answer.' }
    language { 'en' }
    status { :discarded }
  end
end
