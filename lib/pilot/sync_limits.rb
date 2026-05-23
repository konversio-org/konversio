# frozen_string_literal: true

# Constants controlling Pilot document re-sync cadence and rate-limits.
#
# The deepdive specifies an interval-based eligibility check with a
# per-account hourly cap and a global hourly cap. We use a single
# `DEFAULT_REFRESH_INTERVAL` for MVP — per-plan cadence is a deliberate
# follow-up. `STALE_TIMEOUT` is the deliberate gap between the per-source
# worker's own short lock (~10 minutes in the reference product) and the
# scheduler's "treat as crashed and re-eligible" window.
module Pilot::SyncLimits
  PER_ACCOUNT_HOURLY_CAP = 50
  GLOBAL_HOURLY_CAP = 1000
  STALE_TIMEOUT = 2.hours
  DEFAULT_REFRESH_INTERVAL = 24.hours
end
