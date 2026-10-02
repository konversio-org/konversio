# frozen_string_literal: true

# Lists the conversations behind a supported overview metric for administrator
# drilldowns. Each cohort is defined to match exactly what its metric card
# counted in the current window:
# - conversations_involved: conversations with at least one public AI-authored
#   reply in the window;
# - autonomous_resolution_rate: involved conversations with a countable AI
#   resolution event in the window, excluding time-based bot resolutions on
#   conversations that were also handed off;
# - handoff_rate: involved conversations with a handoff event in the window;
# - reopen_after_resolution_rate: auto-resolved conversations that reopened at
#   or after their AI resolution, with the reopen inside the window.
#
# Records are serialized with the shared reports drilldown serializer so the
# existing drawer/card components render them unchanged.
class Pilot::Analytics::DrilldownQuery
  class UnsupportedMetricError < StandardError; end

  SUPPORTED_METRICS = %w[
    conversations_involved
    autonomous_resolution_rate
    handoff_rate
    reopen_after_resolution_rate
  ].freeze
  RESOLUTION_EVENT_NAMES = %w[conversation_pilot_inference_resolved conversation_bot_resolved].freeze
  HANDOFF_EVENT_NAMES = %w[conversation_pilot_inference_handoff conversation_bot_handoff].freeze
  BOT_RESOLUTION_EVENT = 'conversation_bot_resolved'
  REOPEN_EVENT = 'conversation_opened'

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  pattr_initialize [:assistant!, :window!, :metric!, { page: nil, per_page: nil }]

  def self.supported_metric?(metric)
    SUPPORTED_METRICS.include?(metric.to_s)
  end

  def build
    raise UnsupportedMetricError, "Unsupported drilldown metric: #{metric}" unless self.class.supported_metric?(metric)

    records = paginated_records.to_a
    { meta: meta, payload: records.map { |record| record_serializer(records).serialize(record) } }
  end

  private

  def meta
    {
      metric: metric,
      current_page: current_page,
      per_page: per_page_size,
      total_count: paginated_records.total_count,
      since: window.current.begin.to_i,
      until: window.current.end.to_i
    }
  end

  def paginated_records
    @paginated_records ||= conversation_scope.page(current_page).per(per_page_size)
  end

  def conversation_scope
    Conversation.where(account_id: assistant.account_id, id: cohort_conversation_ids)
                .includes(:assignee, :contact, :inbox)
                .order(last_activity_at: :desc)
  end

  def cohort_conversation_ids
    case metric
    when 'conversations_involved' then involved_conversation_ids
    when 'autonomous_resolution_rate' then resolved_conversation_ids.where(conversation_id: involved_conversation_ids)
    when 'handoff_rate' then handed_off_conversation_ids.where(conversation_id: involved_conversation_ids)
    when 'reopen_after_resolution_rate' then reopened_conversation_ids.select(:id)
    end
  end

  # Involved cohort: conversations with at least one AI-authored public reply
  # in the window.
  def involved_conversation_ids
    Message.where(account_id: assistant.account_id, sender_type: 'Pilot::Assistant', sender_id: assistant.id,
                  message_type: :outgoing, private: false, created_at: window.current)
           .select(:conversation_id).distinct
  end

  def resolved_conversation_ids
    ai_resolution_events.where.not(conversation_id: nil).select(:conversation_id).distinct
  end

  def handed_off_conversation_ids
    ReportingEvent.where(account_id: assistant.account_id, name: HANDOFF_EVENT_NAMES, created_at: window.current)
                  .where.not(conversation_id: nil)
                  .select(:conversation_id).distinct
  end

  # Reopen events (a conversation leaving `resolved`) inside the window, at or
  # after an AI resolution on the same conversation. The resolution itself may
  # precede the window; the exclusion of time-based bot resolutions on handed-
  # off conversations mirrors the resolved cohort.
  def reopened_conversation_ids
    Conversation.where("conversations.id IN (#{reopened_conversation_ids_sql})")
  end

  def reopened_conversation_ids_sql
    <<~SQL.squish
      SELECT DISTINCT o.conversation_id FROM reporting_events o
      WHERE o.account_id = #{assistant.account_id.to_i}
        AND o.name = #{quote(REOPEN_EVENT)}
        AND o.created_at >= #{quote(window.current.begin.utc)}
        AND o.created_at < #{quote(window.current.end.utc)}
        AND o.conversation_id IS NOT NULL
        AND EXISTS (#{ai_resolution_before_reopen_sql})
    SQL
  end

  def ai_resolution_before_reopen_sql
    <<~SQL.squish
      SELECT 1 FROM reporting_events r
      WHERE r.account_id = o.account_id
        AND r.conversation_id = o.conversation_id
        AND r.name IN (#{quote(RESOLUTION_EVENT_NAMES[0])}, #{quote(RESOLUTION_EVENT_NAMES[1])})
        AND r.event_end_time <= o.event_end_time
        AND NOT (
          r.name = #{quote(BOT_RESOLUTION_EVENT)}
          AND EXISTS (
            SELECT 1 FROM reporting_events h
            WHERE h.account_id = o.account_id
              AND h.conversation_id = o.conversation_id
              AND h.name IN (#{quote(HANDOFF_EVENT_NAMES[0])}, #{quote(HANDOFF_EVENT_NAMES[1])})
          )
        )
    SQL
  end

  # Countable AI resolutions: Pilot inference resolutions, plus time-based bot
  # resolutions — except time-based closures on conversations that were also
  # handed off (those are human-owned endings, not autonomous resolutions).
  def ai_resolution_events
    scope = ReportingEvent.where(account_id: assistant.account_id, name: RESOLUTION_EVENT_NAMES, created_at: window.current)
    excluded_bot_closures = scope.where(name: BOT_RESOLUTION_EVENT, conversation_id: handed_off_conversation_ids)
    scope.where.not(id: excluded_bot_closures.select(:id))
  end

  def record_serializer(records)
    V2::Reports::DrilldownRecordSerializer.new(assistant.account, metric, false, records)
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end

  def current_page
    [page.to_i, DEFAULT_PAGE].max
  end

  def per_page_size
    requested = per_page.to_i
    requested = DEFAULT_PER_PAGE if requested <= 0

    [requested, MAX_PER_PAGE].min
  end
end
