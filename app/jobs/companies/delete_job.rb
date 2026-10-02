class Companies::DeleteJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 1000

  DETACH_CONTACTS_SQL = <<~SQL.squish.freeze
    company_id = NULL,
    additional_attributes = COALESCE(additional_attributes, '{}'::jsonb) - 'company_name'
  SQL

  def perform(company_id:)
    company = Company.find_by(id: company_id)
    return if company.blank?

    detach_members(company)
    company.destroy!
  end

  private

  # Bypass contact callbacks so detaching members never dispatches contact
  # automations or webhooks.
  # rubocop:disable Rails/SkipsModelValidations
  def detach_members(company)
    company.contacts.in_batches(of: BATCH_SIZE) do |batch|
      batch.update_all(DETACH_CONTACTS_SQL)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end
