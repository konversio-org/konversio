# frozen_string_literal: true

# Computes the per-assistant overview metric set for the current and previous
# reporting windows. Episode-derived funnel and outcome metrics are grouped by
# episode start (a stable cohort as later facts arrive); public-reply activity
# is message-derived because episode reply facts are snapshotted at terminal
# events and would report stale counts for active episodes.
#
# Every metric is packed as { current, previous, trend }; windows that start
# before outcome tracking began return null values (never fabricated zeros)
# and therefore a null trend. Trend semantics differ by metric kind: percent
# change for counts, point difference for rates, absolute difference for
# durations and scores.
#
# Both windows' aggregates are computed in single scans with conditional
# aggregation — one scan over episodes, one over messages, one over CSAT
# responses — so the reopen-after-resolution rate reuses the already-fetched
# autonomous-resolution total as its denominator and never issues a second
# query (and none at all when nothing was resolved).
class Pilot::Analytics::OverviewReport
  C = Pilot::Analytics::OutcomeClassifications

  # Documented assumption: an AI public reply saves two minutes of agent
  # handling effort. Reporting data captures customer wait time, not agent
  # effort, so this is an estimate and is labeled as such in the UI.
  ASSUMED_HANDLING_MINUTES_PER_REPLY = 2

  pattr_initialize :assistant, :window

  def report
    {
      tracking_started_at: tracking_started_at,
      metrics: {
        conversations_involved: pack(:involved, :percent),
        autonomous_resolutions: pack(:autonomous, :percent),
        autonomous_resolution_rate: pack(:autonomous_rate, :point),
        handoffs: pack(:handoffs, :percent),
        handoff_rate: pack(:handoff_rate, :point),
        estimated_hours_saved: pack(:hours_saved, :percent),
        conversation_depth: pack(:depth, :absolute),
        reopen_after_resolution_rate: pack(:reopen_rate, :point),
        durable_resolution_rate: pack(:durable_rate, :point),
        autonomous_csat: pack(:autonomous_csat, :absolute),
        assisted_csat: pack(:assisted_csat, :absolute),
        human_only_csat: pack(:human_only_csat, :absolute),
        median_resolution_seconds: pack(:median_seconds, :absolute)
      }
    }
  end

  private

  def pack(key, mode)
    current = current_values&.[](key)
    previous = previous_values&.[](key)
    { current: current, previous: previous, trend: trend(current, previous, mode) }
  end

  def trend(current, previous, mode)
    return if current.nil? || previous.nil?

    case mode
    when :percent then previous.zero? ? 0 : ((current - previous) / previous.to_f * 100).round(1)
    when :point then (current - previous).round(4)
    when :absolute then (current - previous).round(2)
    end
  end

  def current_values
    @current_values ||= tracked?(window.current_since) ? window_values(:current) : nil
  end

  def previous_values
    @previous_values ||= tracked?(window.previous_since) ? window_values(:previous) : nil
  end

  def tracked?(window_since)
    tracking_started_at.present? && window_since >= tracking_started_at
  end

  def window_values(prefix)
    counts = window_counts(prefix)
    counts.slice(:involved, :autonomous, :handoffs).merge(
      derived_values(prefix, counts)
    )
  end

  def derived_values(prefix, counts)
    rate_values(counts).merge(activity_values(counts), score_values(prefix))
  end

  def rate_values(counts)
    {
      autonomous_rate: ratio(counts[:autonomous], counts[:involved]),
      handoff_rate: ratio(counts[:handoffs], counts[:involved]),
      reopen_rate: ratio(counts[:reopened], counts[:autonomous]),
      durable_rate: counts[:durable_judged].zero? ? nil : (counts[:durable_held].to_f / counts[:durable_judged]).round(4)
    }
  end

  def activity_values(counts)
    {
      hours_saved: (counts[:replies] * ASSUMED_HANDLING_MINUTES_PER_REPLY / 60.0).round(1),
      depth: counts[:reply_conversations].zero? ? 0 : (counts[:replies].to_f / counts[:reply_conversations]).round(2)
    }
  end

  def score_values(prefix)
    {
      autonomous_csat: episode_aggregates["#{prefix}_autonomous_csat"]&.to_f&.round(2),
      assisted_csat: episode_aggregates["#{prefix}_assisted_csat"]&.to_f&.round(2),
      human_only_csat: csat_aggregates["#{prefix}_human_only_csat"]&.to_f&.round(2),
      median_seconds: episode_aggregates["#{prefix}_median_seconds"]&.to_f&.round
    }
  end

  def window_counts(prefix)
    {
      involved: episode_aggregates["#{prefix}_involved"].to_i,
      autonomous: episode_aggregates["#{prefix}_autonomous"].to_i,
      handoffs: episode_aggregates["#{prefix}_handoffs"].to_i,
      reopened: episode_aggregates["#{prefix}_reopened"].to_i,
      durable_judged: episode_aggregates["#{prefix}_durable_judged"].to_i,
      durable_held: episode_aggregates["#{prefix}_durable_held"].to_i,
      replies: message_aggregates["#{prefix}_replies"].to_i,
      reply_conversations: message_aggregates["#{prefix}_reply_conversations"].to_i
    }
  end

  def ratio(numerator, denominator)
    return 0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end

  def episode_aggregates
    @episode_aggregates ||= episodes.select(episode_selects).take.attributes
  end

  def message_aggregates
    @message_aggregates ||= message_scope.select(message_selects).take.attributes
  end

  def csat_aggregates
    @csat_aggregates ||= human_only_csat_scope.select(csat_selects).take.attributes
  end

  def episodes
    Pilot::ConversationOutcome.where(account_id: account_id, assistant_id: assistant.id)
                              .where('started_at < ?', window.current_until)
  end

  def message_scope
    Message.where(account_id: account_id, sender_type: 'Pilot::Assistant', sender_id: assistant.id,
                  message_type: :outgoing, private: false)
           .where('created_at < ?', window.current_until)
  end

  # Account-wide baseline: conversations in the window with no AI involvement
  # at all (any assistant), so operators can compare like with like.
  def human_only_csat_scope
    CsatSurveyResponse.where(account_id: account_id)
                      .where.not(conversation_id: Pilot::ConversationOutcome.where(account_id: account_id).select(:conversation_id))
                      .where('created_at < ?', window.current_until)
  end

  def episode_selects
    { current: window.current, previous: window.previous }
      .map { |prefix, range| window_episode_selects(prefix, range) }
      .join(', ')
  end

  def window_episode_selects(prefix, range)
    started = started_within(range)
    [
      "COUNT(*) FILTER (WHERE #{started} AND #{C.involved_sql}) AS #{prefix}_involved",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.autonomous_sql}) AS #{prefix}_autonomous",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.handoff_sql}) AS #{prefix}_handoffs",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.assisted_sql}) AS #{prefix}_assisted",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.autonomous_sql} AND #{reopened_within(range)}) AS #{prefix}_reopened",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.judgeable_sql(Time.current)}) AS #{prefix}_durable_judged",
      "COUNT(*) FILTER (WHERE #{started} AND #{C.judgeable_sql(Time.current)} AND #{C.durable_sql}) AS #{prefix}_durable_held",
      "AVG(csat_rating) FILTER (WHERE #{started} AND #{C.autonomous_sql} AND csat_rating IS NOT NULL) AS #{prefix}_autonomous_csat",
      "AVG(csat_rating) FILTER (WHERE #{started} AND #{C.assisted_sql} AND csat_rating IS NOT NULL) AS #{prefix}_assisted_csat",
      median_select(started, prefix)
    ].join(', ')
  end

  def median_select(started, prefix)
    <<~SQL.squish
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (resolved_at - started_at)))
        FILTER (WHERE #{started} AND #{C.involved_sql} AND #{C.resolved_sql}) AS #{prefix}_median_seconds
    SQL
  end

  def message_selects
    { current: window.current, previous: window.previous }.map do |prefix, range|
      within = "created_at >= #{quote(range.begin)} AND created_at < #{quote(range.end)}"
      "COUNT(*) FILTER (WHERE #{within}) AS #{prefix}_replies, " \
        "COUNT(DISTINCT conversation_id) FILTER (WHERE #{within}) AS #{prefix}_reply_conversations"
    end.join(', ')
  end

  def csat_selects
    { current: window.current, previous: window.previous }.map do |prefix, range|
      "AVG(rating) FILTER (WHERE created_at >= #{quote(range.begin)} AND created_at < #{quote(range.end)}) AS #{prefix}_human_only_csat"
    end.join(', ')
  end

  # Reopen events at or after the AI resolution, with the reopen inside the window.
  def reopened_within(range)
    "(ended_at IS NOT NULL AND ended_at >= resolved_at AND ended_at < #{quote(range.end)})"
  end

  def started_within(range)
    "(started_at >= #{quote(range.begin)} AND started_at < #{quote(range.end)})"
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value.utc)
  end

  def tracking_started_at
    @tracking_started_at ||= Pilot::OutcomeTrackingHistory.tracking_started_at
  end

  def account_id
    assistant.account_id
  end
end
