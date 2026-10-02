# == Schema Information
#
# Table name: companies
#
#  additional_attributes :jsonb
#  custom_attributes     :jsonb
#  last_activity_at      :datetime
#  id             :bigint           not null, primary key
#  contacts_count :integer
#  description    :text
#  domain         :string
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_companies_on_account_and_domain   (account_id,domain) UNIQUE WHERE (domain IS NOT NULL)
#  index_companies_on_account_id           (account_id)
#  index_companies_on_name_and_account_id  (name,account_id)
#
class Company < ApplicationRecord
  include Avatarable

  # A company row is not rewritten while its stored activity is this fresh, so a
  # burst of member events collapses into a single company update.
  ACTIVITY_ROLLUP_WINDOW = 5.minutes

  # Dotted hostname: one or more labels, each alphanumeric with internal hyphens,
  # ending in an alphabetic TLD. Rejects schemes, paths, spaces and bare labels.
  HOSTNAME_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/i

  validates :account_id, presence: true
  validates :name, presence: true, length: { maximum: Limits::COMPANY_NAME_LENGTH_LIMIT }
  validates :domain,
            allow_blank: true,
            format: { with: HOSTNAME_FORMAT, message: I18n.t('errors.companies.domain.invalid') },
            uniqueness: { scope: :account_id }, if: -> { domain.present? }
  validates :description, length: { maximum: Limits::COMPANY_DESCRIPTION_LENGTH_LIMIT }
  validates :custom_attributes, jsonb_attributes_length: true

  belongs_to :account
  has_many :contacts, dependent: :nullify

  before_validation :normalize_attribute_bags

  after_create_commit :schedule_favicon_fetch, if: -> { domain.present? }
  after_update_commit :schedule_contact_name_sync, if: :saved_change_to_name?

  scope :ordered_by_name, -> { order(:name) }
  scope :search_by_name_or_domain, lambda { |query|
    term = "%#{query.to_s.strip}%"
    where('companies.name ILIKE :term OR companies.domain ILIKE :term', term: term)
  }

  scope :order_on_contacts_count, lambda { |direction|
    order(Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order("\"companies\".\"contacts_count\" #{direction} NULLS LAST")))
  }

  scope :order_on_last_activity_at, lambda { |direction|
    order(Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order("\"companies\".\"last_activity_at\" #{direction} NULLS LAST")))
  }

  def record_activity_at!(activity_at)
    return if activity_at.blank?
    return if last_activity_at.present? && last_activity_at >= activity_at - ACTIVITY_ROLLUP_WINDOW

    update!(last_activity_at: activity_at)
  end

  private

  def normalize_attribute_bags
    self.additional_attributes = {} unless additional_attributes.is_a?(Hash)
    self.custom_attributes = {} unless custom_attributes.is_a?(Hash)
  end

  def schedule_favicon_fetch
    Avatar::AvatarFromFaviconJob.set(wait: 5.seconds).perform_later(self)
  end

  def schedule_contact_name_sync
    Companies::SyncContactNamesJob.perform_later(company_id: id)
  end
end
