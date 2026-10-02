# frozen_string_literal: true

require 'digest'

module Pilot
  module Playground
    # Normalises and validates the optional per-run `playground_config` payload
    # accepted by the Pilot playground endpoint.
    #
    # All state is transient: temporary scenarios are built as unsaved
    # `Pilot::Scenario` rows so the persisted validations (presence, tool
    # references, handoff tool-name length) are reused for per-field error
    # reporting, but nothing is ever written to the database.
    #
    # Validation aggregates every problem into a single error map keyed by
    # field path (for example `temporary_scenarios.0.title`) and raises
    # `Invalid` carrying that map once all checks have run.
    class SessionConfig # rubocop:disable Metrics/ClassLength
      # Raised when the supplied playground configuration fails validation.
      # Carries the aggregated `field => [messages]` map for the 422 body.
      class Invalid < StandardError
        attr_reader :errors

        def initialize(errors)
          @errors = errors
          super('Invalid playground configuration')
        end
      end

      # A temporary scenario paired with its per-run runtime agent name.
      TempScenario = Struct.new(:client_id, :scenario, :runtime_name, keyword_init: true)

      # A participating scenario plus the identity it runs under for this run.
      ScenarioSpec = Struct.new(:scenario, :runtime_name, :temporary, keyword_init: true)

      KNOWLEDGE_TEXT_LIMIT = 10_000
      RUNTIME_NAME_PREFIX = 'pg_draft_'
      RUNTIME_NAME_DIGEST_LENGTH = 16

      attr_reader :assistant, :knowledge_text, :scenario_ids, :response_guidelines,
                  :guardrails, :temporary_scenarios, :errors

      # Builds and validates a config, returning the instance on success.
      def self.build(payload, assistant:)
        new(payload, assistant: assistant).validate!
      end

      def initialize(payload, assistant:)
        @assistant = assistant
        @raw = normalise_payload(payload)
        @errors = {}
        @scenario_ids = nil
        @response_guidelines = nil
        @guardrails = nil
        @knowledge_text = nil
        @temporary_scenarios = []
      end

      # Runs every validation pass, aggregating errors, then raises `Invalid`
      # if any were collected. Returns self otherwise.
      def validate!
        unless raw.is_a?(Hash)
          add_error('playground_config', 'must be an object')
          raise Invalid, errors
        end

        parse_scenario_ids
        parse_rule_list(:response_guidelines)
        parse_rule_list(:guardrails)
        parse_temporary_scenarios
        parse_knowledge_text

        raise Invalid, errors if errors.any?

        self
      end

      # True when a non-blank knowledge snippet was supplied.
      def knowledge?
        knowledge_text.present?
      end

      # True when a scenario selection list was supplied (an empty list counts:
      # it means "run with no persisted scenarios").
      def scenario_selection?
        !scenario_ids.nil?
      end

      # The persisted scenarios participating in this run. When a selection was
      # supplied only those ids are included (regardless of enabled state);
      # otherwise all enabled scenarios participate.
      def persisted_scenarios
        scope = scenario_selection? ? assistant.scenarios.where(id: scenario_ids) : assistant.scenarios.enabled
        scope.to_a
      end

      # Ordered runtime specifications for every participating scenario —
      # persisted first, then temporary — used by the runner to build the agent
      # graph and by the report to map runtime names back to handlers.
      def scenario_specs
        persisted = persisted_scenarios.map do |scenario|
          ScenarioSpec.new(scenario: scenario, runtime_name: scenario.handoff_key, temporary: false)
        end
        temporary = temporary_scenarios.map do |entry|
          ScenarioSpec.new(scenario: entry.scenario, runtime_name: entry.runtime_name, temporary: true)
        end
        persisted + temporary
      end

      private

      attr_reader :raw

      def normalise_payload(payload)
        return nil if payload.nil?
        return payload.to_unsafe_h if payload.respond_to?(:to_unsafe_h)

        payload
      end

      def parse_scenario_ids
        return unless key?(raw, :scenario_ids)

        value = fetch(raw, :scenario_ids)
        unless value.is_a?(Array)
          add_error('scenario_ids', 'must be an array of scenario ids')
          return
        end

        ids = value.map { |entry| normalise_id(entry) }
        if ids.any?(&:nil?)
          add_error('scenario_ids', 'must contain positive integer ids')
          return
        end

        if ids.uniq.length != ids.length
          add_error('scenario_ids', 'must not contain duplicate ids')
          return
        end

        owned = assistant.scenarios.where(id: ids).pluck(:id)
        foreign = ids - owned
        add_error('scenario_ids', "does not include scenario ids: #{foreign.join(', ')}") if foreign.any?

        @scenario_ids = ids
      end

      def normalise_id(entry)
        return entry if entry.is_a?(Integer) && entry.positive?
        return nil unless entry.to_s.match?(/\A\d+\z/)

        value = entry.to_i
        value.positive? ? value : nil
      end

      def parse_rule_list(field)
        return unless key?(raw, field)

        value = fetch(raw, field)
        unless value.is_a?(Array)
          add_error(field.to_s, 'must be an array of strings')
          return
        end

        invalid = value.any? { |entry| !entry.is_a?(String) || entry.strip.blank? }
        add_error(field.to_s, 'must contain only non-blank strings') if invalid

        normalised = value.grep(String).map(&:strip).reject(&:blank?).uniq
        instance_variable_set("@#{field}", normalised)
      end

      def parse_temporary_scenarios
        return unless key?(raw, :temporary_scenarios)

        value = fetch(raw, :temporary_scenarios)
        unless value.is_a?(Array)
          add_error('temporary_scenarios', 'must be an array')
          return
        end

        seen_client_ids = {}
        value.each_with_index do |entry, index|
          parse_temporary_scenario(entry, index, seen_client_ids)
        end
      end

      def parse_temporary_scenario(entry, index, seen_client_ids)
        unless entry.is_a?(Hash)
          add_error("temporary_scenarios.#{index}", 'must be an object')
          return
        end

        client_id = normalise_client_id(entry, index, seen_client_ids)
        scenario = build_temporary_scenario(entry)
        add_scenario_errors(scenario, index)
        return if client_id.blank?

        @temporary_scenarios << TempScenario.new(client_id: client_id, scenario: scenario,
                                                 runtime_name: runtime_name_for(client_id))
      end

      def normalise_client_id(entry, index, seen_client_ids)
        client_id = fetch(entry, :client_id)
        client_id = client_id.to_s.strip if client_id.is_a?(String)
        if client_id.blank?
          add_error("temporary_scenarios.#{index}.client_id", 'is required')
        elsif seen_client_ids.key?(client_id)
          add_error('temporary_scenarios', "contains duplicate client identifier: #{client_id}")
        else
          seen_client_ids[client_id] = true
        end
        client_id
      end

      def build_temporary_scenario(entry)
        instruction = fetch(entry, :instruction).to_s
        scenario = ::Pilot::Scenario.new(
          assistant: assistant,
          account: assistant.account,
          title: fetch(entry, :title),
          description: fetch(entry, :description),
          instruction: instruction
        )
        scenario.tools = ::Pilot::Scenario.extract_tool_ids_from_text(instruction)
        scenario
      end

      # Surface the unsaved scenario's validation errors under per-entry field
      # paths so the UI can highlight the exact input that failed.
      def add_scenario_errors(scenario, index)
        scenario.valid?
        scenario.errors.each do |error|
          add_error("temporary_scenarios.#{index}.#{error.attribute}", error.message)
        end
      end

      # Deterministic, namespaced runtime agent name derived from the
      # client-supplied identifier. The `pg_draft_` namespace cannot collide
      # with persisted `Pilot::Scenario#handoff_key` values (which begin with
      # `scenario_`), and the digest keeps the total handoff tool name within
      # the SDK's 60-character limit.
      def runtime_name_for(client_id)
        "#{RUNTIME_NAME_PREFIX}#{Digest::SHA1.hexdigest(client_id.to_s)[0, RUNTIME_NAME_DIGEST_LENGTH]}"
      end

      def parse_knowledge_text
        return unless key?(raw, :knowledge_text)

        value = fetch(raw, :knowledge_text)
        unless value.is_a?(String)
          add_error('knowledge_text', 'must be a string')
          return
        end

        if value.length > KNOWLEDGE_TEXT_LIMIT
          add_error('knowledge_text', "must be at most #{KNOWLEDGE_TEXT_LIMIT} characters")
          return
        end

        @knowledge_text = value.presence
      end

      def key?(hash, key)
        hash.key?(key) || hash.key?(key.to_s)
      end

      def fetch(hash, key)
        hash.key?(key) ? hash[key] : hash[key.to_s]
      end

      def add_error(field, message)
        (errors[field] ||= []) << message
      end
    end
  end
end
