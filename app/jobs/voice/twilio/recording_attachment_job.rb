class Voice::Twilio::RecordingAttachmentJob < ApplicationJob
  queue_as :low

  retry_on SafeFetch::Error, wait: 5.seconds, attempts: 3

  def perform(call_id, recording_sid, recording_url, recording_duration = nil)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Voice::Twilio::RecordingFetcher.new(
      call: call,
      recording_sid: recording_sid,
      recording_url: recording_url,
      recording_duration: recording_duration
    ).perform
  end
end
