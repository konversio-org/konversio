# frozen_string_literal: true

require 'opentelemetry_config'

# OpenTelemetry-compatible trace span wrapper for Pilot LLM and tool
# call sites.
#
# Per pilot-telemetry "Assistant trace spans" (17.5–17.9): every LLM
# call and every custom-tool invocation made by Pilot SHALL emit a
# span named `pilot.<feature>.<operation>` carrying account/assistant/
# conversation identifiers plus token-usage and billing attributes.
#
# Backend resolution:
#
#   * When OpenTelemetry is configured AND `KonversioApp.otel_enabled?`
#     returns true, spans are emitted through `OpentelemetryConfig.tracer`
#     so they ship to Langfuse / the configured OTLP endpoint.
#   * Otherwise we degrade to a structured `Rails.logger.info` line so
#     dev / test environments still capture the attributes without
#     requiring the SDK to be initialised.
#
# Span emission is best-effort: any error in the tracing backend is
# logged at warn and swallowed so the originating Pilot operation is
# never aborted by telemetry.
#
# Usage:
#
#   Custom::Pilot::TraceSpan.wrap(
#     name: 'pilot.briefing.generate',
#     attributes: {
#       account_id: account.id,
#       conversation_id: conversation.id,
#       conversation_display_id: conversation.display_id,
#       channel_type: conversation.inbox&.channel_type,
#       source: 'production',
#       model: model_for(:briefing),
#       credit_used: true
#     }
#   ) do |span|
#     result = run_llm_call
#     span.set_attribute('prompt_tokens', result.prompt_tokens) if span
#     result
#   end
class Custom::Pilot::TraceSpan
  # Canonical attribute keys carried on every Pilot span (per spec).
  # Extra keys passed by callers are merged on top.
  DEFAULT_ATTRIBUTE_KEYS = %i[
    account_id
    assistant_id
    conversation_id
    conversation_display_id
    channel_type
    source
    model
    prompt_tokens
    completion_tokens
    credit_used
  ].freeze

  class << self
    # Wraps a block in a span. Yields the underlying OpenTelemetry span
    # (or a no-op shim) so callers can attach late-bound attributes
    # (e.g. token counts they only learn AFTER the LLM responds).
    def wrap(name:, attributes: {}, &block)
      return yield(NullSpan.new) unless block

      if otel_active?
        emit_otel_span(name, attributes, &block)
      else
        emit_log_span(name, attributes, &block)
      end
    end

    private

    def otel_active?
      return false unless defined?(::KonversioApp)
      return false unless ::KonversioApp.respond_to?(:otel_enabled?)

      ::KonversioApp.otel_enabled?
    rescue StandardError => e
      Rails.logger.warn("[pilot.trace_span] otel_enabled? check failed: #{e.class}: #{e.message}")
      false
    end

    def emit_otel_span(name, attributes)
      tracer = OpentelemetryConfig.tracer
      result = nil
      tracer.in_span(name) do |span|
        apply_attributes(span, attributes)
        result = yield(span)
      end
      result
    rescue StandardError => e
      Rails.logger.warn("[pilot.trace_span] otel emit failed name=#{name}: #{e.class}: #{e.message}")
      yield(NullSpan.new)
    end

    def emit_log_span(name, attributes)
      shim = LogSpan.new(name, attributes.dup)
      result = yield(shim)
      shim.flush
      result
    rescue StandardError
      shim.flush if shim.respond_to?(:flush)
      raise
    end

    def apply_attributes(span, attributes)
      attributes.each do |key, value|
        next if value.nil?

        span.set_attribute(key.to_s, normalize_attribute_value(value))
      end
    rescue StandardError => e
      Rails.logger.warn("[pilot.trace_span] attribute apply failed: #{e.class}: #{e.message}")
    end

    def normalize_attribute_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass then value
      when Array then value.map { |v| normalize_attribute_value(v) }
      else value.to_s
      end
    end
  end

  # No-op span returned when telemetry is disabled or the OTEL backend
  # itself raises. Lets call sites treat the yielded span uniformly.
  class NullSpan # rubocop:disable Style/OneClassPerFile
    def set_attribute(*); end
    def status=(_); end
  end

  # Span shim used when OTEL is not configured. Captures attributes
  # set during the block and flushes a single structured log line so
  # dev / test sees the same data the production tracing backend would.
  class LogSpan # rubocop:disable Style/OneClassPerFile
    def initialize(name, attributes)
      @name = name
      @attributes = attributes
    end

    def set_attribute(key, value)
      @attributes[key.to_sym] = value if value
    end

    def status=(value)
      @attributes[:status] = value.to_s
    end

    def flush
      payload = @attributes.transform_values { |v| v.is_a?(Array) ? v.join(',') : v }
      Rails.logger.info("[pilot.trace_span] span=#{@name} #{payload.map { |k, v| "#{k}=#{v}" }.join(' ')}")
    rescue StandardError => e
      Rails.logger.warn("[pilot.trace_span] log flush failed name=#{@name}: #{e.class}: #{e.message}")
    end
  end
end
