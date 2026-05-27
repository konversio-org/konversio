require 'rails_helper'

# Direct coverage for the job. The service itself is exercised in
# spec/services/custom/pilot/autopilot_service_spec.rb; here we focus on the
# job's branching: eligibility filters, normal-reply persistence, handover
# side effects, error swallowing, and typing-event bookends.
RSpec.describe Pilot::AutopilotInferenceJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Need help') }
  let(:assistant) do
    create(:pilot_assistant, account: account, config: { 'handoff_message' => 'A teammate will help from here.' })
  end
  let(:dispatcher) { instance_double(Dispatcher, dispatch: true) }

  before do
    account.enable_features!(:pilot, :pilot_autopilot)
    Pilot::Inbox.create!(assistant: assistant, inbox: inbox)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
  end

  describe 'no-op cases' do
    it 'returns when message_id refers to a missing record' do
      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      expect { described_class.perform_now(message_id: -1) }.not_to raise_error
    end

    it 'skips outgoing (non-incoming) messages' do
      outgoing = create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation)

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      described_class.perform_now(message_id: outgoing.id)
    end

    it 'skips template messages' do
      template = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :template)

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      described_class.perform_now(message_id: template.id)
    end

    it 'skips private messages' do
      note = create(:message, account: account, inbox: inbox, conversation: conversation, private: true)

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      described_class.perform_now(message_id: note.id)
    end

    it 'skips when the pilot master feature flag is off' do
      account.disable_features!(:pilot)

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      described_class.perform_now(message_id: message.id)
    end

    it 'skips when pilot_autopilot is off' do
      account.disable_features!(:pilot_autopilot)

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      described_class.perform_now(message_id: message.id)
    end

    it 'skips when the inbox has no assistant attached' do
      message
      Pilot::Inbox.delete_all

      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      expect { described_class.perform_now(message_id: message.id) }
        .not_to(change(Message, :count))
    end
  end

  describe 'normal reply path' do
    let(:result) { service_result(reply: 'Here is the answer.') }
    let(:service) { instance_double(Custom::Pilot::AutopilotService, perform: result) }

    before do
      allow(Custom::Pilot::AutopilotService)
        .to receive(:new).with(assistant: assistant, conversation: conversation, account: account)
                         .and_return(service)
    end

    it 'creates a single outgoing message with the assistant as sender' do
      expect do
        described_class.perform_now(message_id: message.id)
      end.to change { conversation.messages.outgoing.count }.by(1)

      reply = conversation.messages.outgoing.last
      expect(reply.content).to eq('Here is the answer.')
      expect(reply.sender).to eq(assistant)
    end

    it 'leaves the conversation status unchanged' do
      message
      initial_status = conversation.reload.status

      described_class.perform_now(message_id: message.id)

      expect(conversation.reload.status).to eq(initial_status)
    end

    it 'does not append an activity row' do
      expect do
        described_class.perform_now(message_id: message.id)
      end.not_to(change { conversation.messages.activity.count })
    end
  end

  describe 'handover path' do
    let(:handover) { Custom::Pilot::HandoverEvaluator::Result.new(handover?: true, reason: 'sentinel') }
    let(:service) do
      instance_double(Custom::Pilot::AutopilotService,
                      perform: service_result(reply: '[handover]', handover: handover))
    end

    let(:online_agent) { create(:user, account: account) }

    before do
      # bot_handoff! is only invoked when the conversation isn't already open;
      # putting it in :pending forces the transition path we want to assert.
      conversation.update!(status: :pending)
      allow(Custom::Pilot::AutopilotService).to receive(:new).and_return(service)

      # The job now skips handoff when no agents are online and posts an
      # offline-acknowledgement instead. Wire one inbox member with online
      # presence so we exercise the online path covered by this describe.
      create(:inbox_member, user: online_agent, inbox: inbox)
      allow(OnlineStatusTracker).to receive(:get_available_users)
        .with(account.id).and_return(online_agent.id.to_s => 'online')
    end

    it 'transitions the conversation back to open via bot_handoff!' do
      described_class.perform_now(message_id: message.id)

      expect(conversation.reload).to be_open
    end

    it 'posts the assistant-configured handoff message as outgoing' do
      expect do
        described_class.perform_now(message_id: message.id)
      end.to change { conversation.messages.outgoing.count }.by(1)

      expect(conversation.messages.outgoing.last.content).to eq('A teammate will help from here.')
    end

    it 'falls back to the i18n default when no handoff message is configured' do
      assistant.update!(config: {})

      described_class.perform_now(message_id: message.id)

      expect(conversation.messages.outgoing.last.content).to eq(I18n.t('conversations.pilot.handoff'))
    end

    it 'appends an activity message referencing the handover reason' do
      expect do
        described_class.perform_now(message_id: message.id)
      end.to change { conversation.messages.activity.count }.by(1)

      expect(conversation.messages.activity.last.content).to include('sentinel')
    end

    it 'writes pilot_handoff metadata describing the handoff envelope' do
      freeze_time = Time.zone.parse('2026-05-26 12:00:00')
      travel_to(freeze_time) do
        described_class.perform_now(message_id: message.id)
      end

      handoff = conversation.reload.additional_attributes['pilot_handoff']
      expect(handoff).to include('state' => 'handoff_requested')
      expect(handoff['requested_at']).to eq(freeze_time.iso8601)
    end

    it 'leaves the conversation open and schedules no resume timer' do
      expect do
        described_class.perform_now(message_id: message.id)
      end.not_to have_enqueued_job(described_class)

      expect(conversation.reload).to be_open
    end

    it 'dispatches pilot.autopilot.handover.triggered with the conversation envelope' do
      expect(Custom::Pilot::EventDispatcher).to receive(:dispatch).with(
        'pilot.autopilot.handover.triggered',
        hash_including(
          account_id: account.id,
          assistant_id: assistant.id,
          conversation_envelope: hash_including(id: conversation.id, display_id: conversation.display_id),
          reason: 'sentinel'
        ),
        hash_including(time: kind_of(Time), account: account)
      )

      described_class.perform_now(message_id: message.id)
    end
  end

  describe 'failure handling' do
    let(:service) { instance_double(Custom::Pilot::AutopilotService) }

    before do
      allow(Custom::Pilot::AutopilotService).to receive(:new).and_return(service)
    end

    it 'logs and swallows FeatureDisabledError' do
      allow(service).to receive(:perform).and_raise(Custom::Pilot::AutopilotService::FeatureDisabledError, 'off')
      expect(Rails.logger).to receive(:warn).with(/feature disabled/)

      expect { described_class.perform_now(message_id: message.id) }.not_to raise_error
      expect(conversation.messages.outgoing).to be_empty
    end

    it 'hands off to a human on AutopilotService::Error instead of going silent' do
      allow(service).to receive(:perform).and_raise(Custom::Pilot::AutopilotService::Error, 'upstream down')
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(message_id: message.id) }.not_to raise_error

      expect(conversation.reload).to be_open
      expect(conversation.messages.outgoing.last.content).to eq(I18n.t('conversations.pilot.handoff_error'))
    end

    # The job only rescues the two Pilot-specific error classes above. An
    # unexpected StandardError propagates so ActiveJob's retry/dead-set
    # machinery sees it; this asserts that contract.
    it 'lets unexpected StandardError propagate' do
      allow(service).to receive(:perform).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(message_id: message.id) }
        .to raise_error(StandardError, 'boom')
    end
  end

  describe 'typing events' do
    let(:result) { service_result(reply: 'ok') }
    let(:service) { instance_double(Custom::Pilot::AutopilotService, perform: result) }

    before do
      allow(Custom::Pilot::AutopilotService).to receive(:new).and_return(service)
    end

    it 'dispatches CONVERSATION_TYPING_ON then CONVERSATION_TYPING_OFF on success' do
      expect(dispatcher).to receive(:dispatch)
        .with(Events::Types::CONVERSATION_TYPING_ON, kind_of(Time), conversation: conversation, user: assistant)
        .ordered
      expect(dispatcher).to receive(:dispatch)
        .with(Events::Types::CONVERSATION_TYPING_OFF, kind_of(Time), conversation: conversation, user: assistant)
        .ordered

      described_class.perform_now(message_id: message.id)
    end

    it 'still dispatches CONVERSATION_TYPING_OFF when inference raises a handled error' do
      allow(service).to receive(:perform).and_raise(Custom::Pilot::AutopilotService::Error, 'down')
      allow(Rails.logger).to receive(:error)

      expect(dispatcher).to receive(:dispatch)
        .with(Events::Types::CONVERSATION_TYPING_OFF, kind_of(Time), conversation: conversation, user: assistant)
        .at_least(:once)

      described_class.perform_now(message_id: message.id)
    end

    it 'still dispatches CONVERSATION_TYPING_OFF when inference raises an unexpected error' do
      allow(service).to receive(:perform).and_raise(StandardError, 'kaboom')

      expect(dispatcher).to receive(:dispatch)
        .with(Events::Types::CONVERSATION_TYPING_OFF, kind_of(Time), conversation: conversation, user: assistant)
        .at_least(:once)

      expect { described_class.perform_now(message_id: message.id) }.to raise_error(StandardError)
    end
  end

  def service_result(reply:, handover: nil)
    Custom::Pilot::AutopilotService::Result.new(
      reply: reply,
      invoked_tool_names: [],
      handover: handover || Custom::Pilot::HandoverEvaluator::Result.new(handover?: false, reason: nil)
    )
  end
end
