# Purges `pilot_events` rows older than `PILOT_EVENTS_RETENTION_DAYS`.
#
# Scheduled daily via sidekiq-cron (see `config/schedule.yml`). Per the
# pilot-telemetry "Activity log view" requirement, events must be
# retained for at least 30 days; anything older is no longer surfaced
# by the Activity view and can be removed.
#
# `pilot_reporting_events` is NOT touched here — that table inherits
# the host application's reporting-event retention policy (spec
# "Reporting event store": no Pilot-specific sweeper).
class Pilot::EventsRetentionJob < ApplicationJob
  queue_as :scheduled_jobs

  PILOT_EVENTS_RETENTION_DAYS = 30

  def perform
    Pilot::Event.where('created_at < ?', PILOT_EVENTS_RETENTION_DAYS.days.ago).delete_all
  end
end
