# Policy guarding Pilot Activity events.
#
# Reads are open to any account member. The controller scopes rows through
# `Current.account.pilot_events`, so cross-account events are never exposed.
class Pilot::EventPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end
end
