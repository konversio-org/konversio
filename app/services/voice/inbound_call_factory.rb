class Voice::InboundCallFactory
  pattr_initialize [:inbox!, :call_sid!, :caller!, { provider: :twilio }, { extra_meta: {} }]

  def self.perform!(inbox:, call_sid:, caller:, provider: :twilio, extra_meta: {})
    new(inbox: inbox, call_sid: call_sid, caller: caller, provider: provider, extra_meta: extra_meta).perform!
  end

  def perform!
    existing_call || create_call!
  rescue ActiveRecord::RecordNotUnique
    # A provider retry won the create race; reconcile to the existing row.
    existing_call || raise
  end

  private

  def account
    inbox.account
  end

  def provider_sym
    provider.to_sym
  end

  def existing_call
    Call.where(account_id: account.id, inbox_id: inbox.id)
        .find_by(provider: provider_sym, provider_call_id: call_sid)
  end

  def create_call!
    call = ActiveRecord::Base.transaction do
      contact_inbox = resolve_contact_inbox!
      contact = contact_inbox.contact
      conversation = resolve_conversation!(contact_inbox)
      record = persist_call!(contact, conversation)
      message = Voice::CallMessageFactory.new(record).perform!
      record.update!(message_id: message.id)
      record
    end
    call.broadcast_voice_call_event(:created)
    call
  end

  def resolve_contact_inbox!
    Voice::ContactResolver.new(
      inbox: inbox,
      source_ids: Array(caller[:source_ids]),
      contact_attributes: caller[:contact_attributes] || {},
      prefer_first_source_id: provider_sym == :whatsapp
    ).perform
  end

  def resolve_conversation!(contact_inbox)
    reusable = reusable_conversation(contact_inbox)
    return reusable if reusable

    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      status: :open
    )
  end

  # Scoped to the resolved contact_inbox, never the contact: after a dashboard
  # merge the same contact can hold unrelated WhatsApp identities.
  def reusable_conversation(contact_inbox)
    conversations = contact_inbox.conversations
    return conversations.last if inbox.lock_to_single_conversation

    conversations.where.not(status: :resolved).last
  end

  def persist_call!(contact, conversation)
    call = Call.create!(
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: provider_sym,
      direction: :incoming,
      status: 'ringing',
      provider_call_id: call_sid,
      meta: { 'initiated_at' => Time.zone.now.to_i }.merge((extra_meta || {}).stringify_keys)
    )
    # A conference is a Twilio bridging concept; WhatsApp goes browser↔Meta.
    call.update!(conference_sid: call.default_conference_sid) if call.twilio?
    call
  end
end
