# Policy guarding Pilot knowledge-source documents
# (Api::V1::Accounts::Pilot::DocumentsController).
#
# Reads (index/show) are open to any account member so agents can review
# the knowledge base. Writes (create/destroy) are admin-only — only admins
# may ingest new sources or remove them. Account scoping is enforced in
# the controller layer (cross-account access surfaces as 404, not 403).
class Pilot::DocumentPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
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
