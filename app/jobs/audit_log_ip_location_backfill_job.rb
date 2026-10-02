class AuditLogIpLocationBackfillJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 500
  BATCH_DELAY = 5.seconds

  # Resolves one bounded batch per run and reschedules itself from the last id it
  # touched, so an operator-triggered backfill never floods the low queue.
  def perform(cursor = 0)
    audits = pending_audits(cursor).to_a
    return if audits.empty?

    audits.each { |audit| resolve(audit) }
    self.class.set(wait: BATCH_DELAY).perform_later(audits.last.id)
  end

  private

  def pending_audits(cursor)
    AuditLog.where.not(remote_address: nil)
            .where('city IS NULL OR country IS NULL OR country_code IS NULL')
            .where('id > ?', cursor)
            .where(associated_type: 'Account', associated_id: Account.feature_ip_lookup.select(:id))
            .order(:id)
            .limit(BATCH_SIZE)
  end

  def resolve(audit)
    audit.resolve_ip_location!
  rescue StandardError => e
    Rails.logger.warn "AuditLogIpLocationBackfillJob skipped audit #{audit.id}: #{e.message}"
  end
end
