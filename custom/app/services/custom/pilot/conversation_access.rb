module Custom
  module Pilot
    # Resolves the conversations an agent may reference from a Copilot surface.
    #
    # Access mirrors the account's conversation-list visibility: administrators
    # may reference any conversation in the account, while non-admin agents are
    # limited to the conversations the platform's permission model already
    # grants them. Resolution delegates to the existing
    # `Conversations::PermissionFilterService` rather than introducing a
    # parallel ACL — see openspec change pilot-reply-suggestion
    # (pilot-copilot-conversation-access).
    class ConversationAccess
      def self.accessible?(account:, user:, conversation:)
        new(account: account, user: user).accessible?(conversation)
      end

      def initialize(account:, user:)
        @account = account
        @user = user
      end

      def accessible?(conversation)
        return false if conversation.blank? || account.blank? || user.blank?
        return false unless conversation.account_id == account.id

        accessible_scope.exists?(id: conversation.id)
      end

      private

      attr_reader :account, :user

      def accessible_scope
        ::Conversations::PermissionFilterService
          .new(account.conversations, user, account)
          .perform
      end
    end
  end
end
