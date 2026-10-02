class Voice::Twilio::RecordingFetcher
  DEFAULT_EXTENSION = 'wav'.freeze
  AUDIO_CONTENT_TYPES = %w[audio/].freeze

  pattr_initialize [:call!, :recording_sid!, :recording_url!, { recording_duration: nil }]

  def perform
    return unless attachable?

    SafeFetch.fetch(
      recording_url,
      http_basic_authentication: [channel.account_sid, channel.auth_token],
      allowed_content_type_prefixes: AUDIO_CONTENT_TYPES
    ) { |result| persist!(result) }

    # Bump updated_at so the message.updated dispatcher rebroadcasts the call
    # payload now that it carries a recording URL.
    call.message&.touch # rubocop:disable Rails/SkipsModelValidations

    Voice::TranscriptionJob.perform_later(call.id) if @persisted
  end

  private

  def attachable?
    return false if recording_sid.blank? || recording_url.blank?
    # The callback is public; the snapshot decides whether this call records.
    return false unless call.recording_enabled?

    !already_attached?
  end

  def persist!(result)
    call.with_lock do
      next if already_attached?

      call.recording.attach(
        io: result.tempfile,
        filename: filename(result),
        content_type: content_type(result)
      )
      call.recording_sid = recording_sid
      call.duration_seconds ||= normalized_duration
      call.save!
      @persisted = true
    end
  end

  def already_attached?
    call.recording.attached? && call.recording_sid.to_s == recording_sid.to_s
  end

  def normalized_duration
    recording_duration.to_i if recording_duration.present?
  end

  def filename(result)
    return result.original_filename if result.original_filename.present?

    "call-recording-#{recording_sid}.#{extension(result)}"
  end

  def extension(result)
    Rack::Mime::MIME_TYPES.invert[content_type(result)].to_s.delete_prefix('.').presence || DEFAULT_EXTENSION
  end

  def content_type(result)
    result.content_type.presence || 'audio/wav'
  end

  def channel
    @channel ||= call.inbox.channel
  end
end
