# frozen_string_literal: true

# Builds the resolution flow for the current window: the involved episode
# cohort splits into three mutually exclusive terminal branches — resolved
# autonomously, handed off, or closed with the team without either — whose
# counts sum to the cohort total; autonomous resolutions then split into
# stayed-closed vs reopened-within-the-durability-window.
#
# The response is renderable as a flow diagram of nodes and weighted links.
# Handed-off episodes are also broken down by their governed handoff-reason
# category (uncategorized episodes grouped into a single bucket, sorted by
# count); the diagram highlights the top reasons as individual branches and
# aggregates the remainder into a single other-reasons branch so link weights
# stay balanced. Windows that predate outcome tracking return empty
# nodes/links and an empty distribution.
class Pilot::Analytics::ResolutionFlowReport
  C = Pilot::Analytics::OutcomeClassifications

  UNCATEGORIZED = 'uncategorized'
  TOP_REASON_LIMIT = 3

  pattr_initialize :assistant, :window

  def report
    return empty_report unless tracked?

    { nodes: nodes, links: links, handoff_reasons: reason_distribution }
  end

  private

  def empty_report
    { nodes: [], links: [], handoff_reasons: [] }
  end

  def tracked?
    tracking_started_at.present? && window.current_since >= tracking_started_at
  end

  def nodes
    @nodes ||= begin
      list = [
        { id: 'involved', value: involved_count },
        { id: 'autonomous', value: autonomous_count },
        { id: 'handed_off', value: handoff_count },
        { id: 'closed_with_team', value: closed_with_team_count },
        { id: 'stayed_closed', value: stayed_closed_count },
        { id: 'reopened', value: reopened_count }
      ]
      highlighted_reasons.each { |reason| list << { id: reason_node_id(reason[:category]), value: reason[:count] } }
      list << { id: 'other_reasons', value: other_reasons_count } if other_reasons_count.positive?
      list
    end
  end

  def links
    @links ||= begin
      list = [
        { source: 'involved', target: 'autonomous', value: autonomous_count },
        { source: 'involved', target: 'handed_off', value: handoff_count },
        { source: 'involved', target: 'closed_with_team', value: closed_with_team_count },
        { source: 'autonomous', target: 'stayed_closed', value: stayed_closed_count },
        { source: 'autonomous', target: 'reopened', value: reopened_count }
      ]
      highlighted_reasons.each do |reason|
        list << { source: 'handed_off', target: reason_node_id(reason[:category]), value: reason[:count] }
      end
      list << { source: 'handed_off', target: 'other_reasons', value: other_reasons_count } if other_reasons_count.positive?
      list
    end
  end

  def reason_distribution
    @reason_distribution ||= begin
      total = handoff_count
      raw_distribution.map do |category, count|
        {
          category: category,
          count: count,
          percentage: total.zero? ? 0 : (count.to_f / total * 100).round(1)
        }
      end
    end
  end

  def highlighted_reasons
    @highlighted_reasons ||= reason_distribution.first(TOP_REASON_LIMIT)
  end

  def other_reasons_count
    reason_distribution.drop(TOP_REASON_LIMIT).sum { |reason| reason[:count] }
  end

  def reason_node_id(category)
    "reason_#{category}"
  end

  def raw_distribution
    @raw_distribution ||= episodes.where(C.handoff_sql)
                                  .group("COALESCE(handoff_reason_category, '#{UNCATEGORIZED}')")
                                  .count
                                  .sort_by { |_, count| -count }
  end

  def closed_with_team_count
    involved_count - autonomous_count - handoff_count
  end

  def stayed_closed_count
    autonomous_count - reopened_count
  end

  def involved_count
    branch_counts['involved'].to_i
  end

  def autonomous_count
    branch_counts['autonomous'].to_i
  end

  def handoff_count
    branch_counts['handoffs'].to_i
  end

  def reopened_count
    branch_counts['reopened'].to_i
  end

  # One scan for all balanced branch counts over the current-window cohort.
  def branch_counts
    @branch_counts ||= episodes.select(
      "COUNT(*) FILTER (WHERE #{C.involved_sql}) AS involved, " \
      "COUNT(*) FILTER (WHERE #{C.autonomous_sql}) AS autonomous, " \
      "COUNT(*) FILTER (WHERE #{C.handoff_sql}) AS handoffs, " \
      "COUNT(*) FILTER (WHERE #{C.reopened_within_durability_sql}) AS reopened"
    ).take.attributes
  end

  def episodes
    Pilot::ConversationOutcome.where(account_id: assistant.account_id, assistant_id: assistant.id,
                                     started_at: window.current)
  end

  def tracking_started_at
    @tracking_started_at ||= Pilot::OutcomeTrackingHistory.tracking_started_at
  end
end
