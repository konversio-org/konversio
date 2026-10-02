require 'rails_helper'

RSpec.describe Voice::Twilio::RecordingFetcher do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, account: account) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:call) { create(:call, account: account, inbox: inbox, conversation: conversation, contact: contact, status: 'completed') }
  let(:recording_sid) { 'RE123' }
  let(:recording_url) { 'https://api.twilio.com/recordings/RE123' }

  def stub_fetch
    tempfile = Tempfile.new(['recording', '.wav'])
    tempfile.write('fake audio bytes')
    tempfile.rewind
    result = SafeFetch::Result.new(tempfile: tempfile, filename: 'recording.wav', content_type: 'audio/wav')
    allow(SafeFetch).to receive(:fetch).and_yield(result)
  end

  def perform_fetcher(duration: nil)
    described_class.new(call: call, recording_sid: recording_sid, recording_url: recording_url, recording_duration: duration).perform
  end

  it 'attaches the recording and sets the duration when absent' do
    stub_fetch

    perform_fetcher(duration: 42)

    expect(call.reload.recording).to be_attached
    expect(call.recording_sid).to eq(recording_sid)
    expect(call.duration_seconds).to eq(42)
  end

  it 'is idempotent across duplicate callbacks' do
    stub_fetch
    perform_fetcher
    call.reload

    expect { perform_fetcher }.not_to(change { call.reload.recording.attachment.id })
  end

  it 'enqueues transcription only for the invocation that persisted' do
    stub_fetch

    expect { perform_fetcher }.to have_enqueued_job(Voice::TranscriptionJob).once
    expect { perform_fetcher }.not_to have_enqueued_job(Voice::TranscriptionJob)
  end

  it 'ignores a call whose recording snapshot is disabled' do
    call.update!(recording_enabled: false)
    expect(SafeFetch).not_to receive(:fetch)

    perform_fetcher

    expect(call.reload.recording).not_to be_attached
  end
end
