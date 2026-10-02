class Companies::ContactMembershipService
  def initialize(company:)
    @company = company
  end

  def assign(contact:)
    contact.update!(company: @company)
    @company.record_activity_at!(contact.last_activity_at)
  end

  def remove(contact:)
    contact.update!(company: nil)
  end
end
