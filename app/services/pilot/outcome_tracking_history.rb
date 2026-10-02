# frozen_string_literal: true

module Pilot
  # Exposes the timestamp at which Pilot outcome recording began — the
  # creation time of the earliest episode. Future reporting uses this to mark
  # earlier periods as untracked rather than as zero.
  #
  # The value is cached so repeated lookups do not query the table: a short TTL
  # while no episodes exist (so the first episode is picked up quickly), and a
  # long TTL once it is set (it only ever moves earlier, and recording start is
  # effectively fixed once history exists).
  class OutcomeTrackingHistory
    CACHE_KEY = 'pilot_outcome_tracking_start'
    EMPTY_TTL = 5.minutes
    SET_TTL = 1.day

    def self.tracking_started_at
      cached = ::Redis::Alfred.get(CACHE_KEY)
      return Time.zone.parse(cached) if cached.present?

      earliest = ::Pilot::ConversationOutcome.minimum(:created_at)
      ::Redis::Alfred.setex(CACHE_KEY, earliest&.iso8601.to_s, earliest.present? ? SET_TTL : EMPTY_TTL)
      earliest
    end
  end
end
