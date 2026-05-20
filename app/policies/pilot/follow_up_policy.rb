module Pilot
  # Policy guarding the Pilot Follow-up endpoint. Agents may request
  # follow-up suggestions for any conversation they can see.
  class FollowUpPolicy < ApplicationPolicy
    def create?
      return false if record.blank?

      ConversationPolicy.new(user_context, record).show?
    end
  end
end
