# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation AI assignee', type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '#ai_assignee' do
    it 'resolves a Pilot::Assistant when the type discriminator is set' do
      conversation.update!(assignee_agent_bot_id: assistant.id, ai_assignee_type: 'Pilot::Assistant')

      expect(conversation.reload.ai_assignee).to eq(assistant)
    end

    it 'reads a NULL type with a present id as the legacy AgentBot case' do
      agent_bot = create(:agent_bot, account: account)
      conversation.update!(assignee_agent_bot: agent_bot)

      expect(conversation.reload.ai_assignee).to eq(agent_bot)
    end

    it 'is nil when no AI assignee is set' do
      expect(conversation.ai_assignee).to be_nil
    end
  end

  describe 'mutual exclusion of owners' do
    it 'clears the human assignee when a Pilot assistant is set as AI assignee' do
      agent = create(:user, account: account)
      conversation.update!(assignee: agent)
      conversation.ai_assignee = assistant
      conversation.save!

      expect(conversation.reload.assignee_id).to be_nil
      expect(conversation.ai_assignee).to eq(assistant)
    end

    it 'clears the AI assignee when a human assignee is set' do
      conversation.update!(assignee_agent_bot_id: assistant.id, ai_assignee_type: 'Pilot::Assistant')
      agent = create(:user, account: account)
      conversation.update!(assignee: agent)

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
      expect(conversation.ai_assignee_type).to be_nil
    end
  end

  describe 'unassigned / assigned scopes' do
    it 'treats an AI-held conversation as assigned' do
      conversation.update!(assignee_agent_bot_id: assistant.id, ai_assignee_type: 'Pilot::Assistant')

      expect(Conversation.unassigned).not_to include(conversation)
      expect(Conversation.assigned).to include(conversation)
    end

    it 'keeps fully unassigned conversations in the unassigned scope' do
      expect(Conversation.unassigned).to include(conversation)
    end
  end

  describe '#bot_handoff!' do
    it 'clears the AI assignee and opens the conversation' do
      conversation.update!(status: :pending, assignee_agent_bot_id: assistant.id, ai_assignee_type: 'Pilot::Assistant')

      conversation.bot_handoff!

      conversation.reload
      expect(conversation.ai_assignee).to be_nil
      expect(conversation.ai_assignee_type).to be_nil
      expect(conversation.status).to eq('open')
      expect(conversation.waiting_since).to be_present
    end
  end

  describe '#assigned_entity and #assignee_type' do
    it 'returns the AI assignee with its discriminator' do
      conversation.update!(assignee_agent_bot_id: assistant.id, ai_assignee_type: 'Pilot::Assistant')

      expect(conversation.assigned_entity).to eq(assistant)
      expect(conversation.assignee_type).to eq('Pilot::Assistant')
    end

    it 'keeps legacy agent bot rows reading as AgentBot' do
      agent_bot = create(:agent_bot, account: account)
      conversation.update!(assignee_agent_bot: agent_bot)

      expect(conversation.assigned_entity).to eq(agent_bot)
      expect(conversation.assignee_type).to eq('AgentBot')
    end
  end

  describe 'creation-time engagement gating' do
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

    before { Pilot::Inbox.create!(assistant: assistant, inbox: inbox) }

    it 'starts pending with the assistant as AI assignee when the assistant engages' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect(conversation.status).to eq('pending')
      expect(conversation.ai_assignee).to eq(assistant)
    end

    it 'starts open with no AI assignee when the audience does not match' do
      assistant.update!(config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['vip'] }]
                          }
                        })
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect(conversation.status).to eq('open')
      expect(conversation.ai_assignee).to be_nil
    end

    it 'starts pending for a matching contact' do
      contact.update_labels(['vip'])
      assistant.update!(config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['vip'] }]
                          }
                        })
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect(conversation.status).to eq('pending')
      expect(conversation.ai_assignee).to eq(assistant)
    end

    it 'starts open when the response window excludes the current time' do
      inbox.update!(working_hours_enabled: true)
      allow_any_instance_of(Inbox).to receive(:out_of_office?).and_return(true) # rubocop:disable RSpec/AnyInstance
      assistant.update!(config: { 'response_window' => 'business_hours' })

      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect(conversation.status).to eq('open')
      expect(conversation.ai_assignee).to be_nil
    end

    it 'does not re-gate in-flight conversations when the audience changes' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      expect(conversation.status).to eq('pending')

      assistant.update!(config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['vip'] }]
                          }
                        })

      expect(conversation.reload.status).to eq('pending')
      expect(conversation.ai_assignee).to eq(assistant)
    end

    it 'keeps legacy pending behavior when an external bot is also active' do
      agent_bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, agent_bot: agent_bot, inbox: inbox, status: :active)
      assistant.update!(config: {
                          'audience' => {
                            'combinator' => 'and',
                            'conditions' => [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => ['vip'] }]
                          }
                        })

      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect(conversation.status).to eq('pending')
      expect(conversation.ai_assignee).to be_nil
    end
  end
end
