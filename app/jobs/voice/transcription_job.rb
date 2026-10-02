class Voice::TranscriptionJob < ApplicationJob
  queue_as :low

  # Audio the provider can never accept, or credentials it refuses, are not retried.
  discard_on Pilot::SpeechToTextService::PermanentError, Pilot::SpeechToTextService::NotConfigured do |job, error|
    Rails.logger.warn("Discarding call transcription job: call_id=#{job.arguments.first} error=#{error.class}")
  end
  # A blob temporarily unavailable (storage hiccup) is worth a short retry.
  retry_on ActiveStorage::FileNotFoundError, wait: 2.seconds, attempts: 3

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    Voice::TranscriptionService.new(call: call).perform
  end
end
