class CallFinder
  RESULTS_PER_PAGE = 25

  def initialize(current_user, current_account, params)
    @current_user = current_user
    @current_account = current_account
    @params = params
  end

  def perform
    @calls = @current_account.calls
    scope_by_visibility
    filter_by_status
    filter_by_direction
    filter_by_inbox
    filter_by_agent
    filter_by_date_range

    { calls: paginated, count: @calls.count }
  end

  private

  # Admins and report managers see the account; everyone else only the calls
  # they accepted inside conversations they can still access.
  def scope_by_visibility
    return if account_wide?

    @calls = @calls.where(accepted_by_agent_id: @current_user.id, conversation_id: accessible_conversation_ids)
  end

  def accessible_conversation_ids
    Conversations::PermissionFilterService.new(@current_account.conversations, @current_user, @current_account)
                                          .perform
                                          .select(:id)
  end

  # `permissions` carries custom-role grants where present; administrators are
  # handled explicitly so the finder does not depend on the role model.
  def account_wide?
    account_user = Current.account_user
    account_user&.administrator? || account_user&.permissions&.include?('report_manage')
  end

  def filter_by_status
    @calls = @calls.where(status: Call.status_from_display(@params[:status])) if @params[:status].present?
  end

  def filter_by_direction
    @calls = @calls.where(direction: Call.direction_from_label(@params[:direction])) if @params[:direction].present?
  end

  def filter_by_inbox
    @calls = @calls.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
  end

  def filter_by_agent
    @calls = @calls.where(accepted_by_agent_id: @params[:agent_id]) if @params[:agent_id].present?
  end

  def filter_by_date_range
    return if @params[:since].blank? || @params[:until].blank?

    @calls = @calls.where(created_at: Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i))
  end

  def paginated
    @calls.includes(:contact, :conversation, :accepted_by_agent, inbox: :channel)
          .order(created_at: :desc)
          .page(@params[:page] || 1)
          .per(RESULTS_PER_PAGE)
  end
end
