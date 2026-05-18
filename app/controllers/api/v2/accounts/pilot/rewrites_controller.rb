class Api::V2::Accounts::Pilot::RewritesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :ensure_text_and_tone

  def create
    rewritten = Custom::Pilot::RewriteService.new(
      text: params[:text],
      tone: params[:tone],
      account: Current.account
    ).perform

    render json: { rewritten: rewritten }, status: :ok
  rescue Custom::Pilot::RewriteService::FeatureDisabledError
    render json: { error: 'Pilot Rewrite is not enabled for this account' }, status: :forbidden
  rescue ArgumentError => e
    render json: {
      error: e.message,
      allowed_tones: Custom::Pilot::RewriteService::ALLOWED_TONES
    }, status: :unprocessable_entity
  rescue Custom::Pilot::RewriteService::Error => e
    Rails.logger.error("[pilot.rewrites] LLM failure: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_rewrite_enabled

    render json: { error: 'Pilot Rewrite is not enabled for this account' }, status: :forbidden
  end

  def ensure_text_and_tone
    if params[:text].blank?
      render json: { error: 'text is required' }, status: :bad_request
    elsif params[:tone].blank?
      render json: { error: 'tone is required' }, status: :bad_request
    end
  end
end
