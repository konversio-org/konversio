class Whatsapp::CallConversationResolver
  pattr_initialize [:inbox!, :contact!, :user!]

  # Mirrors the continuity rule used for inbound messages: locked inboxes hold
  # each WhatsApp identity to one thread; otherwise reuse the newest visible,
  # non-resolved thread.
  def existing_conversation
    return contact_conversations.first if inbox.lock_to_single_conversation

    Conversations::PermissionFilterService.new(
      contact_conversations.where.not(status: :resolved), user, inbox.account
    ).perform.first
  end

  def new_conversation
    inbox.account.conversations.new(inbox: inbox, contact: contact, assignee_id: user.id, status: :open)
  end

  # Unsaved, so callers can authorize the thread a call would open before dialing.
  def perform!
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform

    conversation = contact_inbox.with_lock do
      existing_conversation || new_conversation.tap { |record| record.update!(contact_inbox: contact_inbox) }
    end

    conversation.tap { |record| record.reload if record.changed? }
  end

  private

  def contact_conversations
    source_id = contact.phone_number&.delete('+')
    inbox.conversations
         .joins(:contact_inbox)
         .where(contact_id: contact.id, contact_inboxes: { source_id: source_id })
         .order(last_activity_at: :desc)
  end
end
