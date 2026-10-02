class AuditLogIpLookupJob < ApplicationJob
  queue_as :low

  def perform(audit)
    audit.resolve_ip_location!
  rescue StandardError => e
    Rails.logger.warn "AuditLogIpLookupJob failed: #{e.message}"
  end
end
