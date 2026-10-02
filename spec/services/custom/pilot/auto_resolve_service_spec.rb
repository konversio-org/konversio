# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Pilot::AutoResolveService do
  subject(:service) { described_class.new(conversation: conversation, assistant: assistant, account: account) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:pilot_assistant, account: account, config: assistant_config) }
  let(:assistant_config) { {} }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, status: :pending, last_activity_at: 2.hours.ago).reload
  end

  before do
    account.enable_features!(:pilot, :pilot_autoresolve)
    account.update!(settings: { pilot_auto_resolve_mode: 'legacy' })
    Pilot::Inbox.create!(inbox: inbox, assistant: assistant)
  end

  describe 'mode routing' do
    it 'does nothing when the assistant mode is disabled' do
      assistant.update!(config: { 'auto_resolve_mode' => 'disabled' })

      expect { service.perform }.not_to(change { conversation.reload.status })
    end

    it 'uses the evaluated path when the assistant overrides the account mode' do
      assistant.update!(config: { 'auto_resolve_mode' => 'evaluated' })
      evaluator = instance_double(Custom::Pilot::ResolutionEvaluator)
      allow(Custom::Pilot::ResolutionEvaluator).to receive(:new).and_return(evaluator)
      allow(evaluator).to receive(:perform).and_return(
        Custom::Pilot::ResolutionEvaluator::Result.new(complete: true, reason: 'all done')
      )

      service.perform

      expect(conversation.reload.status).to eq('resolved')
    end

    it 'falls back to the account mode when the assistant has none (legacy assistants)' do
      assistant.update_column(:config, {}) # rubocop:disable Rails/SkipsModelValidations

      service.perform

      expect(conversation.reload.status).to eq('resolved')
    end
  end

  describe 'per-assistant threshold' do
    let(:assistant_config) { { 'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 180 } }

    it 'leaves a conversation alone when idle less than the assistant threshold' do
      conversation.update!(last_activity_at: 2.hours.ago)

      expect { service.perform }.not_to(change { conversation.reload.status })
    end

    it 'resolves when idle past the assistant threshold' do
      conversation.update!(last_activity_at: 4.hours.ago)

      service.perform

      expect(conversation.reload.status).to eq('resolved')
    end
  end

  describe 'resolution message' do
    it 'posts the assistant custom message when configured' do
      assistant.update!(config: { 'auto_resolve_mode' => 'legacy', 'resolution_message' => 'Custom goodbye' })

      service.perform

      message = conversation.messages.outgoing.where(sender: assistant, private: false).last
      expect(message.content).to eq('Custom goodbye')
    end

    it 'posts the localized default when no custom message is set' do
      service.perform

      message = conversation.messages.outgoing.where(sender: assistant, private: false).last
      expect(message.content).to eq(I18n.t('conversations.pilot.resolution'))
    end

    it 'resolves silently when the toggle is off' do
      assistant.update!(config: { 'auto_resolve_mode' => 'legacy', 'send_inactivity_resolution_message' => false })

      service.perform

      expect(conversation.reload.status).to eq('resolved')
      expect(conversation.messages.outgoing.where(sender: assistant, private: false)).to be_empty
      expect(conversation.messages.where(private: true)).not_to be_empty
    end
  end

  describe 'evaluated path' do
    let(:assistant_config) { { 'auto_resolve_mode' => 'evaluated' } }
    let(:evaluator) { instance_double(Custom::Pilot::ResolutionEvaluator) }

    before do
      allow(Custom::Pilot::ResolutionEvaluator).to receive(:new).and_return(evaluator)
    end

    it 'resolves on a complete verdict' do
      allow(evaluator).to receive(:perform).and_return(
        Custom::Pilot::ResolutionEvaluator::Result.new(complete: true, reason: 'done')
      )

      service.perform

      expect(conversation.reload.status).to eq('resolved')
    end

    it 'hands off on an incomplete verdict' do
      instance_double(Custom::Pilot::HandoffService)
      allow(Custom::Pilot::HandoffService).to receive(:call)
      allow(evaluator).to receive(:perform).and_return(
        Custom::Pilot::ResolutionEvaluator::Result.new(complete: false, reason: 'still waiting')
      )

      service.perform

      expect(Custom::Pilot::HandoffService).to have_received(:call).with(
        hash_including(conversation: conversation, assistant: assistant, source: 'inactivity')
      )
    end

    it 'does not resolve when the customer replied during the LLM call' do
      allow(evaluator).to receive(:perform) do
        conversation.update!(last_activity_at: Time.current)
        Custom::Pilot::ResolutionEvaluator::Result.new(complete: true, reason: 'done')
      end

      expect { service.perform }.not_to(change { conversation.reload.status })
    end

    it 'leaves the conversation pending on evaluator failure' do
      allow(evaluator).to receive(:perform).and_raise(Custom::Pilot::ResolutionEvaluator::Error, 'boom')

      expect { service.perform }.not_to(change { conversation.reload.status })
    end
  end

  describe 'locked transition' do
    it 'skips a conversation resolved by a human during processing' do
      assistant.update!(config: { 'auto_resolve_mode' => 'legacy' })
      resolver_spy = Custom::Pilot::ConversationResolver
      allow(resolver_spy).to receive(:resolve!).and_wrap_original do |original, **kwargs|
        conversation.update!(status: :resolved)
        original.call(**kwargs)
      end
      allow(conversation).to receive(:with_lock).and_wrap_original do |original, &block|
        conversation.update!(status: :resolved)
        original.call(&block)
      end

      service.perform

      expect(resolver_spy).not_to have_received(:resolve!)
      expect(conversation.reload.status).to eq('resolved')
    end
  end
end
