# Per-inbox call settings stored in provider_config and shared by every channel
# type that can place calls. Both default to on so inboxes that predate the
# settings keep recording and transcribing.
module CallSettings
  def recording_enabled?
    provider_config&.fetch('recording_enabled', true) != false
  end

  def transcription_enabled?
    provider_config&.fetch('transcription_enabled', true) != false
  end

  def inbound_calls_enabled?
    provider_config&.fetch('inbound_calls_enabled', true) != false
  end
end
