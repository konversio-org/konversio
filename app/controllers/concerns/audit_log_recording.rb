# Records sign-in and sign-out audit entries for account users.
#
# Authentication must never depend on audit logging, so every failure here is
# logged and swallowed rather than raised into the Devise flow.
module AuditLogRecording
  def render_create_success
    track_user_session unless @impersonation
    record_auth_audit('sign_in')
    render partial: 'devise/auth', formats: [:json], locals: { resource: @resource }
  end

  def destroy
    record_auth_audit('sign_out')
    super
  end

  private

  def record_auth_audit(action)
    return unless @resource

    account_ids = @resource.accounts.ids
    return if account_ids.empty?

    rows = auth_audit_rows(action, account_ids)
    inserted = AuditLog.insert_all!(rows, returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    enqueue_auth_location_lookup(rows.first[:remote_address], account_ids, inserted.rows.flatten)
  rescue StandardError => e
    Rails.logger.warn "Audit log recording failed for #{action}: #{e.message}"
  end

  def auth_audit_rows(action, account_ids)
    base_version = AuditLog.unscoped.auditable_finder(@resource.id, 'User').maximum(:version) || 0
    request_uuid = ::Audited.store[:current_request_uuid].presence || SecureRandom.uuid
    created_at = Time.zone.now
    account_ids.each_with_index.map do |account_id, index|
      {
        auditable_id: @resource.id,
        auditable_type: 'User',
        user_id: @resource.id,
        user_type: 'User',
        username: @resource.email,
        action: action,
        associated_id: account_id,
        associated_type: 'Account',
        version: base_version + index + 1,
        request_uuid: request_uuid,
        remote_address: ::Audited.store[:current_remote_address],
        created_at: created_at
      }
    end
  end

  def enqueue_auth_location_lookup(remote_address, account_ids, audit_ids)
    return if remote_address.blank?
    return unless Account.feature_ip_lookup.exists?(id: account_ids)

    AuditLogSessionIpLookupJob.perform_later(audit_ids, remote_address)
  rescue StandardError => e
    Rails.logger.warn "AuditLogSessionIpLookupJob could not be enqueued: #{e.message}"
  end
end
