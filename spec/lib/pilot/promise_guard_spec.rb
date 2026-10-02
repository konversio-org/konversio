# rubocop:disable RSpec/VerifiedDoubles
require 'rails_helper'

RSpec.describe Pilot::PromiseGuard do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:detector_model) { 'gpt-guard-test' }
  let(:fake_chat) do
    double('Chat').tap do |chat|
      allow(chat).to receive(:with_temperature)
      allow(chat).to receive(:with_instructions)
    end
  end
  let(:fake_context) { double('LlmContext', chat: fake_chat) }

  before do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, content: 'Where is my order?')
    allow(Llm::Config).to receive(:with_api_key).and_yield(fake_context)
    allow(Llm::Config).to receive(:api_key).and_return('test-key')
    allow(Llm::Config).to receive(:api_base).and_return(nil)
    allow(Llm::Config).to receive(:openai_compatible?).and_return(false)
    allow(Llm::Config).to receive(:model_for).and_call_original
    allow(Llm::Config).to receive(:model_for).with(:promise_guard).and_return(detector_model)
  end

  def stub_detector_response(content)
    allow(fake_chat).to receive(:ask).and_return(double('Response', content: content))
  end

  def detect(reply: 'Your order ships tomorrow.')
    described_class.call(conversation: conversation, draft_reply: reply)
  end

  it 'returns a safe verdict with no_future_commitment for a reply without future commitments' do
    stub_detector_response('{"verdict":"safe","reason":"no_future_commitment"}')

    verdict = detect

    expect(verdict).to be_safe
    expect(verdict.reason_category).to eq('no_future_commitment')
    expect(verdict.model).to eq(detector_model)
  end

  it 'returns a promise verdict with the categorized reason for a follow-up commitment' do
    stub_detector_response('{"verdict":"future_promise","reason":"deferred_check_or_follow_up"}')

    verdict = detect(reply: "I'll check on this and get back to you tomorrow.")

    expect(verdict).to be_promise
    expect(verdict.reason_category).to eq('deferred_check_or_follow_up')
  end

  it 'normalizes unknown promise reasons into other_future_commitment' do
    stub_detector_response('{"verdict":"future_promise","reason":"something_made_up"}')

    expect(detect.reason_category).to eq('other_future_commitment')
  end

  it 'tolerates JSON wrapped in code fences' do
    stub_detector_response("```json\n{\"verdict\":\"safe\",\"reason\":\"no_future_commitment\"}\n```")

    expect(detect).to be_safe
  end

  it 'returns inconclusive when the detector output cannot be interpreted' do
    stub_detector_response('definitely not json')

    expect(detect).to be_inconclusive
  end

  it 'returns inconclusive when the verdict value is not one of the two outcomes' do
    stub_detector_response('{"verdict":"maybe","reason":"unsure"}')

    expect(detect).to be_inconclusive
  end

  it 'never raises: a detector error yields an inconclusive verdict and a warning' do
    allow(fake_chat).to receive(:ask).and_raise(Faraday::ConnectionFailed, 'down')
    allow(Rails.logger).to receive(:warn)

    verdict = detect

    expect(verdict).to be_inconclusive
    expect(Rails.logger).to have_received(:warn).with(/promise_guard.*detector failed/)
  end

  it 'runs the detector deterministically at temperature 0 with the resolved model' do
    stub_detector_response('{"verdict":"safe","reason":"no_future_commitment"}')

    detect

    expect(fake_context).to have_received(:chat).with(model: detector_model)
    expect(fake_chat).to have_received(:with_temperature).with(0)
  end

  it 'passes the conversation context and the draft to the detector' do
    stub_detector_response('{"verdict":"safe","reason":"no_future_commitment"}')

    detect(reply: 'THE DRAFT')

    expect(fake_chat).to have_received(:ask) do |input|
      expect(input).to include('Where is my order?')
      expect(input).to include('THE DRAFT')
    end
  end

  it 'logs every detection with verdict, reason, model, account, and conversation' do
    stub_detector_response('{"verdict":"future_promise","reason":"ongoing_monitoring"}')
    allow(Rails.logger).to receive(:info)

    detect

    expect(Rails.logger).to have_received(:info).with(
      /verdict=promise reason=ongoing_monitoring model=#{detector_model} account=#{account.id} conversation=#{conversation.display_id}/
    )
  end
end
# rubocop:enable RSpec/VerifiedDoubles
