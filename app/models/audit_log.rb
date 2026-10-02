# == Schema Information
#
# Table name: audits
#
#  id              :bigint           not null, primary key
#  action          :string
#  associated_type :string
#  auditable_type  :string
#  audited_changes :jsonb
#  comment         :string
#  remote_address  :string
#  request_uuid    :string
#  user_type       :string
#  username        :string
#  version         :integer          default(0)
#  created_at      :datetime
#  associated_id   :bigint
#  auditable_id    :bigint
#  user_id         :bigint
#  city            :string
#  country         :string
#  country_code    :string
#
# Indexes
#
#  associated_index                           (associated_type,associated_id)
#  auditable_index                            (auditable_type,auditable_id,version)
#  index_audits_on_associated_and_created_at  (associated_type,associated_id,created_at)
#  index_audits_on_created_at                 (created_at)
#  index_audits_on_request_uuid               (request_uuid)
#  user_index                                 (user_id,user_type)
#
class AuditLog < Audited::Audit
  after_save :stamp_actor_identity
  after_create_commit :queue_location_lookup, if: -> { remote_address.present? && ip_lookup_enabled? }

  scope :with_auditable_types, ->(types) { where(auditable_type: types) }
  scope :created_after, ->(time) { where(created_at: time..) }
  scope :created_before, ->(time) { where(created_at: ..time) }
  scope :search_by_user, lambda { |term|
    pattern = "%#{sanitize_sql_like(term)}%"
    joins("LEFT JOIN users ON users.id = audits.user_id AND audits.user_type = 'User'")
      .where('audits.username ILIKE :pattern OR users.name ILIKE :pattern OR users.email ILIKE :pattern', pattern: pattern)
  }

  def location
    [city, country].compact_blank.presence&.join(', ')
  end

  def masked_remote_address
    return if remote_address.blank?

    address = IPAddr.new(remote_address)
    address.ipv4? ? mask_ipv4(address) : mask_ipv6(address)
  rescue IPAddr::Error
    nil
  end

  def resolve_ip_location!
    return if remote_address.blank? || !ip_lookup_enabled?

    result = IpLookupService.new.perform(remote_address)
    return unless result

    update_columns(city: result.city, country: result.country, country_code: result.country_code) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def mask_ipv4(address)
    "#{address.to_s.split('.')[0..2].join('.')}.x"
  end

  def mask_ipv6(address)
    "#{address.to_string.split(':')[0..3].join(':')}::"
  end

  def stamp_actor_identity
    attributes = { username: user_as_model&.email }
    if auditable_type == 'Account' && auditable_id.present?
      attributes[:associated_type] = auditable_type
      attributes[:associated_id] = auditable_id
    end
    update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
  end

  def ip_lookup_enabled?
    return false unless associated_type == 'Account'

    associated&.feature_enabled?('ip_lookup')
  end

  def queue_location_lookup
    AuditLogIpLookupJob.perform_later(self)
  end
end
