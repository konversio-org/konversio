module Pilot
  # Policy guarding Pilot Copilot threads.
  #
  # Ownership is per-agent: an agent only sees their own threads. Admins
  # may see every thread in the account.
  #
  # The record is a `Pilot::CopilotThread`. The controller layer is
  # responsible for translating cross-agent access into HTTP 404 (rather
  # than 403) so we don't leak existence — see
  # `Api::V2::Accounts::Pilot::CopilotThreadsController`.
  class CopilotThreadPolicy < ApplicationPolicy
    def index?
      account_user.present?
    end

    def show?
      owned_or_admin?
    end

    def create?
      account_user.present?
    end

    def update?
      owned_or_admin?
    end

    def destroy?
      owned_or_admin?
    end

    private

    def owned_or_admin?
      return false if record.blank?

      administrator? || record.user_id == user&.id
    end

    def administrator?
      account_user&.administrator?
    end
  end
end
