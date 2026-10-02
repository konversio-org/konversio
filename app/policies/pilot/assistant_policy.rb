# Policy guarding Pilot Autopilot assistants.
#
# Reads (index/show) and the playground are open to any account member
# (admin or agent). Writes (create/update/destroy) and the tools registry
# listing are admin-only. The controller layer is responsible for
# account-scoping queries so cross-account access surfaces as 404, not
# 403 — see `Api::V1::Accounts::Pilot::AssistantsController`.
class Pilot::AssistantPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  # Removing a custom avatar is an admin write, same as update.
  def avatar?
    administrator?
  end

  def playground?
    account_user.present?
  end

  # Analytics reads are open to any account member who can view the assistant.
  def overview?
    account_user.present?
  end

  def resolution_flow?
    account_user.present?
  end

  def resolution_trend?
    account_user.present?
  end

  def overview_summary?
    account_user.present?
  end

  # Listing the conversations behind a metric is administrator-only.
  def drilldown?
    administrator?
  end

  def tools?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
