class Api::V2::Accounts::Pilot::EventsController < Api::V1::Accounts::BaseController
  PER_PAGE = 25

  before_action :ensure_feature_enabled
  before_action :authorize_request

  def index
    @events = Current.account.pilot_events.latest.page(current_page).per(PER_PAGE)
  end

  private

  def ensure_feature_enabled
    return if Current.account.feature_enabled?('pilot')

    render json: { error: 'Pilot is not enabled for this account' }, status: :forbidden
  end

  def authorize_request
    return if performed?

    authorize(Pilot::Event, policy_class: Pilot::EventPolicy)
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to perform this action' }, status: :forbidden
  end

  def current_page
    [params[:page].to_i, 1].max
  end
end
