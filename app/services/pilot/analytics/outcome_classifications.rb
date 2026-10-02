# frozen_string_literal: true

# Shared query-time classification rules for `pilot_conversation_outcomes`
# episodes. Every analytics surface — overview cards, flow diagram, trend
# series, drilldowns — classifies episodes through these predicates so the
# numbers always agree.
#
# Each predicate is returned as a SQL fragment so it composes both with
# `where(...)` and with conditional aggregation (`COUNT(*) FILTER (WHERE ...)`),
# letting reports compute every classification in a single table scan. All
# interpolated values are quoted constants from the episode model, never user
# input.
#
# Definitions:
# - involved:   the AI posted at least one public reply, or the episode was
#               handed off for any reason other than a quota-exhaustion
#               transfer that happened before the AI ever replied (blocked
#               demand, not a failed conversation).
# - autonomous: resolved, AI replied, no handoff, and no human public reply
#               preceded the resolution.
# - assisted:   involved and resolved, but not autonomous.
# - handoff:    involved with a handoff timestamp (quota transfers after AI
#               participation count as real handoffs).
# - reopened:   resolved and the episode later closed at or after the
#               resolution (the recorder stamps a reopen by closing the open
#               episode, so `ended_at` on a resolved episode is the reopen time).
# - durable:    autonomous and not reopened within the durability window.
module Pilot::Analytics::OutcomeClassifications
  DURABILITY_WINDOW = 7.days
  QUOTA_REASON = 'quota_exhausted'

  module_function

  def ai_replied_sql
    'first_ai_reply_at IS NOT NULL'
  end

  def resolved_sql
    'resolved_at IS NOT NULL'
  end

  def involved_sql
    quota = ActiveRecord::Base.connection.quote(QUOTA_REASON)
    <<~SQL.squish
      (#{ai_replied_sql} OR (handoff_at IS NOT NULL AND NOT (handoff_reason_category = #{quota} AND first_ai_reply_at IS NULL)))
    SQL
  end

  def autonomous_sql
    <<~SQL.squish
      (#{resolved_sql} AND #{ai_replied_sql} AND handoff_at IS NULL
        AND (first_human_reply_at IS NULL OR first_human_reply_at >= resolved_at))
    SQL
  end

  def assisted_sql
    "(#{involved_sql} AND #{resolved_sql} AND NOT #{autonomous_sql})"
  end

  def handoff_sql
    "(#{involved_sql} AND handoff_at IS NOT NULL)"
  end

  def reopened_sql
    "(#{resolved_sql} AND ended_at IS NOT NULL AND ended_at >= resolved_at)"
  end

  # A reopen counts against durability only when it lands within the
  # durability window after the resolution.
  def reopened_within_durability_sql
    "(#{reopened_sql} AND ended_at <= resolved_at + INTERVAL '#{DURABILITY_WINDOW.to_i} seconds')"
  end

  # Only resolutions at least one durability window old are judgeable; callers
  # combine this with the window predicate to form the durable-rate denominator.
  def judgeable_sql(reference_time)
    quoted = ActiveRecord::Base.connection.quote(reference_time.utc)
    "(#{autonomous_sql} AND resolved_at <= CAST(#{quoted} AS timestamptz) - INTERVAL '#{DURABILITY_WINDOW.to_i} seconds')"
  end

  def durable_sql
    "(ended_at IS NULL OR ended_at > resolved_at + INTERVAL '#{DURABILITY_WINDOW.to_i} seconds')"
  end
end
