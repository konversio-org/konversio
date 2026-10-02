class Voice::OutboundCallFactory
  pattr_initialize [:account!, :inbox!, :user!, :contact!, { conversation: nil }]

  def self.perform!(account:, inbox:, user:, contact:, conversation: nil)
    new(account: account, inbox: inbox, user: user, contact: contact, conversation: conversation).perform!
  end

  def perform!
    raise ArgumentError, 'Contact phone number required' if contact.phone_number.blank?
    raise ArgumentError, 'Agent required' if user.blank?

    # Claim a reused, unassigned conversation for the caller; a new conversation
    # gets the assignee at creation instead.
    claim_for_caller = conversation.present? && conversation.assigned_entity.nil?

    call = ActiveRecord::Base.transaction do
      contact_inbox = ensure_contact_inbox!
      target = conversation || create_conversation!(contact_inbox)
      # Dial before locking so the provider round-trip doesn't hold a row lock.
      call_sid = initiate_call!
      claim_conversation!(target) if claim_for_caller
      record = persist_call!(target, call_sid)
      message = Voice::CallMessageFactory.new(record).perform!
      record.update!(message_id: message.id)
      record
    end
    call.broadcast_voice_call_event(:created, accepted_by_agent_id: call.accepted_by_agent_id)
    call
  end

  private

  def ensure_contact_inbox!
    ContactInbox.find_or_create_by!(contact_id: contact.id, inbox_id: inbox.id) do |record|
      record.source_id = contact.phone_number
    end
  end

  def create_conversation!(contact_inbox)
    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      assignee_id: user.id,
      status: :open
    )
  end

  def initiate_call!
    inbox.channel.initiate_call(to: contact.phone_number)[:call_sid]
  end

  def claim_conversation!(target)
    target.reload.with_lock { target.update!(assignee: user) }
  end

  def persist_call!(target, call_sid)
    call = Call.create!(
      account: account,
      inbox: inbox,
      conversation: target,
      contact: contact,
      accepted_by_agent: user,
      provider: :twilio,
      direction: :outgoing,
      status: 'ringing',
      provider_call_id: call_sid,
      meta: { 'initiated_at' => Time.zone.now.to_i }
    )
    call.update!(conference_sid: call.default_conference_sid)
    call
  end
end
