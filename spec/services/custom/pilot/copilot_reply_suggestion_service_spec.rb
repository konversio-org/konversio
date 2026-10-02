require 'rails_helper'

# The reply-suggestion run reuses the ai-agents SDK runner boundary, so the
# specs mock `Agents::Runner.with_agents` exactly like copilot_service_spec.
RSpec.describe Custom::Pilot::CopilotReplySuggestionService do
  let(:account) { create(:account) }
  let(:service) do
    described_class.new(thread: thread, conversation_id: conversation.display_id, account: account)
  end
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:thread) { create(:pilot_copilot_thread, account: account, user: agent) }
  let(:fake_runner) { instance_double(Agents::AgentRunner) }
  let(:tool_start_callbacks) { [] }

  before do
    account.enable_features!(:pilot, :pilot_copilot)
    create(:inbox_member, user: agent, inbox: inbox)
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :incoming, content: 'Where is my order?')
    create(:pilot_copilot_message, copilot_thread: thread, account: account,
                                   message_type: :user, message: { content: 'Draft a reply.' })
    allow(Agents::Runner).to receive(:with_agents).and_return(fake_runner)
    allow(fake_runner).to receive(:on_tool_start) do |&block|
      tool_start_callbacks << block
      fake_runner
    end
  end

  def stub_runner_success(content)
    allow(fake_runner).to receive(:run).and_return(
      Agents::RunResult.new(output: content, messages: [], usage: nil, context: {})
    )
  end

  describe '#perform' do
    it 'persists a draft flagged as a reply suggestion and records usage' do
      stub_runner_success('Your order ships tomorrow.')

      result = service.perform

      expect(result.message['content']).to eq('Your order ships tomorrow.')
      expect(result.message['reply_suggestion']).to be(true)
      expect(service.credit_used?).to be(true)
    end

    it 'returns the existing response on a duplicate run without creating another' do
      stub_runner_success('First draft.')
      first = service.perform

      duplicate = described_class.new(thread: thread, conversation_id: conversation.display_id, account: account)

      expect { duplicate.perform }.not_to(change { thread.copilot_messages.assistant.count })
      expect(duplicate.persisted_assistant_message.id).to eq(first.id)
      expect(duplicate.credit_used?).to be(false)
    end

    it 'persists a failure response when the agent no longer has access to the conversation' do
      outsider_inbox = create(:inbox, account: account)
      outsider_conversation = create(:conversation, account: account, inbox: outsider_inbox)
      create(:message, account: account, conversation: outsider_conversation, inbox: outsider_inbox,
                       message_type: :incoming, content: 'Help')
      stub_runner_success('Should not be persisted.')

      result = described_class.new(
        thread: thread, conversation_id: outsider_conversation.display_id, account: account
      ).perform

      expect(result.message['content']).to eq(I18n.t('pilot.copilot.reply_suggestion.failed'))
      expect(result.message['reply_suggestion']).to be_nil
      expect(thread.copilot_messages.assistant.last.message['content']).not_to include('Should not be persisted')
    end

    it 'persists a discarded response without running when the latest public message is outgoing' do
      create(:message, account: account, conversation: conversation, inbox: inbox,
                       message_type: :outgoing, content: 'We replied already.')
      expect(Agents::Runner).not_to receive(:with_agents)

      result = service.perform

      expect(result.message['content']).to eq(I18n.t('pilot.copilot.reply_suggestion.discarded'))
      expect(service.credit_used?).to be(false)
    end

    it 'discards the draft when the target message changed during generation' do
      allow(fake_runner).to receive(:run) do
        create(:message, account: account, conversation: conversation, inbox: inbox,
                         message_type: :incoming, content: 'Are you there?')
        Agents::RunResult.new(output: 'Stale draft.', messages: [], usage: nil, context: {})
      end

      result = service.perform

      expect(result.message['content']).to eq(I18n.t('pilot.copilot.reply_suggestion.discarded'))
      expect(thread.copilot_messages.assistant.last.message['content']).not_to eq('Stale draft.')
      expect(service.credit_used?).to be(false)
    end

    it 'retries generation errors and persists a failure response after the final attempt' do
      allow(fake_runner).to receive(:run).and_raise(RuntimeError, 'provider down')

      perform_enqueued_jobs do
        Pilot::CopilotReplySuggestionJob.perform_later(
          thread_id: thread.id, conversation_id: conversation.display_id
        )
      end

      expect(fake_runner).to have_received(:run).exactly(3).times
      last = thread.copilot_messages.assistant.last
      expect(last.message['content']).to eq(I18n.t('pilot.copilot.reply_suggestion.failed'))
      expect(last.message['reply_suggestion']).to be_nil
    end

    it 'raises a recoverable Error when generation fails' do
      allow(fake_runner).to receive(:run).and_raise(RuntimeError, 'provider down')

      expect { service.perform }.to raise_error(described_class::Error, /provider down/)
    end

    it 'raises FeatureDisabledError when copilot is not enabled' do
      account.disable_features!(:pilot_copilot)

      expect { service.perform }.to raise_error(described_class::FeatureDisabledError)
    end
  end

  describe 'restricted tool set' do
    it 'includes a custom tool flagged as available for reply drafting' do
      account.enable_features!(:pilot_tools)
      flagged = create(:pilot_custom_tool, account: account, available_for_reply_drafting: true)

      names = service.send(:draft_tools).map(&:name)

      expect(names).to include(flagged.slug)
    end

    it 'withholds an unflagged custom tool' do
      account.enable_features!(:pilot_tools)
      unflagged = create(:pilot_custom_tool, account: account, available_for_reply_drafting: false)

      names = service.send(:draft_tools).map(&:name)

      expect(names).not_to include(unflagged.slug)
    end

    it 'withholds chat-only tools' do
      names = service.send(:draft_tools).map(&:name)

      expect(names).not_to include('search_conversation', 'get_conversation', 'get_contact')
    end

    it 'applies the permission filter on top of the restricted set' do
      account.disable_features!(:pilot_tools)
      flagged = create(:pilot_custom_tool, account: account, available_for_reply_drafting: true)

      names = service.send(:draft_tools).map(&:name)

      expect(names).not_to include(flagged.slug)
    end
  end
end
