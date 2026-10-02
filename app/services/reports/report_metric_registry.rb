module Reports::ReportMetricRegistry
  # Describes one public report metric.
  # name: API-facing metric name requested by reports.
  # aggregate: whether the metric is a count or average.
  # raw_event_name: source reporting_events name for raw queries.
  # raw_count_strategy: optional raw-query counting rule, such as distinct conversations.
  Metric = Data.define(
    :name,
    :aggregate,
    :raw_event_name,
    :raw_count_strategy
  ) do
    def initialize(name:, aggregate:, raw_event_name: nil, raw_count_strategy: nil)
      super
    end

    def average?
      aggregate == :average
    end

    def count?
      aggregate == :count
    end
  end

  METRICS = {
    conversations_count: Metric.new(
      name: :conversations_count,
      aggregate: :count
    ),
    incoming_messages_count: Metric.new(
      name: :incoming_messages_count,
      aggregate: :count
    ),
    outgoing_messages_count: Metric.new(
      name: :outgoing_messages_count,
      aggregate: :count
    ),
    avg_first_response_time: Metric.new(
      name: :avg_first_response_time,
      aggregate: :average,
      raw_event_name: :first_response
    ),
    avg_resolution_time: Metric.new(
      name: :avg_resolution_time,
      aggregate: :average,
      raw_event_name: :conversation_resolved
    ),
    reply_time: Metric.new(
      name: :reply_time,
      aggregate: :average,
      raw_event_name: :reply_time
    ),
    resolutions_count: Metric.new(
      name: :resolutions_count,
      aggregate: :count,
      raw_event_name: :conversation_resolved
    ),
    bot_resolutions_count: Metric.new(
      name: :bot_resolutions_count,
      aggregate: :count,
      raw_event_name: :conversation_bot_resolved,
      raw_count_strategy: :exclude_bot_handoffs
    ),
    bot_handoffs_count: Metric.new(
      name: :bot_handoffs_count,
      aggregate: :count,
      raw_event_name: :conversation_bot_handoff,
      raw_count_strategy: :distinct_conversation
    )
  }.freeze

  module_function

  def fetch(name)
    return if name.blank?

    METRICS[name.to_sym]
  end

  def supported?(name)
    fetch(name).present?
  end
end
