# == Schema Information
#
# Table name: pilot_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :string
#  enabled_tool_slugs  :jsonb            not null
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_pilot_assistants_on_account_id  (account_id)
#

# Account-scoped Autopilot assistant. Owns documents (knowledge sources),
# assistant responses (the searchable knowledge base), scenarios (rule-based
# behavior), and inbox attachments.
class Pilot::Assistant < ApplicationRecord
  self.table_name = 'pilot_assistants'

  include Avatarable

  # Assistant avatars are fit-and-padded (never cropped) into a transparent
  # 250x250 PNG. Centralised so the model, controller, and prewarm job all
  # build the exact same variant key.
  AVATAR_VARIANT = { resize_and_pad: [250, 250, { alpha: true }], format: :png }.freeze

  belongs_to :account

  has_many :documents,
           class_name: 'Pilot::Document',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :responses,
           class_name: 'Pilot::AssistantResponse',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :scenarios,
           class_name: 'Pilot::Scenario',
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :pilot_inboxes,
           class_name: 'Pilot::Inbox',
           foreign_key: :pilot_assistant_id,
           inverse_of: :assistant,
           dependent: :destroy_async
  has_many :inboxes, through: :pilot_inboxes
  has_many :messages, as: :sender, dependent: :nullify

  before_validation :normalize_enabled_tool_slugs
  # Generate the padded variant as soon as a new avatar is attached so the
  # first widget visitor never triggers cold libvips processing on request.
  after_commit :prewarm_avatar_variant, if: :avatar_recently_attached?

  store_accessor :config,
                 :product_name,
                 :feature_faq,
                 :feature_memory,
                 :feature_contact_attributes,
                 :feature_citation,
                 :citation_behavior,
                 :welcome_message,
                 :handoff_message,
                 :resolution_message,
                 :instructions,
                 :temperature,
                 :keep_assistant_active_during_handoff,
                 :max_history,
                 :reasoning_effort,
                 :max_tokens

  DEFAULT_MAX_HISTORY = 15

  validates :name, presence: true
  validates :account_id, presence: true
  validates :reasoning_effort, inclusion: { in: %w[off low medium high], allow_nil: true }
  validates :max_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 1000, allow_nil: true }

  # Documentation-search citation toggle (default "on"). When "off", the
  # documentation-search tool MUST suppress `Source: <file>` lines for
  # PDF-origin matches; URL-origin matches always surface the URL.
  def citation_behavior
    config&.dig('citation_behavior').presence || 'on'
  end

  # Whether the Autopilot keeps answering customer messages while a
  # handoff is pending and no human has taken over yet. Defaults to true
  # (co-active). When false, the assistant stays silent during the wait.
  def keep_assistant_active_during_handoff
    value = config&.dig('keep_assistant_active_during_handoff')
    value.nil? || ActiveModel::Type::Boolean.new.cast(value)
  end

  # Number of prior conversation messages sent to the LLM per inference.
  # Bounds per-turn token cost. Defaults to 15 if unset or non-positive.
  def max_history
    value = config&.dig('max_history').to_i
    value.positive? ? value : DEFAULT_MAX_HISTORY
  end

  scope :ordered, -> { order(created_at: :desc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def available_name
    name
  end

  def enabled_tool_slugs
    normalize_tool_slugs(self[:enabled_tool_slugs])
  end

  def enabled_tool_slugs=(value)
    self[:enabled_tool_slugs] = normalize_tool_slugs(value)
  end

  def enabled_custom_tools
    return Pilot::CustomTool.none if account.blank?

    account.pilot_custom_tools.enabled.where(slug: enabled_tool_slugs)
  end

  # Stable, content-hashed URL for the padded avatar (see AVATAR_VARIANT for
  # the never-crop rationale). Unlike ActiveStorage's representation URL — which
  # 302-redirects to an expiring signed blob URL the CDN can't cache — this URL
  # is served directly by Pilot::AssistantAvatarsController with immutable cache
  # headers, so Cloudflare and browsers cache it like any other static asset.
  # The hash busts the cache only when the underlying avatar changes.
  # Overrides Avatarable#avatar_url (which uses resize_to_fill).
  def avatar_url
    return '' unless avatar.attached? && avatar.representable?

    pilot_assistant_avatar_url(id: id, hash: avatar_cache_key)
  end

  # The padded PNG representation streamed to the widget. Shared by the
  # controller (serving) and prewarm job (processing) so the variant key matches.
  def avatar_variant
    avatar.representation(**AVATAR_VARIANT)
  end

  # Short content fingerprint embedded in avatar_url for cache busting.
  def avatar_cache_key
    Digest::SHA1.hexdigest(avatar.blob.checksum)[0, 16]
  end

  # Final fallback when the assistant has no custom avatar attached
  # and the inbox also has none. This is the default bot glyph used across
  # the widget and dashboard for AI assistants (e.g. the value resolved at
  # https://support.arnocoenen.art/assets/images/konversio_bot.svg).
  def default_avatar_url
    '/assets/images/konversio_bot.svg'
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || inbox&.avatar_url || default_avatar_url,
      description: description,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'pilot_assistant'
    }
  end

  private

  def avatar_recently_attached?
    avatar.attached? && avatar.attachment.previously_new_record?
  end

  def prewarm_avatar_variant
    Pilot::PrewarmAvatarJob.perform_later(self)
  end

  def normalize_enabled_tool_slugs
    self.enabled_tool_slugs = self[:enabled_tool_slugs]
  end

  def normalize_tool_slugs(value)
    values = value.is_a?(Hash) ? value.values : Array(value)
    values.filter_map { |slug| slug.to_s.presence }.uniq
  end
end
