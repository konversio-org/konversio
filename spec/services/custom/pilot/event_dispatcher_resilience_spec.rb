require 'rails_helper'

RSpec.describe Custom::Pilot::EventDispatcher do
  # Resilience-focused tests for the dispatcher; live in their own file
  # because they stub Rails.configuration.dispatcher per scenario.
  let!(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, status: :resolved) }
  let!(:assistant) { create(:pilot_assistant, account: account) }
  let(:envelope) do
    Custom::Pilot::ConversationPayloadBuilder.call(conversation: conversation, assistant: assistant)
  end

  def stub_raising_host_dispatcher(error = StandardError.new('host listener boom'))
    dispatcher = instance_double(Dispatcher)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    allow(dispatcher).to receive(:dispatch).and_raise(error)
    dispatcher
  end

  it 'still persists the pilot_events row when the host dispatcher listener raises' do
    stub_raising_host_dispatcher

    expect do
      described_class.dispatch(
        'pilot.autopilot.handover.triggered',
        { account_id: account.id, conversation_envelope: envelope, conversation_db_id: conversation.id },
        account: account
      )
    end.to change(Pilot::Event, :count).by(1)
                                       .and change(Pilot::ReportingEvent, :count).by(2)
  end

  it 'leaves the conversation state untouched when a listener raises' do
    stub_raising_host_dispatcher

    expect do
      described_class.dispatch(
        'pilot.autopilot.handover.triggered',
        { account_id: account.id, conversation_envelope: envelope, conversation_db_id: conversation.id },
        account: account
      )
    end.not_to(change { conversation.reload.status })
  end

  it 'reports the listener exception via Rails.error when available' do
    stub_raising_host_dispatcher(StandardError.new('kaboom'))
    hide_const('KonversioExceptionTracker') if defined?(KonversioExceptionTracker)

    reports = []
    fake_error = Class.new do
      define_method(:report) { |error, context: {}| reports << [error, context] }
    end.new
    allow(Rails).to receive(:error).and_return(fake_error)

    described_class.dispatch(
      'pilot.briefing.completed',
      { account_id: account.id },
      account: account
    )

    expect(reports).not_to be_empty
    expect(reports.first[0]).to be_a(StandardError)
    expect(reports.first[1]).to include(listener: :host_dispatcher, event: 'pilot.briefing.completed')
  end

  # §8 race-condition pattern: hook the failure stub to fire during dispatch
  # and assert that subsequent listeners ran anyway. Listener isolation is
  # the dispatcher's primary contract; this spec defends it directly rather
  # than relying on a side-effect count.
  it 'still records reporting_events after the host dispatcher listener has already raised' do
    dispatcher = instance_double(Dispatcher)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    persisted_before_failure = nil
    allow(dispatcher).to receive(:dispatch) do
      # By the time the host-dispatcher listener runs, the persist_event
      # listener has already executed. Capture that and then raise.
      persisted_before_failure = Pilot::Event.where(account_id: account.id).count
      raise StandardError, 'host listener boom'
    end

    described_class.dispatch(
      'pilot.autopilot.handover.triggered',
      { account_id: account.id, conversation_envelope: envelope, conversation_db_id: conversation.id },
      account: account
    )

    expect(persisted_before_failure).to eq(1)
    expect(Pilot::ReportingEvent.where(conversation_id: conversation.id).count).to eq(2)
  end

  # If the persistence listener itself raises, the host listener must still
  # be reached — i.e. listeners run independently, not as a chain.
  it 'still calls the host dispatcher when persist_event raises' do
    captured = []
    dispatcher = instance_double(Dispatcher)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    allow(dispatcher).to receive(:dispatch) { |name, _, _| captured << name }
    allow(Pilot::Event).to receive(:create!).and_raise(StandardError, 'persist boom')

    described_class.dispatch(
      'pilot.briefing.completed',
      { account_id: account.id },
      account: account
    )

    expect(captured).to eq(['pilot.briefing.completed'])
  end

  it 'still records reporting events when persist_event raises' do
    allow(Pilot::Event).to receive(:create!).and_raise(StandardError, 'persist boom')
    dispatcher = instance_double(Dispatcher, dispatch: true)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)

    expect do
      described_class.dispatch(
        'pilot.autopilot.handover.triggered',
        { account_id: account.id, conversation_envelope: envelope, conversation_db_id: conversation.id },
        account: account
      )
    end.to change(Pilot::ReportingEvent, :count).by(2)
  end

  it 'reports every failing listener separately (not just the first)' do
    hide_const('KonversioExceptionTracker') if defined?(KonversioExceptionTracker)
    reports = []
    fake_error = Class.new do
      define_method(:report) { |_error, context: {}| reports << context }
    end.new
    allow(Rails).to receive(:error).and_return(fake_error)
    allow(Pilot::Event).to receive(:create!).and_raise(StandardError, 'persist boom')
    stub_raising_host_dispatcher

    described_class.dispatch('pilot.briefing.completed', { account_id: account.id }, account: account)

    failing_listeners = reports.map { |c| c[:listener] }
    expect(failing_listeners).to include(:persist_event, :host_dispatcher)
  end
end
