class Companies::SyncContactNamesJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 1000

  REWRITE_CONTACT_NAME_SQL = <<~SQL.squish.freeze
    additional_attributes = jsonb_set(
      COALESCE(additional_attributes, '{}'::jsonb),
      '{company_name}',
      ?::jsonb,
      true
    )
  SQL

  def perform(company_id:)
    return if company_id.blank?

    company = Company.find_by(id: company_id)
    return if company.blank?

    rewrite_member_names(company)
  end

  private

  # Denormalized display field only: skip validations and callbacks so the sync
  # cannot trigger contact automations or webhooks.
  # rubocop:disable Rails/SkipsModelValidations
  def rewrite_member_names(company)
    company.contacts.in_batches(of: BATCH_SIZE) do |batch|
      batch.update_all([REWRITE_CONTACT_NAME_SQL, company.name.to_json])
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end
