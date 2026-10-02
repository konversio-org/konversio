# frozen_string_literal: true

# Builds the bucketed resolution trend series over the current window: buckets
# are calendar days for windows up to 15 days and calendar weeks (Sunday
# start) for longer windows, anchored to the viewer's timezone, partitioning
# the window without gaps or overlaps. Each bucket carries the involved
# episode count, the autonomous resolution count, and the resolution rate
# (null when the bucket has no involved episodes).
#
# The comparison series shifts each bucket back by a whole number of calendar
# weeks chosen to cover the window's span, preserving weekdays and local clock
# times; comparison rates are null when the comparison period predates the
# start of outcome tracking. All buckets — current and comparison — are
# aggregated in a single outcome-table scan via conditional aggregation.
class Pilot::Analytics::ResolutionTrendReport
  C = Pilot::Analytics::OutcomeClassifications

  DAILY_GRANULARITY_LIMIT = 15.days

  pattr_initialize :assistant, :window

  def report
    {
      granularity: granularity,
      buckets: buckets.map { |bucket| serialize_bucket(bucket) }
    }
  end

  private

  def serialize_bucket(bucket)
    {
      start_date: bucket[:start].to_date.iso8601,
      end_date: (bucket[:end] - 1.second).to_date.iso8601,
      involved: counts["current_#{bucket[:key]}_involved"].to_i,
      autonomous: counts["current_#{bucket[:key]}_autonomous"].to_i,
      resolution_rate: bucket_rate(bucket, 'current'),
      comparison: serialize_comparison(bucket)
    }
  end

  def serialize_comparison(bucket)
    bounds = comparison_bounds(bucket)
    {
      start_date: bounds[:start].to_date.iso8601,
      end_date: (bounds[:end] - 1.second).to_date.iso8601,
      resolution_rate: comparison_tracked? ? bucket_rate(bucket, 'comparison') : nil
    }
  end

  def bucket_rate(bucket, series)
    involved = counts["#{series}_#{bucket[:key]}_involved"].to_i
    return if involved.zero?

    (counts["#{series}_#{bucket[:key]}_autonomous"].to_i.to_f / involved).round(4)
  end

  def granularity
    window_span <= DAILY_GRANULARITY_LIMIT.to_f ? 'day' : 'week'
  end

  def buckets
    @buckets ||= begin
      list = []
      boundary = window.current_since
      while boundary < window.current_until
        bucket_end = [next_boundary(boundary), window.current_until].min
        list << { key: list.size, start: boundary, end: bucket_end }
        boundary = bucket_end
      end
      list
    end
  end

  def next_boundary(boundary)
    if granularity == 'day'
      (boundary + 1.day).beginning_of_day
    else
      next_sunday = ((boundary.to_date - boundary.to_date.wday.days) + 7.days).beginning_of_day
      next_sunday <= boundary ? next_sunday + 7.days : next_sunday
    end
  end

  # Shift each bucket back by a whole number of weeks covering the window's
  # span so weekdays and local clock times are preserved.
  def comparison_shift
    @comparison_shift ||= (window_span / 7.days.to_f).ceil.weeks
  end

  def comparison_bounds(bucket)
    { start: bucket[:start] - comparison_shift, end: bucket[:end] - comparison_shift }
  end

  def comparison_tracked?
    tracking_started_at.present? && (window.current_since - comparison_shift) >= tracking_started_at
  end

  def counts
    @counts ||= episode_scope.select(conditional_selects).take.attributes
  end

  def conditional_selects
    selects = []
    buckets.each do |bucket|
      { 'current' => bucket, 'comparison' => comparison_bounds(bucket) }.each do |series, bounds|
        within = "started_at >= #{quote(bounds[:start])} AND started_at < #{quote(bounds[:end])}"
        selects << "COUNT(*) FILTER (WHERE #{within} AND #{C.involved_sql}) AS #{series}_#{bucket[:key]}_involved"
        selects << "COUNT(*) FILTER (WHERE #{within} AND #{C.autonomous_sql}) AS #{series}_#{bucket[:key]}_autonomous"
      end
    end
    selects.join(', ')
  end

  def episode_scope
    Pilot::ConversationOutcome.where(account_id: assistant.account_id, assistant_id: assistant.id)
                              .where('started_at >= ?', window.current_since - comparison_shift)
                              .where('started_at < ?', window.current_until)
  end

  def window_span
    window.current_until - window.current_since
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value.utc)
  end

  def tracking_started_at
    @tracking_started_at ||= Pilot::OutcomeTrackingHistory.tracking_started_at
  end
end
