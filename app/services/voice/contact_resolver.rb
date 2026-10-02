# Resolves the contact + contact_inbox for a call across every candidate source
# id (phone number plus WhatsApp aliases). A call must land on the same identity
# that messaging already uses, otherwise history splits across two threads.
class Voice::ContactResolver
  pattr_initialize [:inbox!, :source_ids!, { contact_attributes: {} }, { prefer_first_source_id: false }]

  def perform
    ids = Array(source_ids).compact_blank.map(&:to_s)
    existing = find_contact_inbox(ids)
    return existing if existing

    contact = find_contact(ids) || create_contact!
    create_contact_inbox!(contact, ids)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent webhook created the row; return what now exists.
    find_contact_inbox(ids) || raise
  end

  private

  def account
    inbox.account
  end

  def find_contact_inbox(ids)
    return if ids.empty?

    scope = ContactInbox.where(inbox_id: inbox.id, source_id: ids)
    return scope.first unless prefer_first_source_id

    ids.each do |id|
      found = scope.find_by(source_id: id)
      return found if found
    end
    nil
  end

  def find_contact(ids)
    phone = contact_attributes[:phone_number]
    contact = account.contacts.find_by(phone_number: phone) if phone.present?
    contact ||= account.contacts.find_by(identifier: contact_attributes[:identifier]) if contact_attributes[:identifier].present?
    contact ||= ContactInbox.where(inbox_id: inbox.id, source_id: ids).first&.contact if ids.present?
    contact
  end

  def create_contact!
    account.contacts.create!(
      name: contact_attributes[:name].presence || Haikunator.haikunate(1000),
      phone_number: contact_attributes[:phone_number],
      identifier: contact_attributes[:identifier]
    )
  end

  def create_contact_inbox!(contact, ids)
    primary = ids.first
    raise ActionController::ParameterMissing, 'contact source id' if primary.blank?

    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: primary).perform
  end
end
