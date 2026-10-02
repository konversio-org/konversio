namespace :audit_log do
  desc 'Resolve and store city/country for existing audit log entries that have an IP address'
  task backfill_ip_location: :environment do
    AuditLogIpLocationBackfillJob.perform_later
  end
end
