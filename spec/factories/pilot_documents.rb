# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_document, class: 'Pilot::Document' do
    association :assistant, factory: :pilot_assistant
    account { assistant&.account }
    sequence(:external_link) { |n| "https://example.com/help/article-#{n}" }
    name { 'Help article' }
    content { 'This is the body of a help article.' }
    status { :in_progress }
  end
end
