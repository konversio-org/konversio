module Pilot
  # Policy guarding the Pilot Summary endpoint. Agents may request a
  # summary for any conversation they can see via the normal
  # Chatwoot conversation-access rules.
  class SummaryPolicy < ApplicationPolicy
    def create?
      return false if record.blank?

      ConversationPolicy.new(user_context, record).show?
    end
  end
end
