require 'rails_helper'

RSpec.describe Custom::Pilot::PromiseGuardService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:pilot_assistant, account: account) }
  let(:run_result) { autopilot_result(reply: 'I will check on this and get back to you.') }
  let(:repaired_result) { autopilot_result(reply: 'Your order is on its way; tracking shows it arrives Friday.') }

  def autopilot_result(reply:, handover: false)
    Custom::Pilot::AutopilotService::Result.new(
      reply: reply,
      invoked_tool_names: [],
      handover: Custom::Pilot::HandoverEvaluator::Result.new(handover?: handover, reason: handover ? 'sentinel' : nil)
    )
  end

  def verdict(status, reason = nil)
    Pilot::PromiseGuard::Verdict.new(status: status, reason_category: reason, model: 'gpt-guard-test')
  end

  def call_service
    described_class.call(conversation: conversation, assistant: assistant, run_result: run_result)
  end

  context 'when the account setting is disabled' do
    it 'returns the original result without any detector call' do
      expect(Pilot::PromiseGuard).not_to receive(:call)

      outcome = call_service

      expect(outcome.result).to eq(run_result)
      expect(outcome).not_to be_handed_off
    end
  end

  context 'when the account setting is enabled' do
    before { account.update!(pilot_false_promise_guard_enabled: true) }

    it 'skips detection when the run already requested a handoff' do
      run_result = autopilot_result(reply: 'Let me get a human. [handover]', handover: true)
      expect(Pilot::PromiseGuard).not_to receive(:call)

      outcome = described_class.call(conversation: conversation, assistant: assistant, run_result: run_result)

      expect(outcome.result.reply).to include('[handover]')
      expect(outcome).not_to be_handed_off
    end

    it 'skips detection for a blank reply' do
      run_result = autopilot_result(reply: nil)
      expect(Pilot::PromiseGuard).not_to receive(:call)

      outcome = described_class.call(conversation: conversation, assistant: assistant, run_result: run_result)

      expect(outcome).not_to be_handed_off
    end

    it 'delivers the original reply when the first pass is safe' do
      allow(Pilot::PromiseGuard).to receive(:call).and_return(verdict(:safe, 'no_future_commitment'))
      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      outcome = call_service

      expect(outcome.result).to eq(run_result)
    end

    it 'delivers the original reply when the first pass is inconclusive' do
      allow(Pilot::PromiseGuard).to receive(:call).and_return(verdict(:inconclusive))
      expect(Custom::Pilot::AutopilotService).not_to receive(:new)

      outcome = call_service

      expect(outcome.result).to eq(run_result)
      expect(outcome).not_to be_handed_off
    end

    it 'delivers the original reply when the detector itself errors before any detection' do
      allow(Pilot::PromiseGuard).to receive(:call).and_raise(StandardError, 'detector exploded')
      allow(Rails.logger).to receive(:error)

      outcome = call_service

      expect(outcome.result).to eq(run_result)
      expect(outcome).not_to be_handed_off
      expect(Rails.logger).to have_received(:error).with(/guard error/)
    end

    context 'with a promise verdict' do
      let(:repair_service) { instance_double(Custom::Pilot::AutopilotService, perform: repaired_result) }

      before do
        allow(Pilot::PromiseGuard).to receive(:call)
          .with(conversation: conversation, draft_reply: run_result.reply)
          .and_return(verdict(:promise, 'deferred_check_or_follow_up'))
        allow(Custom::Pilot::AutopilotService).to receive(:new)
          .with(assistant: assistant, conversation: conversation, account: account,
                repair_directive: kind_of(String), repair_draft: run_result.reply)
          .and_return(repair_service)
      end

      it 'regenerates exactly once and delivers the repaired reply when re-verified safe' do
        allow(Pilot::PromiseGuard).to receive(:call)
          .with(conversation: conversation, draft_reply: repaired_result.reply)
          .and_return(verdict(:safe, 'no_future_commitment'))

        outcome = call_service

        expect(repair_service).to have_received(:perform).once
        expect(outcome.result).to eq(repaired_result)
        expect(outcome).not_to be_handed_off
      end

      it 'suppresses the reply and hands off with a categorized guard reason when still flagged' do
        allow(Pilot::PromiseGuard).to receive(:call)
          .with(conversation: conversation, draft_reply: repaired_result.reply)
          .and_return(verdict(:promise, 'ongoing_monitoring'))

        outcome = call_service

        expect(outcome).to be_handed_off
        expect(outcome.result).to be_nil
        expect(conversation.reload.additional_attributes.dig('pilot_handoff', 'state')).to eq('handoff_requested')
        expect(conversation.messages.outgoing.where(private: false).last.content).to eq(I18n.t('conversations.pilot.handoff_guard'))
        activity = conversation.messages.activity.last
        expect(activity.content).to include('promise_guard:ongoing_monitoring')
        note = conversation.messages.outgoing.where(private: true).last
        expect(note.content).to include('promise_guard:ongoing_monitoring')
      end

      it 'hands off when the repaired reply cannot be verified safe (inconclusive second pass)' do
        allow(Pilot::PromiseGuard).to receive(:call)
          .with(conversation: conversation, draft_reply: repaired_result.reply)
          .and_return(verdict(:inconclusive))

        outcome = call_service

        expect(outcome).to be_handed_off
        expect(conversation.messages.outgoing.where(private: false).last.content).to eq(I18n.t('conversations.pilot.handoff_guard'))
      end

      it 'hands off when the repair step errors after a detection fired' do
        allow(repair_service).to receive(:perform).and_raise(Custom::Pilot::AutopilotService::Error, 'llm down')
        allow(Rails.logger).to receive(:error)

        outcome = call_service

        expect(outcome).to be_handed_off
        expect(conversation.reload.additional_attributes.dig('pilot_handoff', 'state')).to eq('handoff_requested')
      end
    end
  end
end
