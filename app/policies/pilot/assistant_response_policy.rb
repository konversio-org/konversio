# Policy guarding the Pilot FAQs CRUD endpoints (Api::V1::Accounts::Pilot::AssistantResponsesController).
#
# Admins may list, view, create, update, and delete assistant responses.
# Non-admin agents have no access — the FAQs surface is admin-only per the
# pilot-faqs spec.
class Pilot::AssistantResponsePolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator?
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

  private

  def administrator?
    account_user&.administrator?
  end
end
