# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_campaign_recipient, class: 'Pilot::CampaignRecipient' do
    account
    contact
    campaign { association :campaign, account: account }
    inbox { campaign.inbox }
    status { :queued }
  end
end
