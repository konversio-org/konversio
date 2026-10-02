# Per-assistant engagement and inactivity-lifecycle configuration, stored in
# `pilot_assistants.config`:
#
# - audience: condition tree deciding which contacts the assistant engages
# - response_window: always / business_hours / outside_business_hours,
#   evaluated against the inbox's working-hours configuration
# - auto_resolve_mode: disabled / legacy / evaluated (falls back to the
#   account-level setting; stamped at creation)
# - auto_resolve_after: idle threshold in minutes (5-minute steps, 5..1440)
# - send_inactivity_resolution_message: whether an inactivity resolution
#   posts a customer-facing message (default on)
module PilotAssistantLifecycle
  extend ActiveSupport::Concern

  # Response-window values gating when the assistant engages a conversation,
  # evaluated against the inbox's working-hours configuration. Blank behaves
  # as `always`.
  RESPONSE_WINDOWS = %w[always business_hours outside_business_hours].freeze

  # Per-assistant auto-resolve modes. `disabled` never touches the
  # conversation, `legacy` resolves purely on elapsed idle time, `evaluated`
  # asks the LLM for a resolve-vs-handoff verdict.
  AUTO_RESOLVE_MODES = AccountPilotAutoResolve::VALID_PILOT_AUTO_RESOLVE_MODES

  # Inactivity threshold bounds (minutes): 5-minute steps between 5 minutes
  # and 24 hours; defaults to 60 (with the installation-level override as
  # fallback when the assistant has no explicit value).
  MIN_INACTIVITY_THRESHOLD_MINUTES = 5
  MAX_INACTIVITY_THRESHOLD_MINUTES = 1440
  INACTIVITY_THRESHOLD_STEP_MINUTES = 5
  DEFAULT_INACTIVITY_THRESHOLD_MINUTES = 60

  included do
    store_accessor :config,
                   :audience,
                   :response_window,
                   :auto_resolve_after

    before_validation :normalize_auto_resolve_after
    before_validation :stamp_auto_resolve_mode, on: :create

    validates :response_window, inclusion: { in: RESPONSE_WINDOWS, allow_blank: true }
    validates :auto_resolve_mode, inclusion: { in: AUTO_RESOLVE_MODES, allow_blank: true }
    validates :auto_resolve_after,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: MIN_INACTIVITY_THRESHOLD_MINUTES,
                less_than_or_equal_to: MAX_INACTIVITY_THRESHOLD_MINUTES,
                allow_nil: true
              }
    validate :validate_send_inactivity_resolution_message
    validate :validate_audience_tree
  end

  class_methods do
    def default_inactivity_threshold_minutes
      global = GlobalConfigService.load('PILOT_AUTORESOLVE_IDLE_MINUTES', DEFAULT_INACTIVITY_THRESHOLD_MINUTES).to_i
      global.positive? ? global : DEFAULT_INACTIVITY_THRESHOLD_MINUTES
    end
  end

  # Per-assistant auto-resolve mode. Falls back to the account-level setting
  # when the assistant has no explicit value.
  def auto_resolve_mode
    config&.dig('auto_resolve_mode').presence || account&.pilot_auto_resolve_mode
  end

  def auto_resolve_mode=(value)
    self.config = (config || {}).merge('auto_resolve_mode' => value)
  end

  # Idle minutes before the inactivity sweep acts on this assistant's pending
  # conversations. Falls back to the installation-level override, then the
  # built-in default.
  def inactivity_threshold_minutes
    explicit = config&.dig('auto_resolve_after').to_i
    explicit.positive? ? explicit : self.class.default_inactivity_threshold_minutes
  end

  # Whether an inactivity auto-resolution posts a customer-facing message.
  # Defaults on; when off the conversation is still resolved silently.
  def send_inactivity_resolution_message
    value = config&.dig('send_inactivity_resolution_message')
    value.nil? || ActiveModel::Type::Boolean.new.cast(value)
  end

  def send_inactivity_resolution_message=(value)
    self.config = (config || {}).merge('send_inactivity_resolution_message' => value)
  end

  # Whether the assistant takes charge of the given conversation: the
  # audience tree must match the contact/conversation and the response window
  # must be open for the conversation's inbox.
  def engages?(contact, conversation)
    audience_matches?(contact, conversation) && response_window_available?(conversation&.inbox)
  end

  def audience_matches?(contact, conversation)
    ::Pilot::Audience::Matcher.call(audience, contact: contact, conversation: conversation)
  end

  def response_window_available?(inbox)
    window = config&.dig('response_window').presence || 'always'
    return true if window == 'always'
    return true unless inbox&.working_hours_enabled?

    window == 'business_hours' ? !inbox.out_of_office? : inbox.out_of_office?
  end

  private

  # New assistants inherit the account-level auto-resolve mode so an explicit
  # value is always on record for assistants created after this feature.
  def stamp_auto_resolve_mode
    return if config&.dig('auto_resolve_mode').present?

    self.config = (config || {}).merge('auto_resolve_mode' => account&.pilot_auto_resolve_mode)
  end

  # Rounds an in-range threshold to the nearest 5-minute step; out-of-range or
  # non-integer values are left untouched so validation rejects them.
  def normalize_auto_resolve_after
    raw = config&.dig('auto_resolve_after')
    return if raw.nil?

    int = Integer(raw, exception: false)
    return if int.nil? || !int.between?(MIN_INACTIVITY_THRESHOLD_MINUTES, MAX_INACTIVITY_THRESHOLD_MINUTES)

    self.config = (config || {}).merge(
      'auto_resolve_after' => (int / INACTIVITY_THRESHOLD_STEP_MINUTES.to_f).round * INACTIVITY_THRESHOLD_STEP_MINUTES
    )
  end

  def validate_send_inactivity_resolution_message
    value = config&.dig('send_inactivity_resolution_message')
    return if value.nil? || [true, false].include?(value)

    errors.add(:config, 'send_inactivity_resolution_message must be a boolean')
  end

  def validate_audience_tree
    message = ::Pilot::Audience::TreeValidator.call(audience, account: account)
    errors.add(:config, message) if message.present?
  end
end
