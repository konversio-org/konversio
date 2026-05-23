# frozen_string_literal: true

module Custom
  module Pilot
    # Strips PII and secrets out of Pilot dispatcher event payloads before
    # they hit listeners. Replaces sensitive string fields with a pair of
    # `<field>_length` and `<field>_sha256` keys so observability tools can
    # still group / compare without ever leaking the raw content.
    #
    # Per pilot-telemetry spec "Sensitive payload redaction":
    #   - LLM prompts (`prompt`, `system_prompt`, `instructions`)
    #   - Tool auth headers (`auth_headers` hash → name list only)
    #   - Customer message bodies (`message_body`, `customer_message`,
    #     `content`, `body`, `transcript`, `raw_content`)
    #
    # The redactor is intentionally non-recursive at the top level: it
    # only inspects the keys it knows about. Callers should hand in the
    # event payload directly; nested service-internal hashes are left
    # alone so consumers can rely on a flat schema.
    class PayloadRedactor
      REDACTED_TEXT_FIELDS = %i[
        prompt
        system_prompt
        instructions
        message_body
        customer_message
        content
        body
        transcript
        raw_content
      ].freeze

      def self.call(payload)
        new.call(payload)
      end

      def call(payload)
        return {} if payload.blank?
        return payload unless payload.is_a?(Hash)

        redacted = payload.dup
        REDACTED_TEXT_FIELDS.each { |field| redact_text_field!(redacted, field) }
        redact_auth_headers!(redacted)
        redacted
      end

      private

      def redact_text_field!(payload, field)
        sym_key = field
        str_key = field.to_s
        value = payload.delete(sym_key)
        value = payload.delete(str_key) if value.nil?
        return if value.nil?

        text = value.to_s
        payload[:"#{field}_length"] = text.length
        payload[:"#{field}_sha256"] = Digest::SHA256.hexdigest(text)
      end

      def redact_auth_headers!(payload)
        headers = payload.delete(:auth_headers) || payload.delete('auth_headers')
        return if headers.nil?

        names =
          if headers.is_a?(Hash)
            headers.keys.map(&:to_s)
          elsif headers.is_a?(Array)
            headers.map(&:to_s)
          else
            []
          end
        payload[:auth_header_names] = names
      end
    end
  end
end
