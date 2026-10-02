# frozen_string_literal: true

module ContactCompanyAssociation
  extend ActiveSupport::Concern

  included do
    belongs_to :company, optional: true, counter_cache: true

    scope :order_on_company_name, lambda { |direction|
      order(
        Arel::Nodes::SqlLiteral.new(
          sanitize_sql_for_order("\"contacts\".\"additional_attributes\"->>'company_name' #{direction} NULLS LAST")
        )
      )
    }

    before_save :sync_company_name_to_additional_attributes, if: :will_save_change_to_company_id?
    after_update_commit :rollup_company_activity, if: :saved_change_to_last_activity_at?
    after_commit :associate_company_from_email, on: [:create, :update], if: :should_associate_company?
  end

  private

  # Only attempt association when the contact first gains an email and has no
  # company yet. Cheap in-memory guards run before any external lookup so the
  # hot contact/message ingest path short-circuits.
  def should_associate_company?
    email.present? &&
      company_id.nil? &&
      saved_change_to_email? &&
      saved_change_to_email.first.nil?
  end

  def associate_company_from_email
    Contacts::CompanyAssociationService.new.associate_company_from_email(self)
  rescue StandardError => e
    Rails.logger.error("Company association failed for contact #{id}: #{e.message}")
  end

  def rollup_company_activity
    company&.record_activity_at!(last_activity_at)
  end

  def sync_company_name_to_additional_attributes
    self.additional_attributes ||= {}

    if company_id.present?
      additional_attributes['company_name'] = company&.name
    else
      additional_attributes.delete('company_name')
    end
  end
end
