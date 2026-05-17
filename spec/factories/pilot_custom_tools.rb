# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_custom_tool, class: 'Pilot::CustomTool' do
    account
    sequence(:title) { |n| "Custom Tool #{n}" }
    description { 'A test tool.' }
    endpoint_url { 'https://example.com/api/things' }
    http_method { 'GET' }
    enabled { true }
  end
end
