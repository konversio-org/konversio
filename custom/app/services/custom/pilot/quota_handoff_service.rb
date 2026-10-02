# Single entry point for handing a Pilot conversation off to humans when an
# AI usage-quota signal fires. No quota enforcement exists in the fork today —
# `Account#usage_limits` covers only agents and inboxes and no Pilot path
# produces a quota/402 signal — so nothing calls this yet. The moment an
# enforcement point lands it calls this service, which runs the standard
# handoff categorized as `quota_exhausted` (source `quota`) so outcome
# recording treats the transfer as blocked demand, not a failed conversation.
#
# No assistant-authored message is posted: the reply-fact snapshot counts
# assistant-sent outgoing messages, and a quota block *before the AI ever
# replied* must keep `first_ai_reply_at` empty so reporting can distinguish
# blocked demand from a genuine escalation. The handoff is still documented
# for agents by the timeline activity message.
class Custom::Pilot::QuotaHandoffService
  REASON_CATEGORY = 'quota_exhausted'.freeze
  SOURCE = 'quota'.freeze

  def self.call(conversation:, assistant:)
    ::Custom::Pilot::HandoffService.call(
      conversation: conversation,
      assistant: assistant,
      reason: REASON_CATEGORY,
      source: SOURCE,
      reason_category: REASON_CATEGORY,
      message: nil
    )
  end
end
