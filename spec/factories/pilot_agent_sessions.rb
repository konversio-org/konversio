# frozen_string_literal: true

FactoryBot.define do
  factory :pilot_agent_session, class: 'Pilot::AgentSession' do
    association :assistant, factory: :pilot_assistant
    account { assistant&.account }
    llm_model { 'llm-test-model' }
    session_kind { :autopilot }
    subject { association :conversation, account: account }
    result { association :message, account: account, conversation: subject }

    trait :copilot do
      session_kind { :copilot }
      subject { association :pilot_copilot_thread, account: account }
      result { association :pilot_copilot_message, account: account, copilot_thread: subject }
    end
  end
end
