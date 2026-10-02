class Voice::TranscriptionService
  pattr_initialize [:call!]

  # Producing and publishing are split so a publish failure can retry without
  # re-running (and re-charging) the provider transcription.
  def perform
    transcribe if call.transcript.blank?
    publish if call.transcript.present?
  end

  private

  def transcribe
    return unless call.recording.attached?
    return unless call.inbox.channel.transcription_enabled?
    return unless Pilot::SpeechToTextService.available_for?(call.account)
    return if Pilot::SpeechToTextService.too_large?(blob)

    text = Pilot::SpeechToTextService.new(blob: blob, account: call.account).perform
    call.update!(transcript: text) if text.present?
  end

  def publish
    message = call.message
    return if message.blank?

    # Reindex before broadcasting: if reindexing fails and the job retries, the
    # transcript is stored so only publish reruns and no duplicate update ships.
    message.reindex if KonversioApp.advanced_search_allowed?
    message.reload.send_update_event
  end

  def blob
    call.recording.blob
  end
end
