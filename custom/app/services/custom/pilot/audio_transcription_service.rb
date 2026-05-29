# rubocop:disable Style/ClassAndModuleChildren
module Custom
  module Pilot
    # Transcribes a single audio attachment (e.g. a WhatsApp voice note) in
    # place, writing the result to `attachment.meta['transcribed_text']`.
    #
    # Downstream consumers already read that field — `Message#content_for_llm`
    # feeds it to the Pilot autopilot LLM, and `Attachment#audio_metadata`
    # surfaces it to the agent dashboard — so populating it is the only
    # missing link.
    #
    # The transcription endpoint is the configured audio slot
    # (`PILOT_LLM_AUDIO_PROVIDER` / `PILOT_LLM_AUDIO_MODEL`, e.g. Scaleway
    # whisper-large-v3) reached through the OpenAI-compatible client, mirroring
    # `Llm::SanityTester#audio_slot_test`.
    #
    # Best-effort by design: a provider/IO hiccup must never break message
    # processing or a bot reply, so we log and return nil rather than raise.
    class AudioTranscriptionService < BaseService
      # WhatsApp Opus voice notes run ~16-32 kbps, so 1 MB is roughly 4-5
      # minutes — comfortably above any real support voice note. Anything
      # larger is skipped (left untranscribed) to bound cost and latency.
      MAX_AUDIO_BYTES = 1.megabyte

      # The OpenAI-compatible transcription endpoint accepts only these
      # container extensions and rejects others (notably ".opus") with HTTP
      # 400 — even though WhatsApp voice notes are Opus-in-OGG. Any blank or
      # unsupported extension is mapped to "ogg" (the real container) so the
      # bytes decode.
      WHISPER_EXTENSIONS = %w[flac m4a mp3 mp4 mpeg mpga oga ogg wav webm].freeze

      # Transcribes every audio attachment on a message in place. Convenience
      # entry point for callers (e.g. the autopilot job) that hold a message.
      def self.transcribe_message(message)
        return if message.blank?

        message.attachments.where(file_type: :audio).find_each do |attachment|
          new(attachment).perform
        end
      end

      def initialize(attachment)
        @attachment = attachment
        super(account: attachment&.account)
      end

      # Returns the transcript on success, or nil when skipped (not audio,
      # already transcribed, oversized, audio slot unconfigured, or feature
      # off) or on error.
      def perform
        return unless eligible?

        config = ::Llm::Config.for_slot(:audio)
        return if config[:api_key].blank?

        text = transcribe(config)
        return if text.blank?

        @attachment.update!(meta: meta.merge('transcribed_text' => text))
        text
      rescue StandardError => e
        Rails.logger.error("[pilot.audio_transcription] attachment=#{@attachment&.id} failed: #{e.message}")
        nil
      end

      private

      def eligible?
        return false if @attachment.blank? || !@attachment.audio?
        return false unless feature_enabled?(:audio_transcription)
        return false if meta['transcribed_text'].present?
        return false unless @attachment.file.attached?
        return false if @attachment.file.blob.byte_size > MAX_AUDIO_BYTES

        true
      end

      def meta
        @attachment.meta || {}
      end

      def transcribe(config)
        client = ::OpenAI::Client.new(access_token: config[:api_key], uri_base: "#{config[:endpoint]}/v1")
        with_audio_tempfile do |file|
          response = client.audio.transcribe(parameters: { model: config[:model], file: file })
          response.is_a?(Hash) ? response['text'].to_s.strip.presence : nil
        end
      end

      # The OpenAI-compatible client uploads the file by path and infers the
      # format from the extension, so the tempfile must carry the audio's real
      # extension (WhatsApp voice notes are `.ogg`).
      def with_audio_tempfile
        blob = @attachment.file.blob
        tempfile = Tempfile.new(['pilot_audio', ".#{audio_extension(blob)}"])
        tempfile.binmode
        tempfile.write(blob.download)
        tempfile.rewind
        yield tempfile
      ensure
        tempfile&.close
        tempfile&.unlink
      end

      def audio_extension(blob)
        raw = (@attachment.extension.presence ||
               File.extname(blob.filename.to_s).delete('.')).to_s.downcase
        WHISPER_EXTENSIONS.include?(raw) ? raw : 'ogg'
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
