module Pilot
  # Policy guarding the Pilot Briefing endpoint.
  #
  # The record is a `Conversation`. An agent may request a briefing for a
  # conversation if they have access to it via the normal Chatwoot
  # conversation-access rules (administrators, agents on the inbox, agents on
  # the team, or the assignee).
  class BriefingPolicy < ApplicationPolicy
    def create?
      return false if record.blank?

      ConversationPolicy.new(user_context, record).show?
    end
  end
end
