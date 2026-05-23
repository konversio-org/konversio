# == Schema Information
#
# Table name: pilot_custom_tools
#
#  id                :bigint           not null, primary key
#  auth_config       :jsonb
#  auth_type         :string           default("none")
#  description       :text
#  enabled           :boolean          default(TRUE), not null
#  endpoint_url      :text             not null
#  http_method       :string           default("GET"), not null
#  param_schema      :jsonb
#  request_template  :text
#  response_template :text
#  slug              :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_pilot_custom_tools_on_account_id           (account_id)
#  index_pilot_custom_tools_on_account_id_and_slug  (account_id,slug) UNIQUE
#

# Account-scoped HTTP tool definition exposed to Autopilot. The full Tools
# sub-feature (executor + guard + per-account limit + admin UI) lands in
# Section 6; this class is the minimal AR record needed for scenarios to
# validate tool references in their instruction text.
class Pilot::CustomTool < ApplicationRecord
  self.table_name = 'pilot_custom_tools'

  NAME_PREFIX = 'custom'.freeze
  NAME_SEPARATOR = '_'.freeze
  MAX_SLUG_LENGTH = 64
  ALLOWED_PARAM_TYPES = %w[string number integer boolean array object].freeze

  belongs_to :account

  validates :slug, presence: true, uniqueness: { scope: :account_id }, length: { maximum: MAX_SLUG_LENGTH }
  validates :title, presence: true
  validates :endpoint_url, presence: true
  validate :validate_param_schema

  before_validation :generate_slug

  scope :enabled, -> { where(enabled: true) }

  def to_tool_metadata
    {
      id: slug,
      title: title,
      description: description,
      custom: true
    }
  end

  private

  def generate_slug
    return if slug.present?
    return if title.blank?

    parameterized = title.parameterize(separator: NAME_SEPARATOR)
    self.slug = "#{NAME_PREFIX}#{NAME_SEPARATOR}#{parameterized}".truncate(MAX_SLUG_LENGTH, omission: '')
  end

  def validate_param_schema
    return if param_schema.blank?

    unless param_schema.is_a?(Array)
      errors.add(:param_schema, 'must be an array')
      return
    end

    param_schema.each_with_index do |entry, index|
      validate_param_entry(entry, index)
    end
  end

  def validate_param_entry(entry, index)
    return errors.add(:param_schema, "entry at index #{index} must be an object") unless entry.is_a?(Hash)

    name = entry['name'] || entry[:name]
    type = entry['type'] || entry[:type]

    errors.add(:param_schema, "entry at index #{index} is missing 'name'") if name.blank?
    return errors.add(:param_schema, "entry at index #{index} is missing 'type'") if type.blank?
    return if ALLOWED_PARAM_TYPES.include?(type.to_s)

    errors.add(:param_schema, "entry at index #{index} has invalid type '#{type}' (allowed: #{ALLOWED_PARAM_TYPES.join(', ')})")
  end
end
