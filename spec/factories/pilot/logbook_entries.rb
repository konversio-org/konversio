# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_logbook_entry, class: 'Pilot::LogbookEntry' do
    content { 'Customer prefers email communication over phone.' }
    account
    contact
  end
end
