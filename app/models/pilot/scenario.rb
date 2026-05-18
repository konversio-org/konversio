# == Schema Information
#
# Table name: pilot_scenarios
#
#  id           :bigint           not null, primary key
#  description  :text
#  enabled      :boolean          default(TRUE), not null
#  instruction  :text
#  title        :string
#  tools        :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  assistant_id :bigint           not null
#
# Indexes
#
#  index_pilot_scenarios_on_account_id                (account_id)
#  index_pilot_scenarios_on_assistant_id              (assistant_id)
#  index_pilot_scenarios_on_assistant_id_and_enabled  (assistant_id,enabled)
#  index_pilot_scenarios_on_enabled                   (enabled)
#

# Rule-based behavior unit attached to a Pilot::Assistant. The scenario's
# `instruction` may reference tools using markdown `[Label](tool://<id>)`
# syntax; on save the referenced tool ids are extracted into the `tools`
# JSONB array and validated against the account's enabled custom tools.
#
# When an assistant runs, each enabled scenario is registered with the agent
# framework as a callable handoff tool named `handoff_to_<scenario_key>`. The
# constructed tool name MUST stay under 60 characters (the ai-agents SDK
# per-tool name limit); scenarios that would exceed this are rejected at
# validation time.
class Pilot::Scenario < ApplicationRecord
  self.table_name = 'pilot_scenarios'

  # Markdown link to a tool reference: [Label](tool://<id>)
  TOOL_REFERENCE_REGEX = %r{\[[^\]]+\]\(tool://([^/)]+)\)}.freeze

  HANDOFF_TOOL_PREFIX = 'handoff_to_'.freeze
  HANDOFF_KEY_PREFIX = 'scenario'.freeze
  HANDOFF_KEY_SUFFIX = 'agent'.freeze
  MAX_HANDOFF_TOOL_NAME_LENGTH = 60
  MAX_AGENT_NAME_LENGTH = MAX_HANDOFF_TOOL_NAME_LENGTH - HANDOFF_TOOL_PREFIX.length
  MAX_HANDOFF_SLUG_LENGTH = 24

  belongs_to :assistant, class_name: 'Pilot::Assistant'
  belongs_to :account

  validates :title, presence: true
  validates :description, presence: true
  validates :instruction, presence: true
  validate :validate_instruction_tools
  validate :validate_handoff_tool_name_length

  scope :enabled, -> { where(enabled: true) }

  before_validation :ensure_account
  before_save :resolve_tool_references

  def handoff_key
    [handoff_id_key, compact_handoff_slug, HANDOFF_KEY_SUFFIX].compact.join('_')
  end

  def handoff_tool_name
    "#{HANDOFF_TOOL_PREFIX}#{handoff_key}"
  end

  # Returns the unique tool ids extracted from the instruction text.
  def referenced_tool_ids
    self.class.extract_tool_ids_from_text(instruction)
  end

  def self.extract_tool_ids_from_text(text)
    return [] if text.blank?

    text.scan(TOOL_REFERENCE_REGEX).flatten.uniq
  end

  private

  def ensure_account
    self.account = assistant&.account if account.blank?
  end

  def handoff_id_key
    return "#{HANDOFF_KEY_PREFIX}_#{id}" if id.present?

    "#{HANDOFF_KEY_PREFIX}_draft"
  end

  def compact_handoff_slug
    slug = title.to_s.parameterize(separator: '_').presence
    return nil if slug.blank?

    max_slug_length = [MAX_HANDOFF_SLUG_LENGTH, dynamic_slug_max_length].min
    return nil if max_slug_length <= 0

    slug.first(max_slug_length).sub(/_+\z/, '').presence
  end

  def dynamic_slug_max_length
    MAX_AGENT_NAME_LENGTH - handoff_id_key.length - HANDOFF_KEY_SUFFIX.length - 2
  end

  def resolve_tool_references
    return if instruction.blank?

    ids = referenced_tool_ids
    self.tools = ids.presence || []
  end

  def validate_instruction_tools
    return if instruction.blank?
    return if account.blank?

    ids = referenced_tool_ids
    return if ids.empty?

    available_ids = account.pilot_custom_tools.enabled.pluck(:slug)
    invalid_ids = ids - available_ids
    return if invalid_ids.empty?

    errors.add(:instruction, "contains invalid tools: #{invalid_ids.join(', ')}")
  end

  def validate_handoff_tool_name_length
    return if title.blank?
    return if handoff_tool_name.length <= MAX_HANDOFF_TOOL_NAME_LENGTH

    errors.add(:title, "produces a handoff tool name longer than #{MAX_HANDOFF_TOOL_NAME_LENGTH} characters")
  end
end
