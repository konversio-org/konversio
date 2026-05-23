# frozen_string_literal: true

module Custom
  module Pilot
    # Single entry point for every Pilot telemetry event.
    #
    # Responsibilities:
    #   * Redact sensitive fields via {PayloadRedactor}
    #   * Persist a row to `pilot_events` for the Activity view
    #   * Forward to the host `Rails.configuration.dispatcher` so existing
    #     webhook + ActionCable + reporting machinery picks the event up
    #   * Persist long-lived `pilot_reporting_events` rows for inference-
    #     driven conversation outcomes (auto-resolve, handover)
    #
    # Per pilot-telemetry spec "Dispatcher exception handling": every
    # listener invocation here is wrapped in `rescue StandardError` and
    # reported via `Rails.error.report` (or KonversioExceptionTracker
    # where available) so a single listener failure cannot abort the
    # originating Pilot operation.
    class EventDispatcher
      # Conversation-outcome events that should write a row into
      # `pilot_reporting_events` for long-term reporting. The companion
      # host event written alongside (e.g. `conversation_bot_handoff`) is
      # handled by the host's existing reporting listener and re-emitted
      # here as a Pilot row keyed against the same conversation.
      INFERENCE_OUTCOME_EVENTS = %w[
        pilot.autopilot.handover.triggered
      ].freeze

      # Companion host-fired event names that get a paired Pilot reporting
      # row so existing BI dashboards stay symmetrical.
      HOST_OUTCOME_COMPANION = {
        'pilot.autopilot.handover.triggered' => 'conversation.bot_handoff'
      }.freeze

      def self.dispatch(name, payload = {}, time: nil, account: nil)
        new.dispatch(name, payload, time: time, account: account)
      end

      def dispatch(name, payload = {}, time: nil, account: nil)
        event_time = time || Time.zone.now
        sanitized = PayloadRedactor.call(payload || {})
        resolved_account = account || resolve_account(sanitized)

        run_listener(:persist_event, name) { persist_event(name, sanitized, event_time, resolved_account) }
        run_listener(:host_dispatcher, name) { dispatch_to_host(name, event_time, sanitized) }
        run_listener(:reporting_event, name) { persist_reporting_events(name, payload, event_time, resolved_account) }
        run_listener(:action_cable, name) { broadcast_to_cable(name, sanitized, event_time, resolved_account) }

        true
      end

      private

      def run_listener(listener_name, event_name)
        yield
      rescue StandardError => e
        report_exception(e, listener: listener_name, event: event_name)
      end

      def report_exception(error, listener:, event:)
        Rails.logger.error("[pilot.event_dispatcher] listener=#{listener} event=#{event} #{error.class}: #{error.message}")

        if defined?(::KonversioExceptionTracker)
          ::KonversioExceptionTracker.new(error).capture_exception
        elsif Rails.respond_to?(:error) && Rails.error.respond_to?(:report)
          Rails.error.report(error, context: { listener: listener, event: event })
        end
      end

      def persist_event(name, payload, time, account)
        return if account.blank?

        related_type, related_id = extract_related_entity(payload)

        ::Pilot::Event.create!(
          account_id: account.id,
          event_name: name.to_s,
          payload: payload.deep_stringify_keys,
          related_entity_type: related_type,
          related_entity_id: related_id,
          created_at: time
        )
      end

      def dispatch_to_host(name, time, payload)
        return unless Rails.configuration.respond_to?(:dispatcher)
        return if Rails.configuration.dispatcher.blank?

        Rails.configuration.dispatcher.dispatch(name.to_s, time, payload)
      end

      def broadcast_to_cable(name, payload, time, account)
        return if account.blank?

        ::ActionCable.server.broadcast(
          "pilot_events_#{account.id}",
          { event: name.to_s, timestamp: time.to_i, payload: payload }
        )
      end

      def persist_reporting_events(name, raw_payload, time, account)
        return if account.blank?
        return unless INFERENCE_OUTCOME_EVENTS.include?(name.to_s)

        conversation = extract_conversation(raw_payload)
        return if conversation.blank?

        attrs = base_reporting_attrs(conversation, account, time)
        ::Pilot::ReportingEvent.create!(attrs.merge(name: name.to_s))

        companion = HOST_OUTCOME_COMPANION[name.to_s]
        ::Pilot::ReportingEvent.create!(attrs.merge(name: companion)) if companion
      end

      def base_reporting_attrs(conversation, account, time)
        start_at = conversation.created_at
        end_at = time
        value = (end_at.to_i - start_at.to_i).to_f
        bh_value = BusinessHoursCalculator.call(inbox: conversation.inbox, from: start_at, to: end_at)

        {
          account_id: account.id,
          inbox_id: conversation.inbox_id,
          user_id: nil,
          conversation_id: conversation.id,
          event_start_at: start_at,
          event_end_at: end_at,
          value: value,
          value_in_business_hours: bh_value,
          created_at: time
        }
      end

      def resolve_account(payload)
        account_id = payload[:account_id] || payload['account_id']
        return nil if account_id.blank?

        ::Account.find_by(id: account_id)
      end

      def extract_conversation(payload)
        conversation = payload[:conversation] || payload['conversation']
        return conversation if conversation.is_a?(::Conversation)

        id = payload[:conversation_db_id] || payload['conversation_db_id'] ||
             extract_envelope_conversation_id(payload)
        ::Conversation.find_by(id: id) if id.present?
      end

      def extract_envelope_conversation_id(payload)
        envelope = payload[:conversation_envelope] || payload['conversation_envelope']
        return nil if envelope.blank?

        envelope[:id] || envelope['id']
      end

      def extract_related_entity(payload)
        return [nil, nil] unless payload.is_a?(Hash)

        conversation_id = envelope_conversation_id(payload)
        return ['Conversation', conversation_id] if conversation_id

        assistant_id = payload[:assistant_id] || payload['assistant_id']
        return ['Pilot::Assistant', assistant_id] if assistant_id

        [nil, nil]
      end

      def envelope_conversation_id(payload)
        envelope = payload[:conversation_envelope] || payload['conversation_envelope']
        return nil unless envelope.is_a?(Hash)

        envelope[:id] || envelope['id']
      end
    end
  end
end
