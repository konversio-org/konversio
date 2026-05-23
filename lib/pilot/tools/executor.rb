# frozen_string_literal: true

require 'json'
require 'liquid'
require 'net/http'
require 'uri'

# Synchronous executor for `Pilot::CustomTool` invocations.
#
# Responsibilities covered here (section 14 of pilot-full):
#   - type-check LLM-supplied arguments against the tool's `param_schema`
#   - render `request_template` / `response_template` as Liquid
#   - resolve the endpoint host once and reject denied CIDR ranges
#   - return a uniform `{ error:, message: }` hash to the LLM on any failure
class Pilot::Tools::Executor
  RESPONSE_BYTE_LIMIT = 8 * 1024
  TRUNCATION_MARKER = '[...truncated]'
  HTTP_OPEN_TIMEOUT = 5
  HTTP_READ_TIMEOUT = 10

  TYPE_MATCHERS = {
    'string' => ->(v) { v.is_a?(String) },
    'number' => ->(v) { v.is_a?(Numeric) },
    'integer' => ->(v) { v.is_a?(Integer) },
    'boolean' => ->(v) { v == true || v == false },
    'array' => ->(v) { v.is_a?(Array) },
    'object' => ->(v) { v.is_a?(Hash) }
  }.freeze

  def initialize(tool)
    @tool = tool
  end

  # Returns either the (post-template, truncated) tool result string, or a
  # structured `{ error:, message: }` hash that the LLM consumes verbatim.
  def call(arguments = {})
    dispatch_event('pilot.tool.invoked')

    ::Custom::Pilot::TraceSpan.wrap(name: 'pilot.tool.custom_http', attributes: span_attributes(arguments)) do |span|
      @span = span
      perform_invocation(arguments)
    end
  ensure
    @span = nil
  end

  private

  def perform_invocation(arguments)
    return finalize_failure(disabled_error) unless @tool.enabled?

    args = stringify_keys(arguments)

    type_error = check_argument_types(args)
    return finalize_failure(type_error) if type_error

    body = render_request_body(args)
    return finalize_failure(body) if structured_error?(body)

    started_at = monotonic_now
    result = perform_http(body, args)

    if structured_error?(result)
      finalize_failure(result)
    else
      finalize_success(result, started_at)
    end
  rescue Liquid::Error => e
    finalize_failure(parse_error("Liquid render failed: #{e.message}"))
  end

  def span_attributes(arguments)
    {
      account_id: @tool.respond_to?(:account_id) ? @tool.account_id : nil,
      tool_slug: @tool.respond_to?(:slug) ? @tool.slug : nil,
      tool_id: @tool.respond_to?(:id) ? @tool.id : nil,
      arguments_json: safe_arguments_json(arguments)
    }
  end

  def safe_arguments_json(arguments)
    stringify_keys(arguments).to_json
  rescue StandardError
    nil
  end

  def record_span_status(status:, http_status: nil, error_code: nil, duration_ms: nil)
    return unless @span

    @span.set_attribute('http_status', http_status) if http_status
    @span.set_attribute('error_code', error_code) if error_code
    @span.set_attribute('duration_ms', duration_ms) if duration_ms
    @span.set_attribute('status', status)
  end

  def stringify_keys(hash)
    return {} if hash.nil?

    hash.transform_keys(&:to_s)
  end

  def check_argument_types(args)
    Array(@tool.param_schema).each do |entry|
      error = check_param_entry(entry, args)
      return error if error
    end
    nil
  end

  def check_param_entry(entry, args)
    name, type = param_entry_name_type(entry)
    return nil if name.blank? || type.blank?
    return nil if skip_entry?(entry, args, name)
    return nil if TYPE_MATCHERS[type]&.call(args[name])

    parse_error("Argument '#{name}' must be #{type}")
  end

  def param_entry_name_type(entry)
    [entry['name'] || entry[:name], (entry['type'] || entry[:type]).to_s]
  end

  def skip_entry?(entry, args, name)
    required = entry['required'] || entry[:required]
    !args.key?(name) && !required
  end

  def render_request_body(args)
    return nil if @tool.http_method.to_s.upcase != 'POST'
    return nil if @tool.request_template.blank?

    Liquid::Template.parse(@tool.request_template).render!(args)
  rescue Liquid::Error => e
    parse_error("Liquid render failed: #{e.message}")
  end

  def perform_http(body, _args)
    uri = URI.parse(@tool.endpoint_url)
    guard = Pilot::Tools::UrlGuard.resolve(uri.host)
    return private_ip_error if guard.denied?

    response = http_request(uri, guard.ip, body)
    @last_http_status = response.code.to_i
    return http_error(response) unless response.is_a?(Net::HTTPSuccess)

    extract_response(response.body)
  rescue Timeout::Error
    timeout_error
  end

  def http_request(uri, resolved_ip, body)
    request = build_request(uri, body)
    Net::HTTP.start(
      resolved_ip,
      uri.port,
      use_ssl: uri.scheme == 'https',
      open_timeout: HTTP_OPEN_TIMEOUT,
      read_timeout: HTTP_READ_TIMEOUT
    ) do |http|
      request['Host'] = uri.host
      http.request(request)
    end
  end

  def build_request(uri, body)
    case @tool.http_method.to_s.upcase
    when 'POST'
      request = Net::HTTP::Post.new(uri.request_uri)
      if body
        request.body = body
        request['Content-Type'] ||= 'application/json'
      end
      request
    else
      Net::HTTP::Get.new(uri.request_uri)
    end
  end

  def extract_response(raw_body)
    rendered =
      if @tool.response_template.present?
        context = response_context(raw_body)
        Liquid::Template.parse(@tool.response_template).render!(context)
      else
        raw_body.to_s
      end

    truncate(rendered)
  rescue Liquid::Error => e
    parse_error("Liquid render failed: #{e.message}")
  end

  def response_context(raw_body)
    parsed = JSON.parse(raw_body.to_s)
    { 'response' => parsed, 'r' => parsed }
  rescue JSON::ParserError
    # Allow templates that don't access JSON fields to still render.
    { 'response' => raw_body.to_s, 'r' => raw_body.to_s }
  end

  def truncate(value)
    str = value.to_s
    return str if str.bytesize <= RESPONSE_BYTE_LIMIT

    "#{str.byteslice(0, RESPONSE_BYTE_LIMIT)}#{TRUNCATION_MARKER}"
  end

  def parse_error(message)
    { error: 'tool.parse_error', message: message }
  end

  def disabled_error
    { error: 'tool.disabled', message: 'Tool is not enabled' }
  end

  def private_ip_error
    { error: 'tool.private_ip_denied', message: 'Resolved address is in a denied range' }
  end

  def http_error(response)
    { error: 'tool.http_error', message: "#{response.code} #{response.message}" }
  end

  def timeout_error
    { error: 'tool.timeout', message: "Tool exceeded #{HTTP_READ_TIMEOUT}s timeout" }
  end

  def structured_error?(value)
    value.is_a?(Hash) && value[:error].is_a?(String)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def dispatch_event(name, extra = {})
    ::Custom::Pilot::EventDispatcher.dispatch(
      name,
      base_event_payload.merge(extra),
      account: @tool.respond_to?(:account) ? @tool.account : nil
    )
  rescue StandardError => e
    Rails.logger.warn("[pilot.tool.executor] dispatch #{name} failed: #{e.class}: #{e.message}")
  end

  def base_event_payload
    {
      account_id: @tool.respond_to?(:account_id) ? @tool.account_id : nil,
      tool_slug: @tool.respond_to?(:slug) ? @tool.slug : nil,
      tool_id: @tool.respond_to?(:id) ? @tool.id : nil
    }
  end

  def finalize_success(result, started_at)
    duration_ms = ((monotonic_now - started_at) * 1000).round
    dispatch_event('pilot.tool.completed', duration_ms: duration_ms)
    record_span_status(status: 'ok', http_status: @last_http_status, duration_ms: duration_ms)
    result
  end

  def finalize_failure(error_hash)
    dispatch_event('pilot.tool.failed', error_code: error_hash[:error])
    record_span_status(status: 'error', http_status: @last_http_status, error_code: error_hash[:error])
    error_hash
  end
end
