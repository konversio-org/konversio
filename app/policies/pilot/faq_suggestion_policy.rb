# Policy guarding the FAQ suggestion review endpoints
# (Api::V1::Accounts::Pilot::FaqSuggestionsController).
#
# Any account member may use the endpoints; the real restriction is
# data-level: Pilot::FaqSuggestionFinder scopes visibility so non-admin
# agents only see suggestions observed in conversations they can access.
class Pilot::FaqSuggestionPolicy < ApplicationPolicy
  def index?
    account_member?
  end

  def show?
    account_member?
  end

  def update?
    account_member?
  end

  def approve?
    account_member?
  end

  def dismiss?
    account_member?
  end

  private

  def account_member?
    account_user.present?
  end
end
