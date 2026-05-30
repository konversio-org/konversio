# Transcribes the audio attachments (e.g. WhatsApp voice notes) on an inbound
# message into `attachment.meta['transcribed_text']` — the field the agent
# dashboard (`Attachment#audio_metadata`) and the Pilot autopilot LLM
# (`Message#content_for_llm`) both read.
#
# Channel-agnostic and consumer-agnostic: fired for any inbound audio
# regardless of whether Autopilot is attached. The service self-gates on the
# `pilot_audio_transcription` feature, idempotency, size, and audio-slot
# configuration, so this job stays thin.
class Pilot::AudioTranscriptionJob < ApplicationJob
  queue_as :low

  def perform(message_id:)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Custom::Pilot::AudioTranscriptionService.transcribe_message(message)

    trigger_autopilot(message)
  end

  private

  def trigger_autopilot(message)
    account = message.account
    inbox = message.inbox
    return if account.blank? || inbox.blank?

    # Verify that autopilot is enabled and conversation is eligible
    return unless account.feature_enabled?('pilot') && account.feature_enabled?('pilot_autopilot')
    return unless PilotAutopilotListener.instance.send(:autopilot_active?, account, inbox)
    return unless PilotAutopilotListener.instance.send(:bot_eligible?, message.conversation)

    ::Pilot::AutopilotInferenceJob.perform_later(message_id: message.id)
  end
end
