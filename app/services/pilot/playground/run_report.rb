# frozen_string_literal: true

module Pilot
  module Playground
    # Collects a single playground run's execution trace through the runner
    # callbacks and renders it as the additive `run_report` returned with the
    # playground response.
    #
    # The collector records tool start/complete and agent handoff events in
    # execution order, sanitises every argument and preview before display, and
    # maps the runtime agent names used during the run back to human-readable
    # handler descriptors (assistant vs scenario, temporary flagged).
    class RunReport # rubocop:disable Metrics/ClassLength
      PREVIEW_LIMIT = 500
      REDACTED = '[REDACTED]'
      HANDOFF_TOOL_PREFIX = 'handoff_to_'
      TOOL_NAMESPACE_PREFIXES = %w[custom_ pilot_].freeze

      # Key fragments that indicate a credential value. Matched against the
      # individual words of a key (after splitting separators and camelCase),
      # so `api_key`, `auth_token` and `clientSecret` are all recognised while
      # `author` is not.
      CREDENTIAL_PARTS = %w[
        password passwd passphrase secret token apikey credential cookie
        authorization auth bearer signature
      ].freeze
      CREDENTIAL_COMPOUNDS = %w[apikey accesskey privatekey secretkey clientsecret
                                sessionid accesstoken authtoken refreshtoken idtoken].freeze

      # HTTP-header-like lines, e.g. `Authorization: Bearer abc` or
      # `X-Api-Key: xyz`.
      HEADER_LINE = /^(\s*[A-Za-z0-9-]+\s*:\s*)(.*)$/
      # `key = value` / `"key": "value"` assignments inside free text or
      # serialized JSON.
      ASSIGNMENT = /("?)([A-Za-z0-9_.-]+)("?)(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;&]+)/

      attr_reader :assistant, :config, :events

      def initialize(assistant:, config:)
        @assistant = assistant
        @config = config
        @events = []
        @handlers = build_handlers
        @started_at = monotonic_now
        @finish = nil
        @final_agent_name = nil
      end

      # Callback set handed to `Custom::Pilot::AutopilotService`. Each value is a
      # proc the runner registers on the ai-agents runner.
      def callbacks
        {
          tool_start: method(:on_tool_start),
          tool_complete: method(:on_tool_complete),
          agent_handoff: method(:on_agent_handoff),
          run_complete: method(:on_run_complete)
        }
      end

      # Stops the wall-clock timer for this run.
      def finish!
        @finish ||= monotonic_now
      end

      def duration_ms
        finish = @finish || monotonic_now
        [((finish - @started_at) * 1000).round, 0].max
      end

      # The handler descriptor for the agent that produced the final reply.
      def handler
        handler_for(@final_agent_name.presence || assistant_agent_name)
      end

      def to_h
        {
          handler: handler,
          knowledge_attached: config&.knowledge? || false,
          duration_ms: duration_ms,
          events: events
        }
      end

      def on_tool_start(tool_name, args = nil, *_rest)
        return if handoff_tool?(tool_name)

        events << {
          type: 'tool',
          tool: display_tool_name(tool_name),
          status: 'running',
          arguments: sanitize_value(args || {}),
          result_preview: nil
        }
      end

      def on_tool_complete(tool_name, result = nil, *_rest)
        return if handoff_tool?(tool_name)

        event = events.reverse.find do |entry|
          entry[:type] == 'tool' && entry[:tool] == display_tool_name(tool_name) && entry[:status] == 'running'
        end
        return unless event

        event[:status] = error_result?(result) ? 'failed' : 'completed'
        event[:result_preview] = preview_for(result)
      end

      def on_agent_handoff(from_agent, to_agent, reason = nil, *_rest)
        events << {
          type: 'handoff',
          from: handler_for(from_agent),
          to: handler_for(to_agent),
          reason_preview: truncate(sanitize_string(reason.to_s))
        }
      end

      def on_run_complete(agent_name, *_rest)
        @final_agent_name = agent_name
      end

      private

      def build_handlers
        handlers = { assistant_agent_name => assistant_descriptor }
        (config&.scenario_specs || []).each do |spec|
          handlers[spec.runtime_name] = scenario_descriptor(spec)
        end
        handlers
      end

      def assistant_agent_name
        ::Custom::Pilot::AutopilotService.assistant_agent_name_for(assistant)
      end

      def assistant_descriptor
        { name: assistant.name, type: 'assistant', temporary: false }
      end

      def scenario_descriptor(spec)
        { name: spec.scenario.title, type: 'scenario', temporary: spec.temporary }
      end

      def handler_for(agent_name)
        @handlers[agent_name] ||
          { name: agent_name.to_s, type: 'agent', temporary: false }
      end

      def handoff_tool?(tool_name)
        tool_name.to_s.start_with?(HANDOFF_TOOL_PREFIX)
      end

      # Strip internal namespace prefixes so testers see the tool they
      # configured rather than the adapter's internal name.
      def display_tool_name(tool_name)
        name = tool_name.to_s
        prefix = TOOL_NAMESPACE_PREFIXES.find { |candidate| name.start_with?(candidate) }
        prefix ? name.delete_prefix(prefix) : name
      end

      # --- sanitisation -----------------------------------------------------

      def sanitize_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), acc|
            acc[key] = credential_key?(key) ? REDACTED : sanitize_value(nested)
          end
        when Array
          value.map { |nested| sanitize_value(nested) }
        when String
          sanitize_string(value)
        else
          value
        end
      end

      def sanitize_string(value)
        text = value.to_s
        text = mask_header_lines(text)
        mask_assignments(text)
      end

      def mask_header_lines(text)
        text.gsub(HEADER_LINE) do |line|
          match = Regexp.last_match
          credential_key?(match[1].strip.chomp(':')) ? "#{match[1]}#{REDACTED}" : line
        end
      end

      def mask_assignments(text)
        text.gsub(ASSIGNMENT) do |match|
          match_data = Regexp.last_match
          opening_quote = match_data[1]
          key = match_data[2]
          closing_quote = match_data[3]
          separator = match_data[4]
          value = match_data[5]
          next match unless credential_key?(key)

          replacement = value.start_with?('"', "'") ? "\"#{REDACTED}\"" : REDACTED
          "#{opening_quote}#{key}#{closing_quote}#{separator}#{replacement}"
        end
      end

      def credential_key?(key)
        parts = key.to_s.split(/[^a-zA-Z0-9]+/)
                   .flat_map { |part| part.split(/(?=[A-Z])/) }
                   .map { |part| part.downcase.delete_suffix('s') }
                   .reject(&:blank?)
        return true if parts.intersect?(CREDENTIAL_PARTS)

        joined = parts.join
        CREDENTIAL_COMPOUNDS.any? { |compound| joined.include?(compound) }
      end

      def preview_for(result)
        text =
          case result
          when String then result
          when nil then ''
          else result.to_json
          end
        truncate(sanitize_string(text))
      rescue StandardError
        truncate(sanitize_string(result.to_s))
      end

      def error_result?(result)
        case result
        when Hash
          result.key?(:error) || result.key?('error')
        when String
          result.start_with?('ERROR:') || result.include?('[BACKEND_ERROR]') || result.match?(/\A\{\s*"error"/)
        else
          false
        end
      end

      def truncate(text)
        text.to_s.truncate(PREVIEW_LIMIT)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
