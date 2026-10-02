# frozen_string_literal: true

# Resolves the current and comparison reporting windows for Pilot assistant
# analytics from a `range` parameter and the viewer's UTC offset in hours (as
# the existing reports API sends it). Every analytics endpoint — and every
# drilldown — resolves windows through this one service so a stat card and its
# drilldown always cover exactly the same rows.
#
# Supported ranges: day counts ("7", "30", "90") and named calendar periods
# ("this_week", "last_week", "this_month", "last_month"). Unknown values fall
# back to the 7-day window. Day-count windows are aligned to whole calendar
# days on the viewer's clock, ending now; named periods follow calendar
# boundaries (weeks start on Sunday). The previous window mirrors the current
# one: the full preceding span for day counts and completed periods, or the
# preceding calendar week/month up to the same elapsed offset for partial
# periods, clamped to that period's end so no day is counted twice.
#
# Internally all boundaries are computed on a "viewer wall clock" (UTC shifted
# by the supplied offset) and shifted back at the edges, so calendar
# boundaries land exactly on the viewer's day without depending on the DST
# rules of any named timezone.
#
# Windows are half-open [since, until): the shared boundary between previous
# and current belongs to the current window only.
class Pilot::Analytics::ReportingWindow
  DAY_RANGES = %w[7 30 90].freeze
  NAMED_RANGES = %w[this_week last_week this_month last_month].freeze
  DEFAULT_RANGE = '7'

  RANGE_LABELS = {
    '7' => 'Last 7 days',
    '30' => 'Last 30 days',
    '90' => 'Last 90 days',
    'this_week' => 'This week',
    'last_week' => 'Last week',
    'this_month' => 'This month',
    'last_month' => 'Last month'
  }.freeze

  attr_reader :range, :timezone_offset

  def initialize(range:, timezone_offset: nil, now: nil)
    @range = normalize_range(range)
    @timezone_offset = timezone_offset
    @now_utc = (now || Time.current).utc
  end

  def current
    to_utc(current_since_local)...to_utc(current_until_local)
  end

  def previous
    to_utc(previous_since_local)...to_utc(previous_until_local)
  end

  def current_since
    current.begin
  end

  def current_until
    current.end
  end

  def previous_since
    previous.begin
  end

  def previous_until
    previous.end
  end

  # False only when a non-blank offset cannot be parsed as hours. Blank means
  # "not supplied" and quietly falls back to the server timezone (offset 0
  # relative to UTC timestamps, which is how the rest of the app reads them).
  def timezone_valid?
    return true if timezone_offset.blank?

    !offset_hours.nil?
  end

  # Human-readable descriptor of the current window, for LLM prompts and logs.
  def period
    {
      label: RANGE_LABELS.fetch(range),
      start_date: current_since_local.to_date.iso8601,
      end_date: (current_until_local - 1.second).to_date.iso8601
    }
  end

  private

  attr_reader :now_utc

  def normalize_range(value)
    candidate = value.to_s
    return candidate if DAY_RANGES.include?(candidate) || NAMED_RANGES.include?(candidate)

    DEFAULT_RANGE
  end

  def offset_hours
    @offset_hours ||= timezone_offset.present? ? Float(timezone_offset, exception: false) : nil
  end

  def offset_seconds
    (offset_hours || 0) * 3600
  end

  def now_local
    now_utc + offset_seconds
  end

  def to_utc(local_time)
    local_time - offset_seconds
  end

  # "last_week"/"last_month" are complete calendar periods. "this_week" and
  # "this_month" are still elapsing: the previous window mirrors only the same
  # elapsed offset into the preceding period (clamped to that period's end).
  # Day counts end now but their previous window is the full span immediately
  # preceding the current one.
  def full_period?
    %w[last_week last_month].include?(range)
  end

  def partial_period?
    %w[this_week this_month].include?(range)
  end

  def current_since_local
    @current_since_local ||= period_start(range)
  end

  def current_until_local
    @current_until_local ||= full_period? ? advance_period(current_since_local) : now_local
  end

  def previous_since_local
    @previous_since_local ||= retreat_period(current_since_local)
  end

  def previous_until_local
    @previous_until_local ||= compute_previous_until_local
  end

  def compute_previous_until_local
    return current_since_local unless partial_period?

    candidate = previous_since_local + (current_until_local - current_since_local)
    [candidate, current_since_local].min
  end

  def period_start(range_key)
    case range_key
    when '7', '30', '90' then local_midnight(now_local.to_date - (range_key.to_i - 1).days)
    when 'this_week' then week_start(now_local.to_date)
    when 'last_week' then week_start(now_local.to_date) - 7.days
    when 'this_month' then local_midnight(now_local.to_date.beginning_of_month)
    when 'last_month' then local_midnight(now_local.to_date.beginning_of_month - 1.month)
    end
  end

  def advance_period(from)
    case range
    when '7', '30', '90' then from + range.to_i.days
    when 'this_week', 'last_week' then from + 7.days
    else from + 1.month
    end
  end

  def retreat_period(from)
    case range
    when '7', '30', '90' then from - range.to_i.days
    when 'this_week', 'last_week' then from - 7.days
    else from - 1.month
    end
  end

  # Weeks start on Sunday, matching existing reports conventions.
  def week_start(date)
    local_midnight(date - date.wday.days)
  end

  def local_midnight(date)
    Time.utc(date.year, date.month, date.day)
  end
end
