require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account).reload }

  describe '#perform' do
    context 'when assignee_id is blank' do
      before do
        conversation.update!(assignee: agent, assignee_agent_bot: agent_bot)
      end

      it 'clears both human and bot assignees' do
        described_class.new(conversation: conversation, assignee_id: nil).perform

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when assigning a user' do
      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
      end

      it 'sets the agent and clears agent bot' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when assigning an agent bot' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: agent_bot.id,
          assignee_type: 'AgentBot'
        )
      end

      it 'sets the agent bot and clears human assignee' do
        conversation.update!(assignee: agent, assignee_agent_bot: nil)

        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
        expect(conversation.assignee_id).to be_nil
      end

      it 'sets the conversation to pending for bot handling' do
        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.status).to eq('pending')
      end
    end

    context 'when assigning a Pilot assistant' do
      let(:assistant) { create(:pilot_assistant, account: account) }
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: assistant.id,
          assignee_type: 'Pilot::Assistant'
        )
      end

      it 'clears the human assignee and sets the conversation to pending' do
        conversation.update!(assignee: agent, status: :open)

        result = service.perform

        conversation.reload
        expect(result).to eq(assistant)
        expect(conversation.assignee_id).to be_nil
        expect(conversation.ai_assignee).to eq(assistant)
        expect(conversation.status).to eq('pending')
      end
    end

    context 'when a human takes over an AI-held conversation' do
      let(:assistant) { create(:pilot_assistant, account: account) }

      before do
        conversation.update!(
          status: :pending,
          assignee: nil,
          assignee_agent_bot_id: assistant.id,
          ai_assignee_type: 'Pilot::Assistant',
          waiting_since: nil
        )
      end

      it 'clears the AI assignee, opens the conversation, and stamps waiting_since' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.ai_assignee).to be_nil
        expect(conversation.ai_assignee_type).to be_nil
        expect(conversation.status).to eq('open')
        expect(conversation.waiting_since).to be_present
      end
    end
  end
end
