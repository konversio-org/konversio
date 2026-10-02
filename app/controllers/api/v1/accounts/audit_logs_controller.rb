class Api::V1::Accounts::AuditLogsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  PAGE_SIZE = 25
  # Largest unix timestamp the database can represent: 9999-12-31T23:59:59Z.
  MAX_EPOCH = 253_402_300_799

  def show
    @audit_logs = listing_scope.page(params[:page]).per(PAGE_SIZE)
    @per_page = PAGE_SIZE
    @current_page = @audit_logs.current_page
    @total_entries = @audit_logs.total_count
  end

  private

  def listing_scope
    return disabled_scope unless Current.account.feature_enabled?(:audit_logs)

    filtered_scope.order(created_at: sort_direction)
  end

  def disabled_scope
    Rails.logger.warn("Audit logs are disabled for account #{Current.account.id}")
    Current.account.associated_audits.none
  end

  def filtered_scope
    scope = Current.account.associated_audits
    scope = scope.with_auditable_types(auditable_types) if auditable_types.any?
    scope = scope.search_by_user(search_term) if search_term
    scope = scope.created_after(window_start) if window_start
    scope = scope.created_before(window_end) if window_end
    scope
  end

  def auditable_types
    @auditable_types ||= Array.wrap(params[:types]).grep(String)
  end

  def search_term
    params[:q] if params[:q].is_a?(String) && params[:q].present?
  end

  def window_start
    return @window_start if defined?(@window_start)

    @window_start = parse_epoch(params[:since])
  end

  def window_end
    return @window_end if defined?(@window_end)

    @window_end = parse_epoch(params[:until])
  end

  def sort_direction
    params[:sort] == 'asc' ? :asc : :desc
  end

  def parse_epoch(value)
    return if value.blank?

    epoch = Integer(value)
    Time.zone.at(epoch) if epoch.between?(0, MAX_EPOCH)
  rescue ArgumentError, TypeError
    nil
  end
end
