# frozen_string_literal: true

FactoryBot.define do
  factory :call do
    after(:build) do |call|
      call.account ||= create(:account)
      call.inbox ||= create(:inbox, account: call.account)
      call.conversation ||= create(:conversation, account: call.account, inbox: call.inbox, contact: call.contact)
      call.contact ||= call.conversation.contact
    end

    sequence(:provider_call_id) { |n| "CA#{n.to_s.rjust(8, '0')}" }
    provider { :twilio }
    direction { :incoming }
    status { 'ringing' }
  end
end
