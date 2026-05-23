# Policy guarding Pilot Custom Tools.
#
# Reads (index/show) are open to any account member (admin or agent).
# Writes (create/update/destroy) and the testing endpoint are admin-only.
# Scoping query is handled at the controller level to return 404 for cross-account access.
class Pilot::CustomToolPolicy < ApplicationPolicy
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

  def test?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
