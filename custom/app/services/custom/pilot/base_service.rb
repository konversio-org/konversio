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

        column = "pilot_#{feature}_enabled"
        return false unless account.respond_to?(:pilot_enabled) && account.respond_to?(column)

        account.pilot_enabled && account.public_send(column)
      end

      # Yields a RubyLLM chat context bound to the install-wide credentials,
      # with the cross-provider system-role flag set.
      def chat_context
        ::Llm::Config.with_api_key(::Llm::Config.api_key, api_base: ::Llm::Config.api_base) do |context|
          yield context
        end
      end

      # Dispatch a Pilot telemetry event. Today this just logs; the real
      # EventDispatcher (`Custom::Pilot::EventDispatcher`) lands with section 7
      # of the Pilot tasks. Service code can already call this without rework
      # later.
      def dispatch_event(name, payload = {})
        Rails.logger.info("[pilot.event] #{name} account=#{account&.id} payload=#{payload.except(:transcript, :raw_content).inspect}")
      end

      def logbook_context_for(contact)
        return nil if contact.blank?
        return nil unless feature_enabled?(:logbook)

        entries = ::Pilot::LogbookEntry.where(contact: contact).order(created_at: :desc).limit(20)
        return nil if entries.empty?

        [
          'Context — Logbook entries for this contact (use these to ground your response in customer history):',
          entries.map { |e| "- [#{e.created_at.to_date}] #{e.content}" }.join("\n")
        ].join("\n")
      end
    end
  end
end
