class AuditLogSessionIpLookupJob < ApplicationJob
  queue_as :low

  # A single authentication event shares one address across every entry it wrote,
  # so the address is resolved once and the result is spread over the batch.
  def perform(audit_ids, remote_address)
    return if audit_ids.blank? || remote_address.blank?

    entries = eligible_entries(audit_ids)
    return if entries.empty?

    result = IpLookupService.new.perform(remote_address)
    return unless result

    entries.update_all(city: result.city, country: result.country, country_code: result.country_code) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "AuditLogSessionIpLookupJob failed: #{e.message}"
  end

  private

  def eligible_entries(audit_ids)
    AuditLog.where(id: audit_ids)
            .where(associated_type: 'Account', associated_id: Account.feature_ip_lookup.select(:id))
  end
end
