# frozen_string_literal: true

# Constants and installation-config-backed limits controlling Pilot document
# re-sync cadence and rate-limits.
#
# Eligibility is computed per account against its configured cadence (daily,
# weekly, or monthly; see `Account#pilot_document_sync_interval_hours`) using
# a due window of half the interval. `STALE_TIMEOUT` is the gap between a
# per-source worker's own lock and the scheduler's "treat as crashed and
# re-eligible" window.
module Pilot::SyncLimits
  PER_ACCOUNT_HOURLY_CAP = 50
  GLOBAL_HOURLY_CAP = 1000
  STALE_TIMEOUT = 2.hours
  DEFAULT_REFRESH_INTERVAL_HOURS = 24
  DEFAULT_REFRESH_INTERVAL = DEFAULT_REFRESH_INTERVAL_HOURS.hours

  # Cadence (in hours) keyed by the account's sync-frequency setting.
  REFRESH_INTERVALS_HOURS = { 'daily' => 24, 'weekly' => 168, 'monthly' => 720 }.freeze

  # Maximum jitter (in hours) used to spread refreshes across the window for
  # each cadence.
  JITTER_WINDOWS_HOURS = { 'daily' => 4, 'weekly' => 24, 'monthly' => 96 }.freeze

  DEFAULT_INTERVAL_KEY = 'daily'
  INSTALLATION_DEFAULT_CONFIG_KEY = 'PILOT_DOCUMENT_SYNC_INTERVAL'

  def self.per_account_cap
    Integer(GlobalConfigService.load('PILOT_DOCUMENTS_SYNC_PER_ACCOUNT_CAP', PER_ACCOUNT_HOURLY_CAP))
  rescue ArgumentError, TypeError
    PER_ACCOUNT_HOURLY_CAP
  end

  def self.global_cap
    Integer(GlobalConfigService.load('PILOT_DOCUMENTS_SYNC_GLOBAL_CAP', GLOBAL_HOURLY_CAP))
  rescue ArgumentError, TypeError
    GLOBAL_HOURLY_CAP
  end

  def self.default_interval_key
    configured = GlobalConfigService.load(INSTALLATION_DEFAULT_CONFIG_KEY, DEFAULT_INTERVAL_KEY).to_s
    REFRESH_INTERVALS_HOURS.key?(configured) ? configured : DEFAULT_INTERVAL_KEY
  end

  def self.interval_hours(key)
    REFRESH_INTERVALS_HOURS.fetch(key, REFRESH_INTERVALS_HOURS[DEFAULT_INTERVAL_KEY])
  end

  def self.jitter_hours(key)
    JITTER_WINDOWS_HOURS.fetch(key, JITTER_WINDOWS_HOURS[DEFAULT_INTERVAL_KEY])
  end
end
