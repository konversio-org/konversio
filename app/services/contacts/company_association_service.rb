class Contacts::CompanyAssociationService
  def associate_company_from_email(contact)
    return nil if contact.company_id.present?
    return nil if contact.email.blank?
    return nil unless Companies::BusinessEmailDetectorService.new(contact.email).perform

    company = find_or_create_company(contact)
    return nil if company.blank?

    link_contact(contact, company)
    company
  end

  private

  def link_contact(contact, company)
    # Write directly to skip contact callbacks so association never fans out
    # into automations or webhooks; keep the counter cache in sync manually.
    # rubocop:disable Rails/SkipsModelValidations
    contact.update_columns(
      company_id: company.id,
      additional_attributes: contact.additional_attributes.to_h.merge('company_name' => company.name)
    )
    Company.increment_counter(:contacts_count, company.id)
    # rubocop:enable Rails/SkipsModelValidations
    company.record_activity_at!(contact.last_activity_at)
  end

  def find_or_create_company(contact)
    domain = domain_from(contact.email)

    found = Company.find_by(account: contact.account, domain: domain)
    return found if found

    Company.create!(account: contact.account, domain: domain, name: humanized_name(domain))
  rescue ActiveRecord::RecordNotUnique
    Company.find_by(account: contact.account, domain: domain)
  end

  def domain_from(email)
    email.to_s.split('@').last.to_s.downcase
  end

  def humanized_name(domain)
    domain.split('.').first.to_s.tr('-_', ' ').titleize
  end
end
