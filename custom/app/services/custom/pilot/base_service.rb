module Custom
  module Pilot
    # Common parent for every Pilot sub-feature service. Centralises:
    #
    #   * per-feature model resolution (delegates to Llm::Config)
    #   * per-account feature-flag checks (`pilot_<feature>_enabled` columns)
    #   * a RubyLLM chat context preconfigured with the system-role flag
    #   * telemetry dispatch stub (proper EventDispatcher lands in section 7)
    #
    # Subclasses are expected to accept an `account:` keyword and use
    # `feature_enabled?(:briefing)`, `model_for(:briefing)`, and
    # `chat_context` as the entry points into the LLM layer.
    class BaseService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      def model_for(feature)
        ::Llm::Config.model_for(feature)
      end

      # Returns true when both the master Pilot flag AND the per-feature flag
      # are set on the given account. When `account` is omitted we fall back
      # to `@account` set at construction time.
      def feature_enabled?(feature, account = @account)
        return false if account.blank?

        account.feature_enabled?('pilot') && account.feature_enabled?("pilot_#{feature}")
      end

      # Yields a RubyLLM chat context bound to the install-wide credentials,
      # with the cross-provider system-role flag set.
      def chat_context(&)
        ::Llm::Config.with_api_key(::Llm::Config.api_key, api_base: ::Llm::Config.api_base, &)
      end

      # Dispatch a Pilot telemetry event through `Custom::Pilot::EventDispatcher`.
      # Translates the symbolic event name passed by legacy callers (e.g.
      # `:briefing_started`) into the canonical dotted form
      # (`pilot.briefing.started`) and routes through the dispatcher so
      # webhooks, ActionCable, and the activity store all see the event.
      #
      # Accepts either a positional payload hash:
      #   dispatch_event(:briefing_completed, { conversation_id: 12 })
      # or trailing kwargs (legacy style preserved for in-flight callers):
      #   dispatch_event(:briefing_completed, conversation_id: 12)
      #
      # An explicit `time:` keyword threads through to listeners — callers at
      # a state-transition site should capture it before they call here so
      # downstream consumers can rely on race-free ordering.
      def dispatch_event(name, payload = nil, time: nil, **kwargs)
        merged_payload = payload.is_a?(Hash) ? payload.merge(kwargs) : kwargs
        canonical = canonicalize_event_name(name)
        payload_with_account = merged_payload.merge(account_id: account&.id).compact
        ::Custom::Pilot::EventDispatcher.dispatch(canonical, payload_with_account, time: time, account: account)
      end

      # Maps the legacy underscore names (`:briefing_started`,
      # `:autopilot_inference_completed`) to their dotted dispatcher form.
      # Keeps callers free to use either symbol or string.
      def canonicalize_event_name(name)
        str = name.to_s
        return str if str.include?('.')

        prefix_match = ::Custom::Pilot::BaseService::EVENT_NAME_MAP.find { |k, _| str.start_with?(k) }
        return "pilot.#{str.tr('_', '.')}" if prefix_match.nil?

        suffix = str.delete_prefix(prefix_match.first).delete_prefix('_')
        suffix.empty? ? prefix_match.last : "#{prefix_match.last}.#{suffix.tr('_', '.')}"
      end

      # Symbolic-prefix → dotted-prefix translation table. Ordered longest-
      # first so e.g. `autopilot_inference_completed` matches the autopilot
      # prefix and not just `pilot.*`.
      EVENT_NAME_MAP = {
        'briefing' => 'pilot.briefing',
        'copilot_inference' => 'pilot.copilot.inference',
        'copilot_message' => 'pilot.copilot.message',
        'autopilot_inference' => 'pilot.autopilot.inference',
        'autopilot_handover' => 'pilot.autopilot.handover',
        'autopilot_skipped' => 'pilot.autopilot.skipped',
        'autopilot_document' => 'pilot.autopilot.document',
        'logbook_extraction' => 'pilot.logbook.extraction',
        'logbook_entry' => 'pilot.logbook.entry',
        'tool' => 'pilot.tool'
      }.freeze

      # Renders the contact's Logbook entries as a system-role message body
      # per the pilot-logbook "Logbook context injection format" requirement.
      #
      # Shape:
      #   "Known facts about this contact:\n- <fact>\n- <fact>"
      #
      # Order: reverse-chronological (newest first). Only the fact strings
      # are emitted — no entry ids, no source-message ids, no timestamps —
      # so the LLM treats them as durable knowledge rather than transcript
      # artifacts.
      #
      # Returns `nil` when the feature is off, the contact has no entries,
      # or the contact is blank — callers should skip adding any system
      # message when this returns nil.
      def logbook_context_for(contact)
        return nil if contact.blank?
        return nil unless feature_enabled?(:logbook)

        entries = ::Pilot::LogbookEntry.where(contact: contact).order(created_at: :desc).limit(20)
        return nil if entries.empty?

        bullets = entries.map { |e| "- #{e.content}" }.join("\n")
        "Known facts about this contact:\n#{bullets}"
      end
    end
  end
end
