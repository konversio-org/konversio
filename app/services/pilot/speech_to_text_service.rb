# Pilot speech-to-text capability. Routing lives on Pilot's existing LLM config
# (the `audio` slot), so transcription reuses the same provider credentials and
# endpoints as the rest of Pilot rather than a separate service.
class Pilot::SpeechToTextService
  DEFAULT_MAX_BYTES = 25.megabytes

  class NotConfigured < StandardError; end
  # Provider errors that can never succeed for this audio (corrupt/unsupported).
  class PermanentError < StandardError; end

  class << self
    def config
      Llm::Config.for_slot(:audio)
    end

    def configured?
      config[:api_key].present? && config[:endpoint].present?
    end

    def available_for?(_account)
      configured?
    end

    def max_size_bytes
      ENV.fetch('PILOT_SPEECH_TO_TEXT_MAX_BYTES', DEFAULT_MAX_BYTES).to_i
    end

    def too_large?(blob)
      blob.present? && blob.byte_size > max_size_bytes
    end
  end

  pattr_initialize [:blob!, :account!]

  def perform
    raise NotConfigured, 'Pilot speech-to-text is not configured' unless self.class.configured?

    response = blob.open { |file| post_transcription(file) }
    raise PermanentError, "Transcription failed with status #{response.status}" unless response.success?

    text = parse_text(response.body)
    raise PermanentError, 'Transcription response missing text' if text.blank?

    text
  rescue Faraday::BadRequestError, Faraday::UnauthorizedError => e
    # The provider refused this audio or the credentials: retrying will not help.
    raise PermanentError, "Transcription rejected: #{e.message}"
  end

  private

  def config
    self.class.config
  end

  def api_key
    config[:api_key]
  end

  def transcription_url
    "#{config[:endpoint]}/v1/audio/transcriptions"
  end

  def post_transcription(file)
    connection.post(transcription_url) do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.body = { model: config[:model], file: file_part(file) }
    end
  end

  def parse_text(body)
    JSON.parse(body)['text']
  rescue JSON::ParserError, TypeError
    nil
  end

  def file_part(file)
    Faraday::Multipart::FilePart.new(file, blob.content_type || 'audio/wav', filename)
  end

  def filename
    blob.filename.to_s.presence || 'call-recording.wav'
  end

  def connection
    @connection ||= Faraday.new do |builder|
      builder.request :multipart
      builder.adapter Faraday.default_adapter
    end
  end
end
